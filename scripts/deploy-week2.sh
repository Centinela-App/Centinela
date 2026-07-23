#!/usr/bin/env bash
# deploy-week2.sh — orquestador de despliegue de Semana 2.
# Modos: --validate-only (no crea nada) | normal (ejecuta el registro de pasos).
#
# Semana 2 asume que Semana 1 ya esta desplegada (Resource Group, red, Storage,
# App Service). Este orquestador solo agrega los recursos del motor de scoring y
# los almacenes de datos, en orden de dependencia.
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

# Registro de pasos de Semana 2. Cada issue agrega su script aqui en orden de dependencia.
PROVISION_STEPS=(
  "provision-cosmos.sh"      # ISS-S2-001  almacen de transacciones (Cosmos/Mongo)
  "provision-postgres.sh"    # ISS-S2-002  almacen de casos (PostgreSQL privado)
  "provision-keyvault.sh"    # ISS-S2-003  gestor de secretos
  "provision-eventgrid.sh"   # ISS-S2-005  mensajeria (evento + cola de casos)
)

main() {
  load_parameters
  validate_parameters

  require_cmd az
  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  local active_sub; active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "Resource Group '$RESOURCE_GROUP' no existe. Despliega primero Semana 1 (deploy-week1.sh)."

  log_info "Plan de despliegue de Semana 2:"
  log_info "  Suscripcion   : $(mask "$SUBSCRIPTION_ID")"
  log_info "  Region        : $LOCATION"
  log_info "  Resource Group: $RESOURCE_GROUP"
  log_info "  Name prefix   : $NAME_PREFIX"
  log_warn "AVISO DE COSTOS: el motor de scoring corre una vez por transaccion. Apaga recursos al cierre de jornada."

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "--validate-only: entorno valido. No se crea ningun recurso."
    return 0
  fi

  for step in "${PROVISION_STEPS[@]}"; do
    if [ -f "$SCRIPT_DIR/$step" ]; then
      log_info "Ejecutando paso: $step"; bash "$SCRIPT_DIR/$step"
    else
      log_warn "Paso pendiente (issue futura): $step"
    fi
  done
  log_info "Despliegue de Semana 2 completado."
}

main
