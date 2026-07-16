#!/usr/bin/env bash
# validate-week1.sh — valida el entorno de despliegue sin crear recursos.
# Semana 1 (sin recursos aun): parametros + sesion az + region + SKU.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

main() {
  load_parameters
  validate_parameters

  require_cmd az
  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  log_info "Sesion de Azure activa."

  local loc_display
  loc_display="$(az account list-locations --query "[?name=='$LOCATION'] | [0].displayName" -o tsv)"
  [ -n "$loc_display" ] || die "Region '$LOCATION' no disponible."
  log_info "Region '$LOCATION' valida ($loc_display)."

  # appservice list-locations usa el nombre display ("East US 2"), no el corto.
  az appservice list-locations --sku "$APP_SERVICE_SKU" --query "[?name=='$loc_display'] | [0].name" -o tsv | grep -q . \
    || die "SKU '$APP_SERVICE_SKU' no disponible en '$LOCATION' o sin soporte de slots/escala."
  log_info "SKU '$APP_SERVICE_SKU' compatible con '$LOCATION'."

  log_info "Entorno validado. Listo para desplegar."
}

main
