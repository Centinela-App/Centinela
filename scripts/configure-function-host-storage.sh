#!/usr/bin/env bash
# ISS-S2-007 corrective integration: complete the private Storage path used by
# the Azure Functions host. Week 1 already creates Blob and Queue private
# endpoints; the host also needs the Table endpoint for identity-based storage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

readonly SUBNET_PE="snet-private-endpoints"
readonly DNS_ZONE_TABLE="privatelink.table.core.windows.net"

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
compute_vnet_name() { printf '%s-vnet-week1' "$NAME_PREFIX"; }

ensure_private_dns_zone() {
  local vnet="$1" link
  link="${vnet}-table-link"
  if az network private-dns zone show --name "$DNS_ZONE_TABLE" \
      --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "Zona DNS privada '$DNS_ZONE_TABLE' ya existe."
  else
    log_info "Creando zona DNS privada '$DNS_ZONE_TABLE'..."
    with_retry 3 az network private-dns zone create \
      --name "$DNS_ZONE_TABLE" --resource-group "$RESOURCE_GROUP" --output none
  fi

  if az network private-dns link vnet show --zone-name "$DNS_ZONE_TABLE" \
      --resource-group "$RESOURCE_GROUP" --name "$link" >/dev/null 2>&1; then
    log_info "Vinculo VNet '$link' ya existe."
  else
    log_info "Vinculando '$DNS_ZONE_TABLE' con '$vnet'..."
    with_retry 3 az network private-dns link vnet create \
      --zone-name "$DNS_ZONE_TABLE" --resource-group "$RESOURCE_GROUP" \
      --name "$link" --virtual-network "$vnet" \
      --registration-enabled false --output none
  fi
}

ensure_table_private_endpoint() {
  local storage="$1" vnet="$2" pe storage_id
  pe="${storage}-table-pe"
  storage_id="$(az storage account show --name "$storage" \
    --resource-group "$RESOURCE_GROUP" --query id -o tsv)"

  if az network private-endpoint show --name "$pe" \
      --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "Private Endpoint '$pe' ya existe."
  else
    log_info "Creando Private Endpoint '$pe' para Storage Table..."
    with_retry 3 az network private-endpoint create \
      --name "$pe" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" \
      --vnet-name "$vnet" --subnet "$SUBNET_PE" \
      --private-connection-resource-id "$storage_id" \
      --group-id table --connection-name "${pe}-plsc" --output none
  fi

  if az network private-endpoint dns-zone-group show \
      --resource-group "$RESOURCE_GROUP" --endpoint-name "$pe" \
      --name default >/dev/null 2>&1; then
    log_info "DNS zone group de '$pe' ya existe."
  else
    log_info "Registrando la IP privada de Table en '$DNS_ZONE_TABLE'..."
    with_retry 3 az network private-endpoint dns-zone-group create \
      --resource-group "$RESOURCE_GROUP" --endpoint-name "$pe" \
      --name default --private-dns-zone "$DNS_ZONE_TABLE" \
      --zone-name table --output none
  fi
}

verify_private_path() {
  local storage="$1" pe group state records public_access
  pe="${storage}-table-pe"
  group="$(az network private-endpoint show --name "$pe" \
    --resource-group "$RESOURCE_GROUP" \
    --query 'privateLinkServiceConnections[0].groupIds[0]' -o tsv)"
  [ "$group" = "table" ] || die "PE '$pe' apunta a '$group' y no a 'table'."

  state="$(az network private-endpoint show --name "$pe" \
    --resource-group "$RESOURCE_GROUP" \
    --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status' \
    -o tsv 2>/dev/null || echo '')"
  [ "$state" = "Approved" ] || log_warn "PE '$pe' en estado '${state:-desconocido}'."

  records="$(az network private-dns record-set a list \
    --zone-name "$DNS_ZONE_TABLE" --resource-group "$RESOURCE_GROUP" \
    --query 'length(@)' -o tsv 2>/dev/null || echo 0)"
  [ "${records:-0}" -ge 1 ] 2>/dev/null \
    || die "La zona '$DNS_ZONE_TABLE' no tiene registros A."

  public_access="$(az storage account show --name "$storage" \
    --resource-group "$RESOURCE_GROUP" --query publicNetworkAccess -o tsv)"
  [ "$public_access" = "Disabled" ] \
    || die "Storage publicNetworkAccess='$public_access'; se esperaba Disabled."

  log_info "Ruta privada de Storage Table validada: PE aprobado, DNS privado y acceso publico bloqueado."
}

main() {
  load_parameters
  validate_parameters
  require_cmd az

  local storage vnet
  storage="$(compute_storage_account_name)"
  vnet="$(compute_vnet_name)"

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "--validate-only: nombres y parametros validos; no se crean recursos."
    return 0
  fi

  az account show >/dev/null 2>&1 \
    || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  [ "$(az account show --query id -o tsv)" = "$SUBSCRIPTION_ID" ] \
    || die "La suscripcion activa no coincide con SUBSCRIPTION_ID."
  az storage account show --name "$storage" --resource-group "$RESOURCE_GROUP" \
    >/dev/null 2>&1 || die "No existe Storage '$storage'."
  az network vnet subnet show --vnet-name "$vnet" \
    --resource-group "$RESOURCE_GROUP" --name "$SUBNET_PE" >/dev/null 2>&1 \
    || die "No existe '$vnet/$SUBNET_PE'."

  ensure_private_dns_zone "$vnet"
  ensure_table_private_endpoint "$storage" "$vnet"
  verify_private_path "$storage"
}

main "$@"
