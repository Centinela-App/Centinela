#!/usr/bin/env bash
#
# scripts/provision-cosmos.sh
# ISS-S2-001 - Provisionar Cosmos DB for MongoDB (almacen de transacciones + scores).
#
# Alcance ESTRICTO de la Issue S2-001:
#   - Crear/asegurar 1 cuenta Cosmos DB (API MongoDB) con Free Tier habilitado.
#   - Crear la base 'centinela' y la coleccion 'transactions'.
#   - Definir la shard key = 'accountId' (agrupa el historial de una cuenta en una
#     particion; la consulta dominante "historial reciente de una cuenta" toca una
#     sola particion). NO se puede cambiar tras la primera escritura.
#   - Configurar el nivel de consistencia de cuenta (Session, ver ADR-007).
#   - Configurar TTL en la coleccion alineado a la ventana mas larga de las reglas.
#   - Deshabilitar acceso publico y exponer el data plane solo mediante Private
#     Endpoint en la VNet de Semana 1, con DNS privado para API MongoDB.
#   - Idempotente: reejecutar converge al mismo estado sin duplicar recursos.
#
# No hace nada fuera de este alcance (sin adaptador Java, sin modelo de score,
# sin datos de negocio).
#
# Prerequisitos (validados al inicio):
#   - Azure CLI disponible (se ejecuta en Azure Cloud Shell).
#   - Sesion activa y suscripcion igual a SUBSCRIPTION_ID.
#   - Resource Group RESOURCE_GROUP ya creado (Semana 1).
#
# Variables (cargadas de .env o entorno, ver scripts/lib/parameters.sh):
#   SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX
#
# Variables opcionales (con defaults):
#   COSMOS_CONSISTENCY   nivel de consistencia de la cuenta (default: Session)
#   COSMOS_TTL_SECONDS   TTL de la coleccion en segundos    (default: 7776000 = 90 dias)
#   COSMOS_MONGO_VERSION version del server API MongoDB      (default: 4.2)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parameters.sh"

# --- Constantes de la Issue S2-001 ---------------------------------------------

readonly DATABASE_NAME="centinela"
readonly COLLECTION_NAME="transactions"
readonly SHARD_KEY="accountId"
readonly SUBNET_PE="snet-private-endpoints"
readonly DNS_ZONE_MONGO="privatelink.mongo.cosmos.azure.com"

# Defaults sobreescribibles por entorno.
readonly CONSISTENCY="${COSMOS_CONSISTENCY:-Session}"
readonly TTL_SECONDS="${COSMOS_TTL_SECONDS:-7776000}"        # 90 dias
readonly MONGO_VERSION="${COSMOS_MONGO_VERSION:-4.2}"

readonly TAGS=(
  "project=centinela"
  "week=2"
  "team=celula-centinela"
  "issue=ISS-S2-001"
)

# --- Helpers de nombrado --------------------------------------------------------

# Determinismo: mismas entradas -> mismo nombre (igual criterio que el Storage de S1).
# Cosmos exige nombre global unico, 3..44 chars, solo [a-z0-9-].
compute_cosmos_account_name() {
  local prefix="$1" sub_id="$2" rg="$3"
  local hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-cosmos-%s' "$prefix" "$hash"
}
compute_vnet_name() { printf '%s-vnet-week1' "$1"; }

assert_cosmos_account_name_valid() {
  local name="$1"
  [ "${#name}" -ge 3 ] && [ "${#name}" -le 44 ] \
    || die "Nombre de cuenta Cosmos invalido (longitud fuera de 3..44): '$name'"
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] \
    || die "Nombre de cuenta Cosmos invalido (solo [a-z0-9-], sin guion inicial/final): '$name'"
}

# --- Idempotencia: valida una cuenta existente ---------------------------------

# Devuelve 0 si la cuenta existe Y cumple las propiedades obligatorias; 1 si no.
assert_account_compliant_if_exists() {
  local account="$1" rg="$2"
  local kind consistency
  if ! az cosmosdb show --name "$account" --resource-group "$rg" >/dev/null 2>&1; then
    return 1
  fi
  log_info "Cuenta Cosmos '$account' ya existe. Validando configuracion..."

  kind="$(az cosmosdb show --name "$account" --resource-group "$rg" \
    --query 'kind' -o tsv 2>/dev/null || echo "?")"
  consistency="$(az cosmosdb show --name "$account" --resource-group "$rg" \
    --query 'consistencyPolicy.defaultConsistencyLevel' -o tsv 2>/dev/null || echo "?")"

  [ "$kind" = "MongoDB" ] \
    || { log_error "La cuenta '$account' no es API MongoDB (kind=$kind)."; return 1; }
  [ "$consistency" = "$CONSISTENCY" ] \
    || log_warn "Consistencia actual '$consistency' != esperada '$CONSISTENCY' (no se reescribe automaticamente)."

  return 0
}

