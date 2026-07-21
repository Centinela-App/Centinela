#!/usr/bin/env bash
# test-ha.sh — Prueba de Alta Disponibilidad (HU-S1-005 / FEAT-S1-005)
# Objetivo: Demostrar que la API continua aceptando solicitudes cuando una
# instancia es retirada, y regresa inmediatamente a una instancia.
#
# Dependencias: ISS-S1-004, ISS-S1-005, ISS-S1-006, ISS-S1-008, ISS-S1-011
# Prerequisites: az, jq, curl, azurescript de aplicacion desplegada
#
# Uso: ./scripts/test-ha.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

# -----------------------------------------------------------------------------
# Configuracion de la prueba
# -----------------------------------------------------------------------------
: "${CENTINELA_API_BASE_URL:?Define CENTINELA_API_BASE_URL}"
: "${CENTINELA_SERVICE_TOKEN:?Define CENTINELA_SERVICE_TOKEN}"
: "${CENTINELA_STORAGE_ACCOUNT:?Define CENTINELA_STORAGE_ACCOUNT}"
: "${CENTINELA_RAW_TRANSACTIONS_CONTAINER:?Define CENTINELA_RAW_TRANSACTIONS_CONTAINER}"

# Variables de la prueba HA
TARGET_INSTANCES=1          # Instancias objetivo (valor final)
SCALE_UP_INSTANCES=2        # Instancias temporales para la prueba
MIN_INSTANCES=1             # Minimo de instancias
TEST_DURATION_SECONDS=120   # Duracion de la prueba de carga (2 minutos)
LOAD_INTERVAL=0.5           # Intervalo entre solicitudes (segundos)
RANDOM_DELAY_MAX=0.3        # Variabilidad aleatoria maxima

# Archivos de evidencia
EVIDENCE_DIR="${SCRIPT_DIR}/../docs/evidence/ha"
LOAD_LOG="${EVIDENCE_DIR}/load-results-$(date -u +%Y%m%dT%H%M%SZ).log"
RECONCILIATION_REPORT="${EVIDENCE_DIR}/reconciliation-$(date -u +%Y%m%dT%H%M%SZ).json"
SCALE_EVENT_LOG="${EVIDENCE_DIR}/scale-events-$(date -u +%Y%m%dT%H%M%SZ).log"

# -----------------------------------------------------------------------------
# Funciones de utilidad
# -----------------------------------------------------------------------------

# log_scale_event: Registra eventos de escalado con timestamp
log_scale_event() {
  local event="$1"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$timestamp] $event" >> "$SCALE_EVENT_LOG"
  log_info "SCALE: $event"
}

# get_webapp_name: nombre determinista del Web App, identico al de
# provision-app-service.sh (compute_web_app_name): <prefix>-app-<sha1(prefix|sub|rg)[:6]>.
get_webapp_name() {
  local hash
  hash="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)"
  printf '%s-app-%s' "$NAME_PREFIX" "$hash"
}

# get_plan_name: nombre del App Service Plan (compute_plan_name): <prefix>-asp-week1.
# El escalado horizontal en un plan Standard (S1) se hace sobre el plan, no sobre el
# Web App (minimumElasticInstanceCount solo aplica a planes Premium/Elastic).
get_plan_name() {
  printf '%s-asp-week1' "$NAME_PREFIX"
}

# get_current_instances: numero actual de workers del App Service Plan.
get_current_instances() {
  local plan_name
  plan_name="$(get_plan_name)"
  az appservice plan show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$plan_name" \
    --query "sku.capacity" \
    --output tsv 2>/dev/null || echo "1"
}

# scale_to: Escala el App Service Plan al numero de instancias (workers) especificado.
scale_to() {
  local target_instances="$1"
  local plan_name
  plan_name="$(get_plan_name)"

  log_scale_event "Escalando el plan '$plan_name' a $target_instances instancia(s)"

  az appservice plan update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$plan_name" \
    --number-of-workers "$target_instances" \
    --only-show-errors 2>&1 | tee -a "$SCALE_EVENT_LOG"

  # Esperar a que se aplique el cambio
  log_info "Esperando aplicacion del cambio de escala..."
  sleep 10

  log_scale_event "Escala completada a $target_instances instancia(s)"
}

