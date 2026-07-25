#!/usr/bin/env bash
# TEST-S1-024: continuidad de la API al reducir temporalmente dos workers a uno.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

SCALE_UP_INSTANCES="${SCALE_UP_INSTANCES:-2}"
TARGET_INSTANCES=1
TEST_DURATION_SECONDS="${TEST_DURATION_SECONDS:-120}"
LOAD_INTERVAL="${LOAD_INTERVAL:-0.5}"
RANDOM_DELAY_MAX="${RANDOM_DELAY_MAX:-0.3}"
SCALE_WAIT_TIMEOUT_SECONDS="${SCALE_WAIT_TIMEOUT_SECONDS:-300}"
SCALE_POLL_SECONDS="${SCALE_POLL_SECONDS:-10}"

RUN_ID="run-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
EVIDENCE_DIR="$SCRIPT_DIR/../docs/evidence/ha/$RUN_ID"
LOAD_LOG="$EVIDENCE_DIR/load-results.log"
LOAD_CSV="${LOAD_LOG%.log}.csv"
RECONCILIATION_REPORT="$EVIDENCE_DIR/reconciliation.json"
SCALE_EVENT_LOG="$EVIDENCE_DIR/scale-events.log"
SUMMARY_REPORT="$EVIDENCE_DIR/summary-report.json"

ORIGINAL_INSTANCES=""
CAPACITY_RESTORED=false
SYNTHETIC_CLEANUP_DONE=false
TEST_FINISHED=false

compute_hash() {
  printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6
}

get_plan_name() {
  printf '%s-asp-week1' "$NAME_PREFIX"
}

get_webapp_name() {
  printf '%s-app-%s' "$NAME_PREFIX" "$(compute_hash)"
}

get_storage_account_name() {
  printf '%sst%s' "$NAME_PREFIX" "$(compute_hash)"
}

get_current_instances() {
  az appservice plan show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$(get_plan_name)" \
    --query sku.capacity -o tsv
}

log_scale_event() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$SCALE_EVENT_LOG" >&2
}

wait_for_capacity() {
  local expected="$1" started_at current elapsed
  started_at="$(date +%s)"
  while true; do
    current="$(get_current_instances)"
    if [ "$current" = "$expected" ]; then
      log_scale_event "Capacidad confirmada: $current worker(s)."
      return 0
    fi

    elapsed=$(( $(date +%s) - started_at ))
    if [ "$elapsed" -ge "$SCALE_WAIT_TIMEOUT_SECONDS" ]; then
      die "Timeout esperando capacidad=$expected; Azure reporta $current."
    fi
    sleep "$SCALE_POLL_SECONDS"
  done
}

scale_to() {
  local target="$1"
  log_scale_event "Solicitando capacidad=$target en el plan $(get_plan_name)."
  az appservice plan update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$(get_plan_name)" \
    --number-of-workers "$target" \
    --only-show-errors >/dev/null
  wait_for_capacity "$target"
}

capture_state() {
  local label="$1"
  jq -n \
    --arg label "$label" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg webApp "$(get_webapp_name)" \
    --arg plan "$(get_plan_name)" \
    --arg capacity "$(get_current_instances)" \
    '{label:$label,timestamp:$timestamp,webApp:$webApp,plan:$plan,capacity:($capacity|tonumber)}' \
    >> "$EVIDENCE_DIR/capacity-events.jsonl"
}

restore_capacity() {
  local target="${ORIGINAL_INSTANCES:-$TARGET_INSTANCES}"
  if [ -z "$ORIGINAL_INSTANCES" ]; then
    return 0
  fi

  log_info "Restaurando capacidad original ($target worker)..."
  if scale_to "$target"; then
    CAPACITY_RESTORED=true
    capture_state "RESTORED"
  else
    CAPACITY_RESTORED=false
    log_error "No se pudo restaurar la capacidad original."
    return 1
  fi
}

