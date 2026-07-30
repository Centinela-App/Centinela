#!/usr/bin/env bash
#
# scripts/provision-network-containerapps.sh
# Red privada para la topologia de Semana 3: Container Apps en lugar de App Service.
#
# POR QUE EXISTE ESTE SCRIPT Y NO SE MODIFICO provision-network.sh
# ----------------------------------------------------------------
# provision-network.sh integra la Web App y su slot a la VNet, y exige que
# ambos existan. Es correcto para la topologia de Semana 1 y sigue siendo la
# referencia de esa entrega; modificarlo para que el App Service fuera opcional
# habria dejado un script que sirve a dos arquitecturas y no describe bien
# ninguna.
#
# La suscripcion de la celula no tiene cuota de App Service en la region del
# proyecto. Como ADR-009 ya sustituye el App Service por Container Apps, la
# salida no es cambiar de region sino desplegar la topologia a la que el
# proyecto ya se dirigia.
#
# DIFERENCIAS CON LA RED DE SEMANA 1
# ----------------------------------
#   - snet-app-integration (delegada a Microsoft.Web/serverFarms) desaparece.
#   - snet-container-apps la sustituye, delegada a Microsoft.App/environments.
#   - snet-private-endpoints se conserva sin cambios: los almacenes siguen sin
#     ser alcanzables desde internet, que es el requisito no negociable.
#
# El /23 de la subred de contenedores no es arbitrario: el perfil Consumption de
# Container Apps exige ese tamano minimo. Con un /24 la creacion del entorno
# falla con un error que no menciona el prefijo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

readonly SUBNET_PE="snet-private-endpoints"
readonly SUBNET_ACA="snet-container-apps"
readonly ACA_DELEGATION="Microsoft.App/environments"

VNET_ADDRESS_SPACE="${VNET_ADDRESS_SPACE:-10.10.0.0/16}"
SUBNET_PE_PREFIX="${SUBNET_PE_PREFIX:-10.10.2.0/24}"
SUBNET_ACA_PREFIX="${SUBNET_ACA_PREFIX:-10.10.4.0/23}"

# Solo las zonas que pertenecen a la red base (las del Storage de Semana 1).
#
# Las de Cosmos, PostgreSQL, Key Vault y Table las crea y enlaza CADA script de
# servicio, que es el patron que Semana 2 ya estableci0. Crearlas tambien aqui
# parecia previsor y rompio el despliegue: una zona privada admite UN solo
# enlace por VNet, asi que el segundo en llegar falla con Conflict. El error no
# dice "esto lo hace otro script"; dice que la zona ya esta enlazada, y hay que
# ir a buscar quien la enlazo.
#
# La leccion es de propiedad, no de DNS: dos scripts que crean el mismo recurso
# no son redundancia, son un conflicto esperando su turno.
readonly DNS_ZONES=(
  "privatelink.blob.core.windows.net"
  "privatelink.queue.core.windows.net"
)

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
  require_cmd az

  local vnet="${NAME_PREFIX}-vnet-week1"

  log_info "Plan de red para Container Apps:"
  log_info "  VNet                 : $vnet ($VNET_ADDRESS_SPACE)"
  log_info "  Subred de PE         : $SUBNET_PE ($SUBNET_PE_PREFIX)"
  log_info "  Subred de contenedores: $SUBNET_ACA ($SUBNET_ACA_PREFIX, delegada a $ACA_DELEGATION)"
  log_info "  Zonas DNS privadas   : ${#DNS_ZONES[@]}"

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "Modo --validate-only: no se crea nada."
    exit 0
  fi

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."
  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 || die "Falta el Resource Group."

  ensure_vnet "$vnet"
  ensure_subnet_pe "$vnet"
  ensure_subnet_aca "$vnet"
  ensure_dns_zones "$vnet"
  verify "$vnet"

  log_info "Red lista."
  log_info "  SUBNET_ACA_ID=$(subnet_id "$vnet" "$SUBNET_ACA")"
}

ensure_vnet() {
  local vnet="$1"
  if az network vnet show -g "$RESOURCE_GROUP" -n "$vnet" >/dev/null 2>&1; then
    log_info "VNet '$vnet' ya existe."
    return
  fi
  log_info "Creando VNet '$vnet'..."
  az network vnet create -g "$RESOURCE_GROUP" -n "$vnet" -l "$LOCATION" \
    --address-prefixes "$VNET_ADDRESS_SPACE" --output none
}

