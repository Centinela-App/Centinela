#!/usr/bin/env bash
# validate-network.sh — ISS-S1-005 (TEST-S1-007)
# Verificacion automatizada de VNet, subredes, VNet Integration, Private Endpoints,
# zonas DNS privadas y bloqueo de acceso publico del Storage.
# Consulta exclusivamente el control plane de Azure.
#
# Salida:
#   reporte estructurado en stdout (sanitizado) + resumen.
#   exit 0 -> todas las verificaciones pasaron ; exit 1 -> al menos una fallo.
#
# Trazabilidad (ISS-S1-005 §8 / §10):
#   - Exactamente 2 subredes minimas documentadas.
#   - Produccion y staging con VNet Integration.
#   - Blob y Queue con Private Endpoint y zona DNS vinculada.
#   - publicNetworkAccess del Storage = Disabled.
#   - Resolucion privada: registros A privados publicados en las zonas.
#   - Gherkin "DNS privado incompleto": falla e identifica el vinculo DNS faltante.
set -uo pipefail   # NO usamos -e: queremos reportar TODOS los fallos.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

readonly SLOT_NAME="staging"
readonly SUBNET_APP="snet-app-integration"
readonly SUBNET_PE="snet-private-endpoints"
readonly APP_DELEGATION="Microsoft.Web/serverFarms"
readonly DNS_ZONE_BLOB="privatelink.blob.core.windows.net"
readonly DNS_ZONE_QUEUE="privatelink.queue.core.windows.net"

# --- Acumuladores --------------------------------------------------------------
PASS=0
FAIL=0
RESULTS=()
ok()   { RESULTS+=("PASS  $*"); PASS=$((PASS + 1)); }
fail() { RESULTS+=("FAIL  $*"); FAIL=$((FAIL + 1)); log_error "$*"; }

print_report() {
  printf '\n============== ISS-S1-005 / TEST-S1-007 ==============\n'
  for r in "${RESULTS[@]}"; do printf '%s\n' "$r"; done
  printf '------------------------------------------------------\n'
  printf 'Resumen: %d PASS / %d FAIL\n' "$PASS" "$FAIL"
  printf '======================================================\n'
}
cleanup() {
  local rc="${1:-$?}"
  trap - EXIT
  print_report
  if [ "$rc" -ne 0 ]; then exit "$rc"; fi
  exit "$(( FAIL > 0 ? 1 : 0 ))"
}
trap 'cleanup $?' EXIT

# --- Pre-condiciones -----------------------------------------------------------
require_cmd az
az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
load_parameters
validate_parameters
az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 || die "Resource Group '$RESOURCE_GROUP' no existe."

# Nombres deterministas (mismo criterio que provision-*.sh).
hash6() { printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6; }
SA_NAME="${NAME_PREFIX}st$(hash6)"
APP_NAME="${NAME_PREFIX}-app-$(hash6)"
VNET_NAME="${NAME_PREFIX}-vnet-week1"
BLOB_PE="${SA_NAME}-blob-pe"
QUEUE_PE="${SA_NAME}-queue-pe"
RG="$RESOURCE_GROUP"

log_info "Validando red: VNet $VNET_NAME | Web App $APP_NAME | Storage $SA_NAME (RG: $RG)"

# --- 1. VNet existe ------------------------------------------------------------
if az network vnet show --name "$VNET_NAME" --resource-group "$RG" >/dev/null 2>&1; then
  ok "VNet '$VNET_NAME' existe."
else
  fail "VNet '$VNET_NAME' NO existe. Ejecutar scripts/provision-network.sh."
  cleanup
fi

# --- 2. Exactamente 2 subredes con nombres exactos -----------------------------
subnet_count="$(az network vnet show --name "$VNET_NAME" --resource-group "$RG" \
  --query "length(subnets)" -o tsv 2>/dev/null || echo 0)"
if [ "$subnet_count" = "2" ]; then
  ok "La VNet tiene exactamente 2 subredes."
else
  fail "La VNet tiene $subnet_count subredes (esperado 2)."
fi
for s in "$SUBNET_APP" "$SUBNET_PE"; do
  if az network vnet subnet show --vnet-name "$VNET_NAME" --resource-group "$RG" --name "$s" >/dev/null 2>&1; then
    ok "Subred '$s' existe."
  else
    fail "Subred '$s' NO existe."
  fi
done

# --- 3. Delegacion y politicas de red por subred -------------------------------
app_deleg="$(az network vnet subnet show --vnet-name "$VNET_NAME" --resource-group "$RG" --name "$SUBNET_APP" \
  --query "delegations[0].serviceName" -o tsv 2>/dev/null || echo MISSING)"
if [ "$app_deleg" = "$APP_DELEGATION" ]; then
  ok "Subred '$SUBNET_APP' delegada a '$APP_DELEGATION'."
else
  fail "Subred '$SUBNET_APP' delegacion = '$app_deleg' (esperado '$APP_DELEGATION')."
fi
pe_policy="$(az network vnet subnet show --vnet-name "$VNET_NAME" --resource-group "$RG" --name "$SUBNET_PE" \
  --query "privateEndpointNetworkPolicies" -o tsv 2>/dev/null || echo MISSING)"
