#!/usr/bin/env bash
# validate-app-service.sh — ISS-S1-004 (TEST-S1-006 / TEST-S1-023)
# Verificacion automatizada de App Service, Managed Identity y slot staging.
# Lee parametros desde .env (o env del proceso) y consulta exclusivamente el
# control plane de Azure.
#
# Salida:
#   imprime un reporte estructurado en stdout (sanitizado) y un resumen final.
#   exit 0  -> todas las verificaciones pasaron.
#   exit 1  -> al menos una verificacion fallo (detalle en stderr).
#
# Trazabilidad:
#   - Cubre los criterios de aceptacion §8 de ISS-S1-004:
#       * Web App y slot staging existen en el mismo plan.
#       * Ambos tienen Managed Identity activa.
#       * Produccion usa recursos '*-production'; staging usa '*-staging'.
#       * El SKU y region provienen de parametros.
#       * El plan queda en una instancia tras el despliegue normal.
#   - Cubre los 3 escenarios Gherkin §10 (produccion/staging separados, SKU no
#     compatible detectado por provision-app-service.sh, configuracion cruzada).
#   - Se conecta a las pruebas posteriores TEST-S1-023/026/027 (E2E) sin
#     convertirlas en dependencia para cerrar esta issue.
set -uo pipefail   # NO usamos -e: queremos reportar TODOS los fallos.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

readonly SLOT_NAME="staging"

# --- Constantes: recursos logicos exactos exigidos por ISS-S1-004 --------------
# Cada setting sticky mapea a su valor esperado en produccion y en staging.
readonly STICKY_SETTINGS=(
  "SPRING_PROFILES_ACTIVE"
  "CENTINELA_ENVIRONMENT"
  "CENTINELA_RAW_TRANSACTIONS_CONTAINER"
  "CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER"
  "CENTINELA_INGESTION_QUEUE"
)

expected_prod_value() {
  case "$1" in
    SPRING_PROFILES_ACTIVE)                     echo "production" ;;
    CENTINELA_ENVIRONMENT)                      echo "production" ;;
    CENTINELA_RAW_TRANSACTIONS_CONTAINER)       echo "raw-transactions-production" ;;
    CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER) echo "verification-documents-production" ;;
    CENTINELA_INGESTION_QUEUE)                  echo "transactions-ingestion-production" ;;
  esac
}
expected_staging_value() {
  case "$1" in
    SPRING_PROFILES_ACTIVE)                     echo "staging" ;;
    CENTINELA_ENVIRONMENT)                      echo "staging" ;;
    CENTINELA_RAW_TRANSACTIONS_CONTAINER)       echo "raw-transactions-staging" ;;
    CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER) echo "verification-documents-staging" ;;
    CENTINELA_INGESTION_QUEUE)                  echo "transactions-ingestion-staging" ;;
  esac
}

# --- Acumuladores de resultados ------------------------------------------------
PASS=0
FAIL=0
RESULTS=()

ok()   { RESULTS+=("PASS  $*"); PASS=$((PASS + 1)); }
fail() { RESULTS+=("FAIL  $*"); FAIL=$((FAIL + 1)); log_error "$*"; }

print_report() {
  printf '\n============== ISS-S1-004 / TEST-S1-006 ==============\n'
  for r in "${RESULTS[@]}"; do printf '%s\n' "$r"; done
  printf '------------------------------------------------------\n'
  printf 'Resumen: %d PASS / %d FAIL\n' "$PASS" "$FAIL"
  printf '======================================================\n'
}

cleanup() {
  local rc="${1:-$?}"
  trap - EXIT
  print_report
  if [ "$rc" -ne 0 ]; then
    exit "$rc"
  fi
  exit "$(( FAIL > 0 ? 1 : 0 ))"
}
trap 'cleanup $?' EXIT

# --- Pre-condiciones ------------------------------------------------------------
require_cmd az
az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
load_parameters
validate_parameters
az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
  || die "Resource Group '$RESOURCE_GROUP' no existe."

# Nombres deterministas (mismo criterio que provision-app-service.sh).
app_name() {
  local hash
  hash="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)"
  printf '%s-app-%s' "$NAME_PREFIX" "$hash"
}
APP_NAME="$(app_name)"
PLAN_NAME="${NAME_PREFIX}-asp-week1"
RG="$RESOURCE_GROUP"

