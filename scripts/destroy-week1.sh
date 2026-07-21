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
for arg in "$@"; do
  case "$arg" in
    --yes|--force) ASSUME_YES=1 ;;
    --keep-entra)  KEEP_ENTRA=1 ;;   # no eliminar la App Registration de ISS-S1-006
    -h|--help) echo "Uso: $0 [--yes] [--keep-entra]"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

# La App Registration de Entra (ISS-S1-006) es de nivel de tenant: NO vive dentro
# del Resource Group, por lo que borrar el RG no la elimina. La limpiamos aparte
# para que "destruir, reconstruir, limpiar" (TEST-S1-027) quede realmente limpio.
cleanup_entra_app() {
  [ "$KEEP_ENTRA" -eq 1 ] && { log_info "--keep-entra: se conserva la App Registration de Entra."; return 0; }
  local display_name app_id
  display_name="${ENTRA_APP_DISPLAY_NAME:-${NAME_PREFIX}-api-week1}"
  app_id="$(az ad app list --display-name "$display_name" --query "[0].appId" -o tsv 2>/dev/null || true)"
  if [ -z "$app_id" ] || [ "$app_id" = "None" ]; then
    log_info "No hay App Registration '$display_name' que eliminar."
    return 0
  fi
  log_warn "Eliminando App Registration '$display_name' (appId $(mask "$app_id")) y su Service Principal..."
  az ad app delete --id "$app_id" >/dev/null 2>&1 \
    && log_info "App Registration eliminada." \
    || log_warn "No se pudo eliminar la App Registration (¿permisos de directorio?). Eliminala manualmente."
}

main() {
  load_parameters
  validate_parameters

  log_warn "Vas a ELIMINAR el Resource Group '$RESOURCE_GROUP' y TODOS sus recursos."
  if [ "$ASSUME_YES" -eq 1 ]; then
    log_warn "--yes activo: confirmacion automatica (modo automatizacion)."
  else
    printf 'Para confirmar, teclea EXACTAMENTE el nombre del Resource Group: ' >&2
    read -r typed
    [ "$typed" = "$RESOURCE_GROUP" ] \
      || die "El nombre '$typed' no coincide con '$RESOURCE_GROUP'. Abortado sin borrar."
  fi

  require_cmd az
  if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "Eliminando Resource Group '$RESOURCE_GROUP'..."
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    log_info "Eliminacion del RG iniciada (--no-wait). Incluye Storage, App Service,"
    log_info "red, Managed Identities y sus asignaciones RBAC (incluida la de prueba de cola)."
  else
    log_info "El Resource Group '$RESOURCE_GROUP' no existe. Nada que eliminar en el RG."
  fi

  # Limpieza tenant-level de la App Registration (fuera del RG).
  cleanup_entra_app
}

main
