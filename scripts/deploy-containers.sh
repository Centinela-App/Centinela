#!/usr/bin/env bash
#
# scripts/deploy-containers.sh
# ISS-S3-008 / ISS-S3-012 — Crea o actualiza las tres Container Apps.
#
# Lo invoca el pipeline de despliegue continuo tras publicar las imagenes, y
# tambien puede ejecutarse a mano para reconstruir el entorno desde cero. Es
# idempotente: la primera corrida crea, las siguientes actualizan la imagen.
#
# Las tres aplicaciones salen de DOS imagenes:
#   - centinela-api        (imagen de la aplicacion, papel: API + consulta)
#   - centinela-explainer  (misma imagen, papel: explicador + extractor documental)
#   - centinela-scoring    (imagen del motor de scoring)
#
# Que el explicador sea la misma imagen con otros interruptores es lo que hace
# trivial el escenario de fallo obligatorio de la sustentacion: detenerlo es
# `az containerapp update --min-replicas 0 --max-replicas 0`, sin tocar la API.
#
# NINGUN secreto viaja en este script. Las cadenas de conexion se referencian
# desde Key Vault mediante la identidad administrada de cada aplicacion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

IMAGE_TAG="${IMAGE_TAG:-latest}"

readonly API_CONCURRENT_REQUESTS="${CENTINELA_API_CONCURRENCY:-10}"
readonly API_MIN_REPLICAS="${CENTINELA_API_MIN_REPLICAS:-1}"
readonly API_MAX_REPLICAS="${CENTINELA_API_MAX_REPLICAS:-10}"
readonly SCORING_MIN_REPLICAS="${CENTINELA_SCORING_MIN_REPLICAS:-0}"
readonly SCORING_MAX_REPLICAS="${CENTINELA_SCORING_MAX_REPLICAS:-8}"
readonly EXPLAINER_MIN_REPLICAS="${CENTINELA_EXPLAINER_MIN_REPLICAS:-0}"
readonly EXPLAINER_MAX_REPLICAS="${CENTINELA_EXPLAINER_MAX_REPLICAS:-3}"
readonly CPU_PER_REPLICA="0.5"
readonly MEMORY_PER_REPLICA="1.0Gi"

usage() {
  cat <<'EOF'
Uso: deploy-containers.sh [--tag <etiqueta>] [--only api|scoring|explainer]

  --tag        Etiqueta de imagen a desplegar (por defecto: $IMAGE_TAG o 'latest').
  --only       Despliega una sola aplicacion.
EOF
}

ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) IMAGE_TAG="${2:?--tag requiere valor}"; shift 2 ;;
    --only) ONLY="${2:?--only requiere valor}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

main() {
  load_parameters
  validate_parameters
  require_cmd az

  local environment_name="cae-${NAME_PREFIX}"
  local registry_name="${NAME_PREFIX}acr"
  local identity_name="id-${NAME_PREFIX}-acrpull"

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."

  local registry_server identity_id
  registry_server="$(az acr show -n "$registry_name" -g "$RESOURCE_GROUP" --query loginServer -o tsv)" \
    || die "Falta el registro. Ejecuta provision-container-registry.sh."
  identity_id="$(az identity show -n "$identity_name" -g "$RESOURCE_GROUP" --query id -o tsv)" \
    || die "Falta la identidad de pull."

  az containerapp env show -g "$RESOURCE_GROUP" -n "$environment_name" >/dev/null 2>&1 \
    || die "Falta el entorno '$environment_name'. Ejecuta provision-container-apps.sh."

  log_info "Desplegando etiqueta '$IMAGE_TAG' desde $registry_server"

  [ -z "$ONLY" ] || [ "$ONLY" = "api" ] \
    && deploy_api "$environment_name" "$registry_server" "$identity_id"
  [ -z "$ONLY" ] || [ "$ONLY" = "scoring" ] \
    && deploy_scoring "$environment_name" "$registry_server" "$identity_id"
  [ -z "$ONLY" ] || [ "$ONLY" = "explainer" ] \
    && deploy_explainer "$environment_name" "$registry_server" "$identity_id"

  log_info "Despliegue completado."
}