log_info "Validando Web App: $APP_NAME (plan: $PLAN_NAME, RG: $RG)"

# --- 1. Existencia de la Web App de produccion ---------------------------------
if az webapp show --name "$APP_NAME" --resource-group "$RG" >/dev/null 2>&1; then
  ok "Web App '$APP_NAME' existe."
else
  fail "Web App '$APP_NAME' NO existe. Ejecutar scripts/provision-app-service.sh."
  cleanup   # sin Web App el resto no aplica
fi

# --- 2. Existencia del slot staging --------------------------------------------
if az webapp show --name "$APP_NAME" --resource-group "$RG" --slot "$SLOT_NAME" >/dev/null 2>&1; then
  ok "Slot '$SLOT_NAME' existe."
else
  fail "Slot '$SLOT_NAME' NO existe."
fi

# --- 3. Web App y slot comparten el MISMO plan ---------------------------------
prod_plan_id="$(az webapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "serverFarmId" -o tsv 2>/dev/null || echo MISSING)"
slot_plan_id="$(az webapp show --name "$APP_NAME" --resource-group "$RG" --slot "$SLOT_NAME" \
  --query "serverFarmId" -o tsv 2>/dev/null || echo MISSING)"
if [ "$prod_plan_id" = "$slot_plan_id" ] && [ "$prod_plan_id" != "MISSING" ]; then
  ok "Web App y slot comparten el mismo App Service Plan."
else
  fail "Web App y slot NO comparten plan (prod='$prod_plan_id' vs slot='$slot_plan_id')."
fi

# El plan referenciado debe ser el esperado por nombre.
if [ "${prod_plan_id##*/}" = "$PLAN_NAME" ]; then
  ok "El plan referenciado es '$PLAN_NAME'."
else
  fail "El plan referenciado ('${prod_plan_id##*/}') no coincide con '$PLAN_NAME'."
fi

# --- 4. Managed Identity activa en produccion y staging ------------------------
prod_pid="$(az webapp identity show --name "$APP_NAME" --resource-group "$RG" \
  --query principalId -o tsv 2>/dev/null || true)"
staging_pid="$(az webapp identity show --name "$APP_NAME" --resource-group "$RG" \
  --slot "$SLOT_NAME" --query principalId -o tsv 2>/dev/null || true)"
if [ -n "$prod_pid" ]; then
  ok "Produccion tiene Managed Identity activa (principalId $(mask "$prod_pid"))."
else
  fail "Produccion SIN Managed Identity activa."
fi
if [ -n "$staging_pid" ]; then
  ok "Staging tiene Managed Identity activa (principalId $(mask "$staging_pid"))."
else
  fail "Staging SIN Managed Identity activa."
fi
# Las identidades system-assigned deben ser distintas entre slot y produccion.
if [ -n "$prod_pid" ] && [ -n "$staging_pid" ] && [ "$prod_pid" != "$staging_pid" ]; then
  ok "Las identidades de produccion y staging son distintas."
elif [ -n "$prod_pid" ] && [ "$prod_pid" = "$staging_pid" ]; then
  fail "Produccion y staging comparten principalId (inesperado en system-assigned)."
fi

# --- 5. SKU y region provienen de parametros -----------------------------------
plan_sku="$(az appservice plan show --name "$PLAN_NAME" --resource-group "$RG" \
  --query "sku.name" -o tsv 2>/dev/null || echo MISSING)"
if [ "$plan_sku" = "$APP_SERVICE_SKU" ]; then
  ok "SKU del plan == parametro APP_SERVICE_SKU ('$APP_SERVICE_SKU')."
else
  fail "SKU del plan = '$plan_sku' (esperado '$APP_SERVICE_SKU')."
fi
app_location="$(az webapp show --name "$APP_NAME" --resource-group "$RG" \
  --query "location" -o tsv 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' ' || echo MISSING)"
param_location="$(printf '%s' "$LOCATION" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
if [ "$app_location" = "$param_location" ]; then
  ok "Region de la Web App == parametro LOCATION ('$LOCATION')."
else
  fail "Region de la Web App = '$app_location' (esperado '$param_location')."
fi

