#!/usr/bin/env bash
# TEST-S2-021: API -> Blob/Event Grid -> score Cosmos -> Queue -> caso PostgreSQL.
#
# La prueba debe ejecutarse desde un host con acceso a la VNet porque Storage,
# Key Vault, Cosmos Mongo y PostgreSQL conservan acceso publico deshabilitado.
# No contiene pasos manuales entre etapas: pausa temporalmente el consumidor solo
# para observar el mensaje en Queue, lo reanuda y comprueba el caso final.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

ENVIRONMENT="${1:-staging}"
case "$ENVIRONMENT" in
  staging|production) ;;
  *) die "Uso: $0 <staging|production>" ;;
esac

readonly TEST_ID="TEST-S2-021"
readonly SLOT_NAME="staging"
readonly COSMOS_DATABASE="centinela"
readonly COSMOS_COLLECTION="transactions"
readonly COSMOS_SECRET_NAME="cosmos-mongo-connection-string"
readonly POSTGRES_DATABASE="centinela"
readonly CONSUMER_SETTING="CENTINELA_QUEUE_AUTO_START"
readonly TIMEOUT_SECONDS="${E2E_TIMEOUT_SECONDS:-240}"
readonly POLL_SECONDS="${E2E_POLL_SECONDS:-5}"
readonly NO_CASE_SETTLE_SECONDS="${E2E_NO_CASE_SETTLE_SECONDS:-20}"
readonly KEEP_E2E_DATA="${KEEP_E2E_DATA:-0}"

RUN_ID="run-e2e-$(date -u +%Y%m%dT%H%M%SZ)-${ENVIRONMENT}-$RANDOM"
EVIDENCE_DIR="$REPO_ROOT/docs/evidence/iss-s2-012/$RUN_ID"
mkdir -p "$EVIDENCE_DIR/high" "$EVIDENCE_DIR/low" "$EVIDENCE_DIR/baseline"

TEMP_ROLE_ASSIGNMENT_IDS=()
TRANSACTION_IDS=()
ACCOUNT_IDS=()
BLOB_NAMES=()
CONSUMER_TOUCHED=0
CONSUMER_RESTORED=0
ORIGINAL_CONSUMER_PRESENT=0
ORIGINAL_CONSUMER_VALUE=""
COSMOS_CONNECTION_STRING=""
POSTGRES_TOKEN=""
POSTGRES_USER=""
POSTGRES_CONNECTION=""
FINAL_STATUS="FAILED"
FINAL_DETAIL="La prueba termino antes de completar el pipeline."
HIGH_TRANSACTION_ID="not-created"
LOW_TRANSACTION_ID="not-created"
QUEUE_NAME="not-resolved"
RAW_CONTAINER="not-resolved"

resource_hash() {
  printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6
}
compute_storage_account_name() { printf '%sst%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_web_app_name() { printf '%s-app-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_function_app_name() { printf '%s-scoring-fn-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_keyvault_name() { printf '%s-kv-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_cosmos_account_name() { printf '%s-cosmos-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_postgres_server_name() { printf '%s-pg-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_eventgrid_topic_name() { printf '%s-egt-%s' "$NAME_PREFIX" "$(resource_hash)"; }

utc_from_epoch() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ
}
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

is_private_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^10\. ]] ||
  [[ "$ip" =~ ^192\.168\. ]] ||
  [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]
}

private_addresses() {
  local host="$1"
  if command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$host" 2>/dev/null | awk '
      /^Name:/ {answer=1; next}
      answer && /^Address: / {print $2}
      answer && /^Addresses: / {sub(/^Addresses: /, ""); print}
    ' | tr ' ' '\n' | sed '/^$/d' | sort -u
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
    if is_private_ipv4 "$ip"; then
      log_info "DNS privado verificado: $label -> $ip"
      return 0
    fi
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
  if [ -n "$PRINCIPAL_OBJECT_ID" ]; then
    PRINCIPAL_TYPE="User"
    return 0
  fi

  local account_name
  account_name="$(az account show --query user.name -o tsv 2>/dev/null || true)"
  [ -n "$account_name" ] || die "No se pudo resolver el principal actual para RBAC temporal."
  PRINCIPAL_OBJECT_ID="$(az ad sp show --id "$account_name" --query id -o tsv 2>/dev/null || true)"
  [ -n "$PRINCIPAL_OBJECT_ID" ] || die "Define CENTINELA_E2E_PRINCIPAL_OBJECT_ID y CENTINELA_E2E_PRINCIPAL_TYPE."
  PRINCIPAL_TYPE="ServicePrincipal"
}