ensure_subnet_pe() {
  local vnet="$1"
  if az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$vnet" -n "$SUBNET_PE" >/dev/null 2>&1; then
    log_info "Subred '$SUBNET_PE' ya existe."
  else
    log_info "Creando subred '$SUBNET_PE'..."
    az network vnet subnet create -g "$RESOURCE_GROUP" --vnet-name "$vnet" -n "$SUBNET_PE" \
      --address-prefixes "$SUBNET_PE_PREFIX" --output none
  fi

  # Sin esto, Azure aplica politicas de red que impiden crear Private Endpoints
  # en la subred, con un error que habla de politicas y no de esta propiedad.
  az network vnet subnet update -g "$RESOURCE_GROUP" --vnet-name "$vnet" -n "$SUBNET_PE" \
    --private-endpoint-network-policies Disabled --output none
}

ensure_subnet_aca() {
  local vnet="$1"
  if az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$vnet" -n "$SUBNET_ACA" >/dev/null 2>&1; then
    log_info "Subred '$SUBNET_ACA' ya existe."
    return
  fi
  log_info "Creando subred '$SUBNET_ACA' delegada a $ACA_DELEGATION..."
  az network vnet subnet create -g "$RESOURCE_GROUP" --vnet-name "$vnet" -n "$SUBNET_ACA" \
    --address-prefixes "$SUBNET_ACA_PREFIX" \
    --delegations "$ACA_DELEGATION" --output none
}

ensure_dns_zones() {
  local vnet="$1"
  local vnet_id; vnet_id="$(az network vnet show -g "$RESOURCE_GROUP" -n "$vnet" --query id -o tsv)"

  for zona in "${DNS_ZONES[@]}"; do
    if ! az network private-dns zone show -g "$RESOURCE_GROUP" -n "$zona" >/dev/null 2>&1; then
      log_info "  Creando zona DNS privada '$zona'..."
      az network private-dns zone create -g "$RESOURCE_GROUP" -n "$zona" --output none
    fi

    # El enlace a la VNet es lo que hace que la zona sea consultable desde
    # dentro. Una zona sin enlace existe y no resuelve nada — el fallo mas
    # silencioso de esta parte de la infraestructura.
    local enlace="${vnet}-link"
    if ! az network private-dns link vnet show -g "$RESOURCE_GROUP" -z "$zona" -n "$enlace" >/dev/null 2>&1; then
      log_info "    Enlazando '$zona' a la VNet..."
      az network private-dns link vnet create -g "$RESOURCE_GROUP" -z "$zona" -n "$enlace" \
        --virtual-network "$vnet_id" --registration-enabled false --output none
    fi
  done
}

subnet_id() {
  az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$1" -n "$2" --query id -o tsv
}

verify() {
  local vnet="$1"

  az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$vnet" -n "$SUBNET_PE" >/dev/null \
    || die "Falta la subred $SUBNET_PE."

  local delegacion
  delegacion="$(az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$vnet" -n "$SUBNET_ACA" \
    --query "delegations[0].serviceName" -o tsv 2>/dev/null)"
  [ "$delegacion" = "$ACA_DELEGATION" ] \
    || die "La subred $SUBNET_ACA no esta delegada a $ACA_DELEGATION (actual: '${delegacion:-ninguna}')."

  local politicas
  politicas="$(az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$vnet" -n "$SUBNET_PE" \
    --query "privateEndpointNetworkPolicies" -o tsv 2>/dev/null)"
  [ "$politicas" = "Disabled" ] \
    || die "La subred $SUBNET_PE tiene politicas de red habilitadas: no admitira Private Endpoints."

  local zonas_ok=0
  for zona in "${DNS_ZONES[@]}"; do
    az network private-dns zone show -g "$RESOURCE_GROUP" -n "$zona" >/dev/null 2>&1 \
      && zonas_ok=$((zonas_ok + 1))
  done
  [ "$zonas_ok" -eq "${#DNS_ZONES[@]}" ] \
    || die "Solo $zonas_ok de ${#DNS_ZONES[@]} zonas DNS existen."

  log_info "Verificacion: 2 subredes, delegacion correcta, politicas de PE deshabilitadas y $zonas_ok zonas DNS."
}

main "$@"
