#!/usr/bin/env bash
# ISS-S2-014 - Reporte de costos y cierre controlado de Semana 2.
# Por defecto SOLO captura evidencia. La eliminacion exige --destroy --yes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$REPO_ROOT/scripts/lib/parameters.sh"

START_DATE=""
END_DATE="$(date -u +%Y-%m-%d)"
DESTROY=0
CONFIRMED=0

usage() {
  cat <<'USAGE'
Uso:
  bash scripts/tests/test-week2-closeout.sh --start-date YYYY-MM-DD [--end-date YYYY-MM-DD]
  bash scripts/tests/test-week2-closeout.sh --start-date YYYY-MM-DD [--end-date YYYY-MM-DD] --destroy --yes

Sin --destroy: captura inventario, RBAC y costos; no elimina recursos.
Con --destroy --yes: captura evidencia, elimina el Resource Group y confirma su ausencia.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --start-date) START_DATE="${2:?Falta valor para --start-date}"; shift 2 ;;
    --end-date) END_DATE="${2:?Falta valor para --end-date}"; shift 2 ;;
    --destroy) DESTROY=1; shift ;;
    --yes) CONFIRMED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

validate_date() {
  local value="$1" name="$2"
  [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "$name debe usar YYYY-MM-DD."
  date -u -d "$value" +%Y-%m-%d >/dev/null 2>&1 || die "$name no es una fecha valida."
}

sanitize_json() {
  local input="$1" output="$2" subscription_id="$3"
  jq --arg subscription "$subscription_id" '
    walk(
      if type == "string" then
        gsub($subscription; "<subscription-id>")
      else . end
    )
  ' "$input" > "$output"
}

capture_costs() {
  local scope="$1" start="$2" end="$3" raw="$4"
  local body
  body="$(jq -nc --arg from "${start}T00:00:00Z" --arg to "${end}T23:59:59Z" '{
    type:"Usage",
    timeframe:"Custom",
    timePeriod:{from:$from,to:$to},
    dataset:{
      granularity:"None",
      aggregation:{totalCost:{name:"PreTaxCost",function:"Sum"}},
      grouping:[
        {type:"Dimension",name:"ServiceName"},
        {type:"Dimension",name:"Currency"}
      ]
    }
  }')"

  az rest --method post \
    --uri "https://management.azure.com${scope}/providers/Microsoft.CostManagement/query?api-version=2025-03-01" \
    --headers Content-Type=application/json \
    --body "$body" > "$raw"
}

render_cost_summary() {
  local input="$1" output="$2"
  jq '
    def column_index($name):
      [.properties.columns[].name] | index($name);
    (column_index("PreTaxCost")) as $costIndex |
    (column_index("ServiceName")) as $serviceIndex |
    (column_index("Currency")) as $currencyIndex |
    {
      columns: .properties.columns,
      rows: [
        .properties.rows[]? |
        {
          service: .[$serviceIndex],
          cost: .[$costIndex],
          currency: .[$currencyIndex]
        }
      ],
      totalsByCurrency: [
        .properties.rows[]? |
        {cost: .[$costIndex], currency: .[$currencyIndex]}
      ]
      | group_by(.currency)
      | map({currency: .[0].currency, total: (map(.cost) | add)})
    }
  ' "$input" > "$output"
}

