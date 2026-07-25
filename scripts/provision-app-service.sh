#!/usr/bin/env bash
#
# scripts/provision-app-service.sh
# ISS-S1-004 - Provisionar App Service Plan + Web App (produccion) + slot staging
#              + Managed Identity + configuracion aislada por ambiente.
#
# Alcance ESTRICTO de la Issue 4:
#   - Crear/asegurar 1 App Service Plan (Linux) con SKU y region por parametros.
#     El SKU DEBE soportar deployment slots y escala horizontal (Standard+).
#   - Crear 1 Web App de produccion y 1 slot 'staging' en el MISMO plan.
#   - Activar System Assigned Managed Identity en produccion y en staging.
#   - Configurar variables NO secretas de ambiente + nombres de contenedores/colas.
#     Produccion apunta a recursos '*-production'; staging a '*-staging'.
#   - Marcar como slot settings (sticky) las variables que NO deben intercambiarse
#     en un swap entre produccion y staging.
#   - Dejar el plan en UNA instancia (capacity=1) tras el despliegue normal.
#   - Idempotente: reejecutar converge al mismo estado sin duplicar recursos.
#
# No hace nada fuera de este alcance (sin GitHub Actions, sin Front Door,
# sin blue/green avanzado, sin multiples planes ni multiples regiones).
#
# Prerequisitos (validados al inicio):
#   - Azure CLI disponible (se ejecuta en Azure Cloud Shell).
#   - Sesion activa y suscripcion igual a SUBSCRIPTION_ID.
#   - Resource Group RESOURCE_GROUP ya creado (ISS-S1-001/002).
#
# Variables (cargadas de .env o entorno, ver scripts/lib/parameters.sh):
#   SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX, APP_SERVICE_SKU

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parameters.sh"

# --- Constantes de la Issue 4 ---------------------------------------------------

readonly SLOT_NAME="staging"

# Runtime del artefacto de la app (Spring Boot 3.4.x / Java 21, ver pom.xml).
readonly LINUX_FX_VERSION="JAVA|21-java21"
readonly HEALTH_CHECK_PATH="/actuator/health"

# Recursos logicos por ambiente (deben existir en el Storage de ISS-S1-003).
readonly RAW_CONTAINER_PROD="raw-transactions-production"
readonly RAW_CONTAINER_STAGING="raw-transactions-staging"
readonly DOCS_CONTAINER_PROD="verification-documents-production"
readonly DOCS_CONTAINER_STAGING="verification-documents-staging"
readonly INGESTION_QUEUE_PROD="transactions-ingestion-production"
readonly INGESTION_QUEUE_STAGING="transactions-ingestion-staging"

# App settings que identifican el ambiente y NO deben viajar en un swap.
# Se registran en slotConfigNames.appSettingNames (sticky / slot settings).
readonly STICKY_SETTINGS=(
  "SPRING_PROFILES_ACTIVE"
  "CENTINELA_ENVIRONMENT"
  "CENTINELA_RAW_TRANSACTIONS_CONTAINER"
  "CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER"
  "CENTINELA_INGESTION_QUEUE"
  "CENTINELA_POSTGRES_JDBC_URL"
  "CENTINELA_POSTGRES_USER"
  "CENTINELA_FLAGGED_CASES_QUEUE"
  "CENTINELA_QUEUE_AUTO_START"
)

readonly TAGS=(
  "project=centinela"
  "week=1"
  "team=celula-centinela"
  "issue=ISS-S1-004"
)

# --- Helpers de nombrado --------------------------------------------------------

# Determinismo: mismas entradas -> mismo nombre (igual criterio que el Storage).
compute_web_app_name() {
  local prefix="$1" sub_id="$2" rg="$3"
  local hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-app-%s' "$prefix" "$hash"
}

# El plan solo debe ser unico dentro del Resource Group (no es un nombre DNS).
compute_plan_name() {
  local prefix="$1"
  printf '%s-asp-week1' "$prefix"
}

# Reutiliza el mismo nombre determinista del Storage de ISS-S1-003, para que las
# app settings puedan referenciar la cuenta compartida sin secretos.
compute_storage_account_name() {
  local prefix="$1" sub_id="$2" rg="$3"
  local hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%sst%s' "$prefix" "$hash"
}

assert_web_app_name_valid() {
  local name="$1"
  [ "${#name}" -ge 2 ] && [ "${#name}" -le 60 ] \
    || die "Nombre de Web App invalido (longitud fuera de 2..60): '$name'"
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] \
    || die "Nombre de Web App invalido (solo [a-z0-9-], sin guion inicial/final): '$name'"
}

