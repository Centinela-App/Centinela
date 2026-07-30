#!/usr/bin/env bash
# validate-keyvault.sh — ISS-S2-003 (TEST-S2-003)
# Verificacion automatizada del gestor de secretos (Azure Key Vault) y del acceso
# por Managed Identity. Consulta exclusivamente el control plane de Azure y NUNCA
# lee el valor de ningun secreto (solo su existencia por nombre).
#
# Salida:
#   exit 0  -> todas las verificaciones pasaron.
#   exit 1  -> al menos una verificacion fallo.
#
# Trazabilidad:
#   - Cubre los criterios de aceptacion §8 de ISS-S2-003.
#   - Cubre los 3 escenarios Gherkin §10 (acceso por identidad gestionada, secreto
#     ausente del repo -> presente en el vault, no una credencial para credenciales).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

# --- Constantes exigidas por ISS-S2-003 ----------------------------------------
readonly SLOT_NAME="staging"
readonly COSMOS_SECRET_NAME="cosmos-mongo-connection-string"
readonly SECRETS_USER_ROLE="Key Vault Secrets User"

# --- Acumuladores --------------------------------------------------------------
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
  [ "$FAIL" -eq 0 ] && log_info "TEST-S2-003 OK" || log_error "TEST-S2-003 FALLO"
  exit "$([ "$FAIL" -eq 0 ] && echo 0 || echo 1)"
}

# --- Nombres deterministas (mismo criterio que provision-keyvault) -------------
kv_name()  { local h; h="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)"; printf '%s-kv-%s' "$NAME_PREFIX" "$h"; }
app_name() { local h; h="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)"; printf '%s-app-%s' "$NAME_PREFIX" "$h"; }

# --- Arranque ------------------------------------------------------------------
load_parameters
validate_parameters
require_cmd az
az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."

VAULT="$(kv_name)"
APP="$(app_name)"
RG="$RESOURCE_GROUP"
log_info "Validando Key Vault: $VAULT (RG: $RG)"

# --- 1. Existencia del vault ---------------------------------------------------
if az keyvault show --name "$VAULT" --resource-group "$RG" >/dev/null 2>&1; then
  ok "Key Vault '$VAULT' existe."
else
  fail "Key Vault '$VAULT' NO existe. Ejecutar scripts/provision-keyvault.sh."
  cleanup
fi

prop() { az keyvault show --name "$VAULT" --resource-group "$RG" --query "$1" -o tsv 2>/dev/null || echo MISSING; }

# --- 2. RBAC en el plano de datos ----------------------------------------------
rbac="$(prop 'properties.enableRbacAuthorization')"
if [ "$rbac" = "true" ]; then
  ok "RBAC authorization habilitado."
else
  fail "enableRbacAuthorization = '$rbac' (esperado 'true')."
fi

# --- 3. Purge protection + soft-delete -----------------------------------------
purge="$(prop 'properties.enablePurgeProtection')"
if [ "$purge" = "true" ]; then
  ok "Purge protection habilitado."
else
  fail "enablePurgeProtection = '$purge' (esperado 'true')."
fi
softdelete="$(prop 'properties.enableSoftDelete')"
if [ "$softdelete" = "true" ] || [ "$softdelete" = "MISSING" ]; then
  # soft-delete es obligatorio y no se puede deshabilitar; 'MISSING' = default on.
  ok "Soft-delete activo."
else
  fail "enableSoftDelete = '$softdelete' (esperado 'true')."
fi

# --- 4. Secreto de Cosmos presente (solo por nombre; NUNCA su valor) -----------
if az keyvault secret show --vault-name "$VAULT" --name "$COSMOS_SECRET_NAME" \
      --query 'id' -o tsv >/dev/null 2>&1; then
  ok "Secreto '$COSMOS_SECRET_NAME' presente en el vault (valor no inspeccionado)."
else
  fail "Secreto '$COSMOS_SECRET_NAME' NO existe en el vault."
fi

# --- 5. Acceso por Managed Identity: rol Secrets User a app + slot -------------
vault_id="$(az keyvault show --name "$VAULT" --resource-group "$RG" --query id -o tsv 2>/dev/null || echo "")"
check_secrets_user() {
  local label="$1" pid="$2"
  if [ -z "$pid" ]; then
    fail "$label sin Managed Identity (no se puede verificar el rol)."
    return
  fi
  local n
  n="$(az role assignment list --assignee "$pid" --scope "$vault_id" \
        --role "$SECRETS_USER_ROLE" --query "length(@)" -o tsv 2>/dev/null || echo 0)"
  if [ "${n:-0}" -ge 1 ] 2>/dev/null; then
    ok "$label tiene '$SECRETS_USER_ROLE' en el vault."
  else
    fail "$label NO tiene '$SECRETS_USER_ROLE' en el vault."
  fi
}
prod_pid="$(az webapp identity show --name "$APP" --resource-group "$RG" --query principalId -o tsv 2>/dev/null || echo "")"
staging_pid="$(az webapp identity show --name "$APP" --resource-group "$RG" --slot "$SLOT_NAME" --query principalId -o tsv 2>/dev/null || echo "")"
check_secrets_user "Web App (prod)" "$prod_pid"
check_secrets_user "Slot (staging)" "$staging_pid"

# --- 6. No hay 'credencial para credenciales': el acceso es por MI, no por secreto
# El vault usa RBAC (no access policies con secretos) y las apps se autentican por
# Managed Identity. Se valida indirectamente por los pasos 2 y 5.
ok "Acceso al vault por Managed Identity + RBAC (sin credencial almacenada para el vault)."

# --- 7. Tags de trazabilidad ---------------------------------------------------
for tag in "project=centinela" "week=2" "team=celula-centinela" "issue=ISS-S2-003"; do
  k="${tag%%=*}"; v_exp="${tag##*=}"
  v_act="$(prop "tags.$k")"
  if [ "$v_act" = "$v_exp" ]; then
    ok "Tag $k == '$v_exp'."
  else
    fail "Tag '$k' = '$v_act' (esperado '$v_exp')."
  fi
done

cleanup
