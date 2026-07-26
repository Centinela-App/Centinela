#!/usr/bin/env bash
# Validacion local de ISS-S2-013. No afirma resultados de Azure: comprueba
# estructura, restauracion y las pruebas unitarias que sostienen los scripts E2E.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATIC_ONLY=0
[ "${1:-}" = "--static-only" ] && STATIC_ONLY=1

PASS=0
FAIL=0

pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
check_file() { [ -f "$REPO_ROOT/$1" ] && pass "Existe $1." || fail "Falta $1."; }
check_grep() {
  local pattern="$1" file="$2" description="$3"
  grep -Eq "$pattern" "$REPO_ROOT/$file" && pass "$description" || fail "$description"
}

DEC="scripts/tests/test-decoupling.sh"
THR="scripts/tests/test-threshold-hot-reload.sh"

check_file "$DEC"
check_file "$THR"
check_file "docs/evidence/iss-s2-013/.gitkeep"

if bash -n "$REPO_ROOT/$DEC" "$REPO_ROOT/$THR"; then
  pass "Los scripts de ISS-S2-013 tienen sintaxis Bash valida."
else
  fail "Los scripts de ISS-S2-013 tienen errores de sintaxis Bash."
fi

check_grep 'apiBeforeScoring' "$DEC" \
  "La evidencia compara respuesta API contra fin del scoring."
check_grep 'set_consumer_auto_start false' "$DEC" \
  "La prueba detiene el consumidor antes de generar backlog."
check_grep 'wait_for_target_queue_count.*CASE_COUNT' "$DEC" \
  "La prueba exige N mensajes en Queue con el consumidor detenido."
check_grep 'wait_for_exact_cases.*CASE_COUNT' "$DEC" \
  "La reanudacion exige exactamente N casos sin duplicados."
check_grep 'COUNT\(DISTINCT transaction_id\)' "$DEC" \
  "El conteo detecta duplicados por transactionId."
check_grep 'set_function_threshold 100' "$DEC" \
  "La prueba usa un umbral alto que no publica el score controlado."
check_grep 'set_function_threshold 50' "$DEC" \
  "La prueba usa un umbral bajo que publica el mismo score controlado."
check_grep 'assert_no_target_queue_messages' "$DEC" \
  "El escenario de umbral alto demuestra ausencia de mensaje."
check_grep 'deployment-source-before|deploymentSourceHashBefore' "$DEC" \
  "La prueba registra la fuente antes del cambio de umbral."
check_grep 'deployment-source-after|deploymentSourceHashAfter' "$DEC" \
  "La prueba confirma que no hubo redespliegue."
check_grep 'restore_consumer' "$DEC" \
  "El trap restaura la configuracion del consumidor."
check_grep 'restore_threshold' "$DEC" \
  "El trap restaura el umbral original."
check_grep 'trap iss13_cleanup EXIT' "$DEC" \
  "La restauracion se ejecuta incluso ante error."
check_grep 'run_threshold_hot_reload' "$THR" \
  "El segundo comando ejecuta la prueba de umbral en caliente."

if [ "$STATIC_ONLY" -eq 0 ]; then
  if (cd "$REPO_ROOT" && mvn -q -Dtest=OpenCaseServiceTest,FlaggedCaseQueueListenerIT test); then
    pass "Pruebas locales de idempotencia, commit y popReceipt aprobadas."
  else
    fail "Fallaron las pruebas locales del consumidor de casos."
  fi

  if (cd "$REPO_ROOT/scoring-function" && \
      mvn -q -Dtest=ScorePersistAndPublishTest,ScoreTransactionServiceTest test); then
    pass "Pruebas locales de persistencia, umbral y publicacion aprobadas."
  else
    fail "Fallaron las pruebas locales del scoring y umbral."
  fi

  if bash "$REPO_ROOT/scripts/tests/scan-repository.sh"; then
    pass "El escaneo de secretos permanece en verde."
  else
    fail "El escaneo de secretos fallo."
  fi
fi

printf '\nResultado: %d PASS / %d FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
