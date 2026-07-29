#!/usr/bin/env bash
#
# scripts/provision-observability.sh
# ISS-S3-014 / ISS-S3-016 — Application Insights y la alerta que exige intervencion.
#
# Alcance ESTRICTO:
#   - Crear un recurso de Application Insights sobre el workspace de Log Analytics.
#   - Fijar un tope diario de ingesta para que la telemetria no se coma el credito.
#   - Crear UNA alerta con umbral justificado y un grupo de accion que notifique.
#   - Idempotente.
#
# ---------------------------------------------------------------------------
# NIVEL GRATUITO Y CONSUMO ESTIMADO
# ---------------------------------------------------------------------------
# Application Insights (basado en Log Analytics) incluye 5 GB de ingesta gratis
# por suscripcion y mes, con 31 dias de retencion sin costo. Por encima de eso
# se factura por GB.
#
# Estimacion del proyecto:
#   - ~7 lineas de etapa por transaccion, ~350 bytes cada una  -> ~2,5 KB/transaccion
#   - telemetria automatica del agente (peticion + dependencias) -> ~4 KB/transaccion
#   Total: ~6,5 KB por transaccion.
#
#   Con 50 000 transacciones en la semana de demostracion: ~325 MB.
#   Con las pruebas de carga del escalado (3 rafagas de 20 000): ~390 MB extra.
#   Total estimado: < 1 GB, holgadamente dentro de los 5 GB gratuitos.
#
# El tope diario se fija igualmente en 1 GB. No por la estimacion, sino porque un
# bucle de reintentos ruidoso puede multiplicar el volumen por veinte en una
# noche, y el tope convierte un susto de facturacion en una perdida de datos
# acotada.
#
# ---------------------------------------------------------------------------
# LA ALERTA: CONDICION, UMBRAL Y POR QUE
# ---------------------------------------------------------------------------
# Condicion: transacciones que se ingirieron pero NO llegaron a puntuarse en los
#            ultimos 15 minutos, es decir, etapas EVENT_PUBLISH sin su SCORING
#            correspondiente.
#
# Umbral   : mas de 5 en 15 minutos.
#
# Por que esta y no otra:
#   - Es la unica condicion del sistema que significa "una transaccion real
#     entro y nadie la analizo". Un cliente recibio su acuse y el fraude no se
#     evaluo. Eso exige intervencion humana; no se resuelve reintentando.
#   - Una alerta por latencia alta o por CPU avisaria de sintomas que el escalado
#     ya corrige solo. Despertar a alguien para que mire como se autorresuelve es
#     la forma mas rapida de que se ignoren las alertas.
#
# Por que 5 y no 1:
#   - Un fallo aislado lo cubre el reintento de Event Grid, que insiste durante
#     24 h. Alertar en el primero produciria falsos positivos constantes.
#   - Cinco en quince minutos ya no es una anomalia puntual: es un patron. Con el
#     volumen previsto (~100 transacciones/hora en demostracion) representa mas
#     del 15 % de perdida, muy por encima de cualquier fluctuacion normal.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

readonly DAILY_CAP_GB="${CENTINELA_TELEMETRY_DAILY_CAP_GB:-1}"
readonly ALERT_THRESHOLD="${CENTINELA_ALERT_UNSCORED_THRESHOLD:-5}"
readonly ALERT_WINDOW_MINUTES=15
readonly ALERT_EVALUATION_MINUTES=5

ALERT_EMAIL="${CENTINELA_ALERT_EMAIL:-}"
VALIDATE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --validate-only) VALIDATE_ONLY=1 ;;
    -h|--help) echo "Uso: $0 [--validate-only]  (CENTINELA_ALERT_EMAIL define el destinatario)"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

main() {
  load_parameters
  validate_parameters
  require_cmd az

  local workspace_name="log-${NAME_PREFIX}"
  local insights_name="appi-${NAME_PREFIX}"
  local action_group_name="ag-${NAME_PREFIX}-oncall"
  local alert_name="alert-${NAME_PREFIX}-transacciones-sin-scoring"

  log_info "Plan de observabilidad:"
  log_info "  Application Insights : $insights_name (tope diario ${DAILY_CAP_GB} GB)"
  log_info "  Alerta               : > $ALERT_THRESHOLD transacciones sin scoring en $ALERT_WINDOW_MINUTES min"
  log_info "  Destinatario         : ${ALERT_EMAIL:-<sin definir: CENTINELA_ALERT_EMAIL>}"

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "Modo --validate-only: no se crea nada."
    exit 0
  fi

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."
  [ -n "$ALERT_EMAIL" ] || die "Define CENTINELA_ALERT_EMAIL: una alerta sin destinatario no alerta a nadie."

  ensure_extension
  ensure_insights "$insights_name" "$workspace_name"
  apply_daily_cap "$workspace_name"
  ensure_action_group "$action_group_name"
  ensure_alert "$alert_name" "$insights_name" "$action_group_name"

  log_info "ISS-S3-016 OK"
  log_info "  APPLICATIONINSIGHTS_CONNECTION_STRING se obtiene con:"
  log_info "    az monitor app-insights component show -g $RESOURCE_GROUP -a $insights_name --query connectionString -o tsv"
}

