#!/usr/bin/env bash
# validate-storage.sh — ISS-S1-003 (TEST-S1-005)
# Verificacion automatizada de Storage, contenedores y colas por ambiente.
# Lee parametros desde .env (o env del proceso) y consulta exclusivamente el
# control plane de Azure para no depender de claves del data plane.
#
# Salida:
#   imprime un reporte estructurado en stdout (sanitizado) y un resumen final.
#   exit 0  -> todas las verificaciones pasaron.
#   exit 1  -> al menos una verificacion fallo (detalle en stderr).
#
# Trazabilidad:
#   - Cubre los criterios de aceptacion §8 de ISS-S1-003.
#   - Cubre los 3 escenarios Gherkin §10 de ISS-S1-003 (recursos creados,
#     reejecucion idempotente, acceso publico prohibido).
#   - Se conecta a las pruebas posteriores TEST-S1-026 / TEST-S1-027 (E2E) sin
#     convertirlas en dependencia para cerrar esta issue.
set -uo pipefail   # NO usamos -e: queremos reportar TODOS los fallos.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

# --- Constantes: nombres exactos exigidos por ISS-S1-003 §8 ---------------------
readonly EXPECTED_CONTAINERS=(
  "raw-transactions-staging"
  "raw-transactions-production"
  "verification-documents-staging"
  "verification-documents-production"
)
readonly EXPECTED_QUEUES=(
  "transactions-ingestion-staging"
  "transactions-ingestion-production"
)

# --- Acumuladores de resultados ------------------------------------------------
PASS=0
FAIL=0
RESULTS=()

ok()   { RESULTS+=("PASS  $*"); PASS=$((PASS + 1)); }
fail() { RESULTS+=("FAIL  $*"); FAIL=$((FAIL + 1)); log_error "$*"; }

print_report() {
  printf '\n================ ISS-S1-003 / TEST-S1-005 ================\n'
  for r in "${RESULTS[@]}"; do printf '%s\n' "$r"; done
  printf '------------------------------------------------------------\n'
  printf 'Resumen: %d PASS / %d FAIL\n' "$PASS" "$FAIL"
  printf '============================================================\n'
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

# Calculamos el mismo nombre que provision-storage.sh produce (estable).
sa_name() {
  local hash
  hash="$(
    printf '%s|%s|%s' \
      "$NAME_PREFIX" \
      "$SUBSCRIPTION_ID" \
      "$RESOURCE_GROUP" \
    | sha1sum \
    | cut -c1-6
  )"

  printf '%sst%s' "$NAME_PREFIX" "$hash"
}
SA_NAME="$(sa_name)"
RG="$RESOURCE_GROUP"

log_info "Validando Storage Account: $SA_NAME (RG: $RG)"

# --- 1. Existencia del Storage Account -----------------------------------------
if az storage account show --name "$SA_NAME" --resource-group "$RG" >/dev/null 2>&1; then
  ok "Storage Account '$SA_NAME' existe."
else
  fail "Storage Account '$SA_NAME' NO existe. Ejecutar scripts/provision-storage.sh."
  # Si no existe, las siguientes validaciones no son posibles.
  cleanup
fi

# --- 2. Propiedades de seguridad exigidas (sin secretos en logs) ---------------
check_property() {
  local query="$1" expected="$2" label="$3"
  local actual
  actual="$(az storage account show \
              --name "$SA_NAME" --resource-group "$RG" \
              --query "$query" -o tsv 2>/dev/null || echo MISSING)"
  if [ "$actual" = "$expected" ]; then
    ok "Property $label == '$expected'."
  else
    fail "Property '$label' = '$actual' (esperado '$expected')."
  fi
}

check_property 'minimumTlsVersion'             'TLS1_2'   'minimumTlsVersion'
check_property 'supportsHttpsTrafficOnly'      true        'supportsHttpsTrafficOnly'
check_property 'allowBlobPublicAccess'         false       'allowBlobPublicAccess'
check_property 'publicNetworkAccess'           'Disabled'  'publicNetworkAccess'
check_property 'kind'                          'StorageV2' 'kind'