write_failure_summary() {
  local rc="$1"
  [ -f "$SUMMARY_REPORT" ] && return 0
  jq -n \
    --arg runId "$RUN_ID" \
    --arg testId "TEST-S1-024" \
    --arg status "FAILED" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson exitCode "$rc" \
    --argjson capacityRestored "$CAPACITY_RESTORED" \
    '{runId:$runId,testId:$testId,status:$status,timestamp:$timestamp,exitCode:$exitCode,capacityRestored:$capacityRestored}' \
    > "$SUMMARY_REPORT"
}

on_exit() {
  local rc=$?
  trap - EXIT

  if [ -n "$ORIGINAL_INSTANCES" ] && [ "$CAPACITY_RESTORED" != true ]; then
    restore_capacity || rc=1
  fi

  if [ "$SYNTHETIC_CLEANUP_DONE" != true ] && [ -f "$EVIDENCE_DIR/accepted-transactions.csv" ]; then
    cleanup_synthetic_blobs || rc=1
  fi

  if [ "$rc" -ne 0 ]; then
    write_failure_summary "$rc"
  fi

  exit "$rc"
}

cleanup_synthetic_blobs() {
  local accepted_file="$EVIDENCE_DIR/accepted-transactions.csv"
  local cleanup_log="$EVIDENCE_DIR/blob-cleanup.log"
  : > "$cleanup_log"

  [ -f "$accepted_file" ] || die "No existe el detalle de transacciones aceptadas para limpiar."

  local blob_name verified failures=0
  while IFS=',' read -r _ _ _ _ blob_name verified _; do
    [ "$blob_name" = "blobName" ] && continue
    [ -n "$blob_name" ] || continue

    if az storage blob delete \
      --account-name "$CENTINELA_STORAGE_ACCOUNT" \
      --container-name "$CENTINELA_RAW_TRANSACTIONS_CONTAINER" \
      --name "$blob_name" \
      --auth-mode login \
      --only-show-errors >/dev/null; then
      printf 'DELETED %s\n' "$blob_name" >> "$cleanup_log"
    else
      printf 'FAILED %s\n' "$blob_name" >> "$cleanup_log"
      failures=$((failures + 1))
    fi
  done < "$accepted_file"

  [ "$failures" -eq 0 ] || die "No se pudieron eliminar $failures Blob(s) sinteticos."
  SYNTHETIC_CLEANUP_DONE=true
}