ensure_temporary_role() {
  local role="$1" scope="$2" existing assignment_id
  existing="$(az role assignment list --assignee "$PRINCIPAL_OBJECT_ID" --scope "$scope" \
    --role "$role" --include-inherited --query 'length(@)' -o tsv 2>/dev/null || echo 0)"
  if [ "${existing:-0}" -ge 1 ] 2>/dev/null; then
    log_info "RBAC existente: '$role' en scope acotado."
    return 0
  fi

  log_info "Creando RBAC temporal '$role' para la corrida..."
  assignment_id="$(az role assignment create \
    --assignee-object-id "$PRINCIPAL_OBJECT_ID" \
    --assignee-principal-type "$PRINCIPAL_TYPE" \
    --role "$role" --scope "$scope" --query id -o tsv)"
  [ -n "$assignment_id" ] || die "No se pudo crear RBAC temporal '$role'."
  TEMP_ROLE_ASSIGNMENT_IDS+=("$assignment_id")
}

webapp_setting_value() {
  if [ "$ENVIRONMENT" = "staging" ]; then
    az webapp config appsettings list --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" \
      --slot "$SLOT_NAME" --query "[?name=='$CONSUMER_SETTING'] | [0].value" -o tsv
  else
    az webapp config appsettings list --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" \
      --query "[?name=='$CONSUMER_SETTING'] | [0].value" -o tsv
  fi
}

set_consumer_auto_start() {
  local value="$1"
  if [ "$ENVIRONMENT" = "staging" ]; then
    az webapp config appsettings set --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" \
      --slot "$SLOT_NAME" --slot-settings "$CONSUMER_SETTING=$value" --output none
  else
    az webapp config appsettings set --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" \
      --slot-settings "$CONSUMER_SETTING=$value" --output none
  fi
}

remove_consumer_setting() {
  if [ "$ENVIRONMENT" = "staging" ]; then
    az webapp config appsettings delete --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" \
      --slot "$SLOT_NAME" --setting-names "$CONSUMER_SETTING" --output none
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
    status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --connect-timeout 10 --max-time 20 "${API_BASE_URL%/}/actuator/health" || true)"
    if [ "$status" = "200" ]; then return 0; fi
    sleep "$POLL_SECONDS"
  done
  die "La Web App no recupero health=200 dentro de ${TIMEOUT_SECONDS}s."
}

restore_consumer() {
  [ "$CONSUMER_TOUCHED" -eq 1 ] || return 0
  [ "$CONSUMER_RESTORED" -eq 0 ] || return 0
  log_info "Restaurando configuracion original del consumidor..."
  if [ "$ORIGINAL_CONSUMER_PRESENT" -eq 1 ]; then
    set_consumer_auto_start "$ORIGINAL_CONSUMER_VALUE" || true
  else
    remove_consumer_setting || true
  fi
  restart_webapp || true
  CONSUMER_RESTORED=1
}