ensure_extension() {
  az extension show --name application-insights >/dev/null 2>&1 \
    || az extension add --name application-insights --upgrade --only-show-errors --output none
}

ensure_insights() {
  local name="$1" workspace="$2"
  if az monitor app-insights component show -g "$RESOURCE_GROUP" -a "$name" >/dev/null 2>&1; then
    log_info "Application Insights '$name' ya existe."
    return
  fi

  local workspace_id
  workspace_id="$(az monitor log-analytics workspace show -g "$RESOURCE_GROUP" -n "$workspace" \
    --query id -o tsv)" || die "Falta el workspace '$workspace'. Ejecuta provision-container-apps.sh."

  log_info "Creando Application Insights '$name'..."
  az monitor app-insights component create \
    -g "$RESOURCE_GROUP" -a "$name" -l "$LOCATION" \
    --workspace "$workspace_id" \
    --application-type web \
    --output none
}

apply_daily_cap() {
  local workspace="$1"
  log_info "Fijando tope diario de ingesta en ${DAILY_CAP_GB} GB..."
  az monitor log-analytics workspace update \
    -g "$RESOURCE_GROUP" -n "$workspace" \
    --quota "$DAILY_CAP_GB" --output none \
    || log_warn "No se pudo fijar el tope diario; verificar manualmente en el portal."
}

ensure_action_group() {
  local name="$1"
  if az monitor action-group show -g "$RESOURCE_GROUP" -n "$name" >/dev/null 2>&1; then
    log_info "Grupo de accion '$name' ya existe."
    return
  fi
  log_info "Creando grupo de accion '$name'..."
  az monitor action-group create \
    -g "$RESOURCE_GROUP" -n "$name" --short-name "centinela" \
    --action email oncall "$ALERT_EMAIL" \
    --output none
}

ensure_alert() {
  local alert_name="$1" insights_name="$2" action_group_name="$3"

  local scope action_group_id
  scope="$(az monitor app-insights component show -g "$RESOURCE_GROUP" -a "$insights_name" --query id -o tsv)"
  action_group_id="$(az monitor action-group show -g "$RESOURCE_GROUP" -n "$action_group_name" --query id -o tsv)"

  # La consulta cuenta transacciones cuya etapa EVENT_PUBLISH existe y cuya
  # etapa SCORING no aparecio. Es la definicion literal de "entro y nadie la
  # analizo".
  local query
  query=$(cat <<'KQL'
let ventana = 15m;
let publicadas = traces
    | where timestamp > ago(ventana)
    | where message has "stage=EVENT_PUBLISH" and message has "outcome=SUCCESS"
    | extend transactionId = extract(@"transactionId=([^\s]+)", 1, message)
    | distinct transactionId;
let puntuadas = traces
    | where timestamp > ago(ventana)
    | where message has "stage=SCORING"
    | extend transactionId = extract(@"transactionId=([^\s]+)", 1, message)
    | distinct transactionId;
publicadas
| join kind=leftanti puntuadas on transactionId
| summarize SinScoring = count()
KQL
)

  log_info "Creando/actualizando la alerta '$alert_name'..."
  az monitor scheduled-query create \
    -g "$RESOURCE_GROUP" -n "$alert_name" \
    --scopes "$scope" \
    --condition "count 'SinScoring' > $ALERT_THRESHOLD" \
    --condition-query "SinScoring=$query" \
    --description "Transacciones ingeridas que no llegaron a puntuarse. Requiere intervencion humana: el cliente recibio acuse y el analisis de fraude no ocurrio." \
    --evaluation-frequency "${ALERT_EVALUATION_MINUTES}m" \
    --window-size "${ALERT_WINDOW_MINUTES}m" \
    --severity 1 \
    --action-groups "$action_group_id" \
    --output none 2>/dev/null \
    || log_warn "La alerta ya existia o requiere ajuste manual; revisar en el portal."
}

main "$@"