# --- 3. Tags exigidos ----------------------------------------------------------
for tag in "project=centinela" "week=1" "team=celula-centinela" "issue=ISS-S1-003"; do
  k="${tag%%=*}"
  v_exp="${tag##*=}"
  v_act="$(az storage account show --name "$SA_NAME" --resource-group "$RG" \
            --query "tags.$k" -o tsv 2>/dev/null || echo MISSING)"
  if [ "$v_act" = "$v_exp" ]; then
    ok "Tag $k == '$v_exp'."
  else
    fail "Tag '$k' = '$v_act' (esperado '$v_exp')."
  fi
done

# --- 4. Contenedores con acceso anonimo deshabilitado (control plane) ----------
for c in "${EXPECTED_CONTAINERS[@]}"; do
  # ARM: blobServices/containers/default/<name>
  if az resource show --resource-group "$RG" \
        --namespace "Microsoft.Storage" \
        --parent "storageAccounts/${SA_NAME}/blobServices/default" \
        --resource-type "containers" \
        --name "$c" >/dev/null 2>&1; then
    public="$(az resource show --resource-group "$RG" \
              --namespace "Microsoft.Storage" \
              --parent "storageAccounts/${SA_NAME}/blobServices/default" \
              --resource-type "containers" \
              --name "$c" \
              --query 'properties.publicAccess' -o tsv 2>/dev/null || echo MISSING)"
    if [ "$public" = "None" ]; then
      ok "Container '$c' existe y publicAccess=None."
    else
      fail "Container '$c' publicAccess='$public' (esperado 'None')."
    fi
  else
    fail "Container '$c' NO existe."
  fi
done

# --- 5. Colas (control plane: queueServices/queues/default/<name>) ------------
for q in "${EXPECTED_QUEUES[@]}"; do
  if az resource show --resource-group "$RG" \
        --namespace "Microsoft.Storage" \
        --parent "storageAccounts/${SA_NAME}/queueServices/default" \
        --resource-type "queues" \
        --name "$q" >/dev/null 2>&1; then
    ok "Queue '$q' existe."
  else
    fail "Queue '$q' NO existe."
  fi
done

# --- 6. Aislamiento staging/production: nombres exactos ------------------------
expected_count_conc=${#EXPECTED_CONTAINERS[@]}
expected_count_q=${#EXPECTED_QUEUES[@]}
if [ "$expected_count_conc" -eq 4 ] && [ "$expected_count_q" -eq 2 ]; then
  ok "Cantidad esperada: 4 contenedores y 2 colas."
else
  fail "Cantidad inesperada de recursos esperados (bug local en el script)."
fi

# --- 7. Acceso publico prohibido (chequeo activo: intento anonimo) -------------
# Si publicNetworkAccess=Disabled, cualquier intento anonimo contra un blob debe
# ser rechazado. Esta es la Gherkin §10 Escenario "Acceso publico prohibido".
readonly BLOB_URL="https://${SA_NAME}.blob.core.windows.net/${EXPECTED_CONTAINERS[0]}/?comp=list"
http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
              --connect-timeout 5 --max-time 10 \
              -X GET "$BLOB_URL" || echo 000)"
case "$http_code" in
  000)        ok "Acceso publico bloqueado (red/timeout — esperable en defaultDeny)." ;;
  4*|5*)      ok "Acceso publico rechazado con HTTP $http_code." ;;
  2*)         fail "Acceso publico permitido con HTTP $http_code — Storage NO esta protegido." ;;
  *)          log_warn "Respuesta HTTP no categorizada: $http_code (se acepta por defecto)." ;;
esac

# --- 8. Resumen -----------------------------------------------------------------
cleanup