mongo_find_score() {
  local transaction_id="$1" account_id="$2" output
  output="$(COSMOS_CONNECTION_STRING="$COSMOS_CONNECTION_STRING" \
    E2E_COSMOS_DATABASE="$COSMOS_DATABASE" E2E_COSMOS_COLLECTION="$COSMOS_COLLECTION" \
    E2E_TRANSACTION_ID="$transaction_id" E2E_ACCOUNT_ID="$account_id" \
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
  local transaction_id="$1" account_id="$2" target_file="$3"
  local deadline=$((SECONDS + TIMEOUT_SECONDS)) document
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

postgres_find_case() {
  local transaction_id="$1"
  PGPASSWORD="$POSTGRES_TOKEN" psql "$POSTGRES_CONNECTION" \
    -v ON_ERROR_STOP=1 -v transaction_id="$transaction_id" -At <<'SQL'
SELECT json_build_object(
  'caseId', c.id,
  'transactionId', c.transaction_id,
  'score', c.score,
  'state', c.state_code,
  'openedAt', c.opened_at,
  'auditCount', (SELECT COUNT(*) FROM case_audit a WHERE a.case_id = c.id)
)::text
FROM fraud_case c
WHERE c.transaction_id = :'transaction_id';
SQL
}

wait_for_case() {
  local transaction_id="$1" target_file="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS)) document
  while [ "$SECONDS" -lt "$deadline" ]; do
    document="$(postgres_find_case "$transaction_id" 2>/dev/null || true)"
    if [ -n "$document" ]; then
      printf '%s\n' "$document" > "$target_file"
      [ "$(jq -r '.auditCount' "$target_file")" -ge 1 ] \
        || die "El caso existe pero no tiene auditoria de apertura."
      return 0
    fi
    sleep "$POLL_SECONDS"
  done
  die "No aparecio caso en PostgreSQL para transactionId=$transaction_id."
}

assert_no_case() {
  local transaction_id="$1" target_file="$2"
  local deadline=$((SECONDS + NO_CASE_SETTLE_SECONDS)) document
  while [ "$SECONDS" -lt "$deadline" ]; do
    document="$(postgres_find_case "$transaction_id" 2>/dev/null || true)"
    if [ -n "$document" ]; then
      printf '%s\n' "$document" > "$target_file"
      die "La transaccion bajo umbral genero un caso inesperado."
    fi
    sleep "$POLL_SECONDS"
  done
  jq -n --arg transactionId "$transaction_id" --arg checkedAt "$(now_utc)" \
    '{transactionId:$transactionId,casePresent:false,checkedAt:$checkedAt}' > "$target_file"
}

queue_payload_filter() {
  local transaction_id="$1"
  jq --arg transactionId "$transaction_id" '
    [ .[]
      | . as $message
      | (try ($message.content | fromjson)
         catch (try ($message.content | @base64d | fromjson) catch {})) as $payload
      | select(($payload.transactionId // "") == $transactionId)
      | {id:$message.id, insertionTime:$message.insertionTime, payload:$payload}
    ] | .[0] // empty
  '
}

peek_queue_for_transaction() {
  local transaction_id="$1" target_file="$2" required="$3"
  local deadline=$((SECONDS + TIMEOUT_SECONDS)) response match
  while [ "$SECONDS" -lt "$deadline" ]; do
    response="$(az storage message peek --queue-name "$QUEUE_NAME" --num-messages 32 \
      --account-name "$STORAGE_ACCOUNT" --auth-mode login --only-show-errors -o json 2>/dev/null || true)"
    if [ -n "$response" ]; then
      match="$(queue_payload_filter "$transaction_id" <<< "$response")"
      if [ -n "$match" ]; then
        printf '%s\n' "$match" > "$target_file"
        return 0
      fi
    fi
    [ "$required" = "0" ] && return 1
    sleep 1
  done
  return 1
}

assert_queue_clean() {
  local deadline=$((SECONDS + TIMEOUT_SECONDS)) response=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    if response="$(az storage message peek --queue-name "$QUEUE_NAME" --num-messages 1 \
        --account-name "$STORAGE_ACCOUNT" --auth-mode login --only-show-errors -o json 2>/dev/null)"; then
      [ "$(jq 'length' <<< "$response")" -eq 0 ] \
        || die "La cola '$QUEUE_NAME' contiene mensajes previos. Limpia/procesa el backlog antes del E2E."
      return 0
    fi
    sleep "$POLL_SECONDS"
  done
  die "No se pudo leer Queue. Revisa RBAC temporal, DNS privado y conectividad."
}

wait_for_queue_absent() {
  local transaction_id="$1" target_file="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS)) response match
  while [ "$SECONDS" -lt "$deadline" ]; do
    response="$(az storage message peek --queue-name "$QUEUE_NAME" --num-messages 32 \
      --account-name "$STORAGE_ACCOUNT" --auth-mode login --only-show-errors -o json 2>/dev/null || true)"
    if [ -n "$response" ]; then
      match="$(queue_payload_filter "$transaction_id" <<< "$response")"
      if [ -z "$match" ]; then
        jq -n --arg transactionId "$transaction_id" --arg checkedAt "$(now_utc)" \
          '{transactionId:$transactionId,queueMessagePresent:false,checkedAt:$checkedAt}' > "$target_file"
        return 0
      fi
    fi
    sleep "$POLL_SECONDS"
  done
  die "El mensaje de $transaction_id sigue visible en Queue despues de crear el caso."
}

find_blob_name() {
  local transaction_id="$1"
  az storage blob list --account-name "$STORAGE_ACCOUNT" --container-name "$RAW_CONTAINER" \
    --auth-mode login --only-show-errors \
    --query "[?ends_with(name, '/${transaction_id}.json')].name | [0]" -o tsv
}

wait_for_blob() {
  local transaction_id="$1" target_file="$2"
  local deadline=$((SECONDS + TIMEOUT_SECONDS)) blob_name
  while [ "$SECONDS" -lt "$deadline" ]; do
    blob_name="$(find_blob_name "$transaction_id" 2>/dev/null || true)"
    if [ -n "$blob_name" ]; then
      az storage blob download --account-name "$STORAGE_ACCOUNT" \
        --container-name "$RAW_CONTAINER" --name "$blob_name" --file "$target_file" \
        --auth-mode login --overwrite true --only-show-errors >/dev/null
      [ "$(jq -r '.transactionId' "$target_file")" = "$transaction_id" ] \
        || die "El Blob recuperado no corresponde a $transaction_id."
      BLOB_NAMES+=("$blob_name")
      return 0
    fi
    sleep "$POLL_SECONDS"
  done
  die "No aparecio Blob para transactionId=$transaction_id."
}

write_payload() {
  local file="$1" transaction_id="$2" account_id="$3" amount="$4" occurred_at="$5"
  local country="$6" city="$7" latitude="$8" longitude="$9" merchant="${10}" category="${11}"
  jq -n \
    --arg transactionId "$transaction_id" --arg accountId "$account_id" \
    --arg amount "$amount" --arg occurredAt "$occurred_at" \
    --arg country "$country" --arg city "$city" \
    --arg latitude "$latitude" --arg longitude "$longitude" \
    --arg merchant "$merchant" --arg category "$category" \
    '{transactionId:$transactionId,accountId:$accountId,amount:($amount|tonumber),currency:"COP",
      occurredAt:$occurredAt,
      location:{countryCode:$country,city:$city,latitude:($latitude|tonumber),longitude:($longitude|tonumber)},
      merchant:{name:$merchant,category:$category}}' > "$file"
}

send_transaction() {
  local payload_file="$1" response_file="$2" transaction_id="$3"
  local http_status
  http_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --connect-timeout 15 --max-time 60 --request POST \
    --header "Authorization: Bearer $CENTINELA_SERVICE_TOKEN" \
    --header 'Content-Type: application/json' --data-binary "@$payload_file" \
    "${API_BASE_URL%/}/api/v1/transactions")"
  [ "$http_status" = "202" ] || die "API devolvio HTTP $http_status para $transaction_id."
  [ "$(jq -r '.transactionId' "$response_file")" = "$transaction_id" ] \
    || die "El recibo no contiene transactionId=$transaction_id."
  [ "$(jq -r '.status' "$response_file")" = "RECEIVED" ] \
    || die "El recibo no contiene status=RECEIVED."
}

run_transaction_and_wait_score() {
  local evidence_subdir="$1" transaction_id="$2" account_id="$3" amount="$4" occurred_at="$5"
  local country="$6" city="$7" latitude="$8" longitude="$9" merchant="${10}" category="${11}"
  local dir="$EVIDENCE_DIR/$evidence_subdir"
  mkdir -p "$dir"
  TRANSACTION_IDS+=("$transaction_id")
  write_payload "$dir/request.json" "$transaction_id" "$account_id" "$amount" "$occurred_at" \
    "$country" "$city" "$latitude" "$longitude" "$merchant" "$category"
  send_transaction "$dir/request.json" "$dir/api-response.json" "$transaction_id"
  jq -n --arg acceptedAt "$(now_utc)" \
    '{apiAcceptedAt:$acceptedAt,eventGridPublishAcceptedBeforeHttp202:true}' > "$dir/api-stage.json"
  wait_for_blob "$transaction_id" "$dir/blob.json"
  jq -n --arg blobVerifiedAt "$(now_utc)" '{blobVerifiedAt:$blobVerifiedAt}' > "$dir/blob-stage.json"
  wait_for_score "$transaction_id" "$account_id" "$dir/score.json"
  jq -n --arg scoreVerifiedAt "$(now_utc)" '{scoreVerifiedAt:$scoreVerifiedAt}' > "$dir/score-stage.json"
}

read_function_setting() {
  local name="$1"
  az functionapp config appsettings list --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" \
    --query "[?name=='$name'] | [0].value" -o tsv
}

first_csv_value() {
  local csv="$1"
  printf '%s' "$csv" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1}'
}

