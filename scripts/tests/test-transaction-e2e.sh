#!/usr/bin/env bash
# TEST-S1-016 (posterior): API desplegada -> caso de uso -> Blob -> 202.
# Requiere red con acceso al Private Endpoint, token SERVICE y Azure CLI autenticado.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_cmd curl
require_cmd jq
require_cmd az

: "${CENTINELA_API_BASE_URL:?Define CENTINELA_API_BASE_URL}"
: "${CENTINELA_SERVICE_TOKEN:?Define CENTINELA_SERVICE_TOKEN}"
: "${CENTINELA_STORAGE_ACCOUNT:?Define CENTINELA_STORAGE_ACCOUNT}"
: "${CENTINELA_RAW_TRANSACTIONS_CONTAINER:?Define CENTINELA_RAW_TRANSACTIONS_CONTAINER}"

az account show >/dev/null 2>&1 || die "No hay sesion Azure activa. Ejecuta az login."

transaction_id="e2e-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
tmp_dir="$(mktemp -d)"
response_file="$tmp_dir/response.json"
payload_file="$tmp_dir/request.json"
blob_file="$tmp_dir/blob.json"
blob_name=""

cleanup() {
  local rc=$?
  if [ -n "$blob_name" ]; then
    az storage blob delete \
      --account-name "$CENTINELA_STORAGE_ACCOUNT" \
      --container-name "$CENTINELA_RAW_TRANSACTIONS_CONTAINER" \
      --name "$blob_name" \
      --auth-mode login \
      --only-show-errors >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
  exit "$rc"
}
trap cleanup EXIT

cat > "$payload_file" <<JSON
{
  "transactionId": "$transaction_id",
  "accountId": "acct-e2e-synthetic",
  "amount": 125000.25,
  "currency": "COP",
  "occurredAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "location": {
    "countryCode": "CO",
    "city": "Bogota"
  },
  "merchant": {
    "name": "Comercio Sintetico",
    "category": "RETAIL"
  }
}
JSON

http_status="$(curl --silent --show-error \
  --output "$response_file" \
  --write-out '%{http_code}' \
  --request POST \
  --header "Authorization: Bearer $CENTINELA_SERVICE_TOKEN" \
  --header 'Content-Type: application/json' \
  --data-binary "@$payload_file" \
  "${CENTINELA_API_BASE_URL%/}/api/v1/transactions")"

[ "$http_status" = "202" ] || die "La API devolvio HTTP $http_status; se esperaba 202."
[ "$(jq -r '.transactionId' "$response_file")" = "$transaction_id" ] \
  || die "El recibo no contiene el transactionId esperado."
[ "$(jq -r '.status' "$response_file")" = "RECEIVED" ] \
  || die "El recibo no contiene status=RECEIVED."

blob_name="$(az storage blob list \
  --account-name "$CENTINELA_STORAGE_ACCOUNT" \
  --container-name "$CENTINELA_RAW_TRANSACTIONS_CONTAINER" \
  --auth-mode login \
  --query "[?ends_with(name, '/${transaction_id}.json')].name | [0]" \
  --output tsv \
  --only-show-errors)"

[ -n "$blob_name" ] || die "No se encontro el Blob de la transaccion despues del 202."

az storage blob download \
  --account-name "$CENTINELA_STORAGE_ACCOUNT" \
  --container-name "$CENTINELA_RAW_TRANSACTIONS_CONTAINER" \
  --name "$blob_name" \
  --file "$blob_file" \
  --auth-mode login \
  --overwrite true \
  --only-show-errors >/dev/null

[ "$(jq -r '.transactionId' "$blob_file")" = "$transaction_id" ] \
  || die "El Blob no contiene la transaccion esperada."

for forbidden in score decision rules caseId; do
  jq -e --arg field "$forbidden" 'has($field) | not' "$blob_file" >/dev/null \
    || die "El Blob contiene el campo futuro '$forbidden'."
done

printf 'PASS TEST-S1-016: HTTP 202 emitido despues de crear %s/%s\n' \
  "$CENTINELA_RAW_TRANSACTIONS_CONTAINER" "$blob_name"
