#!/usr/bin/env bash
# ISS-S2-007 corrective integration: complete the private Storage path used by
# the Azure Functions host. Week 1 already creates Blob and Queue private
# endpoints; the host needs two mas:
#
#   table -> estado interno del host con acceso por identidad.
#   file  -> el host MONTA un recurso compartido de Azure Files como su sistema
#            de archivos. Con el Storage en publicNetworkAccess=Disabled y sin
#            este endpoint, el montaje falla, el contenedor se termina con
#            "Container failed to remount volume. Terminate." y la Function App
#            responde 503 indefinidamente aunque ARM la reporte 'Running'.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

readonly SUBNET_PE="snet-private-endpoints"
# Subrecursos de Storage que el host de Functions necesita por red privada.
readonly HOST_SUBRESOURCES=(table file)

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

# ensure_private_dns_zone <vnet> <subrecurso> — crea y vincula la zona privada
# 'privatelink.<subrecurso>.core.windows.net'.
ensure_private_dns_zone() {
  local vnet="$1" sub="$2" zone link
  zone="privatelink.${sub}.core.windows.net"
  link="${vnet}-${sub}-link"
  if az network private-dns zone show --name "$zone" \
      --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "Zona DNS privada '$zone' ya existe."
  else
    log_info "Creando zona DNS privada '$zone'..."
    with_retry 3 az network private-dns zone create \
      --name "$zone" --resource-group "$RESOURCE_GROUP" --output none
  fi

  if az network private-dns link vnet show --zone-name "$zone" \
      --resource-group "$RESOURCE_GROUP" --name "$link" >/dev/null 2>&1; then
    log_info "Vinculo VNet '$link' ya existe."
  else
    log_info "Vinculando '$zone' con '$vnet'..."
    with_retry 3 az network private-dns link vnet create \
      --zone-name "$zone" --resource-group "$RESOURCE_GROUP" \
      --name "$link" --virtual-network "$vnet" \
      --registration-enabled false --output none
  fi
}

# ensure_storage_private_endpoint <storage> <vnet> <subrecurso>
ensure_storage_private_endpoint() {
  local storage="$1" vnet="$2" sub="$3" pe zone storage_id
  pe="${storage}-${sub}-pe"
  zone="privatelink.${sub}.core.windows.net"
  storage_id="$(az storage account show --name "$storage" \
    --resource-group "$RESOURCE_GROUP" --query id -o tsv)"

  if az network private-endpoint show --name "$pe" \
      --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "Private Endpoint '$pe' ya existe."
  else
    log_info "Creando Private Endpoint '$pe' para Storage ${sub}..."
    with_retry 3 az network private-endpoint create \
      --name "$pe" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" \
      --vnet-name "$vnet" --subnet "$SUBNET_PE" \
      --private-connection-resource-id "$storage_id" \
      --group-id "$sub" --connection-name "${pe}-plsc" --output none
  fi

  if pe_dns_zone_group_exists "$pe" "$RESOURCE_GROUP"; then
    log_info "DNS zone group de '$pe' ya existe."
  else
    log_info "Registrando la IP privada de ${sub} en '$zone'..."
    with_retry 3 az network private-endpoint dns-zone-group create \
      --resource-group "$RESOURCE_GROUP" --endpoint-name "$pe" \
      --name default --private-dns-zone "$zone" \
      --zone-name "$sub" --output none
  fi
}

verify_private_path() {
  local storage="$1" sub pe group state zone public_access

  for sub in "${HOST_SUBRESOURCES[@]}"; do
    pe="${storage}-${sub}-pe"
    zone="privatelink.${sub}.core.windows.net"

    group="$(az network private-endpoint show --name "$pe" \
      --resource-group "$RESOURCE_GROUP" \
      --query 'privateLinkServiceConnections[0].groupIds[0]' -o tsv)"
    [ "$group" = "$sub" ] || die "PE '$pe' apunta a '$group' y no a '$sub'."

    state="$(az network private-endpoint show --name "$pe" \
      --resource-group "$RESOURCE_GROUP" \
      --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status' \
      -o tsv 2>/dev/null || echo '')"
    [ "$state" = "Approved" ] || log_warn "PE '$pe' en estado '${state:-desconocido}'."

    # El registro A lo publica Azure de forma asincrona tras crear el zone group:
    # sin espera, la verificacion falla por carrera aunque todo este bien creado.
    retry_until 8 private_dns_has_a_records "$zone" "$RESOURCE_GROUP" \
      || die "La zona '$zone' no tiene registros A tras esperar su publicacion."
    log_info "  OK ruta privada de Storage ${sub}: PE aprobado y DNS privado resuelto."
  done

  public_access="$(az storage account show --name "$storage" \
    --resource-group "$RESOURCE_GROUP" --query publicNetworkAccess -o tsv)"
  [ "$public_access" = "Disabled" ] \
    || die "Storage publicNetworkAccess='$public_access'; se esperaba Disabled."

  log_info "Ruta privada del host de Functions validada; acceso publico bloqueado."
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

  local sub
  for sub in "${HOST_SUBRESOURCES[@]}"; do
    ensure_private_dns_zone "$vnet" "$sub"
    ensure_storage_private_endpoint "$storage" "$vnet" "$sub"
  done
  verify_private_path "$storage"
}

main "$@"