record_summary() {
  local status="$1" detail="$2"
  jq -n \
    --arg runId "$RUN_ID" --arg testId "$TEST_ID" --arg environment "$ENVIRONMENT" \
    --arg status "$status" --arg detail "$detail" --arg timestamp "$(now_utc)" \
    --arg commit "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo N/A)" \
    --arg branch "$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo N/A)" \
    --arg highTransactionId "$HIGH_TRANSACTION_ID" --arg lowTransactionId "$LOW_TRANSACTION_ID" \
    --arg queue "$QUEUE_NAME" --arg rawContainer "$RAW_CONTAINER" \
    '{runId:$runId,testId:$testId,environment:$environment,status:$status,detail:$detail,
      timestamp:$timestamp,commit:$commit,branch:$branch,
      highTransactionId:$highTransactionId,lowTransactionId:$lowTransactionId,
      queue:$queue,rawContainer:$rawContainer}' > "$EVIDENCE_DIR/summary.json"
}

cleanup_synthetic_data() {
  [ "$KEEP_E2E_DATA" = "0" ] || { log_warn "KEEP_E2E_DATA=1: se conservan datos sinteticos."; return 0; }

  local blob
  for blob in "${BLOB_NAMES[@]:-}"; do
    [ -n "$blob" ] || continue
    az storage blob delete --account-name "$STORAGE_ACCOUNT" --container-name "$RAW_CONTAINER" \
      --name "$blob" --auth-mode login --only-show-errors >/dev/null 2>&1 || true
  done

  if [ -n "$COSMOS_CONNECTION_STRING" ] && [ "${#ACCOUNT_IDS[@]}" -gt 0 ]; then
    local account
    for account in "${ACCOUNT_IDS[@]}"; do
      COSMOS_CONNECTION_STRING="$COSMOS_CONNECTION_STRING" E2E_COSMOS_DATABASE="$COSMOS_DATABASE" \
        E2E_COSMOS_COLLECTION="$COSMOS_COLLECTION" E2E_ACCOUNT_ID="$account" \
        mongosh --nodb --quiet --eval '
          const connection = connect(process.env.COSMOS_CONNECTION_STRING);
          connection.getSiblingDB(process.env.E2E_COSMOS_DATABASE)
            .getCollection(process.env.E2E_COSMOS_COLLECTION)
            .deleteMany({accountId: process.env.E2E_ACCOUNT_ID});
        ' >/dev/null 2>&1 || true
    done
  fi

  if [ -n "$POSTGRES_TOKEN" ] && [ -n "$POSTGRES_CONNECTION" ] && [ "${#TRANSACTION_IDS[@]}" -gt 0 ]; then
    local ids_csv="" transaction_id
    for transaction_id in "${TRANSACTION_IDS[@]}"; do
      ids_csv+="'${transaction_id//\'/\'\'}',"
    done
    ids_csv="${ids_csv%,}"
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

cleanup() {
  local rc=$?
  restore_consumer
  cleanup_synthetic_data

  local assignment_id
  for assignment_id in "${TEMP_ROLE_ASSIGNMENT_IDS[@]:-}"; do
    [ -n "$assignment_id" ] || continue
    az role assignment delete --ids "$assignment_id" >/dev/null 2>&1 || true
  done

  unset COSMOS_CONNECTION_STRING POSTGRES_TOKEN PGPASSWORD CENTINELA_SERVICE_TOKEN
  if [ ! -f "$EVIDENCE_DIR/summary.json" ]; then
    record_summary "$FINAL_STATUS" "$FINAL_DETAIL" || true
  fi
  exit "$rc"
}
trap cleanup EXIT

main() {
  require_cmd az
  require_cmd jq
  require_cmd curl
  require_cmd sha1sum
  require_cmd mongosh
  require_cmd psql
  : "${CENTINELA_SERVICE_TOKEN:?Define CENTINELA_SERVICE_TOKEN con rol SERVICE}"

  load_parameters
  validate_parameters
  az account show >/dev/null 2>&1 || die "No hay sesion Azure activa. Ejecuta az login."
  [ "$(az account show --query id -o tsv)" = "$SUBSCRIPTION_ID" ] \
    || die "La suscripcion activa no coincide con SUBSCRIPTION_ID."

  STORAGE_ACCOUNT="$(compute_storage_account_name)"
  WEB_APP="$(compute_web_app_name)"
  FUNCTION_APP="${SCORING_FUNCTION_APP_NAME:-$(compute_function_app_name)}"
  KEY_VAULT="$(compute_keyvault_name)"
  COSMOS_ACCOUNT="$(compute_cosmos_account_name)"
  POSTGRES_SERVER="$(compute_postgres_server_name)"
  EVENTGRID_TOPIC="$(compute_eventgrid_topic_name)"
  RAW_CONTAINER="raw-transactions-${ENVIRONMENT}"
  QUEUE_NAME="flagged-cases-${ENVIRONMENT}"
  POSTGRES_HOST="${POSTGRES_SERVER}.postgres.database.azure.com"

  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 || die "No existe Resource Group '$RESOURCE_GROUP'."
  az webapp show --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe Web App '$WEB_APP'. Completa Semana 1."
  az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe Function '$FUNCTION_APP'. Ejecuta deploy-week2.sh."
  az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe Cosmos '$COSMOS_ACCOUNT'."
  az postgres flexible-server show --name "$POSTGRES_SERVER" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe PostgreSQL '$POSTGRES_SERVER'."
  az eventgrid topic show --name "$EVENTGRID_TOPIC" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe Event Grid Topic '$EVENTGRID_TOPIC'."
  EVENTGRID_TOPIC_ID="$(az eventgrid topic show --name "$EVENTGRID_TOPIC" \
    --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
  az eventgrid event-subscription show --name score-transaction-v1 \
    --source-resource-id "$EVENTGRID_TOPIC_ID" \
    --query '{name:name,provisioningState:provisioningState,destinationType:destination.endpointType}' \
    -o json > "$EVIDENCE_DIR/eventgrid-subscription.json" \
    || die "No existe la suscripcion score-transaction-v1 hacia la Function."

  if [ "$ENVIRONMENT" = "staging" ]; then
    API_HOST="$(az webapp show --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" \
      --slot "$SLOT_NAME" --query defaultHostName -o tsv)"
  else
    API_HOST="$(az webapp show --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" \
      --query defaultHostName -o tsv)"
  fi
  [ -n "$API_HOST" ] || die "No se pudo resolver el host de la API."
  API_BASE_URL="https://${API_HOST}"

  resolve_current_principal
  STORAGE_ID="$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
  KEYVAULT_ID="$(az keyvault show --name "$KEY_VAULT" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
  ensure_temporary_role "Storage Blob Data Contributor" \
    "$STORAGE_ID/blobServices/default/containers/$RAW_CONTAINER"
  ensure_temporary_role "Storage Queue Data Message Processor" \
    "$STORAGE_ID/queueServices/default/queues/$QUEUE_NAME"
  ensure_temporary_role "Key Vault Secrets User" "$KEYVAULT_ID"

  verify_private_dns "${STORAGE_ACCOUNT}.blob.core.windows.net" "blob"
  verify_private_dns "${STORAGE_ACCOUNT}.queue.core.windows.net" "queue"
  verify_private_dns "${KEY_VAULT}.vault.azure.net" "keyvault"
  verify_private_dns "$POSTGRES_HOST" "postgres"

  local secret_deadline=$((SECONDS + TIMEOUT_SECONDS))
  while [ "$SECONDS" -lt "$secret_deadline" ]; do
    COSMOS_CONNECTION_STRING="$(az keyvault secret show --vault-name "$KEY_VAULT" \
      --name "$COSMOS_SECRET_NAME" --query value -o tsv 2>/dev/null || true)"
    [ -n "$COSMOS_CONNECTION_STRING" ] && break
    sleep "$POLL_SECONDS"
  done
  [ -n "$COSMOS_CONNECTION_STRING" ] || die "No se pudo leer '$COSMOS_SECRET_NAME' desde Key Vault."
  MONGO_HOST="${COSMOS_CONNECTION_STRING#*@}"
  MONGO_HOST="${MONGO_HOST%%[:/]*}"
  [ -n "$MONGO_HOST" ] || die "No se pudo extraer el host Mongo de la connection string."
  verify_private_dns "$MONGO_HOST" "cosmos-mongo"

  POSTGRES_USER="${CENTINELA_POSTGRES_E2E_USER:-$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || true)}"
  [ -n "$POSTGRES_USER" ] \
    || die "Define CENTINELA_POSTGRES_E2E_USER para la identidad Entra con lectura/escritura de prueba."
  POSTGRES_TOKEN="$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)"
  [ -n "$POSTGRES_TOKEN" ] || die "No se obtuvo token Entra para PostgreSQL."
  POSTGRES_CONNECTION="host=$POSTGRES_HOST port=5432 dbname=$POSTGRES_DATABASE user=$POSTGRES_USER sslmode=require connect_timeout=10"
  PGPASSWORD="$POSTGRES_TOKEN" psql "$POSTGRES_CONNECTION" -Atc 'SELECT 1' >/dev/null \
    || die "No hay acceso privado/autorizado a PostgreSQL con '$POSTGRES_USER'."

  ORIGINAL_CONSUMER_VALUE="$(webapp_setting_value 2>/dev/null || true)"
  if [ -n "$ORIGINAL_CONSUMER_VALUE" ]; then ORIGINAL_CONSUMER_PRESENT=1; fi
  CONSUMER_TOUCHED=1
  set_consumer_auto_start false
  restart_webapp
  wait_for_health
  assert_queue_clean

  local epoch threshold risky_merchants risky_categories high_merchant high_category possible_high_score
  epoch="$(date +%s)"
  threshold="$(read_function_setting SCORING_THRESHOLD)"
  threshold="${threshold:-50}"
  [[ "$threshold" =~ ^[0-9]+$ ]] || die "SCORING_THRESHOLD no es numerico: '$threshold'."
  risky_merchants="$(read_function_setting RISKY_MERCHANTS)"
  risky_categories="$(read_function_setting RISKY_CATEGORIES)"
  high_merchant="E2E-HIGH-${RUN_ID}"
  high_category="E2E_SAFE_${RANDOM}"
  possible_high_score=95
  if [ -n "$risky_categories" ]; then
    high_category="$(first_csv_value "$risky_categories")"
    possible_high_score=130
  elif [ -n "$risky_merchants" ]; then
    high_merchant="$(first_csv_value "$risky_merchants")"
    possible_high_score=130
  fi
  [ "$threshold" -le "$possible_high_score" ] \
    || die "El umbral $threshold supera el score sintetico posible ($possible_high_score) sin cambiar configuracion."

  HIGH_ACCOUNT_ID="acct-e2e-high-${RUN_ID}"
  LOW_ACCOUNT_ID="acct-e2e-low-${RUN_ID}"
  ACCOUNT_IDS+=("$HIGH_ACCOUNT_ID" "$LOW_ACCOUNT_ID")
  BASELINE_1_ID="tx-${RUN_ID}-base-1"
  BASELINE_2_ID="tx-${RUN_ID}-base-2"
  BASELINE_3_ID="tx-${RUN_ID}-base-3"
  LOW_TRANSACTION_ID="tx-${RUN_ID}-low"
  HIGH_TRANSACTION_ID="tx-${RUN_ID}-high"

  log_info "Creando historial sintetico controlado para el escenario sobre umbral..."
  run_transaction_and_wait_score "baseline/1" "$BASELINE_1_ID" "$HIGH_ACCOUNT_ID" "10000" \
    "$(utc_from_epoch $((epoch - 180)))" "CO" "Bogota" "4.7110" "-74.0721" \
    "E2E Baseline 1" "E2E_SAFE_${RANDOM}"
  run_transaction_and_wait_score "baseline/2" "$BASELINE_2_ID" "$HIGH_ACCOUNT_ID" "10000" \
    "$(utc_from_epoch $((epoch - 120)))" "CO" "Bogota" "4.7110" "-74.0721" \
    "E2E Baseline 2" "E2E_SAFE_${RANDOM}"
  run_transaction_and_wait_score "baseline/3" "$BASELINE_3_ID" "$HIGH_ACCOUNT_ID" "10000" \
    "$(utc_from_epoch $((epoch - 60)))" "CO" "Bogota" "4.7110" "-74.0721" \
    "E2E Baseline 3" "E2E_SAFE_${RANDOM}"

  log_info "Ejecutando escenario bajo umbral..."
  run_transaction_and_wait_score "low" "$LOW_TRANSACTION_ID" "$LOW_ACCOUNT_ID" "10000" \
    "$(utc_from_epoch "$epoch")" "CO" "Medellin" "6.2442" "-75.5812" \
    "E2E Low ${RUN_ID}" "E2E_SAFE_${RANDOM}"
  LOW_SCORE="$(jq -r '.score.total' "$EVIDENCE_DIR/low/score.json")"
  [ "$LOW_SCORE" -lt "$threshold" ] \
    || die "El escenario bajo umbral obtuvo score=$LOW_SCORE con threshold=$threshold."
  if peek_queue_for_transaction "$LOW_TRANSACTION_ID" "$EVIDENCE_DIR/low/unexpected-queue-message.json" 0; then
    die "La transaccion bajo umbral fue publicada en Queue."
  fi
  jq -n --arg transactionId "$LOW_TRANSACTION_ID" --arg checkedAt "$(now_utc)" \
    '{transactionId:$transactionId,queueMessagePresent:false,checkedAt:$checkedAt}' \
    > "$EVIDENCE_DIR/low/queue-check.json"

  log_info "Ejecutando escenario sobre umbral..."
  run_transaction_and_wait_score "high" "$HIGH_TRANSACTION_ID" "$HIGH_ACCOUNT_ID" "100000" \
    "$(utc_from_epoch $((epoch + 1)))" "JP" "Tokyo" "35.6762" "139.6503" \
    "$high_merchant" "$high_category"
  HIGH_SCORE="$(jq -r '.score.total' "$EVIDENCE_DIR/high/score.json")"
  [ "$HIGH_SCORE" -ge "$threshold" ] \
    || die "El escenario sobre umbral obtuvo score=$HIGH_SCORE con threshold=$threshold."
  peek_queue_for_transaction "$HIGH_TRANSACTION_ID" "$EVIDENCE_DIR/high/queue-message.json" 1 \
    || die "No se observo flagged-case-v1 en Queue para $HIGH_TRANSACTION_ID."
  jq -n --arg queueVerifiedAt "$(now_utc)" '{queueVerifiedAt:$queueVerifiedAt}' \
    > "$EVIDENCE_DIR/high/queue-stage.json"

  log_info "Reanudando consumidor para materializar el caso..."
  set_consumer_auto_start true
  restart_webapp
  wait_for_health
  wait_for_case "$HIGH_TRANSACTION_ID" "$EVIDENCE_DIR/high/case.json"
  jq -n --arg caseVerifiedAt "$(now_utc)" '{caseVerifiedAt:$caseVerifiedAt}' \
    > "$EVIDENCE_DIR/high/case-stage.json"
  wait_for_queue_absent "$HIGH_TRANSACTION_ID" "$EVIDENCE_DIR/high/post-consume-queue-check.json"
  assert_no_case "$LOW_TRANSACTION_ID" "$EVIDENCE_DIR/low/case-check.json"

  jq -n \
    --arg environment "$ENVIRONMENT" --arg apiBaseUrl "$API_BASE_URL" \
    --arg storageAccount "$STORAGE_ACCOUNT" --arg rawContainer "$RAW_CONTAINER" \
    --arg eventGridTopic "$EVENTGRID_TOPIC" --arg functionApp "$FUNCTION_APP" \
    --arg cosmosAccount "$COSMOS_ACCOUNT" --arg queue "$QUEUE_NAME" \
    --arg postgresServer "$POSTGRES_SERVER" --arg threshold "$threshold" \
    '{environment:$environment,apiBaseUrl:$apiBaseUrl,storageAccount:$storageAccount,
      rawContainer:$rawContainer,eventGridTopic:$eventGridTopic,functionApp:$functionApp,
      cosmosAccount:$cosmosAccount,queue:$queue,postgresServer:$postgresServer,
      scoringThreshold:($threshold|tonumber)}' > "$EVIDENCE_DIR/metadata.json"

  FINAL_STATUS="PASSED"
  FINAL_DETAIL="API 202, Blob, Event Grid aceptado, score, Queue y caso reconciliados; escenario bajo umbral sin caso."
  record_summary "$FINAL_STATUS" "$FINAL_DETAIL"
  log_info "$TEST_ID PASSED. Evidencia real: $EVIDENCE_DIR"
}

main "$@"
