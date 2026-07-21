#!/usr/bin/env bash
# deploy-week1.sh — orquestador de despliegue de Semana 1.
# Modos: --validate-only (no crea nada) | normal (ejecuta el registro de pasos).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

VALIDATE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --validate-only) VALIDATE_ONLY=1 ;;
    -h|--help) echo "Uso: $0 [--validate-only]"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

# Registro de pasos (Opcion A). Las issues 003-006 agregan sus scripts aqui.
PROVISION_STEPS=(
  "provision-storage.sh"            # ISS-S1-003
  "provision-app-service.sh"        # ISS-S1-004
  "provision-network.sh"            # ISS-S1-005
  "configure-private-endpoints.sh"  # ISS-S1-005
)

main() {
  load_parameters
  validate_parameters               # fail-fast offline: falla ANTES de tocar Azure

  require_cmd az
  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  local active_sub; active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  local loc_display; loc_display="$(az account list-locations --query "[?name=='$LOCATION'] | [0].displayName" -o tsv)"
  [ -n "$loc_display" ] || die "Region '$LOCATION' no valida/disponible."
  # appservice list-locations usa el nombre display ("East US 2"), no el corto.
  az appservice list-locations --sku "$APP_SERVICE_SKU" --query "[?name=='$loc_display'] | [0].name" -o tsv | grep -q . \
    || die "SKU '$APP_SERVICE_SKU' no disponible en '$LOCATION' o sin soporte de slots/escala."

  log_info "Plan de despliegue:"
  log_info "  Suscripcion   : $(mask "$SUBSCRIPTION_ID")"
  log_info "  Region        : $LOCATION"
  log_info "  Resource Group: $RESOURCE_GROUP"
  log_info "  Name prefix   : $NAME_PREFIX"
  log_info "  App SKU       : $APP_SERVICE_SKU"
  log_warn "AVISO DE COSTOS: consume el credito compartido de USD 200. Ejecuta destroy-week1.sh al terminar."

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "--validate-only: entorno valido. No se crea ningun recurso."
    return 0
  fi

  log_info "Creando/asegurando Resource Group '$RESOURCE_GROUP'..."
  with_retry 3 az group create --name "$RESOURCE_GROUP" --location "$LOCATION" \
    --tags project=centinela week=1 team=celula-centinela --output none

  for step in "${PROVISION_STEPS[@]}"; do
    if [ -f "$SCRIPT_DIR/$step" ]; then
      log_info "Ejecutando paso: $step"; bash "$SCRIPT_DIR/$step"
    else
      log_warn "Paso pendiente (issue futura): $step"
    fi
  done
  log_info "Despliegue base completado."
}

main
