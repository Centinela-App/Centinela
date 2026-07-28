#!/usr/bin/env bash
#
# scripts/provision-network.sh
# ISS-S1-005 - Provisionar VNet + 2 subredes + zonas DNS privadas + VNet Integration.
#
# Alcance ESTRICTO de la Issue 5 (capa de red base; los Private Endpoints los crea
# scripts/configure-private-endpoints.sh):
#   - Crear/asegurar 1 VNet con exactamente 2 subredes:
#       * snet-app-integration   -> delegada a Microsoft.Web/serverFarms (salida App Service).
#       * snet-private-endpoints -> privateEndpointNetworkPolicies=Disabled (aloja los PE).
#   - Crear/asegurar las 2 zonas DNS privadas de Storage y vincularlas a la VNet:
#       * privatelink.blob.core.windows.net
#       * privatelink.queue.core.windows.net
#   - Integrar produccion y el slot 'staging' a snet-app-integration (VNet Integration).
#   - No abrir acceso publico del Storage (se mantiene Disabled de ISS-S1-003).
#
# No hace nada fuera de este alcance (sin App Gateway/Front Door/APIM/firewall,
# sin VPN/ExpressRoute/VMs, sin subred de runners de CI).
#
# Prerequisitos (validados al inicio):
#   - Azure CLI disponible (Azure Cloud Shell).
#   - Sesion activa y suscripcion igual a SUBSCRIPTION_ID.
#   - Resource Group ya creado; Storage (ISS-S1-003) y App Service (ISS-S1-004) existentes.
#
# Variables obligatorias (ver scripts/lib/parameters.sh):
#   SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX, APP_SERVICE_SKU
# Variables opcionales (CIDR parametrizable; el diagrama usa rangos ilustrativos):
#   VNET_ADDRESS_SPACE  (default 10.10.0.0/16)
#   SUBNET_APP_PREFIX   (default 10.10.1.0/24)
#   SUBNET_PE_PREFIX    (default 10.10.2.0/24)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parameters.sh"

# --- Constantes de la Issue 5 ---------------------------------------------------

readonly SLOT_NAME="staging"
readonly SUBNET_APP="snet-app-integration"
readonly SUBNET_PE="snet-private-endpoints"
readonly APP_DELEGATION="Microsoft.Web/serverFarms"
readonly DNS_ZONE_BLOB="privatelink.blob.core.windows.net"
readonly DNS_ZONE_QUEUE="privatelink.queue.core.windows.net"

# CIDR parametrizable con defaults alineados al diagrama de red (10.10.x.x).
VNET_ADDRESS_SPACE="${VNET_ADDRESS_SPACE:-10.10.0.0/16}"
SUBNET_APP_PREFIX="${SUBNET_APP_PREFIX:-10.10.1.0/24}"
SUBNET_PE_PREFIX="${SUBNET_PE_PREFIX:-10.10.2.0/24}"

readonly TAGS_JSON='"project":"centinela","week":"1","team":"celula-centinela","issue":"ISS-S1-005"'

# --- Helpers de nombrado (deterministas, iguales a ISS-S1-003/004) -------------

compute_storage_account_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%sst%s' "$prefix" "$hash"
}
compute_web_app_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-app-%s' "$prefix" "$hash"
}
compute_vnet_name() {
  printf '%s-vnet-week1' "$1"
}

# --- ARM template (VNet + subredes + zonas DNS privadas + links) ---------------