# --- 6. Instancia unica (capacity=1) tras despliegue normal --------------------
capacity="$(az appservice plan show --name "$PLAN_NAME" --resource-group "$RG" \
  --query "sku.capacity" -o tsv 2>/dev/null || echo MISSING)"
if [ "$capacity" = "1" ]; then
  ok "El plan queda en 1 instancia (capacity=1)."
else
  fail "El plan tiene capacity='$capacity' (esperado 1 en operacion normal)."
fi

# --- 7. httpsOnly habilitado en ambos ------------------------------------------
for scope in "prod" "slot"; do
  if [ "$scope" = "prod" ]; then
    v="$(az webapp show --name "$APP_NAME" --resource-group "$RG" \
          --query "httpsOnly" -o tsv 2>/dev/null || echo MISSING)"
    label="produccion"
  else
    v="$(az webapp show --name "$APP_NAME" --resource-group "$RG" --slot "$SLOT_NAME" \
          --query "httpsOnly" -o tsv 2>/dev/null || echo MISSING)"
    label="staging"
  fi
  if [ "$v" = "true" ]; then
    ok "httpsOnly=true en $label."
  else
    fail "httpsOnly='$v' en $label (esperado true)."
  fi
done

# --- 8. Aislamiento por ambiente: cada setting sticky con su valor correcto -----
# (Gherkin "Produccion y staging separados" y "Configuracion cruzada".)
prod_settings_json="$(az webapp config appsettings list --name "$APP_NAME" --resource-group "$RG" \
  -o json 2>/dev/null || echo '[]')"
staging_settings_json="$(az webapp config appsettings list --name "$APP_NAME" --resource-group "$RG" \
  --slot "$SLOT_NAME" -o json 2>/dev/null || echo '[]')"

setting_value() {
  # $1 = json array, $2 = nombre. Devuelve el valor o MISSING.
  printf '%s' "$1" | az_jq "$2"
}
# jq puede no estar; usamos python3 si esta, o fallback con grep/sed.
az_jq() {
  local name="$1" json
  json="$(cat)"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r --arg n "$name" '(.[] | select(.name==$n) | .value) // "MISSING"'
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c "import sys,json;n='$name';d=json.load(sys.stdin);print(next((x['value'] for x in d if x.get('name')==n),'MISSING'))"
  else
    # Fallback minimalista (asume objetos {\"name\":..,\"value\":..}).
    printf '%s' "$json" | tr ',' '\n' | grep -A0 "\"$name\"" >/dev/null 2>&1 && echo "UNPARSED" || echo "MISSING"
  fi
}

for key in "${STICKY_SETTINGS[@]}"; do
  exp_prod="$(expected_prod_value "$key")"
  exp_stg="$(expected_staging_value "$key")"
  act_prod="$(setting_value "$prod_settings_json" "$key")"
  act_stg="$(setting_value "$staging_settings_json" "$key")"

  if [ "$act_prod" = "$exp_prod" ]; then
    ok "PROD $key == '$exp_prod'."
  else
    fail "PROD $key = '$act_prod' (esperado '$exp_prod')."
  fi
  if [ "$act_stg" = "$exp_stg" ]; then
    ok "STAGING $key == '$exp_stg'."
  else
    fail "STAGING $key = '$act_stg' (esperado '$exp_stg')."
  fi
  # Configuracion cruzada: staging NO debe apuntar a recursos de produccion.
  if [ "$act_stg" = "$exp_prod" ] && [ "$exp_prod" != "$exp_stg" ]; then
    fail "CONFIG CRUZADA: STAGING $key apunta a valor de produccion ('$act_stg')."
  fi
done

# --- 9. Slot settings (sticky) registrados en slotConfigNames ------------------
sticky_json="$(az webapp config appsettings list --name "$APP_NAME" --resource-group "$RG" \
  --query "[?slotSetting==\`true\`].name" -o tsv 2>/dev/null || echo "")"
for key in "${STICKY_SETTINGS[@]}"; do
  if printf '%s\n' "$sticky_json" | grep -qx "$key"; then
    ok "Setting '$key' marcado como slot setting (sticky)."
  else
    fail "Setting '$key' NO esta marcado como slot setting (se intercambiaria en un swap)."
  fi
done

# --- 10. Resumen ----------------------------------------------------------------
cleanup