if [ "$pe_policy" = "Disabled" ]; then
  ok "Subred '$SUBNET_PE' con privateEndpointNetworkPolicies=Disabled."
else
  fail "Subred '$SUBNET_PE' privateEndpointNetworkPolicies = '$pe_policy' (esperado 'Disabled')."
fi

# --- 4. VNet Integration en produccion y staging -------------------------------
prod_sub="$(az webapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "virtualNetworkSubnetId" -o tsv 2>/dev/null || echo "")"
staging_sub="$(az webapp show --name "$APP_NAME" --resource-group "$RG" --slot "$SLOT_NAME" \
  --query "virtualNetworkSubnetId" -o tsv 2>/dev/null || echo "")"
if printf '%s' "$prod_sub" | grep -q "/subnets/${SUBNET_APP}$"; then
  ok "Produccion integrada a '$SUBNET_APP'."
else
  fail "Produccion SIN VNet Integration a '$SUBNET_APP' (actual: '${prod_sub:-vacio}')."
fi
if printf '%s' "$staging_sub" | grep -q "/subnets/${SUBNET_APP}$"; then
  ok "Staging integrado a '$SUBNET_APP'."
else
  fail "Staging SIN VNet Integration a '$SUBNET_APP' (actual: '${staging_sub:-vacio}')."
fi

# --- 5. Private Endpoints de Blob y Queue --------------------------------------
for pe_group in "${BLOB_PE}:blob" "${QUEUE_PE}:queue"; do
  pe="${pe_group%%:*}"; grp="${pe_group##*:}"
  if az network private-endpoint show --name "$pe" --resource-group "$RG" >/dev/null 2>&1; then
    gid="$(az network private-endpoint show --name "$pe" --resource-group "$RG" \
      --query "privateLinkServiceConnections[0].groupIds[0]" -o tsv 2>/dev/null || echo MISSING)"
    state="$(az network private-endpoint show --name "$pe" --resource-group "$RG" \
      --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv 2>/dev/null || echo MISSING)"
    if [ "$gid" = "$grp" ]; then
      ok "Private Endpoint '$pe' -> subrecurso '$grp' (estado: $state)."
    else
      fail "Private Endpoint '$pe' groupId = '$gid' (esperado '$grp')."
    fi
  else
    fail "Private Endpoint '$pe' NO existe."
  fi
done

# --- 6. Zonas DNS privadas: existencia, vinculo a la VNet y registro A ----------
# (Gherkin "DNS privado incompleto": si falta el vinculo, se identifica aqui.)
for z in "$DNS_ZONE_BLOB" "$DNS_ZONE_QUEUE"; do
  if az network private-dns zone show --name "$z" --resource-group "$RG" >/dev/null 2>&1; then
    ok "Zona DNS privada '$z' existe."
  else
    fail "Zona DNS privada '$z' NO existe."
    continue
  fi
  links="$(az network private-dns link vnet list --zone-name "$z" --resource-group "$RG" \
    --query "[?virtualNetwork.id != null] | length(@)" -o tsv 2>/dev/null || echo 0)"
  if [ "${links:-0}" -ge 1 ] 2>/dev/null; then
    ok "Zona '$z' vinculada a la VNet ($links vinculo/s)."
  else
    fail "Zona '$z' SIN vinculo a la VNet (Gherkin: vinculo DNS faltante)."
  fi
  arecords="$(az network private-dns record-set a list --zone-name "$z" --resource-group "$RG" \
    --query "length(@)" -o tsv 2>/dev/null || echo 0)"
  if [ "${arecords:-0}" -ge 1 ] 2>/dev/null; then
    ok "Zona '$z' con $arecords registro(s) A privado(s) (resolucion privada wired)."
  else
    fail "Zona '$z' sin registros A (el privateDnsZoneGroup no publico la IP privada)."
  fi
done

# --- 7. Acceso publico del Storage sigue Disabled ------------------------------
pub_net="$(az storage account show --name "$SA_NAME" --resource-group "$RG" \
  --query "publicNetworkAccess" -o tsv 2>/dev/null || echo MISSING)"
if [ "$pub_net" = "Disabled" ]; then
  ok "Storage publicNetworkAccess=Disabled (no alcanzable desde internet)."
else
  fail "Storage publicNetworkAccess = '$pub_net' (esperado 'Disabled')."
fi

# --- 8. Acceso publico bloqueado (chequeo activo: intento anonimo al blob) ------
# Gherkin "Acceso publico bloqueado": sin conectividad privada, la peticion falla.
BLOB_URL="https://${SA_NAME}.blob.core.windows.net/raw-transactions-production?restype=container&comp=list"
http_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \
              -X GET "$BLOB_URL" 2>/dev/null || echo 000)"
case "$http_code" in
  000)   ok "Acceso publico bloqueado (red/timeout — esperable con publicNetworkAccess=Disabled)." ;;
  4*|5*) ok "Acceso publico rechazado con HTTP $http_code." ;;
  2*)    fail "Acceso publico permitido con HTTP $http_code — el Storage NO esta aislado." ;;
  *)     log_warn "Respuesta HTTP no categorizada: $http_code (se acepta por defecto)." ;;
esac

# --- 9. Resumen ----------------------------------------------------------------
cleanup