render_arm_template() {
  cat <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "vnetName":         { "type": "string" },
    "addressSpace":     { "type": "string" },
    "appSubnetPrefix":  { "type": "string" },
    "peSubnetPrefix":   { "type": "string" }
  },
  "variables": {
    "location": "[resourceGroup().location]"
  },
  "resources": [
    {
      "type": "Microsoft.Network/virtualNetworks",
      "apiVersion": "2023-09-01",
      "name": "[parameters('vnetName')]",
      "location": "[variables('location')]",
      "tags": { ${TAGS_JSON} },
      "properties": {
        "addressSpace": { "addressPrefixes": [ "[parameters('addressSpace')]" ] },
        "subnets": [
          {
            "name": "${SUBNET_APP}",
            "properties": {
              "addressPrefix": "[parameters('appSubnetPrefix')]",
              "delegations": [
                {
                  "name": "appServiceDelegation",
                  "properties": { "serviceName": "${APP_DELEGATION}" }
                }
              ],
              "privateEndpointNetworkPolicies": "Enabled",
              "serviceEndpoints": []
            }
          },
          {
            "name": "${SUBNET_PE}",
            "properties": {
              "addressPrefix": "[parameters('peSubnetPrefix')]",
              "privateEndpointNetworkPolicies": "Disabled",
              "serviceEndpoints": []
            }
          }
        ]
      }
    },
    {
      "type": "Microsoft.Network/privateDnsZones",
      "apiVersion": "2020-06-01",
      "name": "${DNS_ZONE_BLOB}",
      "location": "global",
      "tags": { ${TAGS_JSON} },
      "properties": {}
    },
    {
      "type": "Microsoft.Network/privateDnsZones",
      "apiVersion": "2020-06-01",
      "name": "${DNS_ZONE_QUEUE}",
      "location": "global",
      "tags": { ${TAGS_JSON} },
      "properties": {}
    },
    {
      "type": "Microsoft.Network/privateDnsZones/virtualNetworkLinks",
      "apiVersion": "2020-06-01",
      "name": "[concat('${DNS_ZONE_BLOB}', '/', parameters('vnetName'), '-blob-link')]",
      "location": "global",
      "dependsOn": [
        "[resourceId('Microsoft.Network/privateDnsZones', '${DNS_ZONE_BLOB}')]",
        "[resourceId('Microsoft.Network/virtualNetworks', parameters('vnetName'))]"
      ],
      "properties": {
        "registrationEnabled": false,
        "virtualNetwork": {
          "id": "[resourceId('Microsoft.Network/virtualNetworks', parameters('vnetName'))]"
        }
      }
    },
    {
      "type": "Microsoft.Network/privateDnsZones/virtualNetworkLinks",
      "apiVersion": "2020-06-01",
      "name": "[concat('${DNS_ZONE_QUEUE}', '/', parameters('vnetName'), '-queue-link')]",
      "location": "global",
      "dependsOn": [
        "[resourceId('Microsoft.Network/privateDnsZones', '${DNS_ZONE_QUEUE}')]",
        "[resourceId('Microsoft.Network/virtualNetworks', parameters('vnetName'))]"
      ],
      "properties": {
        "registrationEnabled": false,
        "virtualNetwork": {
          "id": "[resourceId('Microsoft.Network/virtualNetworks', parameters('vnetName'))]"
        }
      }
    }
  ]
}
JSON
}

render_arm_parameters() {
  local vnet_name="$1"
  cat <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "vnetName":        { "value": "${vnet_name}" },
    "addressSpace":    { "value": "${VNET_ADDRESS_SPACE}" },
    "appSubnetPrefix": { "value": "${SUBNET_APP_PREFIX}" },
    "peSubnetPrefix":  { "value": "${SUBNET_PE_PREFIX}" }
  }
}
JSON
}

# --- Side effects (Azure) -------------------------------------------------------