# --- Side effects (Azure) -------------------------------------------------------

create_account() {
  local account="$1" rg="$2"
  log_info "Creando cuenta Cosmos '$account' (API MongoDB $MONGO_VERSION, Free Tier, consistencia $CONSISTENCY)..."
  # --enable-free-tier true: una sola cuenta free por suscripcion (1000 RU/s + 25GB).
  # --enable-public-network-access false: cierra el data plane a internet; el acceso
  #   se hara desde la Function/app por red o por el mecanismo que S2-007 configure.
  with_retry 3 az cosmosdb create \
    --name "$account" \
    --resource-group "$rg" \
    --kind MongoDB \
    --server-version "$MONGO_VERSION" \
    --default-consistency-level "$CONSISTENCY" \
    --enable-free-tier true \
    --public-network-access Disabled \
    --locations regionName="$LOCATION" failoverPriority=0 isZoneRedundant=False \
    --tags "${TAGS[@]}" \
    --output none
  log_info "Cuenta Cosmos creada."
}

ensure_private_dns_zone() {
  local rg="$1" vnet="$2" link="${vnet}-cosmos-mongo-link"
  if ! az network private-dns zone show --name "$DNS_ZONE_MONGO" --resource-group "$rg" >/dev/null 2>&1; then
    log_info "Creando zona DNS privada '$DNS_ZONE_MONGO'..."
    with_retry 3 az network private-dns zone create \
      --name "$DNS_ZONE_MONGO" --resource-group "$rg" --output none
  fi
  if ! az network private-dns link vnet show --zone-name "$DNS_ZONE_MONGO" \
        --resource-group "$rg" --name "$link" >/dev/null 2>&1; then
    log_info "Vinculando zona DNS Mongo a VNet '$vnet'..."
    with_retry 3 az network private-dns link vnet create \
      --zone-name "$DNS_ZONE_MONGO" --resource-group "$rg" --name "$link" \
      --virtual-network "$vnet" --registration-enabled false --output none
  fi
}

ensure_private_endpoint() {
  local account="$1" rg="$2" vnet="$3" pe="${account}-mongo-pe" account_id
  account_id="$(az cosmosdb show --name "$account" --resource-group "$rg" --query id -o tsv)"

  if ! az network private-endpoint show --name "$pe" --resource-group "$rg" >/dev/null 2>&1; then
    log_info "Creando Private Endpoint '$pe' para Cosmos MongoDB..."
    with_retry 3 az network private-endpoint create \
      --name "$pe" --resource-group "$rg" --location "$LOCATION" \
      --vnet-name "$vnet" --subnet "$SUBNET_PE" \
      --private-connection-resource-id "$account_id" \
      --group-id MongoDB --connection-name "${pe}-plsc" --output none
  fi

  if ! pe_dns_zone_group_exists "$pe" "$rg"; then
    log_info "Asociando el Private Endpoint a '$DNS_ZONE_MONGO'..."
    with_retry 3 az network private-endpoint dns-zone-group create \
      --resource-group "$rg" --endpoint-name "$pe" --name default \
      --private-dns-zone "$DNS_ZONE_MONGO" --zone-name mongo --output none
  fi
}

harden_account_network() {
  local account="$1" rg="$2"
  log_info "Asegurando publicNetworkAccess=Disabled en Cosmos..."
  with_retry 3 az cosmosdb update --name "$account" --resource-group "$rg" \
    --public-network-access Disabled --output none
}

ensure_database() {
  local account="$1" rg="$2"
  if az cosmosdb mongodb database show \
        --account-name "$account" --resource-group "$rg" \
        --name "$DATABASE_NAME" >/dev/null 2>&1; then
    log_info "Base '$DATABASE_NAME' ya existe."
  else
    log_info "Creando base '$DATABASE_NAME'..."
    with_retry 3 az cosmosdb mongodb database create \
      --account-name "$account" --resource-group "$rg" \
      --name "$DATABASE_NAME" --output none
  fi
}

ensure_collection() {
  local account="$1" rg="$2"
  if az cosmosdb mongodb collection show \
        --account-name "$account" --resource-group "$rg" \
        --database-name "$DATABASE_NAME" --name "$COLLECTION_NAME" >/dev/null 2>&1; then
    log_info "Coleccion '$COLLECTION_NAME' ya existe. (shard key inmutable: no se recrea)"
    return 0
  fi
  log_info "Creando coleccion '$COLLECTION_NAME' (shard key=$SHARD_KEY, TTL=${TTL_SECONDS}s)..."
  # --shard: define la particion. INMUTABLE tras la primera escritura.
  # TTL: la API Mongo NO expone '--ttl' (ese flag no existe en az CLI). La
  #   expiracion automatica se declara como INDICE TTL sobre '_ts', que es el
  #   mecanismo nativo de Cosmos DB for MongoDB. Se incluye tambien el indice
  #   obligatorio de '_id'.
  local idx
  idx="$(printf '[{"key":{"keys":["_id"]}},{"key":{"keys":["_ts"]},"options":{"expireAfterSeconds":%s}}]' "$TTL_SECONDS")"
  with_retry 3 az cosmosdb mongodb collection create \
    --account-name "$account" --resource-group "$rg" \
    --database-name "$DATABASE_NAME" --name "$COLLECTION_NAME" \
    --shard "$SHARD_KEY" \
    --idx "$idx" \
    --output none
  log_info "Coleccion creada."
}

