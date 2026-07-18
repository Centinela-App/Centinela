#!/usr/bin/env bash
# TEST-S1-023 (posterior): staging escribe solo en su contenedor.
# Requiere ISS-S1-009 para cerrar el aislamiento funcional completo de Semana 1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_cmd curl
require_cmd jq
require_cmd az

: "${CENTINELA_STAGING_API_BASE_URL:?Define CENTINELA_STAGING_API_BASE_URL}"
: "${CENTINELA_SERVICE_TOKEN:?Define CENTINELA_SERVICE_TOKEN}"
: "${CENTINELA_STORAGE_ACCOUNT:?Define CENTINELA_STORAGE_ACCOUNT}"

readonly STAGING_CONTAINER="raw-transactions-staging"
readonly PRODUCTION_CONTAINER="raw-transactions-production"
transaction_id="isolation-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
tmp_dir="$(mktemp -d)"
response_file="$tmp_dir/response.json"
blob_name=""

cleanup() {
  local rc=$?
  if [ -n "$blob_name" ]; then
    az storage blob delete \
      --account-name "$CENTINELA_STORAGE_ACCOUNT" \
      --container-name "$STAGING_CONTAINER" \
      --name "$blob_name" \
      --auth-mode login \
      --only-show-errors >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
  exit "$rc"
}
trap cleanup EXIT

payload="$(cat <<JSON
{
  "transactionId": "$transaction_id",
  "accountId": "acct-isolation-synthetic",
  "amount": 1000.00,
  "currency": "COP",
  "occurredAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "location": {"countryCode": "CO", "city": "Bogota"},
  "merchant": {"name": "Comercio Sintetico", "category": "RETAIL"}
}
JSON
)"

status="$(curl --silent --show-error \
  --output "$response_file" \
  --write-out '%{http_code}' \
  --request POST \
  --header "Authorization: Bearer $CENTINELA_SERVICE_TOKEN" \
  --header 'Content-Type: application/json' \
  --data "$payload" \
  "${CENTINELA_STAGING_API_BASE_URL%/}/api/v1/transactions")"
[ "$status" = "202" ] || die "Staging devolvio HTTP $status; se esperaba 202."

blob_name="$(az storage blob list \
  --account-name "$CENTINELA_STORAGE_ACCOUNT" \
  --container-name "$STAGING_CONTAINER" \
  --auth-mode login \
  --query "[?ends_with(name, '/${transaction_id}.json')].name | [0]" \
  --output tsv --only-show-errors)"
[ -n "$blob_name" ] || die "La transaccion no aparecio en $STAGING_CONTAINER."

production_match="$(az storage blob list \
  --account-name "$CENTINELA_STORAGE_ACCOUNT" \
  --container-name "$PRODUCTION_CONTAINER" \
  --auth-mode login \
  --query "[?ends_with(name, '/${transaction_id}.json')].name | [0]" \
  --output tsv --only-show-errors)"
[ -z "$production_match" ] \
  || die "La transaccion de staging aparecio indebidamente en produccion."

printf 'PASS TEST-S1-023: staging escribio solo en %s.\n' "$STAGING_CONTAINER"
