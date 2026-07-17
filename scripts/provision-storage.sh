#!/usr/bin/env bash
#
# scripts/provision-storage.sh
# ISS-S1-003 - Provisionar Storage Account + containers + queues por ambiente.
#
# Alcance ESTRICTO de la Issue 3:
#   - Crear/asegurar 1 Storage Account (idempotente, nombres segregados por ambiente).
#   - Crear 4 contenedores (staging/production para 2 subdominios).
#   - Crear 2 colas (staging/production).
#   - Aplicar propiedades de seguridad obligatorias (TLS1_2, HTTPS only,
#     allowBlobPublicAccess=false, publicNetworkAccess=Disabled, networkAcl Deny
#     con bypass AzureServices, cifrado en reposo).
#   - Aplicar tags de trazabilidad.
#
# No hace nada fuera de este alcance.
#
# Prerequisitos (validados al inicio):
#   - Azure CLI disponible (se ejecuta en Azure Cloud Shell).
#   - Sesion activa y suscripcion igual a SUBSCRIPTION_ID.
#   - Resource Group RESOURCE_GROUP ya creado (ISS-S1-001/002).
#
# Variables (cargadas de .env o entorno, ver scripts/lib/parameters.sh):
#   SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parameters.sh"

# --- Constantes de la Issue 3 ---------------------------------------------------

readonly CONTAINERS=(
  "raw-transactions-staging"
  "raw-transactions-production"
  "verification-documents-staging"
  "verification-documents-production"
)

readonly QUEUES=(
  "transactions-ingestion-staging"
  "transactions-ingestion-production"
)

readonly TAGS=(
  "project=centinela"
  "week=1"
  "team=celula-centinela"
  "issue=ISS-S1-003"
)

# --- Helpers de nombrado --------------------------------------------------------

assert_storage_account_name_valid() {
  local name="$1"
  [ "${#name}" -ge 3 ] && [ "${#name}" -le 24 ] \
    || die "Nombre de Storage Account invalido (longitud fuera de 3..24): '$name'"
  [[ "$name" =~ ^[a-z0-9]+$ ]] \
    || die "Nombre de Storage Account invalido (solo [a-z0-9]): '$name'"
}

# Determinismo: mismas entradas -> mismo nombre.
compute_storage_account_name() {
  local prefix="$1" sub_id="$2" rg="$3"
  local hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%sst%s' "$prefix" "$hash"
}

# --- ARM template (control plane, genera Storage + containers + queues) --------

render_arm_template() {
  local containers_json queues_json tags_json
  containers_json="$(printf '"%s",' "${CONTAINERS[@]}" | sed 's/,$//')"
  queues_json="$(printf '"%s",' "${QUEUES[@]}" | sed 's/,$//')"
  tags_json='"project":"centinela","week":"1","team":"celula-centinela","issue":"ISS-S1-003"'

  cat <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "storageAccountName": {
      "type": "string",
      "minLength": 3,
      "maxLength": 24
    }
  },
  "variables": {
    "containers": [ ${containers_json} ],
    "queues":     [ ${queues_json} ]
  },
  "resources": [
    {
      "type": "Microsoft.Storage/storageAccounts",
      "apiVersion": "2023-01-01",
      "name": "[parameters('storageAccountName')]",
      "location": "[resourceGroup().location]",
      "kind": "StorageV2",
      "sku": { "name": "Standard_LRS" },
      "tags": { ${tags_json} },
      "properties": {
        "minimumTlsVersion":             "TLS1_2",
        "supportsHttpsTrafficOnly":       true,
        "allowBlobPublicAccess":          false,
        "allowSharedKeyAccess":           true,
        "publicNetworkAccess":            "Disabled",
        "defaultToOAuthAuthentication":   false,
        "networkAcls": {
          "defaultAction": "Deny",
          "bypass":        "AzureServices",
          "virtualNetworkRules": [],
          "ipRules":           []
        },
        "encryption": {
          "services": {
            "blob":  { "enabled": true },
            "queue": { "enabled": true },
            "file":  { "enabled": true },
            "table": { "enabled": true }
          },
          "keySource": "Microsoft.Storage"
        }
      }
    },
    {
      "type": "Microsoft.Storage/storageAccounts/blobServices/containers",
      "apiVersion": "2023-01-01",
      "name": "[concat(parameters('storageAccountName'), '/default/', variables('containers')[copyIndex('containersCopy')])]",
      "dependsOn": [ "[resourceId('Microsoft.Storage/storageAccounts', parameters('storageAccountName'))]" ],
      "copy": {
        "name": "containersCopy",
        "count": "[length(variables('containers'))]"
      },
      "properties": { "publicAccess": "None" }
    },
    {
      "type": "Microsoft.Storage/storageAccounts/queueServices/queues",
      "apiVersion": "2023-01-01",
      "name": "[concat(parameters('storageAccountName'), '/default/', variables('queues')[copyIndex('queuesCopy')])]",
      "dependsOn": [ "[resourceId('Microsoft.Storage/storageAccounts', parameters('storageAccountName'))]" ],
      "copy": {
        "name": "queuesCopy",
        "count": "[length(variables('queues'))]"
      },
      "properties": {}
    }
  ]
}
JSON
}

