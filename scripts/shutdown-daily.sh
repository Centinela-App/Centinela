#!/usr/bin/env bash
#
# scripts/shutdown-daily.sh
# Apagado al cierre de la jornada.
#
# El enunciado lo dice sin rodeos: el consumo de credito alcanza su punto maximo
# en la Semana 3, porque la generacion de carga, la construccion repetida de
# imagenes y la ingesta de telemetria consumen a la vez. Este script apaga lo
# que cuesta por hora y deja intacto lo que cuesta por uso.
#
# Que se apaga y que no:
#   - Container Apps        -> a cero replicas (facturan por vCPU-segundo)
#   - App Service Plan      -> detenido (factura por hora, es el mayor gasto)
#   - PostgreSQL            -> detenido (factura por hora)
#   - Cosmos, Storage, ACR  -> NO se tocan: facturan por almacenamiento y
#                              operaciones, y apagarlos significaria destruirlos
#
# Uso:
#   bash scripts/shutdown-daily.sh          # apagar
#   bash scripts/shutdown-daily.sh --start  # volver a encender

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

ACTION="stop"
for arg in "$@"; do
  case "$arg" in
    --start) ACTION="start" ;;
    --stop) ACTION="stop" ;;
    -h|--help) echo "Uso: $0 [--stop|--start]"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

main() {
  load_parameters
  validate_parameters
  require_cmd az
  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."

  if [ "$ACTION" = "stop" ]; then
    log_info "Apagando recursos que facturan por tiempo..."
    # min=0 apaga (cero replicas activas). max se deja en 1 y NO en 0: Container
    # Apps rechaza max=0 con "must be in the range [1,1000]". Con min=0/max=1 el
    # contenedor queda a cero replicas y solo podria levantar UNA si algo lo
    # invocara — no factura mientras no lo hagan, que es el objetivo del apagado.
    container_apps 0 1
    app_service stop
    postgres stop
    log_info "Apagado completo. Cosmos, Storage y ACR siguen activos: facturan por"
    log_info "almacenamiento, y apagarlos equivaldria a destruirlos."
  else
    log_info "Encendiendo recursos..."
    postgres start
    app_service start
    container_apps 1 10
    log_info "Encendido. La primera peticion tardara varios minutos: la aplicacion"
    log_info "arranca Spring Boot, aplica Flyway y abre la primera conexion a"
    log_info "PostgreSQL por Private Endpoint."
  fi
}

container_apps() {
  local minimo="$1" maximo="$2"
  local apps=("ca-${NAME_PREFIX}-api" "ca-${NAME_PREFIX}-scoring" "ca-${NAME_PREFIX}-explainer" "ca-${NAME_PREFIX}-lab")

  for app in "${apps[@]}"; do
    if az containerapp show -g "$RESOURCE_GROUP" -n "$app" >/dev/null 2>&1; then
      log_info "  $app -> replicas $minimo..$maximo"
      # El maximo tambien se pone a cero al apagar: dejarlo en 10 permitiria que
      # una regla de escalado levantara replicas por trafico residual.
      az containerapp update -g "$RESOURCE_GROUP" -n "$app" \
        --min-replicas "$minimo" --max-replicas "$maximo" --output none
    fi
  done
}

app_service() {
  local accion="$1"
  local plan_apps
  plan_apps="$(az webapp list -g "$RESOURCE_GROUP" --query '[].name' -o tsv 2>/dev/null || true)"
  [ -n "$plan_apps" ] || return 0

  while read -r app; do
    [ -z "$app" ] && continue
    log_info "  App Service '$app' -> $accion"
    az webapp "$accion" -g "$RESOURCE_GROUP" -n "$app" --output none 2>/dev/null || true
  done <<< "$plan_apps"
}

postgres() {
  local accion="$1"
  local servidores
  servidores="$(az postgres flexible-server list -g "$RESOURCE_GROUP" --query '[].name' -o tsv 2>/dev/null || true)"
  [ -n "$servidores" ] || return 0

  while read -r servidor; do
    [ -z "$servidor" ] && continue
    log_info "  PostgreSQL '$servidor' -> $accion"
    # Azure reinicia solo un servidor detenido a los 7 dias; para el horizonte
    # de este proyecto no supone problema.
    az postgres flexible-server "$accion" -g "$RESOURCE_GROUP" -n "$servidor" --output none 2>/dev/null \
      || log_warn "    No se pudo $accion (¿ya estaba en ese estado?)."
  done <<< "$servidores"
}

main "$@"
