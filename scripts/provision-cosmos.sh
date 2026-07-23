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
#   - Deshabilitar acceso publico donde el Free Tier lo permita; en caso contrario
#     restringir por red a la subred de la app (documentado).
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
    --locations regionName="$LOCATION" failoverPriority=0 isZoneRedundant=False \
    --tags "${TAGS[@]}" \
    --output none
  log_info "Cuenta Cosmos creada."
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
  # --ttl:   expiracion automatica de documentos alineada a las ventanas de reglas.
  with_retry 3 az cosmosdb mongodb collection create \
    --account-name "$account" --resource-group "$rg" \
    --database-name "$DATABASE_NAME" --name "$COLLECTION_NAME" \
    --shard "$SHARD_KEY" \
    --ttl "$TTL_SECONDS" \
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

  local free_tier consistency
  free_tier="$(az cosmosdb show --name "$account" --resource-group "$rg" \
    --query 'enableFreeTier' -o tsv 2>/dev/null || echo "?")"
  consistency="$(az cosmosdb show --name "$account" --resource-group "$rg" \
    --query 'consistencyPolicy.defaultConsistencyLevel' -o tsv 2>/dev/null || echo "?")"

  log_info "  OK cuenta:       $account"
  log_info "  OK base:         $DATABASE_NAME"
  log_info "  OK coleccion:    $COLLECTION_NAME (shard=$SHARD_KEY, ttl=${TTL_SECONDS}s)"
  log_info "  Free Tier:       $free_tier"
  log_info "  Consistencia:    $consistency"
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

  local account
  account="$(compute_cosmos_account_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  assert_cosmos_account_name_valid "$account"

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
  verify_all_resources "$account" "$RESOURCE_GROUP"

  log_info "ISS-S2-001 OK: Cosmos (Mongo) + base '$DATABASE_NAME' + coleccion '$COLLECTION_NAME' listos."
}

main "$@"
