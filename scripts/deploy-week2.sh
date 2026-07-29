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
  "configure-function-host-storage.sh" # ISS-S2-007 host Storage privado (Table)
  "configure-postgres-managed-identity.sh" # ISS-S2-002/010/011 principal DB + JDBC MI
)

main() {
  load_parameters
  validate_parameters

  require_cmd az
  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  local active_sub; active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  # En --validate-only el Resource Group todavia puede no existir: el ensayo en seco
  # debe poder correr en una maquina limpia, ANTES de desplegar Semana 1. Solo el
  # despliegue real exige que ya exista.
  if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    [ "$VALIDATE_ONLY" -eq 1 ] \
      || die "Resource Group '$RESOURCE_GROUP' no existe. Despliega primero Semana 1 (deploy-week1.sh)."
    log_warn "El Resource Group '$RESOURCE_GROUP' aun no existe; lo creara deploy-week1.sh. En --validate-only no es un error."
  fi

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
      log_info "Ejecutando paso: $step"
      # Se captura el codigo explicitamente: sin esto, un 'set -e' dentro del
      # sub-script aborta sin decir cual paso murio ni con que codigo.
      local step_status=0
      bash "$SCRIPT_DIR/$step" || step_status=$?
      if [ "$step_status" -ne 0 ]; then
        die "El paso '$step' fallo con codigo $step_status. Revisa el registro anterior a esta linea."
      fi
    else
      log_warn "Paso pendiente (issue futura): $step"
    fi
  done

  require_cmd mvn
  log_info "Verificando la app principal antes de desplegar el consumidor de casos..."
  (cd "$SCRIPT_DIR/.." && mvn -q clean verify)
  log_info "Desplegando primero en produccion para que Flyway aplique el esquema con su propia identidad..."
  bash "$SCRIPT_DIR/deploy-application.sh" --slot production
  log_info "Reaplicando grants sobre las tablas creadas por Flyway para la identidad de staging..."
  bash "$SCRIPT_DIR/configure-postgres-managed-identity.sh"
  log_info "Desplegando el mismo artefacto corregido en staging..."
  bash "$SCRIPT_DIR/deploy-application.sh" --slot staging

  log_info "Desplegando la Function de scoring cuando ambos consumidores ya estan disponibles..."
  bash "$SCRIPT_DIR/deploy-scoring-function.sh"
  log_info "Despliegue de Semana 2 completado."
}

main
