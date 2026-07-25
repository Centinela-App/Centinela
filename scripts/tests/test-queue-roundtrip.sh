#!/usr/bin/env bash
# TEST-S1-020: escritura, lectura y eliminacion de un mensaje tecnico en Queue Storage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

ENVIRONMENT="${1:-}"
case "$ENVIRONMENT" in
  staging|production) ;;
  *) die "Uso: $0 <staging|production>" ;;
esac

MAX_RETRIES="${MAX_RETRIES:-10}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-3}"
VISIBILITY_TIMEOUT_SECONDS="${VISIBILITY_TIMEOUT_SECONDS:-5}"
SKIP_PRIVATE_DNS_CHECK="${SKIP_PRIVATE_DNS_CHECK:-0}"

RUN_ID="run-$(date -u +%Y%m%dT%H%M%SZ)-${ENVIRONMENT}-$RANDOM"
EVIDENCE_DIR="$SCRIPT_DIR/../../docs/evidence/queue/$RUN_ID"
mkdir -p "$EVIDENCE_DIR"

MESSAGE_ID=""
POP_RECEIPT=""
MESSAGE_DELETED=0
TEST_RUN_ID="$(date +%s)-$RANDOM"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
MESSAGE_BODY="$(jq -cn \
  --arg testRunId "$TEST_RUN_ID" \
  --arg environment "$ENVIRONMENT" \
  --arg createdAt "$CREATED_AT" \
  '{testRunId:$testRunId,environment:$environment,createdAt:$createdAt}')"

compute_storage_account_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%sst%s' "$prefix" "$hash"
}

is_private_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^10\. ]] ||
  [[ "$ip" =~ ^192\.168\. ]] ||
  [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]
}

verify_private_queue_dns() {
  [ "$SKIP_PRIVATE_DNS_CHECK" -eq 1 ] && {
    log_warn "SKIP_PRIVATE_DNS_CHECK=1: se omite la comprobacion DNS privada."
    return 0
  }

  local host="${STORAGE_ACCOUNT}.queue.core.windows.net"
  local addresses=""

  if command -v getent >/dev/null 2>&1; then
    addresses="$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u || true)"
  elif command -v nslookup >/dev/null 2>&1; then
    addresses="$(nslookup "$host" 2>/dev/null | awk '/^Address: /{print $2}' | sort -u || true)"
  else
    die "No hay getent ni nslookup para comprobar que Queue resuelve por Private Endpoint."
  fi

  [ -n "$addresses" ] || die "No se pudo resolver '$host'. Revisa la zona DNS privada."
  printf '%s\n' "$addresses" > "$EVIDENCE_DIR/dns-addresses.txt"

  local ip
  while IFS= read -r ip; do
    if is_private_ipv4 "$ip"; then
      log_info "DNS privado verificado: $host -> $ip"
      return 0
    fi
  done <<< "$addresses"

  die "'$host' no resolvio a una IP privada. Ejecuta la prueba desde un host conectado a la VNet o usa Cloud Shell inyectado en la VNet."
}

record_summary() {
  local status="$1" detail="$2"
  jq -n \
    --arg runId "$RUN_ID" \
    --arg testId "TEST-S1-020" \
    --arg environment "$ENVIRONMENT" \
    --arg queue "$QUEUE_NAME" \
    --arg testRunId "$TEST_RUN_ID" \
    --arg messageId "${MESSAGE_ID:-not-available}" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg commit "$(git rev-parse HEAD 2>/dev/null || echo N/A)" \
    '{runId:$runId,testId:$testId,environment:$environment,queue:$queue,testRunId:$testRunId,messageId:$messageId,status:$status,detail:$detail,timestamp:$timestamp,commit:$commit}' \
    > "$EVIDENCE_DIR/summary.json"
}

cleanup_own_message() {
  local rc=$?
  if [ "$MESSAGE_DELETED" -eq 0 ] && [ -n "$MESSAGE_ID" ] && [ -n "$POP_RECEIPT" ]; then
    log_warn "Intentando eliminar el mensaje tecnico durante la limpieza..."
    az storage message delete \
      --queue-name "$QUEUE_NAME" \
      --id "$MESSAGE_ID" \
      --pop-receipt "$POP_RECEIPT" \
      --account-name "$STORAGE_ACCOUNT" \
      --auth-mode login \
      --only-show-errors >/dev/null 2>&1 || true
  fi

  if [ "$rc" -ne 0 ] && [ ! -f "$EVIDENCE_DIR/summary.json" ]; then
    record_summary "FAILED" "La prueba termino antes de completar el roundtrip."
  fi
  return "$rc"
}

