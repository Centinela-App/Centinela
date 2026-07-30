#!/usr/bin/env bash
#
# scripts/configure-private-endpoints.sh
# ISS-S1-005 - Crear los Private Endpoints de Blob y Queue del Storage y vincularlos
#              a las zonas DNS privadas (registro A automatico via privateDnsZoneGroup).
#
# Alcance ESTRICTO (se ejecuta DESPUES de provision-network.sh):
#   - Crear/asegurar 2 Private Endpoints en snet-private-endpoints:
#       * <sa>-blob-pe  -> subrecurso 'blob'  del Storage Account.
#       * <sa>-queue-pe -> subrecurso 'queue' del Storage Account.
#   - Crear/asegurar los privateDnsZoneGroups que registran las IP privadas en:
#       * privatelink.blob.core.windows.net
#       * privatelink.queue.core.windows.net
#   - Verificar que el acceso publico del Storage permanece Disabled (ISS-S1-003).
#
# No modifica la VNet ni el Storage (los crean ISS-S1-003 y provision-network.sh);
# no abre acceso publico en ningun momento.
#
# Prerequisitos: VNet + subredes + zonas DNS (provision-network.sh) y Storage (ISS-S1-003).
#
# Variables (ver scripts/lib/parameters.sh):
#   SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX, APP_SERVICE_SKU

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parameters.sh"

# --- Constantes de la Issue 5 ---------------------------------------------------

readonly SUBNET_PE="snet-private-endpoints"
readonly DNS_ZONE_BLOB="privatelink.blob.core.windows.net"
readonly DNS_ZONE_QUEUE="privatelink.queue.core.windows.net"
readonly TAGS_JSON='"project":"centinela","week":"1","team":"celula-centinela","issue":"ISS-S1-005"'

# --- Helpers de nombrado (deterministas, iguales a ISS-S1-003/004/005) ---------

compute_storage_account_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%sst%s' "$prefix" "$hash"
}
compute_vnet_name() { printf '%s-vnet-week1' "$1"; }

# --- ARM template (Private Endpoints + privateDnsZoneGroups) -------------------

render_arm_template() {
  cat <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "storageAccountName": { "type": "string" },
    "vnetName":           { "type": "string" },
    "blobPeName":         { "type": "string" },
    "queuePeName":        { "type": "string" }
  },
  "variables": {
    "location":     "[resourceGroup().location]",
    "storageId":    "[resourceId('Microsoft.Storage/storageAccounts', parameters('storageAccountName'))]",
    "peSubnetId":   "[resourceId('Microsoft.Network/virtualNetworks/subnets', parameters('vnetName'), '${SUBNET_PE}')]",
    "blobZoneId":   "[resourceId('Microsoft.Network/privateDnsZones', '${DNS_ZONE_BLOB}')]",
    "queueZoneId":  "[resourceId('Microsoft.Network/privateDnsZones', '${DNS_ZONE_QUEUE}')]"
  },
  "resources": [
    {
      "type": "Microsoft.Network/privateEndpoints",
      "apiVersion": "2023-09-01",
      "name": "[parameters('blobPeName')]",
      "location": "[variables('location')]",
      "tags": { ${TAGS_JSON} },
      "properties": {
        "subnet": { "id": "[variables('peSubnetId')]" },
        "privateLinkServiceConnections": [
          {
            "name": "[concat(parameters('blobPeName'), '-plsc')]",
            "properties": {
              "privateLinkServiceId": "[variables('storageId')]",
              "groupIds": [ "blob" ]
            }
          }
        ]
      }
    },
    {
      "type": "Microsoft.Network/privateEndpoints/privateDnsZoneGroups",
      "apiVersion": "2023-09-01",
      "name": "[concat(parameters('blobPeName'), '/default')]",
      "dependsOn": [
        "[resourceId('Microsoft.Network/privateEndpoints', parameters('blobPeName'))]"
      ],
      "properties": {
        "privateDnsZoneConfigs": [
          {
            "name": "blob",
            "properties": { "privateDnsZoneId": "[variables('blobZoneId')]" }
          }
        ]
      }
    },
    {
      "type": "Microsoft.Network/privateEndpoints",
      "apiVersion": "2023-09-01",
      "name": "[parameters('queuePeName')]",
      "location": "[variables('location')]",
      "tags": { ${TAGS_JSON} },
      "properties": {
        "subnet": { "id": "[variables('peSubnetId')]" },
        "privateLinkServiceConnections": [
          {
            "name": "[concat(parameters('queuePeName'), '-plsc')]",
            "properties": {
              "privateLinkServiceId": "[variables('storageId')]",
              "groupIds": [ "queue" ]
            }
          }
        ]
      }
    },
    {
      "type": "Microsoft.Network/privateEndpoints/privateDnsZoneGroups",
      "apiVersion": "2023-09-01",
      "name": "[concat(parameters('queuePeName'), '/default')]",
      "dependsOn": [
        "[resourceId('Microsoft.Network/privateEndpoints', parameters('queuePeName'))]"
      ],
      "properties": {
        "privateDnsZoneConfigs": [
          {
            "name": "queue",
            "properties": { "privateDnsZoneId": "[variables('queueZoneId')]" }
          }
        ]
      }
    }
  ]
}
JSON
}

render_arm_parameters() {
  local sa_name="$1" vnet_name="$2" blob_pe="$3" queue_pe="$4"
  cat <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "storageAccountName": { "value": "${sa_name}" },
    "vnetName":           { "value": "${vnet_name}" },
    "blobPeName":         { "value": "${blob_pe}" },
    "queuePeName":        { "value": "${queue_pe}" }
  }
}
JSON
}

