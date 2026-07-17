#!/usr/bin/env bash
# validate-rbac.sh — ISS-S1-006 (comando de validacion §12; agrega TEST-S1-008/009/010)
# Ejecuta las tres validaciones de identidad/RBAC y agrega el resultado, ademas de
# un escaneo global de asignaciones de administracion en el Resource Group.
#
#   exit 0 -> todas pasaron ; exit 1 -> alguna fallo.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

require_cmd az
az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."
load_parameters
validate_parameters

FAILED=0
run_check() {
  local name="$1"; shift
  log_info "==== Ejecutando: $name ===="
  if bash "$SCRIPT_DIR/$name" "$@"; then
    log_info "==== $name: OK ===="
  else
    log_error "==== $name: FALLO ===="
    FAILED=1
  fi
}

run_check "validate-entra-roles.sh"
run_check "validate-managed-identity.sh"
run_check "test-analyst-rbac.sh"

# --- Escaneo global: asignaciones de administracion en el RG (informativo) -----
RG_ID="$(az group show --name "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || true)"
if [ -n "$RG_ID" ]; then
  log_info "==== Escaneo de asignaciones Owner/Contributor en el Resource Group ===="
  admins="$(az role assignment list --scope "$RG_ID" \
    --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='Contributor'].{p:principalName, r:roleDefinitionName, t:principalType}" \
    -o tsv 2>/dev/null || echo "")"
  if [ -z "$admins" ]; then
    log_info "Sin asignaciones Owner/Contributor a nivel de Resource Group."
  else
    log_warn "Asignaciones Owner/Contributor detectadas en el RG (revisar que no sean usuarios funcionales):"
    printf '%s\n' "$admins" | while IFS=$'\t' read -r p r t; do
      log_warn "  - $r  ($t)  $(mask "${p:-?}")"
    done
    log_warn "Nota: Analista/Auditor NO deben aparecer aqui (lo valida test-analyst-rbac.sh)."
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  log_info "ISS-S1-006 RBAC: TODAS las validaciones agregadas pasaron."
  exit 0
else
  log_error "ISS-S1-006 RBAC: al menos una validacion fallo (ver detalle arriba)."
  exit 1
fi