render_arm_parameters() {
  local sa_name="$1"
  cat <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "storageAccountName": { "value": "${sa_name}" }
  }
}
JSON
}

# --- Side effects (Azure) -------------------------------------------------------

# Si el Storage Account ya existe, valida que cumple las propiedades obligatorias.
# Devuelve 0 si cumple, 1 si no existe o no cumple.
assert_storage_account_compliant_if_exists() {
  local sa_name="$1" rg="$2"
  local blob_pub pub_net tls_min https_only
  if ! az storage account show --name "$sa_name" --resource-group "$rg" >/dev/null 2>&1; then
    return 1
  fi
  log_info "Storage Account '$sa_name' ya existe. Validando configuracion..."

  blob_pub="$(az storage account show \
    --name "$sa_name" --resource-group "$rg" \
    --query 'allowBlobPublicAccess' -o tsv)"
  pub_net="$(az storage account show \
    --name "$sa_name" --resource-group "$rg" \
    --query 'publicNetworkAccess' -o tsv)"
  tls_min="$(az storage account show \
    --name "$sa_name" --resource-group "$rg" \
    --query 'minimumTlsVersion' -o tsv)"
  https_only="$(az storage account show \
    --name "$sa_name" --resource-group "$rg" \
    --query 'supportsHttpsTrafficOnly' -o tsv)"

  [ "$blob_pub" = "false" ]    || { log_error "allowBlobPublicAccess debe ser false (actual: $blob_pub)"; return 1; }
  [ "$pub_net"  = "Disabled" ] || { log_error "publicNetworkAccess debe ser Disabled (actual: $pub_net)"; return 1; }
  [ "$tls_min"  = "TLS1_2" ]   || { log_error "minimumTlsVersion debe ser TLS1_2 (actual: $tls_min)"; return 1; }
  [ "$https_only" = "true" ]   || { log_error "supportsHttpsTrafficOnly debe ser true (actual: $https_only)"; return 1; }

  return 0
}

deploy_storage_via_arm() {
  local sa_name="$1" rg="$2" template="$3" params="$4"
  log_info "Desplegando Storage Account '$sa_name' via ARM (control plane)..."
  with_retry 3 az deployment group create \
    --resource-group "$rg" \
    --template-file  "$template" \
    --parameters     @"$params" \
    --name "iss-s1-003-${sa_name}" \
    >/dev/null
  log_info "Deployment ARM completado."
}

verify_all_resources() {
  local sa_name="$1" rg="$2"

  log_info "Verificando contenedores mediante control plane..."
  local c
  for c in "${CONTAINERS[@]}"; do
    az resource show \
      --resource-group "$rg" \
      --namespace "Microsoft.Storage" \
      --parent "storageAccounts/${sa_name}/blobServices/default" \
      --resource-type "containers" \
      --name "$c" \
      >/dev/null 2>&1 || die "Falta contenedor: $c"

    log_info "  OK contenedor: $c"
  done

  log_info "Verificando colas mediante control plane..."
  local q
  for q in "${QUEUES[@]}"; do
    az resource show \
      --resource-group "$rg" \
      --namespace "Microsoft.Storage" \
      --parent "storageAccounts/${sa_name}/queueServices/default" \
      --resource-type "queues" \
      --name "$q" \
      >/dev/null 2>&1 || die "Falta cola: $q"

    log_info "  OK cola: $q"
  done
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

  local sa_name
  sa_name="$(compute_storage_account_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  log_info "Storage Account objetivo: $sa_name (longitud: ${#sa_name})"
  assert_storage_account_name_valid "$sa_name"

  if ! assert_storage_account_compliant_if_exists "$sa_name" "$RESOURCE_GROUP"; then
    local tmp_dir template_file params_file
    tmp_dir="$(mktemp -d)"
    trap "rm -rf '$tmp_dir'" EXIT
    template_file="$tmp_dir/storage.template.json"
    params_file="$tmp_dir/storage.parameters.json"
    render_arm_template    > "$template_file"
    render_arm_parameters "$sa_name" > "$params_file"
    deploy_storage_via_arm "$sa_name" "$RESOURCE_GROUP" "$template_file" "$params_file"
  else
    log_info "Storage Account '$sa_name' ya existe y cumple las propiedades obligatorias. Sin cambios."
  fi

  verify_all_resources "$sa_name" "$RESOURCE_GROUP"
  log_info "ISS-S1-003 OK: Storage + ${#CONTAINERS[@]} contenedores + ${#QUEUES[@]} colas listos."
}

main "$@"