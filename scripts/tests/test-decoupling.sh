#!/usr/bin/env bash
# ISS-S2-013 / TEST-S2-022 and TEST-S2-023.
# Verifies that HTTP 202 precedes scoring, that the API remains available while
# the case consumer is stopped, and that the queued backlog is processed exactly
# once after the consumer resumes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

readonly COSMOS_DATABASE="centinela"
readonly COSMOS_COLLECTION="transactions"
readonly COSMOS_SECRET_NAME="cosmos-mongo-connection-string"
readonly POSTGRES_DATABASE="centinela"
readonly CONSUMER_SETTING="CENTINELA_QUEUE_AUTO_START"
readonly THRESHOLD_SETTING="SCORING_THRESHOLD"
readonly SLOT_NAME="staging"
readonly TIMEOUT_SECONDS="${ISS13_TIMEOUT_SECONDS:-300}"
readonly POLL_SECONDS="${ISS13_POLL_SECONDS:-5}"
readonly NO_MESSAGE_SETTLE_SECONDS="${ISS13_NO_MESSAGE_SETTLE_SECONDS:-25}"
readonly CASE_COUNT="${ISS13_CASE_COUNT:-3}"
readonly KEEP_TEST_DATA="${KEEP_ISS13_DATA:-0}"

TEMP_ROLE_ASSIGNMENT_IDS=()
TRANSACTION_IDS=()
ACCOUNT_IDS=()
BLOB_NAMES=()
TARGET_TRANSACTION_IDS=()
CONSUMER_TOUCHED=0
CONSUMER_RESTORED=0
ORIGINAL_CONSUMER_PRESENT=0
ORIGINAL_CONSUMER_VALUE=""
THRESHOLD_TOUCHED=0
THRESHOLD_RESTORED=0
ORIGINAL_THRESHOLD_PRESENT=0
ORIGINAL_THRESHOLD_VALUE=""
COSMOS_CONNECTION_STRING=""
POSTGRES_TOKEN=""
POSTGRES_USER=""
POSTGRES_CONNECTION=""
FINAL_STATUS="FAILED"
FINAL_DETAIL="La prueba termino antes de completar sus verificaciones."
TEST_ID=""
RUN_ID=""
EVIDENCE_DIR=""
ENVIRONMENT=""
QUEUE_NAME=""
RAW_CONTAINER=""

resource_hash() {
  printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6
}
compute_storage_account_name() { printf '%sst%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_web_app_name() { printf '%s-app-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_function_app_name() { printf '%s-scoring-fn-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_keyvault_name() { printf '%s-kv-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_cosmos_account_name() { printf '%s-cosmos-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_postgres_server_name() { printf '%s-pg-%s' "$NAME_PREFIX" "$(resource_hash)"; }

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch_ms() { date -u +%s%3N; }
utc_from_epoch() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
rfc3339_to_epoch_ms() { date -u -d "$1" +%s%3N; }

is_private_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^192\.168\. ]] || [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]
}

private_addresses() {
  local host="$1"
  if command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$host" 2>/dev/null | awk '/^Name:/ {answer=1; next} answer && /^Address: / {print $2}' | sort -u
  else
    die "No hay getent ni nslookup para validar DNS privado."
  fi
}

verify_private_dns() {
  local host="$1" label="$2" addresses ip
  addresses="$(private_addresses "$host" || true)"
  [ -n "$addresses" ] || die "No se pudo resolver $label '$host'."
  printf '%s\n' "$addresses" > "$EVIDENCE_DIR/dns-${label}.txt"
  while IFS= read -r ip; do
    if is_private_ipv4 "$ip"; then return 0; fi
  done <<< "$addresses"
  die "$label '$host' no resolvio a IP privada. Ejecuta desde un host conectado a la VNet."
}

resolve_current_principal() {
  PRINCIPAL_OBJECT_ID="${CENTINELA_E2E_PRINCIPAL_OBJECT_ID:-}"
  PRINCIPAL_TYPE="${CENTINELA_E2E_PRINCIPAL_TYPE:-}"
  if [ -n "$PRINCIPAL_OBJECT_ID" ]; then
    case "$PRINCIPAL_TYPE" in User|ServicePrincipal) return 0 ;; esac
    die "CENTINELA_E2E_PRINCIPAL_TYPE debe ser User o ServicePrincipal."
  fi
  PRINCIPAL_OBJECT_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
  if [ -n "$PRINCIPAL_OBJECT_ID" ]; then PRINCIPAL_TYPE="User"; return 0; fi
  local account_name
  account_name="$(az account show --query user.name -o tsv 2>/dev/null || true)"
  PRINCIPAL_OBJECT_ID="$(az ad sp show --id "$account_name" --query id -o tsv 2>/dev/null || true)"
  [ -n "$PRINCIPAL_OBJECT_ID" ] || die "Define CENTINELA_E2E_PRINCIPAL_OBJECT_ID y CENTINELA_E2E_PRINCIPAL_TYPE."
  PRINCIPAL_TYPE="ServicePrincipal"
}