# --- Side effects (Azure) -------------------------------------------------------

deploy_private_endpoints_via_arm() {
  local sa_name="$1" rg="$2" template="$3" params="$4"
  log_info "Desplegando Private Endpoints (blob + queue) + DNS zone groups via ARM..."
  with_retry 3 az deployment group create \
    --resource-group "$rg" \
    --template-file  "$template" \
    --parameters     @"$params" \
    --name "iss-s1-005-pe-${sa_name}" \
    >/dev/null
  log_info "Deployment ARM de Private Endpoints completado."
}

verify_all_resources() {
  local rg="$1" sa_name="$2" blob_pe="$3" queue_pe="$4"

  log_info "Verificando Private Endpoints y su conexion aprobada..."
  local pe_group pe group gid state
  for pe_group in "${blob_pe}:blob" "${queue_pe}:queue"; do
    pe="${pe_group%%:*}"; group="${pe_group##*:}"
    retry_until 5 az network private-endpoint show --name "$pe" --resource-group "$rg" \
      || die "Falta Private Endpoint: $pe"
    gid="$(az network private-endpoint show --name "$pe" --resource-group "$rg" \
      --query "privateLinkServiceConnections[0].groupIds[0]" -o tsv 2>/dev/null || echo "")"
    [ "$gid" = "$group" ] || die "PE '$pe' apunta a groupId '$gid' (esperado '$group')."
    state="$(az network private-endpoint show --name "$pe" --resource-group "$rg" \
      --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv 2>/dev/null || echo "")"
    [ "$state" = "Approved" ] || log_warn "PE '$pe' en estado '$state' (esperado 'Approved')."
    log_info "  OK PE '$pe' -> subrecurso '$group' (estado: ${state:-?})."
  done

  # El privateDnsZoneGroup registra la IP privada de forma ASINCRONA: el A record
  # aparece segundos despues de que el PE quede aprobado. Se espera antes de fallar.
  log_info "Verificando registro DNS privado (A records) en las zonas..."
  local z n
  zone_has_a_records() {
    local zone="$1" rgroup="$2" count
    count="$(az network private-dns record-set a list --zone-name "$zone" --resource-group "$rgroup" \
      --query "length(@)" -o tsv 2>/dev/null || echo 0)"
    [ "${count:-0}" -ge 1 ] 2>/dev/null
  }
  for z in "$DNS_ZONE_BLOB" "$DNS_ZONE_QUEUE"; do
    retry_until 8 zone_has_a_records "$z" "$rg" \
      || die "Zona DNS '$z' sin registros A (el privateDnsZoneGroup no registro la IP privada)."
    n="$(az network private-dns record-set a list --zone-name "$z" --resource-group "$rg" \
      --query "length(@)" -o tsv 2>/dev/null || echo 0)"
    log_info "  OK zona '$z' con $n registro(s) A privado(s)."
  done

  log_info "Verificando que el acceso publico del Storage sigue Disabled..."
  local pub_net
  pub_net="$(az storage account show --name "$sa_name" --resource-group "$rg" \
    --query "publicNetworkAccess" -o tsv 2>/dev/null || echo "")"
  [ "$pub_net" = "Disabled" ] || die "publicNetworkAccess del Storage = '$pub_net' (esperado 'Disabled')."
  log_info "  OK Storage con publicNetworkAccess=Disabled."
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

  local sa_name vnet_name blob_pe queue_pe
  sa_name="$(compute_storage_account_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  vnet_name="$(compute_vnet_name "$NAME_PREFIX")"
  blob_pe="${sa_name}-blob-pe"
  queue_pe="${sa_name}-queue-pe"

  az storage account show --name "$sa_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "El Storage '$sa_name' no existe (ISS-S1-003)."
  az network vnet subnet show --vnet-name "$vnet_name" --resource-group "$RESOURCE_GROUP" --name "$SUBNET_PE" >/dev/null 2>&1 \
    || die "No existe la subred '$SUBNET_PE' en '$vnet_name'. Ejecuta primero scripts/provision-network-containerapps.sh."
  az network private-dns zone show --name "$DNS_ZONE_BLOB"  --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "Falta la zona DNS '$DNS_ZONE_BLOB'. Ejecuta primero scripts/provision-network-containerapps.sh."
  az network private-dns zone show --name "$DNS_ZONE_QUEUE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "Falta la zona DNS '$DNS_ZONE_QUEUE'. Ejecuta primero scripts/provision-network-containerapps.sh."

  log_info "Storage:      $sa_name"
  log_info "VNet/subred:  $vnet_name / $SUBNET_PE"
  log_info "PE objetivo:  $blob_pe (blob), $queue_pe (queue)"

  local tmp_dir template_file params_file
  tmp_dir="$(mktemp -d)"
  trap "rm -rf '$tmp_dir'" EXIT
  template_file="$tmp_dir/pe.template.json"
  params_file="$tmp_dir/pe.parameters.json"
  render_arm_template > "$template_file"
  render_arm_parameters "$sa_name" "$vnet_name" "$blob_pe" "$queue_pe" > "$params_file"

  # ARM declarativo: reejecutar converge al mismo estado (idempotente).
  deploy_private_endpoints_via_arm "$sa_name" "$RESOURCE_GROUP" "$template_file" "$params_file"

  verify_all_resources "$RESOURCE_GROUP" "$sa_name" "$blob_pe" "$queue_pe"
  log_info "ISS-S1-005 (PE) OK: Blob y Queue accesibles por red privada; acceso publico bloqueado."
}

main "$@"