main() {
  local cmd active_subscription scope run_id evidence_dir raw_inventory raw_rbac raw_cost
  for cmd in az jq date git sha256sum; do require_cmd "$cmd"; done
  [ -n "$START_DATE" ] || die "--start-date es obligatorio."
  validate_date "$START_DATE" "--start-date"
  validate_date "$END_DATE" "--end-date"
  [[ "$START_DATE" < "$END_DATE" || "$START_DATE" == "$END_DATE" ]] \
    || die "--start-date no puede ser posterior a --end-date."
  [ "$DESTROY" -eq 0 ] || [ "$CONFIRMED" -eq 1 ] \
    || die "La eliminacion requiere --destroy --yes."

  load_parameters
  validate_parameters
  az account show >/dev/null 2>&1 || die "No hay sesion Azure activa."
  active_subscription="$(az account show --query id -o tsv)"
  [ "$active_subscription" = "$SUBSCRIPTION_ID" ] \
    || die "La suscripcion activa no coincide con SUBSCRIPTION_ID."
  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "No existe el Resource Group '$RESOURCE_GROUP'."

  run_id="run-closeout-$(date -u +%Y%m%dT%H%M%SZ)"
  evidence_dir="$REPO_ROOT/docs/evidence/iss-s2-014/$run_id"
  mkdir -p "$evidence_dir"
  scope="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
  raw_inventory="$evidence_dir/.inventory.raw.json"
  raw_rbac="$evidence_dir/.rbac.raw.json"
  raw_cost="$evidence_dir/.cost.raw.json"

  jq -n \
    --arg issue "ISS-S2-014" \
    --arg runId "$run_id" \
    --arg timestampUtc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg commit "$(git -C "$REPO_ROOT" rev-parse HEAD)" \
    --arg branch "$(git -C "$REPO_ROOT" branch --show-current)" \
    --arg resourceGroup "$RESOURCE_GROUP" \
    --arg startDate "$START_DATE" \
    --arg endDate "$END_DATE" \
    --argjson destroyRequested "$DESTROY" \
    '{issue:$issue,runId:$runId,timestampUtc:$timestampUtc,commit:$commit,branch:$branch,
      resourceGroup:$resourceGroup,startDate:$startDate,endDate:$endDate,
      destroyRequested:($destroyRequested == 1)}' > "$evidence_dir/metadata.json"

  az resource list --resource-group "$RESOURCE_GROUP" -o json > "$raw_inventory"
  sanitize_json "$raw_inventory" "$evidence_dir/resources-before.json" "$SUBSCRIPTION_ID"
  jq '[.[] | {name,type,location,tags}] | sort_by(.type,.name)' \
    "$evidence_dir/resources-before.json" > "$evidence_dir/resources-summary.json"

  az role assignment list --resource-group "$RESOURCE_GROUP" --all -o json > "$raw_rbac"
  sanitize_json "$raw_rbac" "$evidence_dir/rbac-before.json" "$SUBSCRIPTION_ID"

  capture_costs "$scope" "$START_DATE" "$END_DATE" "$raw_cost"
  sanitize_json "$raw_cost" "$evidence_dir/cost-query.json" "$SUBSCRIPTION_ID"
  render_cost_summary "$evidence_dir/cost-query.json" "$evidence_dir/cost-summary.json"

  sha256sum "$evidence_dir"/*.json > "$evidence_dir/checksums.sha256"
  rm -f "$raw_inventory" "$raw_rbac" "$raw_cost"

  if [ "$DESTROY" -eq 0 ]; then
    jq -n --arg status "EVIDENCE_CAPTURED" --arg detail "No se eliminaron recursos." \
      '{status:$status,detail:$detail}' > "$evidence_dir/summary.json"
    log_info "ISS-S2-014: evidencia capturada sin eliminar recursos: $evidence_dir"
    return 0
  fi

  log_warn "Eliminando Resource Group '$RESOURCE_GROUP'. Esta accion es irreversible."
  az group delete --name "$RESOURCE_GROUP" --yes
  if az group exists --name "$RESOURCE_GROUP" | grep -qx false; then
    printf 'false\n' > "$evidence_dir/resource-group-exists-after.txt"
  else
    die "Azure aun reporta el Resource Group despues de la eliminacion."
  fi

  jq -n --arg status "PASSED" \
    --arg detail "Costos e inventario capturados; Resource Group eliminado y ausencia confirmada." \
    '{status:$status,detail:$detail}' > "$evidence_dir/summary.json"
  log_info "ISS-S2-014 PASSED: $evidence_dir"
}

main "$@"