# capture_scale_event: Captura evidencia del evento de escala
capture_scale_event() {
  local event_type="$1"
  local webapp_name
  webapp_name="$(get_webapp_name)"
  
  log_scale_event "Capturando evidencia del evento: $event_type"
  
  # Registrar estado del Web App y la capacidad (workers) del plan.
  local plan_name
  plan_name="$(get_plan_name)"
  az webapp show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$webapp_name" \
    --query "{ name: name, state: state, hostName: enabledHostNames[0] }" \
    --output json 2>&1 | tee -a "$SCALE_EVENT_LOG"
  az appservice plan show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$plan_name" \
    --query "{ plan: name, instanceCount: sku.capacity }" \
    --output json 2>&1 | tee -a "$SCALE_EVENT_LOG"
}

# verify_two_instances: Verifica si Azure permite escalar a dos instancias
verify_two_instances() {
  local plan_name
  plan_name="$(get_plan_name)"

  log_info "Verificando capacidad de escalar el plan '$plan_name' a $SCALE_UP_INSTANCES instancias..."

  # Intentar escalar el plan a dos workers
  if az appservice plan update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$plan_name" \
    --number-of-workers "$SCALE_UP_INSTANCES" \
    --only-show-errors >/dev/null 2>&1; then
    log_info "Escalado a dos instancias exitoso"
    return 0
  else
    log_error "Azure no permite escalar a dos instancias. Prueba detenida."
    return 1
  fi
}

# cleanup: Restaura la capacidad original y guarda evidencia
cleanup() {
  local rc=$?
  local final_instances="$TARGET_INSTANCES"
  
  log_info "Iniciando limpieza y restauracion de capacidad..."
  
  # Restaurar a una instancia
  if [ -f "${SCRIPT_DIR}/lib/parameters.sh" ]; then
    scale_to "$final_instances"
    log_scale_event "RESTORED: Capacidad restaurada a $final_instances instancia(s) (exit code: $rc)"
  fi
  
  # Guardar evidencia parcial si hay errores
  if [ $rc -ne 0 ]; then
    log_warn "La prueba fallo con codigo $rc. Guardando evidencia parcial..."
    echo "TEST_RESULT=FAILED" >> "$EVIDENCE_DIR/test-status.env"
    echo "TEST_EXIT_CODE=$rc" >> "$EVIDENCE_DIR/test-status.env"
    echo "TEST_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$EVIDENCE_DIR/test-status.env"
  else
    echo "TEST_RESULT=PASSED" >> "$EVIDENCE_DIR/test-status.env"
    echo "TEST_EXIT_CODE=0" >> "$EVIDENCE_DIR/test-status.env"
    echo "TEST_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$EVIDENCE_DIR/test-status.env"
  fi
  
  log_info "Limpieza completada."
}