# --- Validacion de SKU (Gherkin: "SKU no compatible") ---------------------------

# Deriva el tier de App Service desde el nombre de SKU. Cadena vacia = desconocido.
sku_tier() {
  case "${1^^}" in
    F1)                                          echo "Free" ;;
    D1)                                          echo "Shared" ;;
    B1|B2|B3)                                    echo "Basic" ;;
    S1|S2|S3)                                    echo "Standard" ;;
    P1V2|P2V2|P3V2)                              echo "PremiumV2" ;;
    P0V3|P1V3|P2V3|P3V3|P4V3|P5V3)               echo "PremiumV3" ;;
    P1MV3|P2MV3|P3MV3|P4MV3|P5MV3)               echo "PremiumV3" ;;
    I1|I2|I3)                                    echo "Isolated" ;;
    I1V2|I2V2|I3V2|I4V2|I5V2|I6V2)               echo "IsolatedV2" ;;
    *)                                           echo "" ;;
  esac
}

# Falla ANTES de crear nada si el SKU no soporta deployment slots + escala horizontal.
# Slots requieren tier Standard o superior. Free/Shared/Basic NO tienen slots.
assert_sku_supports_slots() {
  local sku="$1" tier
  tier="$(sku_tier "$sku")"
  case "$tier" in
    Standard|PremiumV2|PremiumV3|Isolated|IsolatedV2)
      log_info "SKU '$sku' (tier $tier) soporta deployment slots y escala horizontal."
      printf '%s' "$tier"
      return 0
      ;;
    Free|Shared|Basic)
      die "SKU '$sku' (tier $tier) NO soporta deployment slots. Los slots requieren tier Standard (S1+), Premium o Isolated. Aborta sin crear el App Service."
      ;;
    *)
      die "SKU '$sku' no reconocido o incompatible con slots/escala horizontal. Usa S1/S2/S3, P#V2, P#V3 o I# (Isolated)."
      ;;
  esac
}

# --- ARM template (control plane declarativo, idempotente) ---------------------

# Emite un array JSON de app settings a partir de pares "K=V" pasados como args.
render_app_settings_json() {
  local first=1 pair k v
  for pair in "$@"; do
    k="${pair%%=*}"
    v="${pair#*=}"
    if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
    printf '{ "name": "%s", "value": "%s" }' "$k" "$v"
  done
}

# Emite el array JSON de nombres de settings sticky para slotConfigNames.
render_sticky_names_json() {
  printf '"%s",' "${STICKY_SETTINGS[@]}" | sed 's/,$//'
}

