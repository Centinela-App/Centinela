#!/usr/bin/env bash
# validate-week1-scope.sh — Verifica que no se implemento alcance de Semana 2
# TEST-S1-028: Control de alcance
#
# Uso: ./scripts/tests/validate-week1-scope.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

FAILED_CHECKS=0

# Patterns que indican implementacion de Semana 2 (no referencias en docs)
SCOPE_VIOLATIONS=()

# Check: No hay implementacion de base de datos
check_no_database() {
  log_info "Verificando ausencia de base de datos..."
  
  # Buscar en codigo fuente
  local db_patterns=(
    "jdbc:JdbcTemplate"
    "spring-boot-starter-data-jpa"
    "EntityManager"
    "@Table\("
    "@Column\("
    "CREATE TABLE"
  )
  
  for pattern in "${db_patterns[@]}"; do
    if grep -rE "$pattern" src/ 2>/dev/null | grep -v "test" | grep -v "//.*$pattern" >/dev/null 2>&1; then
      log_error "  [FAIL] Patron de BD encontrado: $pattern"
      FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
  done
  log_info "  [OK] Sin implementacion de base de datos"
}

# Check: No hay implementacion de Queue en flujo principal
check_no_queue_flow() {
  log_info "Verificando Queue desconectada del flujo..."
  
  # Buscar publishers de queue en codigo principal
  if grep -rE "QueueClient|ServiceBusSender|queue\.send" src/main/ 2>/dev/null >/dev/null 2>&1; then
    log_error "  [FAIL] Queue conectada al flujo principal"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  else
    log_info "  [OK] Queue desconectada del flujo"
  fi
}

# Check: No hay implementacion de scoring
check_no_scoring() {
  log_info "Verificando ausencia de scoring..."
  
  local scoring_patterns=(
    "ScoringService"
    "RiskScore"
    "FraudDetection"
    "RuleEngine"
  )
  
  for pattern in "${scoring_patterns[@]}"; do
    if grep -r "$pattern" src/ 2>/dev/null | grep -v test | grep -v "//.*$pattern" >/dev/null 2>&1; then
      log_error "  [FAIL] Implementacion de scoring: $pattern"
      FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
  done
  log_info "  [OK] Sin implementacion de scoring"
}

# Check: No hay consumer de eventos
check_no_event_consumer() {
  log_info "Verificando ausencia de consumer de eventos..."
  
  if grep -rE "@EventListener|@ServiceBusListener|@QueueTrigger" src/ 2>/dev/null | grep -v test >/dev/null 2>&1; then
    log_error "  [FAIL] Consumer de eventos implementado"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  else
    log_info "  [OK] Sin consumer de eventos"
  fi
}

# Check: No hay multi-region en scripts
check_no_multiregion() {
  log_info "Verificando ausencia de multi-region..."
  
  # Solo revisar que no haya scripts de failover
  if ls scripts/*failover* scripts/*multiregion* 2>/dev/null | grep -v "week2" >/dev/null 2>&1; then
    log_error "  [FAIL] Scripts de multi-region encontrados"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  else
    log_info "  [OK] Sin scripts de multi-region"
  fi
}

# Check: No hay multi-slot / blue-green avanzado (el slot 'staging' de ISS-S1-004
# SÍ es alcance de Semana 1, por eso no se prohíbe un único slot staging).
check_no_advanced_slots() {
  log_info "Verificando ausencia de slots avanzados (blue-green / multi-slot)..."

  # Solo cuenta implementacion real: el flag de swap por fases (blue-green avanzado)
  # o un segundo slot de produccion. Se ignoran comentarios (que solo mencionan que
  # NO se hace) y los propios scripts de escaneo.
  if grep -rEi "swap-with-preview|slot(s)?-(prod|production)-[0-9]" scripts/ 2>/dev/null \
       --exclude='validate-week1-scope.sh' \
       | grep -vE ":[0-9]+:[[:space:]]*#" | grep -v "week2\|Semana 2" >/dev/null 2>&1; then
    log_error "  [FAIL] Estrategia de slots avanzada (fuera de alcance Semana 1)"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  else
    log_info "  [OK] Solo el slot staging previsto en Semana 1"
  fi
}

# Check: Storage sigue privado
check_storage_private() {
  log_info "Verificando que Storage sea privado..."

  # Verificar que no hay Account Key en scripts. Se excluyen los propios scripts
  # de escaneo (contienen el patron como cadena de busqueda, no como secreto).
  if grep -rE "AccountKey=|DefaultEndpointsProtocol.*AccountKey" scripts/ 2>/dev/null \
       --exclude='validate-week1-scope.sh' --exclude='scan-repository.sh' \
       | grep -v "\.example\|#.*AccountKey" >/dev/null 2>&1; then
    log_error "  [FAIL] Account Key encontrada en scripts"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  else
    log_info "  [OK] Sin Account Keys en scripts"
  fi
}

# Main
main() {
  log_info "========================================"
  log_info "  Validacion de Alcance Semana 1 (TEST-S1-028)"
  log_info "========================================"
  
  check_no_database
  check_no_queue_flow
  check_no_scoring
  check_no_event_consumer
  check_no_multiregion
  check_no_advanced_slots
  check_storage_private
  
  log_info "========================================"
  
  if [ $FAILED_CHECKS -eq 0 ]; then
    log_info "VALIDACION PASADA: Alcance de Semana 1 respetado"
    exit 0
  else
    log_error "VALIDACION FALLIDA: $FAILED_CHECKS violaciones de alcance"
    exit 1
  fi
}

main