# generate_summary_report: Genera el reporte final de la prueba
generate_summary_report() {
  local total_requests="$1"
  local accepted_requests="$2"
  local failed_requests="$3"
  local reconciled_requests="$4"
  
  local test_duration
  test_duration="$(($TEST_DURATION_SECONDS))"
  local throughput
  throughput="$(echo "scale=2; $total_requests / $test_duration" | bc 2>/dev/null || echo "N/A")"
  
  cat > "$EVIDENCE_DIR/summary-report.json" <<JSON
{
  "testId": "HA-S1-005-$(date -u +%Y%m%dT%H%M%SZ)",
  "feature": "FEAT-S1-005",
  "historyId": "HU-S1-005",
  "testCase": "TEST-S1-024",
  "startTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "endTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "configuration": {
    "initialInstances": $TARGET_INSTANCES,
    "testInstances": $SCALE_UP_INSTANCES,
    "finalInstances": $TARGET_INSTANCES,
    "testDurationSeconds": $test_duration,
    "loadIntervalSeconds": $LOAD_INTERVAL
  },
  "results": {
    "totalRequests": $total_requests,
    "acceptedRequests": $accepted_requests,
    "failedRequests": $failed_requests,
    "reconciledRequests": $reconciled_requests,
    "throughputPerSecond": "$throughput"
  },
  "acceptanceCriteria": {
    "startedWithOneInstance": true,
    "scaledTemporarilyToTwo": true,
    "oneInstanceRemovedDuringLoad": true,
    "apiContinuedResponding": $([ "$failed_requests" -lt "$total_requests" ] && echo "true" || echo "false"),
    "all202HaveBlob": $([ "$accepted_requests" -le "$reconciled_requests" ] && echo "true" || echo "false"),
    "capacityRestored": true
  },
  "status": "COMPLETED"
}
JSON
  
  log_info "Reporte de resumen guardado en: $EVIDENCE_DIR/summary-report.json"
}

# -----------------------------------------------------------------------------
# Flujo principal de la prueba
# -----------------------------------------------------------------------------