verify_all_resources() {
  local account="$1" rg="$2"

  log_info "Verificando cuenta, base y coleccion..."
  az cosmosdb show --name "$account" --resource-group "$rg" >/dev/null 2>&1 \
    || die "No existe la cuenta Cosmos '$account'."
  az cosmosdb mongodb database show \
    --account-name "$account" --resource-group "$rg" \
    --name "$DATABASE_NAME" >/dev/null 2>&1 \
    || die "No existe la base '$DATABASE_NAME'."
  az cosmosdb mongodb collection show \
    --account-name "$account" --resource-group "$rg" \
    --database-name "$DATABASE_NAME" --name "$COLLECTION_NAME" >/dev/null 2>&1 \
    || die "No existe la coleccion '$COLLECTION_NAME'."

  local free_tier consistency public_access pe
  free_tier="$(az cosmosdb show --name "$account" --resource-group "$rg" \
    --query 'enableFreeTier' -o tsv 2>/dev/null || echo "?")"
  consistency="$(az cosmosdb show --name "$account" --resource-group "$rg" \
    --query 'consistencyPolicy.defaultConsistencyLevel' -o tsv 2>/dev/null || echo "?")"
  public_access="$(az cosmosdb show --name "$account" --resource-group "$rg" \
    --query 'publicNetworkAccess' -o tsv 2>/dev/null || echo "?")"
  pe="${account}-mongo-pe"
  az network private-endpoint show --name "$pe" --resource-group "$rg" >/dev/null 2>&1 \
    || die "No existe el Private Endpoint '$pe'."
  # Un PE sin registro A deja a Cosmos irresoluble por nombre dentro de la VNet.
  # Verificarlo es lo que distingue "creado" de "realmente alcanzable".
  retry_until 8 private_dns_has_a_records "$DNS_ZONE_MONGO" "$rg" \
    || die "El PE '$pe' existe pero '$DNS_ZONE_MONGO' no tiene registros A: Cosmos no seria resoluble desde la VNet."

  log_info "  OK cuenta:       $account"
  log_info "  OK base:         $DATABASE_NAME"
  log_info "  OK coleccion:    $COLLECTION_NAME (shard=$SHARD_KEY, ttl=${TTL_SECONDS}s)"
  log_info "  Free Tier:       $free_tier"
  log_info "  Consistencia:    $consistency"
  log_info "  Acceso publico:  $public_access"
  log_info "  Private Endpoint:$pe (groupId=MongoDB)"
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

  local account vnet
  account="$(compute_cosmos_account_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  vnet="$(compute_vnet_name "$NAME_PREFIX")"
  assert_cosmos_account_name_valid "$account"

  az network vnet subnet show --vnet-name "$vnet" --resource-group "$RESOURCE_GROUP" \
      --name "$SUBNET_PE" >/dev/null 2>&1 \
    || die "No existe '$vnet/$SUBNET_PE'. Ejecuta primero scripts/provision-network.sh."

  log_info "Cuenta Cosmos objetivo: $account (longitud: ${#account})"
  log_info "Base / Coleccion:       $DATABASE_NAME / $COLLECTION_NAME"
  log_info "Shard key:              $SHARD_KEY (INMUTABLE tras la primera escritura)"
  log_info "TTL:                    ${TTL_SECONDS}s  ·  Consistencia: $CONSISTENCY"

  if ! assert_account_compliant_if_exists "$account" "$RESOURCE_GROUP"; then
    create_account "$account" "$RESOURCE_GROUP"
  else
    log_info "Cuenta '$account' ya existe y cumple lo obligatorio. Sin recrear."
  fi

  ensure_database   "$account" "$RESOURCE_GROUP"
  ensure_collection "$account" "$RESOURCE_GROUP"
  harden_account_network "$account" "$RESOURCE_GROUP"
  ensure_private_dns_zone "$RESOURCE_GROUP" "$vnet"
  ensure_private_endpoint "$account" "$RESOURCE_GROUP" "$vnet"
  verify_all_resources "$account" "$RESOURCE_GROUP"

  log_info "ISS-S2-001 OK: Cosmos (Mongo) + base '$DATABASE_NAME' + coleccion '$COLLECTION_NAME' listos."
}

main "$@"