render_arm_template() {
  local plan_name="$1" app_name="$2" sku="$3" tier="$4" sa_name="$5"

  # Settings comunes (compartidos, NO sticky): identifican la cuenta de Storage
  # compartida y el puerto del contenedor Java. Iguales en ambos ambientes.
  local common_settings
  common_settings="$(render_app_settings_json \
    "CENTINELA_STORAGE_ACCOUNT=${sa_name}" \
    "WEBSITES_PORT=8080")"

  # Settings de PRODUCCION (sticky): ambiente + recursos logicos '*-production'.
  local prod_env_settings
  prod_env_settings="$(render_app_settings_json \
    "SPRING_PROFILES_ACTIVE=production" \
    "CENTINELA_ENVIRONMENT=production" \
    "CENTINELA_RAW_TRANSACTIONS_CONTAINER=${RAW_CONTAINER_PROD}" \
    "CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER=${DOCS_CONTAINER_PROD}" \
    "CENTINELA_INGESTION_QUEUE=${INGESTION_QUEUE_PROD}")"

  # Settings de STAGING (sticky): ambiente + recursos logicos '*-staging'.
  local staging_env_settings
  staging_env_settings="$(render_app_settings_json \
    "SPRING_PROFILES_ACTIVE=staging" \
    "CENTINELA_ENVIRONMENT=staging" \
    "CENTINELA_RAW_TRANSACTIONS_CONTAINER=${RAW_CONTAINER_STAGING}" \
    "CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER=${DOCS_CONTAINER_STAGING}" \
    "CENTINELA_INGESTION_QUEUE=${INGESTION_QUEUE_STAGING}")"

  local sticky_names tags_json
  sticky_names="$(render_sticky_names_json)"
  tags_json='"project":"centinela","week":"1","team":"celula-centinela","issue":"ISS-S1-004"'

  cat <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "planName":    { "type": "string" },
    "appName":     { "type": "string" },
    "skuName":     { "type": "string" },
    "skuTier":     { "type": "string" },
    "linuxFxVersion": { "type": "string" }
  },
  "variables": {
    "location": "[resourceGroup().location]"
  },
  "resources": [
    {
      "type": "Microsoft.Web/serverfarms",
      "apiVersion": "2023-01-01",
      "name": "[parameters('planName')]",
      "location": "[variables('location')]",
      "kind": "linux",
      "tags": { ${tags_json} },
      "sku": {
        "name":     "[parameters('skuName')]",
        "tier":     "[parameters('skuTier')]",
        "capacity": 1
      },
      "properties": {
        "reserved": true
      }
    },
    {
      "type": "Microsoft.Web/sites",
      "apiVersion": "2023-01-01",
      "name": "[parameters('appName')]",
      "location": "[variables('location')]",
      "kind": "app,linux",
      "tags": { ${tags_json} },
      "identity": { "type": "SystemAssigned" },
      "dependsOn": [
        "[resourceId('Microsoft.Web/serverfarms', parameters('planName'))]"
      ],
      "properties": {
        "serverFarmId": "[resourceId('Microsoft.Web/serverfarms', parameters('planName'))]",
        "httpsOnly": true,
        "siteConfig": {
          "linuxFxVersion":  "[parameters('linuxFxVersion')]",
          "alwaysOn":        true,
          "ftpsState":       "Disabled",
          "minTlsVersion":   "1.2",
          "http20Enabled":   true,
          "healthCheckPath": "${HEALTH_CHECK_PATH}",
          "appSettings": [ ${common_settings}, ${prod_env_settings} ]
        }
      }
    },
    {
      "type": "Microsoft.Web/sites/config",
      "apiVersion": "2023-01-01",
      "name": "[concat(parameters('appName'), '/slotConfigNames')]",
      "dependsOn": [
        "[resourceId('Microsoft.Web/sites', parameters('appName'))]"
      ],
      "properties": {
        "appSettingNames": [ ${sticky_names} ]
      }
    },
    {
      "type": "Microsoft.Web/sites/slots",
      "apiVersion": "2023-01-01",
      "name": "[concat(parameters('appName'), '/${SLOT_NAME}')]",
      "location": "[variables('location')]",
      "kind": "app,linux",
      "tags": { ${tags_json} },
      "identity": { "type": "SystemAssigned" },
      "dependsOn": [
        "[resourceId('Microsoft.Web/sites', parameters('appName'))]"
      ],
      "properties": {
        "serverFarmId": "[resourceId('Microsoft.Web/serverfarms', parameters('planName'))]",
        "httpsOnly": true,
        "siteConfig": {
          "linuxFxVersion":  "[parameters('linuxFxVersion')]",
          "alwaysOn":        true,
          "ftpsState":       "Disabled",
          "minTlsVersion":   "1.2",
          "http20Enabled":   true,
          "healthCheckPath": "${HEALTH_CHECK_PATH}",
          "appSettings": [ ${common_settings}, ${staging_env_settings} ]
        }
      }
    }
  ]
}
JSON
}

render_arm_parameters() {
  local plan_name="$1" app_name="$2" sku="$3" tier="$4"
  cat <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "planName":       { "value": "${plan_name}" },
    "appName":        { "value": "${app_name}" },
    "skuName":        { "value": "${sku}" },
    "skuTier":        { "value": "${tier}" },
    "linuxFxVersion": { "value": "${LINUX_FX_VERSION}" }
  }
}
JSON
}

# --- Side effects (Azure) -------------------------------------------------------

deploy_app_service_via_arm() {
  local app_name="$1" rg="$2" template="$3" params="$4"
  log_info "Desplegando App Service '$app_name' + slot '$SLOT_NAME' via ARM (control plane)..."
  with_retry 3 az deployment group create \
    --resource-group "$rg" \
    --template-file  "$template" \
    --parameters     @"$params" \
    --name "iss-s1-004-${app_name}" \
    >/dev/null
  log_info "Deployment ARM completado."
}

