#!/usr/bin/env bash
# destroy-week1.sh — elimina el Resource Group de Semana 1 con confirmacion segura.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --yes|--force) ASSUME_YES=1 ;;
    -h|--help) echo "Uso: $0 [--yes]"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

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
  if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "El Resource Group '$RESOURCE_GROUP' no existe. Nada que eliminar."; return 0
  fi
  log_info "Eliminando Resource Group '$RESOURCE_GROUP'..."
  az group delete --name "$RESOURCE_GROUP" --yes --no-wait
  log_info "Eliminacion iniciada (--no-wait)."
}

main