# Devuelve 0 si la VNet ya existe con las 2 subredes correctas y ambas zonas DNS
# vinculadas; 1 en cualquier otro caso (para decidir si desplegar el ARM).
assert_network_compliant_if_exists() {
  local vnet="$1" rg="$2"
  az network vnet show --name "$vnet" --resource-group "$rg" >/dev/null 2>&1 || return 1

  local app_deleg pe_policy z
  az network vnet subnet show --vnet-name "$vnet" --resource-group "$rg" --name "$SUBNET_APP" >/dev/null 2>&1 || return 1
  az network vnet subnet show --vnet-name "$vnet" --resource-group "$rg" --name "$SUBNET_PE"  >/dev/null 2>&1 || return 1

  app_deleg="$(az network vnet subnet show --vnet-name "$vnet" --resource-group "$rg" --name "$SUBNET_APP" \
    --query "delegations[0].serviceName" -o tsv 2>/dev/null || echo "")"
  [ "$app_deleg" = "$APP_DELEGATION" ] || return 1

  pe_policy="$(az network vnet subnet show --vnet-name "$vnet" --resource-group "$rg" --name "$SUBNET_PE" \
    --query "privateEndpointNetworkPolicies" -o tsv 2>/dev/null || echo "")"
  [ "$pe_policy" = "Disabled" ] || return 1

  for z in "$DNS_ZONE_BLOB" "$DNS_ZONE_QUEUE"; do
    az network private-dns zone show --name "$z" --resource-group "$rg" >/dev/null 2>&1 || return 1
    az network private-dns link vnet list --zone-name "$z" --resource-group "$rg" \
      --query "[?virtualNetwork.id != null] | length(@)" -o tsv 2>/dev/null | grep -q '^[1-9]' || return 1
  done
  return 0
}

deploy_network_via_arm() {
  local vnet="$1" rg="$2" template="$3" params="$4"
  log_info "Desplegando VNet '$vnet' + subredes + zonas DNS privadas via ARM..."
  with_retry 3 az deployment group create \
    --resource-group "$rg" \
    --template-file  "$template" \
    --parameters     @"$params" \
    --name "iss-s1-005-net-${vnet}" \
    >/dev/null
  log_info "Deployment ARM de red completado."
}

# Integra un sitio (produccion o slot) a snet-app-integration de forma idempotente.
ensure_vnet_integration() {
  local app="$1" rg="$2" vnet="$3" scope="$4"   # scope: "" (prod) o nombre de slot
  local slot_args=() label="produccion" current subnet_id
  if [ -n "$scope" ]; then slot_args=(--slot "$scope"); label="slot '$scope'"; fi

  current="$(az webapp show --name "$app" --resource-group "$rg" "${slot_args[@]}" \
    --query "virtualNetworkSubnetId" -o tsv 2>/dev/null || echo "")"
  if printf '%s' "$current" | grep -q "/subnets/${SUBNET_APP}$"; then
    log_info "  VNet Integration ya activa en $label."
    return 0
  fi
  log_info "  Integrando $label a ${SUBNET_APP}..."
  with_retry 3 az webapp vnet-integration add \
    --name "$app" --resource-group "$rg" "${slot_args[@]}" \
    --vnet "$vnet" --subnet "$SUBNET_APP" >/dev/null
  log_info "  OK VNet Integration en $label."
}