main() {
  require_cmd az
  require_cmd jq
  require_cmd curl
  require_cmd sha1sum

  load_parameters
  validate_parameters

  : "${CENTINELA_SERVICE_TOKEN:?Define CENTINELA_SERVICE_TOKEN con un token SERVICE valido}"
  CENTINELA_STORAGE_ACCOUNT="${CENTINELA_STORAGE_ACCOUNT:-$(get_storage_account_name)}"
  CENTINELA_RAW_TRANSACTIONS_CONTAINER="${CENTINELA_RAW_TRANSACTIONS_CONTAINER:-raw-transactions-production}"
  CENTINELA_API_BASE_URL="${CENTINELA_API_BASE_URL:-https://$(get_webapp_name).azurewebsites.net}"
  export CENTINELA_STORAGE_ACCOUNT CENTINELA_RAW_TRANSACTIONS_CONTAINER CENTINELA_API_BASE_URL

  az account show >/dev/null 2>&1 || die "No hay sesion Azure activa. Ejecuta az login."
  local active_sub
  active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  mkdir -p "$EVIDENCE_DIR"
  : > "$SCALE_EVENT_LOG"
  trap on_exit EXIT

  ORIGINAL_INSTANCES="$(get_current_instances)"
  [ "$ORIGINAL_INSTANCES" = "$TARGET_INSTANCES" ] \
    || die "La prueba debe iniciar con una instancia; capacidad actual=$ORIGINAL_INSTANCES."
  capture_state "INITIAL"

  scale_to "$SCALE_UP_INSTANCES"
  capture_state "SCALED_TO_TWO"

  "$SCRIPT_DIR/tests/send-transaction-load.sh" \
    --duration "$TEST_DURATION_SECONDS" \
    --interval "$LOAD_INTERVAL" \
    --max-random-delay "$RANDOM_DELAY_MAX" \
    --output "$LOAD_LOG" \
    --load-log "$LOAD_CSV" > "$EVIDENCE_DIR/load-script-output.txt" 2>&1 &
  local load_pid=$!

  sleep 10
  capture_state "BEFORE_INSTANCE_REMOVAL"
  scale_to "$TARGET_INSTANCES"
  capture_state "AFTER_INSTANCE_REMOVAL"

  local load_exit=0
  if wait "$load_pid"; then
    load_exit=0
  else
    load_exit=$?
  fi
  [ "$load_exit" -eq 0 ] || die "El generador de carga fallo con codigo $load_exit."

  local reconciliation_exit=0
  if "$SCRIPT_DIR/tests/reconcile-accepted-transactions.sh" \
    --load-log "$LOAD_CSV" \
    --output "$RECONCILIATION_REPORT" \
    --storage-account "$CENTINELA_STORAGE_ACCOUNT" \
    --container "$CENTINELA_RAW_TRANSACTIONS_CONTAINER" \
    > "$EVIDENCE_DIR/reconciliation.log" 2>&1; then
    reconciliation_exit=0
  else
    reconciliation_exit=$?
  fi

  local total accepted failed reconciled other
  total="$(jq -r '.metrics.totalRequests' "$RECONCILIATION_REPORT")"
  accepted="$(jq -r '.metrics.acceptedRequests' "$RECONCILIATION_REPORT")"
  failed="$(jq -r '.metrics.failedRequests' "$RECONCILIATION_REPORT")"
  other="$(jq -r '.metrics.otherHttpResponses' "$RECONCILIATION_REPORT")"
  reconciled="$(jq -r '.metrics.reconciledRequests' "$RECONCILIATION_REPORT")"

  local api_continued=false all_202_have_blob=false passed=false
  [ "$total" -gt 0 ] && [ "$accepted" -gt 0 ] && [ "$failed" -lt "$total" ] && api_continued=true
  [ "$accepted" -eq "$reconciled" ] && [ "$reconciliation_exit" -eq 0 ] && all_202_have_blob=true

  restore_capacity
  [ "$(get_current_instances)" = "$TARGET_INSTANCES" ] || die "La capacidad final no quedo en una instancia."

  cleanup_synthetic_blobs

  if [ "$api_continued" = true ] && [ "$all_202_have_blob" = true ] && [ "$CAPACITY_RESTORED" = true ]; then
    passed=true
  fi

  jq -n \
    --arg runId "$RUN_ID" \
    --arg testId "TEST-S1-024" \
    --arg status "$([ "$passed" = true ] && echo PASSED || echo FAILED)" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg commit "$(git rev-parse HEAD 2>/dev/null || echo N/A)" \
    --argjson totalRequests "$total" \
    --argjson acceptedRequests "$accepted" \
    --argjson failedRequests "$failed" \
    --argjson otherHttpResponses "$other" \
    --argjson reconciledRequests "$reconciled" \
    --argjson apiContinued "$api_continued" \
    --argjson all202HaveBlob "$all_202_have_blob" \
    --argjson capacityRestored "$CAPACITY_RESTORED" \
    '{runId:$runId,testId:$testId,status:$status,timestamp:$timestamp,commit:$commit,results:{totalRequests:$totalRequests,acceptedRequests:$acceptedRequests,failedRequests:$failedRequests,otherHttpResponses:$otherHttpResponses,reconciledRequests:$reconciledRequests},acceptanceCriteria:{apiContinuedResponding:$apiContinued,all202HaveBlob:$all202HaveBlob,capacityRestored:$capacityRestored}}' \
    > "$SUMMARY_REPORT"

  [ "$passed" = true ] || die "TEST-S1-024 no cumplio todos los criterios. Revisa $SUMMARY_REPORT."
  TEST_FINISHED=true
  log_info "TEST-S1-024 PASSED. Evidencia: $EVIDENCE_DIR"
}

main "$@"
