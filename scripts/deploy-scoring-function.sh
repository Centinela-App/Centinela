#!/usr/bin/env bash
# scripts/deploy-scoring-function.sh
# Integracion correctiva ISS-S2-001..011: aprovisiona, configura y despliega la
# Azure Function de scoring sobre el App Service Plan de Semana 1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

readonly SUBNET_APP="snet-app-integration"
readonly RAW_CONTAINERS=("raw-transactions-production" "raw-transactions-staging")
readonly CASE_QUEUES=("flagged-cases-production" "flagged-cases-staging")
readonly COSMOS_DATABASE="centinela"
readonly COSMOS_COLLECTION="transactions"
readonly KEYVAULT_SECRETS_USER_ROLE="Key Vault Secrets User"
readonly BLOB_READER_ROLE="Storage Blob Data Reader"
readonly QUEUE_SENDER_ROLE="Storage Queue Data Message Sender"
readonly HOST_BLOB_OWNER_ROLE="Storage Blob Data Owner"
readonly HOST_TABLE_ROLE="Storage Table Data Contributor"

VALIDATE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --validate-only) VALIDATE_ONLY=1 ;;
    -h|--help) echo "Uso: $0 [--validate-only]"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

resource_hash() {
  printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6
}
compute_storage_account_name() { printf '%sst%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_function_app_name() { printf '%s-scoring-fn-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_plan_name() { printf '%s-asp-week1' "$NAME_PREFIX"; }
compute_vnet_name() { printf '%s-vnet-week1' "$NAME_PREFIX"; }
compute_keyvault_name() { printf '%s-kv-%s' "$NAME_PREFIX" "$(resource_hash)"; }
compute_eventgrid_topic_name() { printf '%s-egt-%s' "$NAME_PREFIX" "$(resource_hash)"; }

assign_role_scope() {
  local principal="$1" role="$2" scope="$3" count
  count="$(az role assignment list --assignee "$principal" --role "$role" --scope "$scope" \
    --query 'length(@)' -o tsv 2>/dev/null || echo 0)"
  if [ "${count:-0}" -ge 1 ] 2>/dev/null; then
    log_info "  YA asignado: '$role' a $(mask "$principal")."
    return 0
  fi
  with_retry 3 az role assignment create \
    --assignee-object-id "$principal" --assignee-principal-type ServicePrincipal \
    --role "$role" --scope "$scope" --output none
  log_info "  OK: '$role' -> $(mask "$principal")."
}

ensure_function_app() {
  local app="$1" plan="$2" storage="$3"
  if az functionapp show --name "$app" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "Function App '$app' ya existe."
  else
    log_info "Creando Function App '$app' sobre el plan '$plan'..."
    with_retry 3 az functionapp create \
      --name "$app" --resource-group "$RESOURCE_GROUP" \
      --storage-account "$storage" --plan "$plan" \
      --functions-version 4 --runtime java --runtime-version 21 --os-type Linux \
      --output none
  fi
  with_retry 3 az functionapp identity assign \
    --name "$app" --resource-group "$RESOURCE_GROUP" --output none
}

ensure_vnet_integration() {
  local app="$1" vnet="$2"
  if az functionapp vnet-integration list --name "$app" --resource-group "$RESOURCE_GROUP" \
      --query "[?contains(subnetResourceId, '/subnets/${SUBNET_APP}')].subnetResourceId | [0]" \
      -o tsv 2>/dev/null | grep -q .; then
    log_info "Function App ya integrada a '$vnet/$SUBNET_APP'."
  else
    log_info "Integrando Function App a '$vnet/$SUBNET_APP'..."
    with_retry 3 az functionapp vnet-integration add \
      --name "$app" --resource-group "$RESOURCE_GROUP" \
      --vnet "$vnet" --subnet "$SUBNET_APP" --output none
  fi
}

configure_identity_and_settings() {
  local app="$1" storage="$2" vault="$3" principal="$4"
  local storage_id vault_id container queue scope
  storage_id="$(az storage account show --name "$storage" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
  vault_id="$(az keyvault show --name "$vault" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"

  log_info "Asignando RBAC minimo a la Managed Identity de la Function..."
  assign_role_scope "$principal" "$KEYVAULT_SECRETS_USER_ROLE" "$vault_id"
  for container in "${RAW_CONTAINERS[@]}"; do
    scope="${storage_id}/blobServices/default/containers/${container}"
    assign_role_scope "$principal" "$BLOB_READER_ROLE" "$scope"
  done
  for queue in "${CASE_QUEUES[@]}"; do
    scope="${storage_id}/queueServices/default/queues/${queue}"
    assign_role_scope "$principal" "$QUEUE_SENDER_ROLE" "$scope"
  done
  assign_role_scope "$principal" "$HOST_BLOB_OWNER_ROLE" "$storage_id"
  assign_role_scope "$principal" "$HOST_TABLE_ROLE" "$storage_id"

  log_info "Configurando App Settings sin connection strings de Storage..."
  with_retry 3 az functionapp config appsettings set \
    --name "$app" --resource-group "$RESOURCE_GROUP" \
    --settings \
      "FUNCTIONS_WORKER_RUNTIME=java" \
      "FUNCTIONS_EXTENSION_VERSION=~4" \
      "AzureWebJobsStorage__accountName=$storage" \
      "AzureWebJobsStorage__credential=managedidentity" \
      "CENTINELA_STORAGE_ACCOUNT=$storage" \
      "CENTINELA_RAW_TRANSACTIONS_CONTAINER_PRODUCTION=${RAW_CONTAINERS[0]}" \
      "CENTINELA_RAW_TRANSACTIONS_CONTAINER_STAGING=${RAW_CONTAINERS[1]}" \
      "CENTINELA_FLAGGED_CASES_QUEUE_PRODUCTION=${CASE_QUEUES[0]}" \
      "CENTINELA_FLAGGED_CASES_QUEUE_STAGING=${CASE_QUEUES[1]}" \
      "KEY_VAULT_URI=https://${vault}.vault.azure.net" \
      "COSMOS_DATABASE=$COSMOS_DATABASE" \
      "COSMOS_COLLECTION=$COSMOS_COLLECTION" \
      "SCORING_THRESHOLD=${SCORING_THRESHOLD:-50}" \
      "WEBSITE_RUN_FROM_PACKAGE=1" \
    --output none

  # El comando de creacion puede agregar AzureWebJobsStorage con clave. Se elimina
  # tras configurar la conexion identity-based.
  az functionapp config appsettings delete --name "$app" --resource-group "$RESOURCE_GROUP" \
    --setting-names AzureWebJobsStorage --output none >/dev/null 2>&1 || true
}

ensure_event_subscription() {
  local app="$1" topic="$2" function_id topic_id subscription_name
  topic_id="$(az eventgrid topic show --name "$topic" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
  function_id="$(az functionapp show --name "$app" --resource-group "$RESOURCE_GROUP" --query id -o tsv)/functions/ScoreTransaction"
  subscription_name="score-transaction-v1"

  if az eventgrid event-subscription show --name "$subscription_name" \
      --source-resource-id "$topic_id" >/dev/null 2>&1; then
    log_info "Suscripcion Event Grid '$subscription_name' ya existe."
  else
    log_info "Conectando Event Grid Topic con la Function ScoreTransaction..."
    with_retry 3 az eventgrid event-subscription create \
      --name "$subscription_name" --source-resource-id "$topic_id" \
      --endpoint-type azurefunction --endpoint "$function_id" --output none
  fi
}

main() {
  load_parameters
  validate_parameters
  require_cmd az

  local app plan storage vnet vault topic module_dir principal
  app="${SCORING_FUNCTION_APP_NAME:-$(compute_function_app_name)}"
  plan="$(compute_plan_name)"
  storage="$(compute_storage_account_name)"
  vnet="$(compute_vnet_name)"
  vault="$(compute_keyvault_name)"
  topic="$(compute_eventgrid_topic_name)"
  module_dir="$REPO_ROOT/scoring-function"

  [ -d "$module_dir" ] || die "No existe '$module_dir'."
  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  [ "$(az account show --query id -o tsv)" = "$SUBSCRIPTION_ID" ] \
    || die "La suscripcion activa no coincide con SUBSCRIPTION_ID."

  log_info "Plan de integracion de scoring:"
  log_info "  Function App: $app"
  log_info "  Plan:         $plan"
  log_info "  VNet:         $vnet/$SUBNET_APP"
  log_info "  Storage:      $storage"
  log_info "  Key Vault:    $vault"
  log_info "  Event Grid:   $topic"

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    [ -f "$module_dir/pom.xml" ] || die "Falta scoring-function/pom.xml."
    log_info "--validate-only: estructura y parametros validos; no se crean recursos."
    return 0
  fi

  require_cmd mvn
  az appservice plan show --name "$plan" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe el App Service Plan '$plan' de Semana 1."
  az storage account show --name "$storage" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe Storage '$storage'."
  az keyvault show --name "$vault" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe Key Vault '$vault'."
  az eventgrid topic show --name "$topic" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe Event Grid Topic '$topic'."

  ensure_function_app "$app" "$plan" "$storage"
  ensure_vnet_integration "$app" "$vnet"
  principal="$(az functionapp identity show --name "$app" --resource-group "$RESOURCE_GROUP" \
    --query principalId -o tsv)"
  [ -n "$principal" ] || die "La Function App no obtuvo Managed Identity."
  configure_identity_and_settings "$app" "$storage" "$vault" "$principal"

  log_info "Compilando y ejecutando pruebas de scoring-function..."
  (cd "$module_dir" && mvn -q clean verify)
  log_info "Desplegando la Function en Azure..."
  (cd "$module_dir" && mvn -q azure-functions:deploy \
      -DfunctionAppName="$app" \
      -DfunctionResourceGroup="$RESOURCE_GROUP" \
      -DfunctionAppRegion="$LOCATION")

  ensure_event_subscription "$app" "$topic"
  log_info "ISS-S2-007/009 integradas: Function desplegada, RBAC aplicado y Event Grid conectado."
}

main "$@"