# --- API de ingesta y consulta ----------------------------------------------
deploy_api() {
  local environment="$1" registry="$2" identity="$3"
  local app="ca-${NAME_PREFIX}-api"
  local image="${registry}/centinela-api:${IMAGE_TAG}"

  if app_exists "$app"; then
    log_info "Actualizando '$app' a $image"
    az containerapp update -g "$RESOURCE_GROUP" -n "$app" --image "$image" --output none
  else
    log_info "Creando '$app'"
    az containerapp create \
      -g "$RESOURCE_GROUP" -n "$app" --environment "$environment" \
      --image "$image" \
      --user-assigned "$identity" \
      --registry-server "$registry" --registry-identity "$identity" \
      --target-port 8080 --ingress external \
      --cpu "$CPU_PER_REPLICA" --memory "$MEMORY_PER_REPLICA" \
      --min-replicas "$API_MIN_REPLICAS" --max-replicas "$API_MAX_REPLICAS" \
      --env-vars \
        CENTINELA_SCORING_RECORD_ENABLED=true \
        CENTINELA_INQUIRY_ENABLED=true \
        CENTINELA_EXPLAINER_ENABLED=false \
        CENTINELA_DOCUMENT_VERIFICATION_ENABLED=false \
        CENTINELA_ROLE_NAME=centinela-api \
      --output none
  fi

  # Regla de escalado por concurrencia HTTP. Ver la justificacion completa en
  # provision-container-apps.sh: la API espera E/S, asi que la CPU no refleja su
  # saturacion y escalar por ella llegaria tarde.
  az containerapp update -g "$RESOURCE_GROUP" -n "$app" \
    --min-replicas "$API_MIN_REPLICAS" --max-replicas "$API_MAX_REPLICAS" \
    --scale-rule-name http-concurrency \
    --scale-rule-type http \
    --scale-rule-http-concurrency "$API_CONCURRENT_REQUESTS" \
    --output none

  log_info "  FQDN: $(az containerapp show -g "$RESOURCE_GROUP" -n "$app" --query properties.configuration.ingress.fqdn -o tsv)"
}

# --- Motor de scoring --------------------------------------------------------
deploy_scoring() {
  local environment="$1" registry="$2" identity="$3"
  local app="ca-${NAME_PREFIX}-scoring"
  local image="${registry}/centinela-scoring:${IMAGE_TAG}"

  if app_exists "$app"; then
    log_info "Actualizando '$app' a $image"
    az containerapp update -g "$RESOURCE_GROUP" -n "$app" --image "$image" --output none
  else
    log_info "Creando '$app'"
    # Ingreso interno: el motor lo invoca Event Grid dentro del entorno, no
    # necesita —ni debe tener— una direccion publica.
    az containerapp create \
      -g "$RESOURCE_GROUP" -n "$app" --environment "$environment" \
      --image "$image" \
      --user-assigned "$identity" \
      --registry-server "$registry" --registry-identity "$identity" \
      --target-port 80 --ingress internal \
      --cpu "$CPU_PER_REPLICA" --memory "$MEMORY_PER_REPLICA" \
      --min-replicas "$SCORING_MIN_REPLICAS" --max-replicas "$SCORING_MAX_REPLICAS" \
      --env-vars \
        FUNCTIONS_WORKER_RUNTIME=java \
        CENTINELA_ROLE_NAME=centinela-scoring \
      --output none
  fi

  az containerapp update -g "$RESOURCE_GROUP" -n "$app" \
    --min-replicas "$SCORING_MIN_REPLICAS" --max-replicas "$SCORING_MAX_REPLICAS" \
    --scale-rule-name event-concurrency \
    --scale-rule-type http \
    --scale-rule-http-concurrency 20 \
    --output none
}

# --- Explicador y extractor documental ---------------------------------------
deploy_explainer() {
  local environment="$1" registry="$2" identity="$3"
  local app="ca-${NAME_PREFIX}-explainer"
  local image="${registry}/centinela-api:${IMAGE_TAG}"

  if app_exists "$app"; then
    log_info "Actualizando '$app' a $image"
    az containerapp update -g "$RESOURCE_GROUP" -n "$app" --image "$image" --output none
  else
    log_info "Creando '$app' (misma imagen que la API, otro papel)"
    # Sin ingreso: no atiende peticiones, consulta trabajo pendiente.
    az containerapp create \
      -g "$RESOURCE_GROUP" -n "$app" --environment "$environment" \
      --image "$image" \
      --user-assigned "$identity" \
      --registry-server "$registry" --registry-identity "$identity" \
      --ingress internal --target-port 8080 \
      --cpu "$CPU_PER_REPLICA" --memory "$MEMORY_PER_REPLICA" \
      --min-replicas "$EXPLAINER_MIN_REPLICAS" --max-replicas "$EXPLAINER_MAX_REPLICAS" \
      --env-vars \
        CENTINELA_SCORING_RECORD_ENABLED=true \
        CENTINELA_INQUIRY_ENABLED=false \
        CENTINELA_EXPLAINER_ENABLED=true \
        CENTINELA_DOCUMENT_VERIFICATION_ENABLED=true \
        CENTINELA_QUEUE_AUTO_START=false \
        CENTINELA_ROLE_NAME=centinela-explainer \
      --output none
  fi

  az containerapp update -g "$RESOURCE_GROUP" -n "$app" \
    --min-replicas "$EXPLAINER_MIN_REPLICAS" --max-replicas "$EXPLAINER_MAX_REPLICAS" \
    --output none
}

app_exists() {
  az containerapp show -g "$RESOURCE_GROUP" -n "$1" >/dev/null 2>&1
}

main "$@"
