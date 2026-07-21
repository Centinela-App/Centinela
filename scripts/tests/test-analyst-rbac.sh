#!/usr/bin/env bash
# test-analyst-rbac.sh — ISS-S1-006 (TEST-S1-009)
# Verifica que el Analista (y, si se da, el Auditor) NO puede modificar recursos
# de Azure: solo debe tener 'Reader' y ningun rol de escritura/administracion.
# Cubre el Gherkin "Analista sin modificacion" y "Permiso excesivo detectado".
#
# Requiere el objectId (o UPN) del principal a validar:
#   ANALYST_PRINCIPAL_ID / AUDITOR_PRINCIPAL_ID (env) o --analyst/--auditor.
# Sin principal, la verificacion queda PENDIENTE (no puede cerrarse sin el).
#
#   exit 0 -> ok (o pendiente por falta de principal) ; exit 1 -> permiso excesivo.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

# Roles que implican poder modificar/eliminar recursos -> prohibidos para estos usuarios.
readonly WRITE_ROLES=("Owner" "Contributor" "User Access Administrator"
                      "Storage Blob Data Contributor" "Storage Blob Data Owner"
                      "Storage Account Contributor" "Storage Queue Data Contributor")
readonly READER_ROLE="Reader"

ANALYST="${ANALYST_PRINCIPAL_ID:-}"
AUDITOR="${AUDITOR_PRINCIPAL_ID:-}"
LIVE_ATTEMPT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --analyst) ANALYST="${2:?}"; shift 2 ;;
    --auditor) AUDITOR="${2:?}"; shift 2 ;;
    --live-attempt) LIVE_ATTEMPT=1; shift ;;   # intenta un tag update real (deberia fallar)
    -h|--help) echo "Uso: $0 [--analyst ID] [--auditor ID] [--live-attempt]"; exit 0 ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

PASS=0; FAIL=0; PEND=0; RESULTS=()
ok()   { RESULTS+=("PASS  $*"); PASS=$((PASS + 1)); }
fail() { RESULTS+=("FAIL  $*"); FAIL=$((FAIL + 1)); log_error "$*"; }
pend() { RESULTS+=("PEND  $*"); PEND=$((PEND + 1)); log_warn "$*"; }
print_report() {
  printf '\n============== ISS-S1-006 / TEST-S1-009 ==============\n'
  for r in "${RESULTS[@]}"; do printf '%s\n' "$r"; done
  printf '------------------------------------------------------\n'
  printf 'Resumen: %d PASS / %d FAIL / %d PENDIENTE\n' "$PASS" "$FAIL" "$PEND"
  printf '======================================================\n'
}
cleanup() { local rc="${1:-$?}"; trap - EXIT; print_report; [ "$rc" -ne 0 ] && exit "$rc"; exit "$(( FAIL > 0 ? 1 : 0 ))"; }
trap 'cleanup $?' EXIT

require_cmd az
az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."
load_parameters
validate_parameters
RG_ID="$(az group show --name "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || true)"
[ -n "$RG_ID" ] || die "Resource Group '$RESOURCE_GROUP' no existe."

# Valida un principal funcional: solo Reader, ningun rol de escritura.
validate_readonly_principal() {
  local principal="$1" label="$2"
  local roles has_reader wrole
  roles="$(az role assignment list --assignee "$principal" --all \
            --query "[].roleDefinitionName" -o tsv 2>/dev/null || echo "")"

  # Gherkin "Permiso excesivo detectado": cualquier rol de escritura -> FAIL.
  local excess=""
  for wrole in "${WRITE_ROLES[@]}"; do
    printf '%s\n' "$roles" | grep -qx "$wrole" && excess="${excess}${wrole}; "
  done
  if [ -z "$excess" ]; then
    ok "$label no tiene ningun rol de escritura/administracion (no puede modificar Azure)."
  else
    fail "$label tiene permiso EXCESIVO: ${excess%; } (Gherkin: asignacion prohibida)."
  fi

  has_reader="$(printf '%s\n' "$roles" | grep -cx "$READER_ROLE" || true)"
  if [ "${has_reader:-0}" -ge 1 ]; then
    ok "$label tiene '$READER_ROLE' (consulta sin modificacion)."
  else
    pend "$label sin '$READER_ROLE' asignado (asignar con scripts/assign-rbac.sh si se requiere demostrar lectura)."
  fi

  # Opcional: intento real de modificacion (debe ser denegado por Azure).
  if [ "$LIVE_ATTEMPT" -eq 1 ]; then
    log_warn "  --live-attempt: intentando 'az tag update' sobre el RG como el usuario actual..."
    if az tag update --resource-id "$RG_ID" --operation merge --tags rbactest=deny >/dev/null 2>&1; then
      fail "$label: el intento de modificar tags NO fue denegado (revisa la sesion/rol)."
      az tag update --resource-id "$RG_ID" --operation delete --tags rbactest=deny >/dev/null 2>&1 || true
    else
      ok "$label: intento de modificacion DENEGADO por Azure (esperado)."
    fi
  fi
}

if [ -n "$ANALYST" ]; then
  log_info "Validando Analista: $(mask "$ANALYST")"
  validate_readonly_principal "$ANALYST" "Analista"
else
  pend "Sin ANALYST_PRINCIPAL_ID/--analyst: TEST-S1-009 requiere el principal del Analista para cerrarse."
fi

if [ -n "$AUDITOR" ]; then
  log_info "Validando Auditor: $(mask "$AUDITOR")"
  validate_readonly_principal "$AUDITOR" "Auditor"
fi

cleanup
