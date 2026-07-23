#!/usr/bin/env bash
# deploy-week2.sh — orquestador de despliegue de Semana 2.
#
# Mismo contrato que deploy-week1.sh: un REGISTRO de pasos donde cada issue de
# aprovisionamiento inscribe su script. Un paso todavia no implementado se reporta
# como pendiente y no rompe la corrida (permite desplegar el subconjunto listo).
#
# Semana 2 NO crea el Resource Group ni la red: los consume de Semana 1. Si la
# infraestructura base no existe, falla antes de tocar Azure.
#
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

# Registro de pasos en orden de dependencia. Las issues 001-011 agregan sus
# scripts aqui. ISS-S2-004 (contratos) y ISS-S2-006 (API) no aprovisionan
# infraestructura: viajan en el codigo via deploy-application.sh.
PROVISION_STEPS=(
  "provision-cosmos.sh"           # ISS-S2-001 (Cosmos for MongoDB: shard key + TTL)
  "provision-postgres.sh"         # ISS-S2-002 (PostgreSQL privado + respaldo)
  "provision-keyvault.sh"         # ISS-S2-003 (Key Vault + secreto de Cosmos)
  "provision-eventgrid.sh"        # ISS-S2-005 (Event Grid Topic + colas de casos + RBAC)
  "deploy-scoring-function.sh"    # ISS-S2-007 (Function de scoring + suscripcion del topico)
)

main() {
  load_parameters
  validate_parameters               # fail-fast offline: falla ANTES de tocar Azure

  require_cmd az
  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  local active_sub; active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  # Semana 2 se apoya en Semana 1: el RG debe existir, no se crea aqui.
  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "Resource Group '$RESOURCE_GROUP' no existe. Ejecuta primero deploy-week1.sh."

  log_info "Plan de despliegue (Semana 2):"
  log_info "  Suscripcion   : $(mask "$SUBSCRIPTION_ID")"
  log_info "  Region        : $LOCATION"
  log_info "  Resource Group: $RESOURCE_GROUP"
  log_info "  Name prefix   : $NAME_PREFIX"

  local pending=()
  local step
  for step in "${PROVISION_STEPS[@]}"; do
    [ -f "$SCRIPT_DIR/$step" ] || pending+=("$step")
  done
  if [ "${#pending[@]}" -gt 0 ]; then
    log_warn "Pasos pendientes (issues aun no implementadas): ${pending[*]}"
  fi

  log_warn "AVISO DE COSTOS: Semana 2 agrega Cosmos, PostgreSQL, Key Vault y Event Grid."
  log_warn "El motor de scoring corre una vez por transaccion. Ejecuta destroy-week1.sh al terminar la jornada."

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