find_own_message() {
  local response_file="$1"
  jq -r --arg runId "$TEST_RUN_ID" '
    .[]
    | select((.content | fromjson? | .testRunId // "") == $runId)
    | [.id, .popReceipt]
    | @tsv
  ' "$response_file" | head -n 1
}

main() {
  require_cmd az
  require_cmd jq
  require_cmd sha1sum

  load_parameters
  validate_parameters

  az account show >/dev/null 2>&1 || die "No hay sesion Azure activa. Ejecuta az login."
  local active_sub
  active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  local default_storage
  default_storage="$(compute_storage_account_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  if [ "$ENVIRONMENT" = "staging" ]; then
    STORAGE_ACCOUNT="${STAGING_STORAGE_ACCOUNT:-$default_storage}"
    QUEUE_NAME="${STAGING_QUEUE_NAME:-transactions-ingestion-staging}"
  else
    STORAGE_ACCOUNT="${PRODUCTION_STORAGE_ACCOUNT:-$default_storage}"
    QUEUE_NAME="${PRODUCTION_QUEUE_NAME:-transactions-ingestion-production}"
  fi

  trap cleanup_own_message EXIT

  local public_network
  public_network="$(az storage account show \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query publicNetworkAccess -o tsv)"
  [ "$public_network" = "Disabled" ] \
    || die "El Storage debe conservar publicNetworkAccess=Disabled (actual: $public_network)."

  verify_private_queue_dns

  cat > "$EVIDENCE_DIR/payload.json" <<JSON
$MESSAGE_BODY
JSON

  log_info "Enviando mensaje tecnico a '$QUEUE_NAME' ($ENVIRONMENT)..."
  az storage message put \
    --queue-name "$QUEUE_NAME" \
    --content "$MESSAGE_BODY" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --only-show-errors -o json > "$EVIDENCE_DIR/send-response.json"

  MESSAGE_ID="$(jq -r '.id // empty' "$EVIDENCE_DIR/send-response.json")"
  POP_RECEIPT="$(jq -r '.popReceipt // empty' "$EVIDENCE_DIR/send-response.json")"
  [ -n "$MESSAGE_ID" ] || die "Azure no devolvio el id del mensaje enviado."

  local attempt match response_file found=0
  response_file="$EVIDENCE_DIR/receive-response.json"
  for attempt in $(seq 1 "$MAX_RETRIES"); do
    az storage message get \
      --queue-name "$QUEUE_NAME" \
      --num-messages 32 \
      --visibility-timeout "$VISIBILITY_TIMEOUT_SECONDS" \
      --account-name "$STORAGE_ACCOUNT" \
      --auth-mode login \
      --only-show-errors -o json > "$response_file"

    match="$(find_own_message "$response_file")"
    if [ -n "$match" ]; then
      MESSAGE_ID="${match%%$'\t'*}"
      POP_RECEIPT="${match#*$'\t'}"
      found=1
      log_info "Mensaje del run recuperado en el intento $attempt."
      break
    fi

    log_warn "Intento $attempt/$MAX_RETRIES: el mensaje del run aun no aparece."
    sleep "$RETRY_DELAY_SECONDS"
  done

  [ "$found" -eq 1 ] || die "No se recupero el mensaje con testRunId=$TEST_RUN_ID."

  az storage message delete \
    --queue-name "$QUEUE_NAME" \
    --id "$MESSAGE_ID" \
    --pop-receipt "$POP_RECEIPT" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --only-show-errors >/dev/null
  MESSAGE_DELETED=1

  sleep 1
  az storage message peek \
    --queue-name "$QUEUE_NAME" \
    --num-messages 32 \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login \
    --only-show-errors -o json > "$EVIDENCE_DIR/post-delete-peek.json"

  if jq -e --arg id "$MESSAGE_ID" '.[] | select(.id == $id)' "$EVIDENCE_DIR/post-delete-peek.json" >/dev/null; then
    die "El mensaje propio sigue visible despues de eliminarlo."
  fi

  record_summary "PASSED" "Mensaje enviado, recuperado por testRunId, eliminado con pop receipt y sin residuo propio."
  log_info "TEST-S1-020 PASSED. Evidencia: $EVIDENCE_DIR"
}

main "$@"
