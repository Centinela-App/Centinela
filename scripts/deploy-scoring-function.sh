#!/usr/bin/env bash
# scripts/deploy-scoring-function.sh
# ISS-S2-007 - Empaqueta y despliega el modulo scoring-function (Azure Functions Java).
#
# Alcance: SOLO el paquete/despliegue de la Function. NO provisiona el Function
# App, Event Grid ni RBAC (eso es de provision-*.sh / assign-rbac.sh); asume
# que esos recursos ya existen (dependencias ISS-S2-001, 003, 005).
#
# Uso:
#   scripts/deploy-scoring-function.sh [--validate-only]
#
# Variables (ver scripts/lib/parameters.sh) + especificas de esta issue:
#   SCORING_FUNCTION_APP_NAME  -> nombre del Function App destino (por defecto: <NAME_PREFIX>-scoring-fn)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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

main() {
  load_parameters
  validate_parameters
  require_cmd mvn
  require_cmd az

  local function_app="${SCORING_FUNCTION_APP_NAME:-${NAME_PREFIX}-scoring-fn}"
  local module_dir="$REPO_ROOT/scoring-function"
  [ -d "$module_dir" ] || die "No existe '$module_dir'. Ejecuta este script desde el repo con el modulo creado."

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  local active_sub; active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  az functionapp show --name "$function_app" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "El Function App '$function_app' no existe en '$RESOURCE_GROUP'. Provisionalo antes (fuera de alcance de este script)."

  log_info "Plan de despliegue de scoring-function:"
  log_info "  Function App  : $function_app"
  log_info "  Resource Group: $RESOURCE_GROUP"
  log_info "  Modulo        : $module_dir"

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "--validate-only: entorno valido. No se compila ni despliega nada."
    return 0
  fi

  log_info "Compilando y empaquetando (mvn clean package)..."
  (cd "$module_dir" && mvn -q clean package)

  log_info "Desplegando via azure-functions-maven-plugin (mvn azure-functions:deploy)..."
  (cd "$module_dir" && mvn -q azure-functions:deploy \
      -DfunctionAppName="$function_app" \
      -DfunctionResourceGroup="$RESOURCE_GROUP" \
      -DfunctionAppRegion="$LOCATION")

  log_info "Despliegue de scoring-function completado."
}

main
