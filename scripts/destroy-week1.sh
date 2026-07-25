#!/usr/bin/env bash
# destroy-week1.sh — elimina el Resource Group de Semana 1 con confirmacion segura.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

ASSUME_YES=0
KEEP_ENTRA=0
WAIT_FOR_DELETE=0
DESTROY_TIMEOUT_SECONDS="${DESTROY_TIMEOUT_SECONDS:-1800}"
DESTROY_POLL_SECONDS="${DESTROY_POLL_SECONDS:-10}"

usage() {
  cat <<USAGE
Uso: $0 [--yes] [--keep-entra] [--wait]

  --yes         Confirma automaticamente la eliminacion.
  --keep-entra  Conserva la App Registration de Entra.
  --wait        Espera y verifica que el Resource Group desaparezca.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes|--force) ASSUME_YES=1; shift ;;
    --keep-entra) KEEP_ENTRA=1; shift ;;
    --wait) WAIT_FOR_DELETE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

cleanup_entra_app() {
  if [ "$KEEP_ENTRA" -eq 1 ]; then
    log_info "--keep-entra: se conserva la App Registration de Entra."
    return 0
  fi

  local display_name app_id remaining_app_id
  display_name="${ENTRA_APP_DISPLAY_NAME:-${NAME_PREFIX}-api-week1}"
  app_id="$(az ad app list --display-name "$display_name" --query "[0].appId" -o tsv 2>/dev/null || true)"

  if [ -z "$app_id" ] || [ "$app_id" = "None" ]; then
    log_info "No hay App Registration '$display_name' que eliminar."
    return 0
  fi

  log_warn "Eliminando App Registration '$display_name' (appId $(mask "$app_id")) y su Service Principal..."
  az ad app delete --id "$app_id" >/dev/null

  local started_at elapsed
  started_at="$(date +%s)"
  while true; do
    remaining_app_id="$(az ad app list --display-name "$display_name" --query "[0].appId" -o tsv 2>/dev/null || true)"
    if [ -z "$remaining_app_id" ] || [ "$remaining_app_id" = "None" ]; then
      log_info "App Registration eliminada y verificada."
      return 0
    fi

    elapsed=$(( $(date +%s) - started_at ))
    if [ "$elapsed" -ge "$DESTROY_TIMEOUT_SECONDS" ]; then
      die "Timeout: la App Registration '$display_name' aun existe despues de ${DESTROY_TIMEOUT_SECONDS}s."
    fi
    sleep "$DESTROY_POLL_SECONDS"
  done
}

wait_for_resource_group_deletion() {
  local started_at elapsed exists
  started_at="$(date +%s)"

  log_info "Esperando eliminacion completa del Resource Group '$RESOURCE_GROUP'..."
  while true; do
    exists="$(az group exists --name "$RESOURCE_GROUP" -o tsv 2>/dev/null || echo true)"
    if [ "$exists" = "false" ]; then
      log_info "Resource Group eliminado y verificado."
      return 0
    fi

    elapsed=$(( $(date +%s) - started_at ))
    if [ "$elapsed" -ge "$DESTROY_TIMEOUT_SECONDS" ]; then
      die "Timeout: el Resource Group sigue existiendo despues de ${DESTROY_TIMEOUT_SECONDS}s."
    fi

    sleep "$DESTROY_POLL_SECONDS"
  done
}

main() {
  load_parameters
  validate_parameters

  log_warn "Vas a ELIMINAR el Resource Group '$RESOURCE_GROUP' y TODOS sus recursos."
  if [ "$ASSUME_YES" -eq 1 ]; then
    log_warn "--yes activo: confirmacion automatica."
  else
    printf 'Para confirmar, teclea EXACTAMENTE el nombre del Resource Group: ' >&2
    read -r typed
    [ "$typed" = "$RESOURCE_GROUP" ] \
      || die "El nombre '$typed' no coincide con '$RESOURCE_GROUP'. Abortado sin borrar."
  fi

  require_cmd az
  az account show >/dev/null 2>&1 || die "No hay sesion Azure activa. Ejecuta 'az login'."

  local active_sub
  active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "Eliminando Resource Group '$RESOURCE_GROUP'..."
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    log_info "Eliminacion del RG iniciada."
    if [ "$WAIT_FOR_DELETE" -eq 1 ]; then
      wait_for_resource_group_deletion
    else
      log_warn "La eliminacion continua en Azure. Usa --wait para confirmar que termino."
    fi
  else
    log_info "El Resource Group '$RESOURCE_GROUP' no existe. Nada que eliminar en el RG."
  fi

  cleanup_entra_app
}

main "$@"
