#!/usr/bin/env bash
# validate-postgres.sh — ISS-S2-002 (TEST-S2-002)
# Verificacion automatizada del almacen de casos (PostgreSQL Flexible Server privado).
# Lee parametros desde .env (o env del proceso) y consulta exclusivamente el control
# plane de Azure (sin usar credenciales del data plane).
#
# Salida:
#   imprime un reporte estructurado (sanitizado) y un resumen final.
#   exit 0  -> todas las verificaciones pasaron.
#   exit 1  -> al menos una verificacion fallo (detalle en stderr).
#
# Trazabilidad:
#   - Cubre los criterios de aceptacion §8 de ISS-S2-002.
#   - Cubre los 3 escenarios Gherkin §10 (servidor privado operativo, acceso publico
#     bloqueado, respaldo documentado -> se valida la retencion configurada).
set -uo pipefail   # NO usamos -e: queremos reportar TODOS los fallos.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

# --- Constantes: valores exactos exigidos por ISS-S2-002 -----------------------
readonly DNS_ZONE_PG="privatelink.postgres.database.azure.com"
readonly EXPECTED_TIER="${POSTGRES_TIER:-Burstable}"
readonly EXPECTED_SKU="${POSTGRES_SKU:-Standard_B1ms}"
readonly EXPECTED_RETENTION="${POSTGRES_BACKUP_RETENTION:-7}"

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
  [ "$FAIL" -eq 0 ] && log_info "TEST-S2-002 OK" || log_error "TEST-S2-002 FALLO"
  exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
}

# --- Nombre determinista del servidor (mismo criterio que provision-postgres) --
postgres_server_name() {
  local hash
  hash="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" \
    | sha1sum | cut -c1-6)"
  printf '%s-pg-%s' "$NAME_PREFIX" "$hash"
}

# --- Arranque ------------------------------------------------------------------
load_parameters
validate_parameters
require_cmd az
az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."

SERVER="$(postgres_server_name)"
RG="$RESOURCE_GROUP"
PE="${SERVER}-pe"
log_info "Validando servidor Postgres: $SERVER (RG: $RG)"

# --- 1. Existencia del servidor ------------------------------------------------
if az postgres flexible-server show --name "$SERVER" --resource-group "$RG" >/dev/null 2>&1; then
  ok "Servidor Postgres '$SERVER' existe."
else
  fail "Servidor Postgres '$SERVER' NO existe. Ejecutar scripts/provision-postgres.sh."
  cleanup   # sin servidor no hay nada mas que validar
fi

# --- Helper de propiedades -----------------------------------------------------
prop() {
  az postgres flexible-server show --name "$SERVER" --resource-group "$RG" \
    --query "$1" -o tsv 2>/dev/null || echo MISSING
}

# --- 2. SKU de nivel gratuito (Burstable / B1ms) -------------------------------
tier="$(prop 'sku.tier')"
if [ "$tier" = "$EXPECTED_TIER" ]; then
  ok "Tier == '$EXPECTED_TIER'."
else
  fail "Tier = '$tier' (esperado '$EXPECTED_TIER')."
fi
sku="$(prop 'sku.name')"
if [ "$sku" = "$EXPECTED_SKU" ]; then
  ok "SKU == '$EXPECTED_SKU'."
else
  fail "SKU = '$sku' (esperado '$EXPECTED_SKU')."
fi

# --- 3. Acceso publico deshabilitado -------------------------------------------
pub="$(prop 'network.publicNetworkAccess')"
if [ "$pub" = "Disabled" ]; then
  ok "publicNetworkAccess == 'Disabled'."
else
  fail "publicNetworkAccess = '$pub' (esperado 'Disabled')."
fi

# --- 4. Autenticacion: Entra ID habilitada, password deshabilitada -------------
aad="$(prop 'authConfig.activeDirectoryAuth')"
if [ "$aad" = "Enabled" ]; then
  ok "activeDirectoryAuth == 'Enabled'."
else
  fail "activeDirectoryAuth = '$aad' (esperado 'Enabled')."
fi
pwd_auth="$(prop 'authConfig.passwordAuth')"
if [ "$pwd_auth" = "Disabled" ]; then
  ok "passwordAuth == 'Disabled' (sin secreto de conexion)."
else
  fail "passwordAuth = '$pwd_auth' (esperado 'Disabled')."
fi

# --- 5. Respaldo configurado ---------------------------------------------------
retention="$(prop 'backup.backupRetentionDays')"
if [ "$retention" = "$EXPECTED_RETENTION" ]; then
  ok "backupRetentionDays == ${EXPECTED_RETENTION}d."
elif [ "$retention" != "MISSING" ] && [ "$retention" -ge 7 ] 2>/dev/null; then
  ok "backupRetentionDays = ${retention}d (>= 7; revisar si difiere a proposito)."
else
  fail "backupRetentionDays = '$retention' (esperado '$EXPECTED_RETENTION')."
fi

# --- 6. Private Endpoint y su groupId ------------------------------------------
if az network private-endpoint show --name "$PE" --resource-group "$RG" >/dev/null 2>&1; then
  ok "Private Endpoint '$PE' existe."
  gid="$(az network private-endpoint show --name "$PE" --resource-group "$RG" \
    --query "privateLinkServiceConnections[0].groupIds[0]" -o tsv 2>/dev/null || echo MISSING)"
  if [ "$gid" = "postgresqlServer" ]; then
    ok "PE apunta al subrecurso 'postgresqlServer'."
  else
    fail "PE groupId = '$gid' (esperado 'postgresqlServer')."
  fi
  state="$(az network private-endpoint show --name "$PE" --resource-group "$RG" \
    --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" \
    -o tsv 2>/dev/null || echo MISSING)"
  if [ "$state" = "Approved" ]; then
    ok "Conexion del PE en estado 'Approved'."
  else
    fail "Conexion del PE en estado '$state' (esperado 'Approved')."
  fi
else
  fail "Private Endpoint '$PE' NO existe."
fi

# --- 7. Zona DNS privada con registro A ----------------------------------------
if az network private-dns zone show --name "$DNS_ZONE_PG" --resource-group "$RG" >/dev/null 2>&1; then
  ok "Zona DNS privada '$DNS_ZONE_PG' existe."
  n="$(az network private-dns record-set a list --zone-name "$DNS_ZONE_PG" --resource-group "$RG" \
    --query "length(@)" -o tsv 2>/dev/null || echo 0)"
  if [ "$n" -ge 1 ] 2>/dev/null; then
    ok "Zona DNS con $n registro(s) A privado(s)."
  else
    fail "Zona DNS '$DNS_ZONE_PG' sin registros A (el dns-zone-group no registro la IP)."
  fi
else
  fail "Zona DNS privada '$DNS_ZONE_PG' NO existe."
fi

# --- 8. Tags de trazabilidad ---------------------------------------------------
for tag in "project=centinela" "week=2" "team=celula-centinela" "issue=ISS-S2-002"; do
  k="${tag%%=*}"; v_exp="${tag##*=}"
  v_act="$(prop "tags.$k")"
  if [ "$v_act" = "$v_exp" ]; then
    ok "Tag $k == '$v_exp'."
  else
    fail "Tag '$k' = '$v_act' (esperado '$v_exp')."
  fi
done

cleanup