ensure_temporary_role() {
  local role="$1" scope="$2" existing assignment_id
  existing="$(az role assignment list --assignee "$PRINCIPAL_OBJECT_ID" --scope "$scope" \
    --role "$role" --include-inherited --query 'length(@)' -o tsv 2>/dev/null || echo 0)"
  if [ "${existing:-0}" -ge 1 ] 2>/dev/null; then return 0; fi
  assignment_id="$(az role assignment create --assignee-object-id "$PRINCIPAL_OBJECT_ID" \
    --assignee-principal-type "$PRINCIPAL_TYPE" --role "$role" --scope "$scope" --query id -o tsv)"
  [ -n "$assignment_id" ] || die "No se pudo crear RBAC temporal '$role'."
  TEMP_ROLE_ASSIGNMENT_IDS+=("$assignment_id")
}

webapp_setting_value() {
  if [ "$ENVIRONMENT" = "staging" ]; then
    az webapp config appsettings list --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" --slot "$SLOT_NAME" \
      --query "[?name=='$CONSUMER_SETTING'] | [0].value" -o tsv
  else
    az webapp config appsettings list --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" \
      --query "[?name=='$CONSUMER_SETTING'] | [0].value" -o tsv
  fi
}

set_consumer_auto_start() {
  local value="$1"
  if [ "$ENVIRONMENT" = "staging" ]; then
    az webapp config appsettings set --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" --slot "$SLOT_NAME" \
      --slot-settings "$CONSUMER_SETTING=$value" --output none
  else
    az webapp config appsettings set --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" \
      --slot-settings "$CONSUMER_SETTING=$value" --output none
  fi
}

remove_consumer_setting() {
  if [ "$ENVIRONMENT" = "staging" ]; then
    az webapp config appsettings delete --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" --slot "$SLOT_NAME" \
      --setting-names "$CONSUMER_SETTING" --output none
  else
    az webapp config appsettings delete --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" \
      --setting-names "$CONSUMER_SETTING" --output none
  fi
}

restart_webapp() {
  if [ "$ENVIRONMENT" = "staging" ]; then
    az webapp restart --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" --slot "$SLOT_NAME" --output none
  else
    az webapp restart --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" --output none
  fi
}

wait_for_health() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS)) status
  while [ "$SECONDS" -lt "$deadline" ]; do
    status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 10 --max-time 20 \
      "${API_BASE_URL%/}/actuator/health" || true)"
    [ "$status" = "200" ] && return 0
    sleep "$POLL_SECONDS"
  done
  die "La Web App no recupero health=200 dentro de ${TIMEOUT_SECONDS}s."
}

function_setting_value() {
  local name="$1"
  az functionapp config appsettings list --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" \
    --query "[?name=='$name'] | [0].value" -o tsv
}

set_function_threshold() {
  local value="$1"
  az functionapp config appsettings set --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" \
    --settings "$THRESHOLD_SETTING=$value" --output none
  THRESHOLD_TOUCHED=1
  sleep "${FUNCTION_RESTART_SETTLE_SECONDS:-20}"
}

remove_function_threshold() {
  az functionapp config appsettings delete --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" \
    --setting-names "$THRESHOLD_SETTING" --output none
}

restore_consumer() {
  [ "$CONSUMER_TOUCHED" -eq 1 ] || return 0
  [ "$CONSUMER_RESTORED" -eq 0 ] || return 0
  if [ "$ORIGINAL_CONSUMER_PRESENT" -eq 1 ]; then set_consumer_auto_start "$ORIGINAL_CONSUMER_VALUE" || true
  else remove_consumer_setting || true
  fi
  restart_webapp || true
  CONSUMER_RESTORED=1
}

restore_threshold() {
  [ "$THRESHOLD_TOUCHED" -eq 1 ] || return 0
  [ "$THRESHOLD_RESTORED" -eq 0 ] || return 0
  if [ "$ORIGINAL_THRESHOLD_PRESENT" -eq 1 ]; then set_function_threshold "$ORIGINAL_THRESHOLD_VALUE" || true
  else remove_function_threshold || true
  fi
  THRESHOLD_RESTORED=1
}