verify_all_resources() {
  local vnet="$1" rg="$2" app="$3"

  log_info "Verificando VNet y subredes..."
  # Las subredes son recursos hijo: se reintenta antes de darlas por ausentes.
  retry_until 5 az network vnet show --name "$vnet" --resource-group "$rg" || die "No existe la VNet '$vnet'."
  retry_until 5 az network vnet subnet show --vnet-name "$vnet" --resource-group "$rg" --name "$SUBNET_APP" || die "Falta $SUBNET_APP."
  retry_until 5 az network vnet subnet show --vnet-name "$vnet" --resource-group "$rg" --name "$SUBNET_PE"  || die "Falta $SUBNET_PE."
  local subnet_count
  subnet_count="$(az network vnet show --name "$vnet" --resource-group "$rg" \
    --query "length(subnets)" -o tsv 2>/dev/null || echo 0)"
  [ "$subnet_count" = "2" ] || die "La VNet debe tener exactamente 2 subredes (actual: $subnet_count)."
  log_info "  OK 2 subredes: $SUBNET_APP (delegada) y $SUBNET_PE (PE)."

  log_info "Verificando zonas DNS privadas y vinculos..."
  local z
  for z in "$DNS_ZONE_BLOB" "$DNS_ZONE_QUEUE"; do
    retry_until 5 az network private-dns zone show --name "$z" --resource-group "$rg" || die "Falta zona DNS: $z"
    az network private-dns link vnet list --zone-name "$z" --resource-group "$rg" \
      --query "[?virtualNetwork.id != null] | length(@)" -o tsv 2>/dev/null | grep -q '^[1-9]' \
      || die "Zona DNS '$z' sin vinculo a la VNet."
    log_info "  OK zona '$z' vinculada a la VNet."
  done

  log_info "Verificando VNet Integration (produccion y staging)..."
  local prod_sub staging_sub
  prod_sub="$(az webapp show --name "$app" --resource-group "$rg" \
    --query "virtualNetworkSubnetId" -o tsv 2>/dev/null || echo "")"
  staging_sub="$(az webapp show --name "$app" --resource-group "$rg" --slot "$SLOT_NAME" \
    --query "virtualNetworkSubnetId" -o tsv 2>/dev/null || echo "")"
  printf '%s' "$prod_sub"    | grep -q "/subnets/${SUBNET_APP}$" || die "Produccion sin VNet Integration a $SUBNET_APP."
  printf '%s' "$staging_sub" | grep -q "/subnets/${SUBNET_APP}$" || die "Staging sin VNet Integration a $SUBNET_APP."
  log_info "  OK produccion y staging integrados a $SUBNET_APP."
}

# --- Main ----------------------------------------------------------------------

main() {
  load_parameters
  validate_parameters

  require_cmd az
  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login' primero."
  local active_sub; active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "Resource Group '$RESOURCE_GROUP' no existe. Ejecuta primero deploy-week1.sh."

  local vnet_name app_name sa_name
  vnet_name="$(compute_vnet_name "$NAME_PREFIX")"
  app_name="$(compute_web_app_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  sa_name="$(compute_storage_account_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"

  az webapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "La Web App '$app_name' no existe. Ejecuta primero scripts/provision-app-service.sh (ISS-S1-004)."
  az storage account show --name "$sa_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "El Storage '$sa_name' no existe. Ejecuta primero scripts/provision-storage.sh (ISS-S1-003)."

  log_info "VNet objetivo:   $vnet_name ($VNET_ADDRESS_SPACE)"
  log_info "  $SUBNET_APP -> $SUBNET_APP_PREFIX (delegada a $APP_DELEGATION)"
  log_info "  $SUBNET_PE  -> $SUBNET_PE_PREFIX (PE policies Disabled)"
  log_info "Web App:         $app_name  (+ slot $SLOT_NAME)"

  if assert_network_compliant_if_exists "$vnet_name" "$RESOURCE_GROUP"; then
    log_info "VNet + subredes + zonas DNS ya existen y cumplen. Sin cambios de topologia."
  else
    local tmp_dir template_file params_file
    tmp_dir="$(mktemp -d)"
    trap "rm -rf '$tmp_dir'" EXIT
    template_file="$tmp_dir/network.template.json"
    params_file="$tmp_dir/network.parameters.json"
    render_arm_template > "$template_file"
    render_arm_parameters "$vnet_name" > "$params_file"
    deploy_network_via_arm "$vnet_name" "$RESOURCE_GROUP" "$template_file" "$params_file"
  fi

  log_info "Asegurando VNet Integration..."
  ensure_vnet_integration "$app_name" "$RESOURCE_GROUP" "$vnet_name" ""
  ensure_vnet_integration "$app_name" "$RESOURCE_GROUP" "$vnet_name" "$SLOT_NAME"

  verify_all_resources "$vnet_name" "$RESOURCE_GROUP" "$app_name"
  log_info "ISS-S1-005 (red) OK: VNet '$vnet_name', 2 subredes, 2 zonas DNS y VNet Integration listos."
  log_info "Siguiente paso: scripts/configure-private-endpoints.sh (Private Endpoints Blob/Queue)."
}

main "$@"
