#!/usr/bin/env bash
# validate-managed-identity.sh — ISS-S1-006 (TEST-S1-010)
# Verifica el MINIMO PRIVILEGIO de la Managed Identity de la Web App:
#   - Produccion y staging tienen 'Storage Blob Data Contributor' en SUS contenedores.
#   - NINGUNA de las dos identidades tiene rol alguno de Queue.
#   - NINGUNA tiene roles de administracion (Owner/Contributor/UAA).
# Consulta exclusivamente el control plane de Azure.
#
#   exit 0 -> ok ; exit 1 -> alguna verificacion fallo.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

readonly SLOT_NAME="staging"
readonly BLOB_DATA_ROLE="Storage Blob Data Contributor"
readonly PROD_CONTAINERS=("raw-transactions-production" "verification-documents-production")
readonly STAGING_CONTAINERS=("raw-transactions-staging" "verification-documents-staging")
readonly FORBIDDEN=("Owner" "Contributor" "User Access Administrator")

PASS=0; FAIL=0; RESULTS=()
ok()   { RESULTS+=("PASS  $*"); PASS=$((PASS + 1)); }
fail() { RESULTS+=("FAIL  $*"); FAIL=$((FAIL + 1)); log_error "$*"; }
print_report() {
  printf '\n============== ISS-S1-006 / TEST-S1-010 ==============\n'
  for r in "${RESULTS[@]}"; do printf '%s\n' "$r"; done
  printf '%s\n' '------------------------------------------------------'
  printf 'Resumen: %d PASS / %d FAIL\n' "$PASS" "$FAIL"
  printf '======================================================\n'
}
cleanup() { local rc="${1:-$?}"; trap - EXIT; print_report; [ "$rc" -ne 0 ] && exit "$rc"; exit "$(( FAIL > 0 ? 1 : 0 ))"; }
trap 'cleanup $?' EXIT

require_cmd az
az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."
load_parameters
validate_parameters
az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 || die "Resource Group '$RESOURCE_GROUP' no existe."

hash6() { printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6; }
SA_NAME="${NAME_PREFIX}st$(hash6)"
APP_NAME="${NAME_PREFIX}-app-$(hash6)"
RG="$RESOURCE_GROUP"
SA_ID="$(az storage account show --name "$SA_NAME" --resource-group "$RG" --query id -o tsv 2>/dev/null || true)"
[ -n "$SA_ID" ] || { fail "Storage '$SA_NAME' NO existe."; cleanup; }

PROD_PID="$(az webapp identity show --name "$APP_NAME" --resource-group "$RG" \
  --query principalId -o tsv 2>/dev/null || true)"
STAGING_PID="$(az webapp identity show --name "$APP_NAME" --resource-group "$RG" \
  --slot "$SLOT_NAME" --query principalId -o tsv 2>/dev/null || true)"
[ -n "$PROD_PID" ]    && ok "Produccion tiene Managed Identity." || fail "Produccion SIN Managed Identity."
[ -n "$STAGING_PID" ] && ok "Staging tiene Managed Identity."    || fail "Staging SIN Managed Identity."
[ -n "$PROD_PID" ] && [ -n "$STAGING_PID" ] || cleanup

# --- 1. Blob Data Contributor en los contenedores correctos --------------------
check_blob_role() {
  local pid="$1" label="$2"; shift 2
  local c scope n
  for c in "$@"; do
    scope="${SA_ID}/blobServices/default/containers/${c}"
    n="$(az role assignment list --assignee "$pid" --scope "$scope" --role "$BLOB_DATA_ROLE" \
          --query "length(@)" -o tsv 2>/dev/null || echo 0)"
    if [ "${n:-0}" -ge 1 ] 2>/dev/null; then
      ok "MI $label puede escribir Blob en '$c' (rol de datos, sin claves)."
    else
      fail "MI $label SIN '$BLOB_DATA_ROLE' en '$c'."
    fi
  done
}
check_blob_role "$PROD_PID"    "produccion" "${PROD_CONTAINERS[@]}"
check_blob_role "$STAGING_PID" "staging"    "${STAGING_CONTAINERS[@]}"

# --- 2. NINGUN rol de Queue en ninguna de las dos identidades ------------------
check_no_queue_and_no_admin() {
  local pid="$1" label="$2"
  local roles queue_hits admin_hits
  roles="$(az role assignment list --assignee "$pid" --all \
            --query "[].roleDefinitionName" -o tsv 2>/dev/null || echo "")"
  queue_hits="$(printf '%s\n' "$roles" | grep -i "queue" || true)"
  if [ -z "$queue_hits" ]; then
    ok "MI $label NO tiene ningun rol de Queue (correcto: cola fuera del negocio S1)."
  else
    fail "MI $label tiene rol(es) de Queue: $(printf '%s' "$queue_hits" | tr '\n' ',')"
  fi
  admin_hits=""
  local f
  for f in "${FORBIDDEN[@]}"; do
    printf '%s\n' "$roles" | grep -qx "$f" && admin_hits="${admin_hits}${f},"
  done
  if [ -z "$admin_hits" ]; then
    ok "MI $label sin roles de administracion (Owner/Contributor/UAA)."
  else
    fail "MI $label con rol de administracion prohibido: ${admin_hits%,}"
  fi
}
check_no_queue_and_no_admin "$PROD_PID"    "produccion"
check_no_queue_and_no_admin "$STAGING_PID" "staging"

cleanup
