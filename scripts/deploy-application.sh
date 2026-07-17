#!/usr/bin/env bash
#
# scripts/deploy-application.sh
# ISS-S1-004 - Desplegar UN unico artefacto de la aplicacion al App Service.
#
# Alcance ESTRICTO:
#   - Empaquetar (o recibir) un unico artefacto .jar de la app Spring Boot.
#   - Publicarlo en un slot (por defecto 'staging') de la Web App creada por
#     provision-app-service.sh, usando el control plane de Azure.
#   - Opcionalmente, hacer swap staging -> produccion tras validar.
#
# NO exige pipeline CI/CD, GitHub Actions ni blue/green avanzado. Es un despliegue
# manual reproducible pensado para Azure Cloud Shell.
#
# Uso:
#   scripts/deploy-application.sh [--slot <nombre>] [--artifact <ruta.jar>] [--swap] [--build]
#     --slot <nombre>     Slot destino. Por defecto 'staging'. Usa 'production'
#                         para publicar directo en produccion (no recomendado).
#     --artifact <ruta>   Ruta a un .jar ya construido. Si se omite, se busca en
#                         target/*.jar (o se construye con --build).
#     --build             Construye el artefacto con 'mvn -q -DskipTests package'.
#     --swap              Tras desplegar en 'staging', hace swap a 'production'.
#
# Variables (cargadas de .env o entorno, ver scripts/lib/parameters.sh):
#   SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX, APP_SERVICE_SKU

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parameters.sh"

readonly PRODUCTION_SLOT_ALIAS="production"

TARGET_SLOT="staging"
ARTIFACT=""
DO_BUILD=0
DO_SWAP=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --slot)     TARGET_SLOT="${2:?Falta valor para --slot}"; shift 2 ;;
    --artifact) ARTIFACT="${2:?Falta valor para --artifact}"; shift 2 ;;
    --build)    DO_BUILD=1; shift ;;
    --swap)     DO_SWAP=1; shift ;;
    -h|--help)
      echo "Uso: $0 [--slot <nombre>] [--artifact <ruta.jar>] [--build] [--swap]"; exit 0 ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

# Nombre determinista de la Web App (mismo criterio que provision-app-service.sh).
compute_web_app_name() {
  local prefix="$1" sub_id="$2" rg="$3"
  local hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-app-%s' "$prefix" "$hash"
}

# Localiza (o construye) el UNICO artefacto .jar a desplegar.
resolve_artifact() {
  if [ -n "$ARTIFACT" ]; then
    [ -f "$ARTIFACT" ] || die "El artefacto indicado no existe: $ARTIFACT"
    printf '%s' "$ARTIFACT"
    return 0
  fi

  local repo_root; repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"
  if [ "$DO_BUILD" -eq 1 ]; then
    require_cmd mvn
    log_info "Construyendo artefacto con Maven (skipTests)..."
    ( cd "$repo_root" && mvn -q -DskipTests clean package )
  fi

  # Selecciona el jar de la app (excluye *-sources/*-javadoc/original-*).
  local jar
  jar="$(find "$repo_root/target" -maxdepth 1 -type f -name '*.jar' \
          ! -name '*-sources.jar' ! -name '*-javadoc.jar' ! -name 'original-*.jar' \
          2>/dev/null | head -n 1 || true)"
  [ -n "$jar" ] || die "No se encontro un .jar en target/. Ejecuta con --build o pasa --artifact <ruta>."
  printf '%s' "$jar"
}

main() {
  load_parameters
  validate_parameters

  require_cmd az
  az account show >/dev/null 2>&1 \
    || die "No hay sesion de Azure activa. Ejecuta 'az login' primero."
  local active_sub; active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "Resource Group '$RESOURCE_GROUP' no existe. Ejecuta primero deploy-week1.sh."

  local app_name; app_name="$(compute_web_app_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  az webapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "La Web App '$app_name' no existe. Ejecuta primero scripts/provision-app-service.sh."

  local artifact; artifact="$(resolve_artifact)"
  log_info "Artefacto a desplegar: $artifact"
  log_info "Web App: $app_name"
  log_info "Slot destino: $TARGET_SLOT"

  # El slot 'production' es el sitio raiz: az usa --slot solo para slots no-produccion.
  local slot_args=()
  if [ "$TARGET_SLOT" != "$PRODUCTION_SLOT_ALIAS" ]; then
    az webapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" --slot "$TARGET_SLOT" >/dev/null 2>&1 \
      || die "El slot '$TARGET_SLOT' no existe en '$app_name'."
    slot_args=(--slot "$TARGET_SLOT")
  fi

  log_info "Publicando artefacto (az webapp deploy --type jar)..."
  with_retry 3 az webapp deploy \
    --name "$app_name" \
    --resource-group "$RESOURCE_GROUP" \
    "${slot_args[@]}" \
    --type jar \
    --src-path "$artifact" \
    --async false \
    >/dev/null
  log_info "Despliegue completado en slot '$TARGET_SLOT'."

  if [ "$DO_SWAP" -eq 1 ]; then
    [ "$TARGET_SLOT" != "$PRODUCTION_SLOT_ALIAS" ] \
      || die "--swap requiere desplegar en un slot no-produccion (ej. 'staging')."
    log_info "Haciendo swap '$TARGET_SLOT' -> produccion..."
    with_retry 3 az webapp deployment slot swap \
      --name "$app_name" \
      --resource-group "$RESOURCE_GROUP" \
      --slot "$TARGET_SLOT" \
      --target-slot "$PRODUCTION_SLOT_ALIAS" \
      >/dev/null
    log_info "Swap completado: '$TARGET_SLOT' es ahora produccion."
  fi

  log_info "ISS-S1-004 (deploy): artefacto unico publicado sin pipeline CI/CD."
}

main "$@"