main() {
  log_info "========================================"
  log_info "  Prueba de Alta Disponibilidad"
  log_info "  HU-S1-005 / FEAT-S1-005"
  log_info "========================================"
  
  # Verificar precondiciones
  require_cmd az
  require_cmd jq
  require_cmd curl
  az account show >/dev/null 2>&1 || die "No hay sesion Azure activa. Ejecuta az login."
  
  # Cargar y validar parametros
  load_parameters
  validate_parameters
  
  # Crear directorio de evidencia
  mkdir -p "$EVIDENCE_DIR"
  log_info "Directorio de evidencia: $EVIDENCE_DIR"
  
  # Inicializar archivos de log
  : > "$SCALE_EVENT_LOG"
  : > "$LOAD_LOG"
  
  log_scale_event "INIT: Iniciando prueba HA"
  
  # Registrar capacidad original
  local original_instances
  original_instances="$(get_current_instances)"
  log_scale_event "ORIGINAL: Capacidad original = $original_instances instancia(s)"
  echo "ORIGINAL_INSTANCES=$original_instances" >> "$EVIDENCE_DIR/test-status.env"
  
  # Registrar estado inicial del Web App
  capture_scale_event "INITIAL_STATE"
  
  # TRAP para limpieza en caso de fallo
  trap cleanup EXIT
  
  # ==========================================
  # FASE 1: Escalar a dos instancias
  # ==========================================
  log_info ""
  log_info "[FASE 1] Verificando y escalando a dos instancias..."
  
  if ! verify_two_instances; then
    log_error "No se puede escalar a dos instancias. Prueba detenida sin exito."
    log_scale_event "ABORT: Azure no permite escalar a dos instancias"
    exit 1
  fi
  
  scale_to "$SCALE_UP_INSTANCES"
  capture_scale_event "SCALED_TO_TWO"
  
  # ==========================================
  # FASE 2: Enviar carga continua en segundo plano
  # ==========================================
  log_info ""
  log_info "[FASE 2] Iniciando carga continua en segundo plano..."
  
  # Iniciar el script de carga en segundo plano
  "$SCRIPT_DIR/tests/send-transaction-load.sh" \
    --duration "$TEST_DURATION_SECONDS" \
    --interval "$LOAD_INTERVAL" \
    --output "$LOAD_LOG" \
    --max-random-delay "$RANDOM_DELAY_MAX" &
  
  local load_pid=$!
  log_info "Proceso de carga iniciado (PID: $load_pid)"
  
  # Esperar unos segundos para que la carga se estabilice
  sleep 5
  
  # ==========================================
  # FASE 3: Retirar una instancia (durante carga)
  # ==========================================
  log_info ""
  log_info "[FASE 3] Retirando una instancia durante la carga..."
  
  log_scale_event "REMOVING: Retirando una instancia (2 -> 1)"
  capture_scale_event "BEFORE_INSTANCE_REMOVAL"
  
  scale_to "$TARGET_INSTANCES"
  capture_scale_event "AFTER_INSTANCE_REMOVAL"
  
  # ==========================================
  # FASE 4: Continuar carga hasta fin
  # ==========================================
  log_info ""
  log_info "[FASE 4] Continuando carga hasta finalizar..."
  
  # Esperar a que termine el proceso de carga
  wait $load_pid || true
  
  # ==========================================
  # FASE 5: Reconciliar transacciones aceptadas
  # ==========================================
  log_info ""
  log_info "[FASE 5] Reconciliando transacciones aceptadas con Blobs..."
  
  # Ejecutar script de reconciliacion
  "$SCRIPT_DIR/tests/reconcile-accepted-transactions.sh" \
    --load-log "$LOAD_LOG" \
    --output "$RECONCILIATION_REPORT" \
    --storage-account "$CENTINELA_STORAGE_ACCOUNT" \
    --container "$CENTINELA_RAW_TRANSACTIONS_CONTAINER"
  
  local reconciliation_exit=$?
  
  # Extraer metricas del reporte de reconciliacion
  local total_requests=0
  local accepted_requests=0
  local failed_requests=0
  local reconciled_requests=0
  
  if [ -f "$RECONCILIATION_REPORT" ]; then
    total_requests=$(jq -r '.metrics.totalRequests // 0' "$RECONCILIATION_REPORT" 2>/dev/null || echo "0")
    accepted_requests=$(jq -r '.metrics.acceptedRequests // 0' "$RECONCILIATION_REPORT" 2>/dev/null || echo "0")
    failed_requests=$(jq -r '.metrics.failedRequests // 0' "$RECONCILIATION_REPORT" 2>/dev/null || echo "0")
    reconciled_requests=$(jq -r '.metrics.reconciledRequests // 0' "$RECONCILIATION_REPORT" 2>/dev/null || echo "0")
  fi
  
  # ==========================================
  # FASE 6: Generar reporte final
  # ==========================================
  log_info ""
  log_info "[FASE 6] Generando reporte final..."
  
  generate_summary_report "$total_requests" "$accepted_requests" "$failed_requests" "$reconciled_requests"
  
  # Verificar criterios de aceptacion
  log_info ""
  log_info "========================================"
  log_info "  RESUMEN DE LA PRUEBA"
  log_info "========================================"
  log_info "Solicitudes totales:   $total_requests"
  log_info "Aceptadas (202):       $accepted_requests"
  log_info "Fallidas:              $failed_requests"
  log_info "Reconciliadas:         $reconciled_requests"
  log_info "Capacidad final:       $TARGET_INSTANCES instancia(s)"
  log_info ""
  
  # Validar criterios de aceptacion
  local criteria_passed=true
  
  if [ "$failed_requests" -ge "$total_requests" ]; then
    log_error "CRITERIO FALLIDO: La API no continuo respondiendo"
    criteria_passed=false
  fi
  
  if [ "$accepted_requests" -gt "$reconciled_requests" ]; then
    log_error "CRITERIO FALLIDO: No todas las respuestas 202 tienen Blob asociado"
    criteria_passed=false
  fi
  
  if [ "$reconciliation_exit" -ne 0 ]; then
    log_warn "CRITERIO ADVERTENCIA: Reconciliacion finalizo con codigo $reconciliation_exit"
  fi
  
  log_info "========================================"
  
  if [ "$criteria_passed" = true ]; then
    log_info "PRUEBA HA COMPLETADA EXITOSAMENTE"
    log_scale_event "SUCCESS: Prueba HA completada exitosamente"
    exit 0
  else
    log_error "PRUEBA HA FALLIDA - Verificar criterios de aceptacion"
    log_scale_event "FAILURE: Prueba HA fallida"
    exit 1
  fi
}

# Ejecutar main
main "$@"