mongo_find_score() {
  local transaction_id="$1" account_id="$2" output
  output="$(COSMOS_CONNECTION_STRING="$COSMOS_CONNECTION_STRING" E2E_COSMOS_DATABASE="$COSMOS_DATABASE" \
    E2E_COSMOS_COLLECTION="$COSMOS_COLLECTION" E2E_TRANSACTION_ID="$transaction_id" E2E_ACCOUNT_ID="$account_id" \
    mongosh --nodb --quiet --eval '
      const connection = connect(process.env.COSMOS_CONNECTION_STRING);
      const document = connection.getSiblingDB(process.env.E2E_COSMOS_DATABASE)
        .getCollection(process.env.E2E_COSMOS_COLLECTION)
        .findOne({accountId: process.env.E2E_ACCOUNT_ID, transactionId: process.env.E2E_TRANSACTION_ID}, {_id: 0});
      if (document) print("CENTINELA_JSON=" + EJSON.stringify(document, {relaxed: true}));
    ' 2>/dev/null || true)"
  printf '%s\n' "$output" | sed -n 's/^CENTINELA_JSON=//p' | tail -n 1
}

wait_for_score() {
  local transaction_id="$1" account_id="$2" target_file="$3" deadline document
  deadline=$((SECONDS + TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    document="$(mongo_find_score "$transaction_id" "$account_id")"
    if [ -n "$document" ] && jq -e '.score.total != null' <<< "$document" >/dev/null 2>&1; then
      printf '%s\n' "$document" > "$target_file"
      return 0
    fi
    sleep "$POLL_SECONDS"
  done
  die "No aparecio score en Cosmos para transactionId=$transaction_id."
}

postgres_case_count() {
  local ids_csv="$1"
  PGPASSWORD="$POSTGRES_TOKEN" psql "$POSTGRES_CONNECTION" -At -v ON_ERROR_STOP=1 \
    -c "SELECT COUNT(*) || ':' || COUNT(DISTINCT transaction_id) FROM fraud_case WHERE transaction_id IN ($ids_csv);"
}

wait_for_exact_cases() {
  local expected="$1" ids_csv="$2" target_file="$3" deadline result total distinct
  deadline=$((SECONDS + TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    result="$(postgres_case_count "$ids_csv" 2>/dev/null || true)"
    total="${result%%:*}"; distinct="${result##*:}"
    if [ "$total" = "$expected" ] && [ "$distinct" = "$expected" ]; then
      jq -n --argjson expected "$expected" --argjson total "$total" --argjson distinct "$distinct" \
        --arg checkedAt "$(now_utc)" '{expected:$expected,total:$total,distinct:$distinct,checkedAt:$checkedAt}' > "$target_file"
      return 0
    fi
    sleep "$POLL_SECONDS"
  done
  die "No se materializaron exactamente $expected casos sin duplicados. Ultimo conteo=${result:-N/A}."
}

queue_messages_json() {
  az storage message peek --queue-name "$QUEUE_NAME" --num-messages 32 --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login --only-show-errors -o json 2>/dev/null || printf '[]'
}

queue_target_matches() {
  local response="$1"
  jq --argjson ids "$(printf '%s\n' "${TARGET_TRANSACTION_IDS[@]}" | jq -R . | jq -s .)" '
    [ .[]
      | . as $message
      | (try ($message.content | fromjson) catch (try ($message.content | @base64d | fromjson) catch {})) as $payload
      | select($ids | index($payload.transactionId))
      | {id:$message.id,insertionTime:$message.insertionTime,transactionId:$payload.transactionId,payload:$payload}
    ]' <<< "$response"
}

assert_queue_clean() {
  local response
  response="$(queue_messages_json)"
  [ "$(jq 'length' <<< "$response")" -eq 0 ] || die "La cola '$QUEUE_NAME' contiene backlog previo."
}

wait_for_target_queue_count() {
  local expected="$1" target_file="$2" deadline response matches count
  deadline=$((SECONDS + TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    response="$(queue_messages_json)"
    matches="$(queue_target_matches "$response")"
    count="$(jq 'length' <<< "$matches")"
    if [ "$count" -eq "$expected" ]; then printf '%s\n' "$matches" > "$target_file"; return 0; fi
    sleep "$POLL_SECONDS"
  done
  die "Queue no alcanzo $expected mensajes objetivo. Ultimo conteo=${count:-0}."
}

assert_no_target_queue_messages() {
  local target_file="$1" settle_seconds="${2:-$NO_MESSAGE_SETTLE_SECONDS}"
  local deadline response matches count
  [[ "$settle_seconds" =~ ^[1-9][0-9]*$ ]] || die "El tiempo de espera sin mensajes debe ser entero positivo."
  deadline=$((SECONDS + settle_seconds))
  while [ "$SECONDS" -lt "$deadline" ]; do
    response="$(queue_messages_json)"
    matches="$(queue_target_matches "$response")"
    count="$(jq 'length' <<< "$matches")"
    if [ "$count" -ne 0 ]; then
      printf '%s
' "$matches" > "$target_file"
      die "Se publicaron $count mensajes objetivo cuando no debia publicarse ninguno."
    fi
    sleep "$POLL_SECONDS"
  done
  jq -n --arg checkedAt "$(now_utc)" --argjson settleSeconds "$settle_seconds" \
    '{targetMessages:0,settleSeconds:$settleSeconds,checkedAt:$checkedAt}' > "$target_file"
}

wait_for_target_queue_empty() {
  local target_file="$1" deadline response matches count
  deadline=$((SECONDS + TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$deadline" ]; do
    response="$(queue_messages_json)"; matches="$(queue_target_matches "$response")"; count="$(jq 'length' <<< "$matches")"
    if [ "$count" -eq 0 ]; then
      jq -n --arg checkedAt "$(now_utc)" '{targetMessages:0,checkedAt:$checkedAt}' > "$target_file"
      return 0
    fi
    sleep "$POLL_SECONDS"
  done
  die "Persisten $count mensajes objetivo en Queue despues de reanudar el consumidor."
}

find_blob_name() {
  local transaction_id="$1"
  az storage blob list --account-name "$STORAGE_ACCOUNT" --container-name "$RAW_CONTAINER" --auth-mode login \
    --only-show-errors --query "[?ends_with(name, '/${transaction_id}.json')].name | [0]" -o tsv
}

write_payload() {
  local file="$1" transaction_id="$2" account_id="$3" amount="$4" occurred_at="$5"
  local country="$6" city="$7" latitude="$8" longitude="$9" merchant="${10}" category="${11}"
  jq -n --arg transactionId "$transaction_id" --arg accountId "$account_id" --arg amount "$amount" \
    --arg occurredAt "$occurred_at" --arg country "$country" --arg city "$city" --arg latitude "$latitude" \
    --arg longitude "$longitude" --arg merchant "$merchant" --arg category "$category" \
    '{transactionId:$transactionId,accountId:$accountId,amount:($amount|tonumber),currency:"COP",occurredAt:$occurredAt,
      location:{countryCode:$country,city:$city,latitude:($latitude|tonumber),longitude:($longitude|tonumber)},
      merchant:{name:$merchant,category:$category}}' > "$file"
}

send_transaction() {
  local payload_file="$1" response_file="$2" timing_file="$3" transaction_id="$4" start_ms end_ms http_status
  start_ms="$(now_epoch_ms)"
  http_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' --connect-timeout 15 \
    --max-time 60 --request POST --header "Authorization: Bearer $CENTINELA_SERVICE_TOKEN" \
    --header 'Content-Type: application/json' --data-binary "@$payload_file" "${API_BASE_URL%/}/api/v1/transactions")"
  end_ms="$(now_epoch_ms)"
  [ "$http_status" = "202" ] || die "API devolvio HTTP $http_status para $transaction_id."
  [ "$(jq -r '.transactionId' "$response_file")" = "$transaction_id" ] || die "Recibo incorrecto para $transaction_id."
  jq -n --arg transactionId "$transaction_id" --argjson requestStartedMs "$start_ms" \
    --argjson responseReceivedMs "$end_ms" --argjson httpStatus "$http_status" \
    '{transactionId:$transactionId,requestStartedMs:$requestStartedMs,responseReceivedMs:$responseReceivedMs,httpStatus:$httpStatus}' > "$timing_file"
}

submit_and_wait_score() {
  local dir="$1" transaction_id="$2" account_id="$3" amount="$4" occurred_at="$5"
  local country="$6" city="$7" latitude="$8" longitude="$9" merchant="${10}" category="${11}"
  mkdir -p "$dir"
  TRANSACTION_IDS+=("$transaction_id")
  write_payload "$dir/request.json" "$transaction_id" "$account_id" "$amount" "$occurred_at" \
    "$country" "$city" "$latitude" "$longitude" "$merchant" "$category"
  send_transaction "$dir/request.json" "$dir/api-response.json" "$dir/api-timing.json" "$transaction_id"
  wait_for_score "$transaction_id" "$account_id" "$dir/score.json"
  local blob_name
  blob_name="$(find_blob_name "$transaction_id" 2>/dev/null || true)"
  if [ -n "$blob_name" ]; then BLOB_NAMES+=("$blob_name"); fi
}

seed_account() {
  local label="$1" account_id="$2" epoch="$3" i tx_id
  ACCOUNT_IDS+=("$account_id")
  for i in 1 2 3; do
    tx_id="tx-${RUN_ID}-${label}-base-${i}"
    submit_and_wait_score "$EVIDENCE_DIR/$label/baseline-$i" "$tx_id" "$account_id" "10000" \
      "$(utc_from_epoch $((epoch - (4 - i) * 60)))" "CO" "Bogota" "4.7110" "-74.0721" \
      "ISS13 Baseline $i" "ISS13_SAFE_${RUN_ID}"
  done
}

submit_high_target() {
  local label="$1" account_id="$2" epoch="$3" tx_id="$4"
  submit_and_wait_score "$EVIDENCE_DIR/$label" "$tx_id" "$account_id" "100000" \
    "$(utc_from_epoch "$epoch")" "JP" "Tokyo" "35.6762" "139.6503" \
    "ISS13 Target ${RUN_ID}" "ISS13_SAFE_${RUN_ID}"
  local score
  score="$(jq -r '.score.total' "$EVIDENCE_DIR/$label/score.json")"
  [ "$score" -eq 95 ] || die "El escenario controlado esperaba score=95 y obtuvo score=$score."
}

ids_to_sql_list() {
  local value result=""
  for value in "$@"; do result+="'${value//\'/\'\'}',"; done
  printf '%s' "${result%,}"
}

record_summary() {
  jq -n --arg testId "$TEST_ID" --arg runId "$RUN_ID" --arg environment "$ENVIRONMENT" \
    --arg status "$FINAL_STATUS" --arg detail "$FINAL_DETAIL" --arg timestamp "$(now_utc)" \
    --arg commit "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo N/A)" \
    '{testId:$testId,runId:$runId,environment:$environment,status:$status,detail:$detail,timestamp:$timestamp,commit:$commit}' \
    > "$EVIDENCE_DIR/summary.json"
}

cleanup_synthetic_data() {
  [ "$KEEP_TEST_DATA" = "0" ] || return 0
  local blob account ids_csv
  for blob in "${BLOB_NAMES[@]:-}"; do
    [ -n "$blob" ] && az storage blob delete --account-name "$STORAGE_ACCOUNT" --container-name "$RAW_CONTAINER" \
      --name "$blob" --auth-mode login --only-show-errors >/dev/null 2>&1 || true
  done
  for account in "${ACCOUNT_IDS[@]:-}"; do
    [ -n "$account" ] || continue
    COSMOS_CONNECTION_STRING="$COSMOS_CONNECTION_STRING" E2E_COSMOS_DATABASE="$COSMOS_DATABASE" \
      E2E_COSMOS_COLLECTION="$COSMOS_COLLECTION" E2E_ACCOUNT_ID="$account" mongosh --nodb --quiet --eval '
        const connection=connect(process.env.COSMOS_CONNECTION_STRING);
        connection.getSiblingDB(process.env.E2E_COSMOS_DATABASE).getCollection(process.env.E2E_COSMOS_COLLECTION)
          .deleteMany({accountId:process.env.E2E_ACCOUNT_ID});' >/dev/null 2>&1 || true
  done
  if [ "${#TRANSACTION_IDS[@]}" -gt 0 ] && [ -n "$POSTGRES_CONNECTION" ]; then
    ids_csv="$(ids_to_sql_list "${TRANSACTION_IDS[@]}")"
    PGPASSWORD="$POSTGRES_TOKEN" psql "$POSTGRES_CONNECTION" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL || true
BEGIN;
DELETE FROM case_audit WHERE case_id IN (SELECT id FROM fraud_case WHERE transaction_id IN ($ids_csv));
DELETE FROM case_assignment WHERE case_id IN (SELECT id FROM fraud_case WHERE transaction_id IN ($ids_csv));
DELETE FROM case_resolution WHERE case_id IN (SELECT id FROM fraud_case WHERE transaction_id IN ($ids_csv));
DELETE FROM fraud_case WHERE transaction_id IN ($ids_csv);
COMMIT;
SQL
  fi
}

iss13_cleanup() {
  local rc=$?
  restore_consumer
  restore_threshold
  cleanup_synthetic_data
  local assignment_id
  for assignment_id in "${TEMP_ROLE_ASSIGNMENT_IDS[@]:-}"; do
    [ -n "$assignment_id" ] && az role assignment delete --ids "$assignment_id" >/dev/null 2>&1 || true
  done
  if [ -n "$EVIDENCE_DIR" ] && [ ! -f "$EVIDENCE_DIR/summary.json" ]; then record_summary || true; fi
  unset COSMOS_CONNECTION_STRING POSTGRES_TOKEN PGPASSWORD CENTINELA_SERVICE_TOKEN
  trap - EXIT
  return "$rc"
}

bootstrap_iss13() {
  TEST_ID="$1"; local evidence_name="$2"; ENVIRONMENT="${3:-staging}"
  case "$ENVIRONMENT" in staging|production) ;; *) die "Ambiente invalido: $ENVIRONMENT" ;; esac
  [[ "$CASE_COUNT" =~ ^[1-9][0-9]*$ ]] || die "ISS13_CASE_COUNT debe ser entero positivo."
  [ "$CASE_COUNT" -le 10 ] || die "ISS13_CASE_COUNT debe ser <= 10 para inspeccionar Queue sin carga masiva."
  RUN_ID="run-${evidence_name}-$(date -u +%Y%m%dT%H%M%SZ)-${ENVIRONMENT}-$RANDOM"
  EVIDENCE_DIR="$REPO_ROOT/docs/evidence/iss-s2-013/$RUN_ID"
  mkdir -p "$EVIDENCE_DIR"
  trap iss13_cleanup EXIT

  local cmd
  for cmd in az jq curl sha1sum mongosh psql date; do require_cmd "$cmd"; done
  : "${CENTINELA_SERVICE_TOKEN:?Define CENTINELA_SERVICE_TOKEN con rol SERVICE}"
  load_parameters; validate_parameters
  az account show >/dev/null 2>&1 || die "No hay sesion Azure activa."
  [ "$(az account show --query id -o tsv)" = "$SUBSCRIPTION_ID" ] || die "La suscripcion activa no coincide."

  STORAGE_ACCOUNT="$(compute_storage_account_name)"; WEB_APP="$(compute_web_app_name)"
  FUNCTION_APP="${SCORING_FUNCTION_APP_NAME:-$(compute_function_app_name)}"; KEY_VAULT="$(compute_keyvault_name)"
  COSMOS_ACCOUNT="$(compute_cosmos_account_name)"; POSTGRES_SERVER="$(compute_postgres_server_name)"
  RAW_CONTAINER="raw-transactions-${ENVIRONMENT}"; QUEUE_NAME="flagged-cases-${ENVIRONMENT}"
  POSTGRES_HOST="${POSTGRES_SERVER}.postgres.database.azure.com"

  az webapp show --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" >/dev/null || die "Falta Web App de Semana 1."
  az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" >/dev/null || die "Falta Function de Semana 2."
  az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null || die "Falta Cosmos."
  az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$RESOURCE_GROUP" >/dev/null || die "Falta PostgreSQL."

  if [ "$ENVIRONMENT" = "staging" ]; then
    API_HOST="$(az webapp show --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" --slot "$SLOT_NAME" --query defaultHostName -o tsv)"
  else
    API_HOST="$(az webapp show --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" --query defaultHostName -o tsv)"
  fi
  API_BASE_URL="https://${API_HOST}"

  resolve_current_principal
  local storage_id keyvault_id
  storage_id="$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
  keyvault_id="$(az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
  ensure_temporary_role "Storage Blob Data Contributor" "$storage_id/blobServices/default/containers/$RAW_CONTAINER"
  ensure_temporary_role "Storage Queue Data Message Processor" "$storage_id/queueServices/default/queues/$QUEUE_NAME"
  ensure_temporary_role "Key Vault Secrets User" "$keyvault_id"

  verify_private_dns "${STORAGE_ACCOUNT}.blob.core.windows.net" blob
  verify_private_dns "${STORAGE_ACCOUNT}.queue.core.windows.net" queue
  verify_private_dns "${KEY_VAULT}.vault.azure.net" keyvault
  verify_private_dns "$POSTGRES_HOST" postgres

  COSMOS_CONNECTION_STRING="$(az keyvault secret show --vault-name "$KEY_VAULT" --name "$COSMOS_SECRET_NAME" --query value -o tsv)"
  [ -n "$COSMOS_CONNECTION_STRING" ] || die "No se pudo leer el secreto de Cosmos."
  local mongo_host
  mongo_host="${COSMOS_CONNECTION_STRING#*@}"; mongo_host="${mongo_host%%[:/]*}"
  verify_private_dns "$mongo_host" cosmos-mongo

  POSTGRES_USER="${CENTINELA_POSTGRES_E2E_USER:-$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || true)}"
  [ -n "$POSTGRES_USER" ] || die "Define CENTINELA_POSTGRES_E2E_USER."
  POSTGRES_TOKEN="$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)"
  POSTGRES_CONNECTION="host=$POSTGRES_HOST port=5432 dbname=$POSTGRES_DATABASE user=$POSTGRES_USER sslmode=require connect_timeout=10"
  PGPASSWORD="$POSTGRES_TOKEN" psql "$POSTGRES_CONNECTION" -Atc 'SELECT 1' >/dev/null || die "Sin acceso a PostgreSQL privado."

  ORIGINAL_CONSUMER_VALUE="$(webapp_setting_value 2>/dev/null || true)"
  [ -n "$ORIGINAL_CONSUMER_VALUE" ] && ORIGINAL_CONSUMER_PRESENT=1
  ORIGINAL_THRESHOLD_VALUE="$(function_setting_value "$THRESHOLD_SETTING" 2>/dev/null || true)"
  [ -n "$ORIGINAL_THRESHOLD_VALUE" ] && ORIGINAL_THRESHOLD_PRESENT=1

  jq -n --arg testId "$TEST_ID" --arg environment "$ENVIRONMENT" --arg apiBaseUrl "$API_BASE_URL" \
    --arg functionApp "$FUNCTION_APP" --arg queue "$QUEUE_NAME" --arg caseCount "$CASE_COUNT" \
    '{testId:$testId,environment:$environment,apiBaseUrl:$apiBaseUrl,functionApp:$functionApp,queue:$queue,caseCount:($caseCount|tonumber)}' \
    > "$EVIDENCE_DIR/metadata.json"
}

run_decoupling() {
  bootstrap_iss13 "TEST-S2-022+TEST-S2-023" "decoupling" "${1:-staging}"
  local threshold epoch i account_id tx_id ids_csv api_end scored_at scored_ms
  threshold="${ORIGINAL_THRESHOLD_VALUE:-50}"
  [[ "$threshold" =~ ^[0-9]+$ ]] || die "SCORING_THRESHOLD no es numerico."
  [ "$threshold" -le 95 ] || die "El umbral $threshold supera el score controlado 95."

  CONSUMER_TOUCHED=1
  set_consumer_auto_start false; restart_webapp; wait_for_health; assert_queue_clean
  epoch="$(date +%s)"

  for ((i=1; i<=CASE_COUNT; i++)); do
    account_id="acct-${RUN_ID}-${i}"; tx_id="tx-${RUN_ID}-target-${i}"
    seed_account "case-$i" "$account_id" "$epoch"
    TARGET_TRANSACTION_IDS+=("$tx_id")
    submit_high_target "case-$i/target" "$account_id" "$((epoch + i))" "$tx_id"
  done

  api_end="$(jq -r '.responseReceivedMs' "$EVIDENCE_DIR/case-1/target/api-timing.json")"
  scored_at="$(jq -r '.score.scoredAt | if type=="object" then .["$date"] else . end' "$EVIDENCE_DIR/case-1/target/score.json")"
  scored_ms="$(rfc3339_to_epoch_ms "$scored_at")"
  [ "$api_end" -lt "$scored_ms" ] || die "HTTP 202 no fue anterior al fin de scoring: api=$api_end scoring=$scored_ms."
  jq -n --argjson apiResponseMs "$api_end" --argjson scoringCompletedMs "$scored_ms" --arg scoredAt "$scored_at" \
    '{apiResponseMs:$apiResponseMs,scoringCompletedMs:$scoringCompletedMs,scoredAt:$scoredAt,apiBeforeScoring:($apiResponseMs<$scoringCompletedMs)}' \
    > "$EVIDENCE_DIR/api-before-scoring.json"

  wait_for_target_queue_count "$CASE_COUNT" "$EVIDENCE_DIR/backlog-while-consumer-stopped.json"
  ids_csv="$(ids_to_sql_list "${TARGET_TRANSACTION_IDS[@]}")"
  [ "$(postgres_case_count "$ids_csv")" = "0:0" ] || die "Se crearon casos mientras el consumidor estaba detenido."

  set_consumer_auto_start true; restart_webapp; wait_for_health
  wait_for_exact_cases "$CASE_COUNT" "$ids_csv" "$EVIDENCE_DIR/cases-after-resume.json"
  wait_for_target_queue_empty "$EVIDENCE_DIR/queue-after-resume.json"

  FINAL_STATUS="PASSED"
  FINAL_DETAIL="HTTP 202 anterior al scoring; consumidor detenido acumulo $CASE_COUNT mensajes y al reanudar creo exactamente $CASE_COUNT casos sin duplicados."
  record_summary
  log_info "ISS-S2-013 desacoplamiento PASSED: $EVIDENCE_DIR"
}

run_threshold_hot_reload() {
  bootstrap_iss13 "TEST-S2-014" "threshold" "${1:-staging}"
  local epoch high_account low_account high_tx low_tx high_score low_score source_before source_after ids_csv
  CONSUMER_TOUCHED=1
  set_consumer_auto_start false; restart_webapp; wait_for_health; assert_queue_clean

  az functionapp deployment source show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" -o json \
    > "$EVIDENCE_DIR/deployment-source-before.json" 2>/dev/null || printf '{}\n' > "$EVIDENCE_DIR/deployment-source-before.json"
  source_before="$(jq -S . "$EVIDENCE_DIR/deployment-source-before.json" | sha256sum | awk '{print $1}')"

  epoch="$(date +%s)"; high_account="acct-${RUN_ID}-high-threshold"; low_account="acct-${RUN_ID}-low-threshold"
  high_tx="tx-${RUN_ID}-high-threshold"; low_tx="tx-${RUN_ID}-low-threshold"
  seed_account high-threshold "$high_account" "$epoch"
  seed_account low-threshold "$low_account" "$epoch"

  set_function_threshold 100
  TARGET_TRANSACTION_IDS=("$high_tx")
  submit_high_target "high-threshold/target" "$high_account" "$((epoch + 1))" "$high_tx"
  high_score="$(jq -r '.score.total' "$EVIDENCE_DIR/high-threshold/target/score.json")"
  assert_no_target_queue_messages "$EVIDENCE_DIR/high-threshold-no-message.json"
  jq -n --arg transactionId "$high_tx" --argjson score "$high_score" --argjson threshold 100 \
    '{transactionId:$transactionId,score:$score,threshold:$threshold,published:false}' > "$EVIDENCE_DIR/high-threshold-result.json"

  set_function_threshold 50
  TARGET_TRANSACTION_IDS=("$low_tx")
  submit_high_target "low-threshold/target" "$low_account" "$((epoch + 1))" "$low_tx"
  low_score="$(jq -r '.score.total' "$EVIDENCE_DIR/low-threshold/target/score.json")"
  wait_for_target_queue_count 1 "$EVIDENCE_DIR/low-threshold-message.json"

  set_consumer_auto_start true; restart_webapp; wait_for_health
  ids_csv="$(ids_to_sql_list "$low_tx")"
  wait_for_exact_cases 1 "$ids_csv" "$EVIDENCE_DIR/low-threshold-case.json"
  TARGET_TRANSACTION_IDS=("$low_tx")
  wait_for_target_queue_empty "$EVIDENCE_DIR/low-threshold-queue-after-consume.json"
  [ "$(postgres_case_count "$(ids_to_sql_list "$high_tx")")" = "0:0" ] || die "El escenario threshold=100 genero caso."

  az functionapp deployment source show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" -o json \
    > "$EVIDENCE_DIR/deployment-source-after.json" 2>/dev/null || printf '{}\n' > "$EVIDENCE_DIR/deployment-source-after.json"
  source_after="$(jq -S . "$EVIDENCE_DIR/deployment-source-after.json" | sha256sum | awk '{print $1}')"
  [ "$source_before" = "$source_after" ] || die "Cambio la fuente de despliegue durante la prueba de umbral."
  jq -n --arg before "$source_before" --arg after "$source_after" \
    '{deploymentSourceHashBefore:$before,deploymentSourceHashAfter:$after,redeployed:false}' > "$EVIDENCE_DIR/no-redeploy.json"
  jq -n --argjson score "$low_score" --argjson highThreshold 100 --argjson lowThreshold 50 \
    '{sameControlledScore:$score,highThreshold:$highThreshold,highThresholdPublished:false,
      lowThreshold:$lowThreshold,lowThresholdPublished:true}' > "$EVIDENCE_DIR/threshold-comparison.json"

  FINAL_STATUS="PASSED"
  FINAL_DETAIL="El mismo score controlado ($low_score) no publico con threshold=100 y publico con threshold=50; fuente de despliegue sin cambios."
  record_summary
  log_info "ISS-S2-013 umbral en caliente PASSED: $EVIDENCE_DIR"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_decoupling "$@"
fi
