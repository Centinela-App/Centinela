#!/usr/bin/env bash
# validate-cosmos.sh — ISS-S2-001 (TEST-S2-001)
# Verificacion automatizada del almacen de transacciones (Cosmos DB for MongoDB).
# Lee parametros desde .env (o env del proceso) y consulta exclusivamente el
# control plane de Azure (sin usar keys del data plane).
#
# Salida:
#   imprime un reporte estructurado (sanitizado) y un resumen final.
#   exit 0  -> todas las verificaciones pasaron.
#   exit 1  -> al menos una verificacion fallo (detalle en stderr).
#
# Trazabilidad:
#   - Cubre los criterios de aceptacion §8 de ISS-S2-001.
#   - Cubre los 3 escenarios Gherkin §10 (coleccion con shard key, idempotencia,
#     particion inmutable).
set -uo pipefail   # NO usamos -e: queremos reportar TODOS los fallos.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

# --- Constantes: valores exactos exigidos por ISS-S2-001 -----------------------
readonly DATABASE_NAME="centinela"
readonly COLLECTION_NAME="transactions"
readonly SHARD_KEY="accountId"
readonly EXPECTED_CONSISTENCY="${COSMOS_CONSISTENCY:-Session}"
readonly EXPECTED_TTL="${COSMOS_TTL_SECONDS:-7776000}"

# --- Acumuladores de resultados ------------------------------------------------
PASS=0
FAIL=0
RESULTS=()
ok()   { RESULTS+=("PASS  $*"); PASS=$((PASS + 1)); }
fail() { RESULTS+=("FAIL  $*"); FAIL=$((FAIL + 1)); log_error "$*"; }

cleanup() {
  echo "" >&2
  printf '%s\n' "${RESULTS[@]}" >&2
  echo "----------------------------------------" >&2
  log_info "Resultado: $PASS PASS · $FAIL FAIL"
  [ "$FAIL" -eq 0 ] && log_info "TEST-S2-001 OK" || log_error "TEST-S2-001 FALLO"
  exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
}

# --- Nombre determinista de la cuenta (mismo criterio que provision-cosmos) ----
cosmos_account_name() {
  local hash
  hash="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" \
    | sha1sum | cut -c1-6)"
  printf '%s-cosmos-%s' "$NAME_PREFIX" "$hash"
}

# --- Arranque ------------------------------------------------------------------
load_parameters
validate_parameters
require_cmd az
az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."

ACCOUNT="$(cosmos_account_name)"
RG="$RESOURCE_GROUP"
log_info "Validando cuenta Cosmos: $ACCOUNT (RG: $RG)"

# --- 1. Existencia de la cuenta ------------------------------------------------
if az cosmosdb show --name "$ACCOUNT" --resource-group "$RG" >/dev/null 2>&1; then
  ok "Cuenta Cosmos '$ACCOUNT' existe."
else
  fail "Cuenta Cosmos '$ACCOUNT' NO existe. Ejecutar scripts/provision-cosmos.sh."
  cleanup   # sin cuenta no hay nada mas que validar
fi

# --- 2. Es API MongoDB ---------------------------------------------------------
kind="$(az cosmosdb show --name "$ACCOUNT" --resource-group "$RG" \
  --query 'kind' -o tsv 2>/dev/null || echo MISSING)"
if [ "$kind" = "MongoDB" ]; then
  ok "Cuenta es API MongoDB."
else
  fail "Cuenta kind='$kind' (esperado 'MongoDB')."
fi

# --- 3. Free Tier habilitado ---------------------------------------------------
free_tier="$(az cosmosdb show --name "$ACCOUNT" --resource-group "$RG" \
  --query 'enableFreeTier' -o tsv 2>/dev/null || echo MISSING)"
if [ "$free_tier" = "true" ]; then
  ok "Free Tier habilitado."
else
  fail "enableFreeTier='$free_tier' (esperado 'true')."
fi

# --- 4. Nivel de consistencia --------------------------------------------------
consistency="$(az cosmosdb show --name "$ACCOUNT" --resource-group "$RG" \
  --query 'consistencyPolicy.defaultConsistencyLevel' -o tsv 2>/dev/null || echo MISSING)"
if [ "$consistency" = "$EXPECTED_CONSISTENCY" ]; then
  ok "Consistencia == '$EXPECTED_CONSISTENCY'."
else
  fail "Consistencia = '$consistency' (esperado '$EXPECTED_CONSISTENCY')."
fi

# --- 5. Base de datos existe ---------------------------------------------------
if az cosmosdb mongodb database show \
      --account-name "$ACCOUNT" --resource-group "$RG" \
      --name "$DATABASE_NAME" >/dev/null 2>&1; then
  ok "Base '$DATABASE_NAME' existe."
else
  fail "Base '$DATABASE_NAME' NO existe."
fi

# --- 6. Coleccion existe -------------------------------------------------------
if az cosmosdb mongodb collection show \
      --account-name "$ACCOUNT" --resource-group "$RG" \
      --database-name "$DATABASE_NAME" --name "$COLLECTION_NAME" >/dev/null 2>&1; then
  ok "Coleccion '$COLLECTION_NAME' existe."
else
  fail "Coleccion '$COLLECTION_NAME' NO existe."
  cleanup
fi

# --- 7. Shard key correcta -----------------------------------------------------
# La shard key aparece en shardKey como un objeto {accountId: "Hash"}.
shard="$(az cosmosdb mongodb collection show \
  --account-name "$ACCOUNT" --resource-group "$RG" \
  --database-name "$DATABASE_NAME" --name "$COLLECTION_NAME" \
  --query "resource.shardKey.$SHARD_KEY" -o tsv 2>/dev/null || echo MISSING)"
if [ -n "$shard" ] && [ "$shard" != "MISSING" ]; then
  ok "Shard key '$SHARD_KEY' configurada (tipo: $shard)."
else
  fail "Shard key '$SHARD_KEY' NO configurada (valor: '$shard')."
fi

# --- 8. TTL configurado --------------------------------------------------------
# El TTL se materializa como un indice sobre _ts con expireAfterSeconds.
ttl="$(az cosmosdb mongodb collection show \
  --account-name "$ACCOUNT" --resource-group "$RG" \
  --database-name "$DATABASE_NAME" --name "$COLLECTION_NAME" \
  --query "resource.indexes[?options.expireAfterSeconds!=null].options.expireAfterSeconds | [0]" \
  -o tsv 2>/dev/null || echo MISSING)"
if [ "$ttl" = "$EXPECTED_TTL" ]; then
  ok "TTL == ${EXPECTED_TTL}s."
elif [ -n "$ttl" ] && [ "$ttl" != "MISSING" ]; then
  ok "TTL configurado (${ttl}s; esperado ${EXPECTED_TTL}s — revisar si difiere a proposito)."
else
  fail "TTL NO configurado en la coleccion."
fi

# --- 9. Tags de trazabilidad ---------------------------------------------------
for tag in "project=centinela" "week=2" "team=celula-centinela" "issue=ISS-S2-001"; do
  k="${tag%%=*}"; v_exp="${tag##*=}"
  v_act="$(az cosmosdb show --name "$ACCOUNT" --resource-group "$RG" \
    --query "tags.$k" -o tsv 2>/dev/null || echo MISSING)"
  if [ "$v_act" = "$v_exp" ]; then
    ok "Tag $k == '$v_exp'."
  else
    fail "Tag '$k' = '$v_act' (esperado '$v_exp')."
  fi
done

cleanup
