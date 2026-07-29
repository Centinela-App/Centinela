#!/usr/bin/env bash
# validate-eventgrid.sh — ISS-S2-005 (TEST-S2-006)
# Verificacion automatizada del Event Grid Topic, las colas de casos y el RBAC de
# mensajeria. Consulta exclusivamente el control plane de Azure (sin claves del
# data plane) y produce un reporte sanitizado.
#
# Salida:
#   exit 0  -> todas las verificaciones pasaron.
#   exit 1  -> al menos una verificacion fallo.
#
# Trazabilidad:
#   - Cubre los criterios de aceptacion §8 de ISS-S2-005 (topico, colas, RBAC,
#     idempotencia por nombres deterministas).
#   - Cubre el escenario Gherkin "Topico y cola creados" (la distincion documental
#     evento-vs-cola se valida en validate-documentation / revision del doc).
set -uo pipefail   # NO usamos -e: queremos reportar TODOS los fallos.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

# --- Constantes: mismos nombres que produce provision-eventgrid.sh -------------
readonly EXPECTED_CASE_QUEUES=(
  "flagged-cases-staging"
  "flagged-cases-production"
)
readonly EVENTGRID_SENDER_ROLE="EventGrid Data Sender"
readonly SLOT_NAME="staging"

# --- Acumuladores de resultados ------------------------------------------------
PASS=0
FAIL=0
RESULTS=()

ok()   { RESULTS+=("PASS  $*"); PASS=$((PASS + 1)); }
fail() { RESULTS+=("FAIL  $*"); FAIL=$((FAIL + 1)); log_error "$*"; }

print_report() {
  printf '\n================ ISS-S2-005 / TEST-S2-006 ================\n'
  for r in "${RESULTS[@]}"; do printf '%s\n' "$r"; done
  printf '%s\n' '------------------------------------------------------------'
  printf 'Resumen: %d PASS / %d FAIL\n' "$PASS" "$FAIL"
  printf '============================================================\n'
}

cleanup() {
  local rc="${1:-$?}"
  trap - EXIT
  print_report
  if [ "$rc" -ne 0 ]; then exit "$rc"; fi
  exit "$(( FAIL > 0 ? 1 : 0 ))"
}
trap 'cleanup $?' EXIT

# --- Nombres deterministas (iguales a provision-eventgrid.sh) ------------------
det_hash() { printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6; }
sa_name()    { printf '%sst%s'    "$NAME_PREFIX" "$(det_hash)"; }
app_name()   { printf '%s-app-%s' "$NAME_PREFIX" "$(det_hash)"; }
topic_name() { printf '%s-egt-%s' "$NAME_PREFIX" "$(det_hash)"; }

# --- Pre-condiciones -----------------------------------------------------------
require_cmd az
az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
load_parameters
validate_parameters
az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
  || die "Resource Group '$RESOURCE_GROUP' no existe."

RG="$RESOURCE_GROUP"
SA_NAME="$(sa_name)"
APP_NAME="$(app_name)"
TOPIC_NAME="$(topic_name)"

log_info "Validando Event Grid Topic: $TOPIC_NAME | Storage: $SA_NAME (RG: $RG)"

# --- 1. Event Grid Topic existe y esta aprovisionado ---------------------------
TOPIC_ID=""
if az eventgrid topic show --name "$TOPIC_NAME" --resource-group "$RG" >/dev/null 2>&1; then
  ok "Event Grid Topic '$TOPIC_NAME' existe."
  TOPIC_ID="$(az eventgrid topic show --name "$TOPIC_NAME" --resource-group "$RG" --query id -o tsv 2>/dev/null || true)"
  prov="$(az eventgrid topic show --name "$TOPIC_NAME" --resource-group "$RG" \
            --query 'provisioningState' -o tsv 2>/dev/null || echo MISSING)"
  if [ "$prov" = "Succeeded" ]; then
    ok "Topico en provisioningState=Succeeded."
  else
    fail "Topico en provisioningState='$prov' (esperado 'Succeeded')."
  fi
else
  fail "Event Grid Topic '$TOPIC_NAME' NO existe. Ejecutar scripts/provision-eventgrid.sh."
fi

# --- 2. Tags de trazabilidad del topico ----------------------------------------
if [ -n "$TOPIC_ID" ]; then
  for tag in "project=centinela" "week=2" "issue=ISS-S2-005"; do
    k="${tag%%=*}"; v_exp="${tag##*=}"
    v_act="$(az eventgrid topic show --name "$TOPIC_NAME" --resource-group "$RG" \
              --query "tags.$k" -o tsv 2>/dev/null || echo MISSING)"
    if [ "$v_act" = "$v_exp" ]; then ok "Tag topico $k == '$v_exp'."; else fail "Tag topico '$k' = '$v_act' (esperado '$v_exp')."; fi
  done
fi

# --- 3. Colas de casos existen (control plane) ---------------------------------
for q in "${EXPECTED_CASE_QUEUES[@]}"; do
  if az resource show --resource-group "$RG" \
        --namespace "Microsoft.Storage" \
        --parent "storageAccounts/${SA_NAME}/queueServices/default" \
        --resource-type "queues" \
        --name "$q" >/dev/null 2>&1; then
    ok "Cola de casos '$q' existe."
  else
    fail "Cola de casos '$q' NO existe."
  fi
done

# --- 4. RBAC de publicacion: la MI de la Web App es EventGrid Data Sender -------
if [ -n "$TOPIC_ID" ]; then
  prod_pid="$(az webapp identity show --name "$APP_NAME" --resource-group "$RG" \
    --query principalId -o tsv 2>/dev/null || true)"
  staging_pid="$(az webapp identity show --name "$APP_NAME" --resource-group "$RG" \
    --slot "$SLOT_NAME" --query principalId -o tsv 2>/dev/null || true)"

  check_sender_role() {
    local label="$1" pid="$2"
    if [ -z "$pid" ]; then fail "MI de $label no encontrada (ISS-S1-004)."; return; fi
    n="$(az role assignment list --assignee "$pid" --scope "$TOPIC_ID" \
          --role "$EVENTGRID_SENDER_ROLE" --query "length(@)" -o tsv 2>/dev/null || echo 0)"
    if [ "${n:-0}" -ge 1 ] 2>/dev/null; then
      ok "MI de $label tiene '$EVENTGRID_SENDER_ROLE' sobre el topico."
    else
      fail "MI de $label SIN '$EVENTGRID_SENDER_ROLE' sobre el topico."
    fi
  }
  check_sender_role "produccion" "$prod_pid"
  check_sender_role "staging"    "$staging_pid"
fi

# --- 5. Minimo privilegio: la MI de la app NO tiene Owner/Contributor ----------
if [ -n "$TOPIC_ID" ] && [ -n "${prod_pid:-}" ]; then
  bad="$(az role assignment list --assignee "$prod_pid" --scope "$TOPIC_ID" \
          --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='Contributor'] | length(@)" \
          -o tsv 2>/dev/null || echo 0)"
  if [ "${bad:-0}" -eq 0 ] 2>/dev/null; then
    ok "Sin roles de administracion (Owner/Contributor) sobre el topico."
  else
    fail "La MI tiene roles de administracion sobre el topico (viola minimo privilegio)."
  fi
fi

cleanup