# Verifica el estado final: existencia, identidades, aislamiento y 1 instancia.
verify_all_resources() {
  local plan_name="$1" app_name="$2" rg="$3"

  log_info "Verificando Web App de produccion..."
  az webapp show --name "$app_name" --resource-group "$rg" >/dev/null 2>&1 \
    || die "No existe la Web App '$app_name'."
  log_info "  OK Web App: $app_name"

  log_info "Verificando slot '$SLOT_NAME'..."
  az webapp show --name "$app_name" --resource-group "$rg" --slot "$SLOT_NAME" >/dev/null 2>&1 \
    || die "No existe el slot '$SLOT_NAME' en '$app_name'."
  log_info "  OK slot: $SLOT_NAME"

  log_info "Verificando Managed Identity (produccion y staging)..."
  local prod_pid staging_pid
  prod_pid="$(az webapp identity show --name "$app_name" --resource-group "$rg" \
    --query principalId -o tsv 2>/dev/null || true)"
  staging_pid="$(az webapp identity show --name "$app_name" --resource-group "$rg" \
    --slot "$SLOT_NAME" --query principalId -o tsv 2>/dev/null || true)"
  [ -n "$prod_pid" ]    || die "Produccion sin System Assigned Managed Identity."
  [ -n "$staging_pid" ] || die "Staging sin System Assigned Managed Identity."
  log_info "  OK identidad produccion: $(mask "$prod_pid")"
  log_info "  OK identidad staging:    $(mask "$staging_pid")"

  log_info "Verificando aislamiento por ambiente..."
  local prod_env staging_env
  prod_env="$(az webapp config appsettings list --name "$app_name" --resource-group "$rg" \
    --query "[?name=='CENTINELA_ENVIRONMENT'].value | [0]" -o tsv 2>/dev/null || true)"
  staging_env="$(az webapp config appsettings list --name "$app_name" --resource-group "$rg" \
    --slot "$SLOT_NAME" --query "[?name=='CENTINELA_ENVIRONMENT'].value | [0]" -o tsv 2>/dev/null || true)"
  [ "$prod_env" = "production" ] \
    || die "CENTINELA_ENVIRONMENT en produccion = '$prod_env' (esperado 'production')."
  [ "$staging_env" = "staging" ] \
    || die "CENTINELA_ENVIRONMENT en staging = '$staging_env' (esperado 'staging')."
  log_info "  OK produccion -> production ; staging -> staging"

  log_info "Verificando instancia unica (capacity=1)..."
  local capacity
  capacity="$(az appservice plan show --name "$plan_name" --resource-group "$rg" \
    --query "sku.capacity" -o tsv 2>/dev/null || echo "?")"
  [ "$capacity" = "1" ] \
    || log_warn "El plan tiene capacity=$capacity (esperado 1 en operacion normal)."
  [ "$capacity" = "1" ] && log_info "  OK plan en 1 instancia."
}

# --- Main ----------------------------------------------------------------------

main() {
  load_parameters
  validate_parameters

  require_cmd az
  az account show >/dev/null 2>&1 \
    || die "No hay sesion de Azure activa. Ejecuta 'az login' primero."

  local active_sub
  active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "Resource Group '$RESOURCE_GROUP' no existe. Ejecuta primero deploy-week1.sh."

  # Gherkin "SKU no compatible": falla ANTES de tocar Azure si el SKU no da slots.
  local tier
  tier="$(assert_sku_supports_slots "$APP_SERVICE_SKU")"

  local plan_name app_name sa_name
  plan_name="$(compute_plan_name "$NAME_PREFIX")"
  app_name="$(compute_web_app_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  sa_name="$(compute_storage_account_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  assert_web_app_name_valid "$app_name"

  log_info "App Service Plan objetivo: $plan_name (SKU $APP_SERVICE_SKU / tier $tier)"
  log_info "Web App objetivo:          $app_name"
  log_info "Slot objetivo:             $SLOT_NAME"
  log_info "Storage compartido (ref):  $sa_name"

  local tmp_dir template_file params_file
  tmp_dir="$(mktemp -d)"
  trap "rm -rf '$tmp_dir'" EXIT
  template_file="$tmp_dir/app-service.template.json"
  params_file="$tmp_dir/app-service.parameters.json"
  render_arm_template    "$plan_name" "$app_name" "$APP_SERVICE_SKU" "$tier" "$sa_name" > "$template_file"
  render_arm_parameters  "$plan_name" "$app_name" "$APP_SERVICE_SKU" "$tier" > "$params_file"

  # ARM es declarativo: reejecutar converge al mismo estado (idempotente) y
  # restablece capacity=1 tras una prueba HA (ISS-S1-012).
  deploy_app_service_via_arm "$app_name" "$RESOURCE_GROUP" "$template_file" "$params_file"

  verify_all_resources "$plan_name" "$app_name" "$RESOURCE_GROUP"
  log_info "ISS-S1-004 OK: Web App '$app_name' + slot '$SLOT_NAME' con Managed Identity y ambientes aislados."
}

main "$@"
