#!/usr/bin/env bash
# TEST-S1-019 (posterior): Analista -> API staging -> Blob documental -> 201.
# Requiere ISS-S1-011, API desplegada, token ANALYST y acceso al Storage privado.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

require_cmd curl
require_cmd jq
require_cmd az

: "${CENTINELA_API_BASE_URL:?Define CENTINELA_API_BASE_URL}"
: "${CENTINELA_ANALYST_TOKEN:?Define CENTINELA_ANALYST_TOKEN}"
: "${CENTINELA_STORAGE_ACCOUNT:?Define CENTINELA_STORAGE_ACCOUNT}"
: "${CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER:?Define CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER}"

az account show >/dev/null 2>&1 || die "No hay sesion Azure activa. Ejecuta az login."

tmp_dir="$(mktemp -d)"
request_file="$tmp_dir/verification-document.txt"
response_file="$tmp_dir/response.json"
downloaded_file="$tmp_dir/downloaded-document.txt"
blob_name=""

cleanup() {
  local rc=$?
  if [ -n "$blob_name" ]; then
    az storage blob delete \
      --account-name "$CENTINELA_STORAGE_ACCOUNT" \
      --container-name "$CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER" \
      --name "$blob_name" \
      --auth-mode login \
      --only-show-errors >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
  exit "$rc"
}
trap cleanup EXIT

printf 'synthetic verification document\n' > "$request_file"

http_status="$(curl --silent --show-error \
  --output "$response_file" \
  --write-out '%{http_code}' \
  --request POST \
  --header "Authorization: Bearer $CENTINELA_ANALYST_TOKEN" \
  --form "file=@${request_file};filename=verification-document.txt;type=text/plain" \
  "${CENTINELA_API_BASE_URL%/}/api/v1/verification-documents")"

[ "$http_status" = "201" ] || die "La API devolvio HTTP $http_status; se esperaba 201."
[ "$(jq -r '.status' "$response_file")" = "STORED" ] \
  || die "El recibo no contiene status=STORED."
jq -e 'has("caseId") | not' "$response_file" >/dev/null \
  || die "La respuesta contiene el campo prohibido caseId."

document_id="$(jq -r '.documentId // empty' "$response_file")"
[ -n "$document_id" ] || die "La respuesta no contiene documentId."

blob_name="$(az storage blob list \
  --account-name "$CENTINELA_STORAGE_ACCOUNT" \
  --container-name "$CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER" \
  --auth-mode login \
  --query "[?contains(name, '/${document_id}/')].name | [0]" \
  --output tsv \
  --only-show-errors)"

[ -n "$blob_name" ] || die "No se encontro el Blob del documento despues del 201."
case "$blob_name" in
  *"/${document_id}/verification-document.txt") ;;
  *) die "La ruta fisica del Blob no coincide con el contrato: $blob_name" ;;
esac

az storage blob download \
  --account-name "$CENTINELA_STORAGE_ACCOUNT" \
  --container-name "$CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER" \
  --name "$blob_name" \
  --file "$downloaded_file" \
  --auth-mode login \
  --overwrite true \
  --only-show-errors >/dev/null

cmp --silent "$request_file" "$downloaded_file" \
  || die "Los bytes descargados no coinciden con el documento enviado."

printf 'PASS TEST-S1-019: HTTP 201 y Blob %s/%s verificados.\n' \
  "$CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER" "$blob_name"
