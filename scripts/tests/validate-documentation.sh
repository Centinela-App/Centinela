#!/usr/bin/env bash
# validate-documentation.sh — Valida entregables documentales y trazabilidad
# TEST-S1-025: Obligatoria para cerrar
#
# Uso: ./scripts/tests/validate-documentation.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

DOCS_DIR="${SCRIPT_DIR}/../../docs"
FAILED_CHECKS=0

# Check: Arquitectura existe
check_architecture() {
  log_info "Verificando documentacion de arquitectura..."
  local arch_file="${DOCS_DIR}/architecture/centinela-week1.md"
  if [ -f "$arch_file" ]; then
    log_info "  [OK] Arquitectura encontrada: $arch_file"
  else
    log_error "  [FAIL] Falta archivo de arquitectura"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
}

# Check: ADRs existen
check_adrs() {
  log_info "Verificando ADRs..."
  local adr_dir="${DOCS_DIR}/adr"
  local required_adrs=(
    "ADR-001-hexagonal.md"
    "ADR-002-managed-identity.md"
    "ADR-003-private-storage.md"
    "ADR-004-environment-separation.md"
  )
  
  for adr in "${required_adrs[@]}"; do
    if [ -f "${adr_dir}/${adr}" ]; then
      log_info "  [OK] $adr"
    else
      log_error "  [FAIL] Falta $adr"
      FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
  done
}

# Check: Indice de evidencias
check_evidence_index() {
  log_info "Verificando indice de evidencias..."
  local index_file="${DOCS_DIR}/evidence/INDEX.md"
  if [ -f "$index_file" ]; then
    log_info "  [OK] Indice de evidencias encontrado"
  else
    log_error "  [FAIL] Falta indice de evidencias"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
}

# Check: Decisiones abiertas Semana 2
check_open_decisions() {
  log_info "Verificando documento de decisiones abiertas..."
  local open_dec="${DOCS_DIR}/week2/OPEN_DECISIONS.md"
  if [ -f "$open_dec" ]; then
    log_info "  [OK] Decisiones abiertas documentadas"
  else
    log_error "  [FAIL] Falta documento de decisiones abiertas"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
}

# Check: Matriz de trazabilidad
check_traceability_matrix() {
  log_info "Verificando matriz de trazabilidad..."
  local matrix_file="${DOCS_DIR}/5_Issues_y_Trazabilidad/2_Matriz_Trazabilidad.md"
  if [ -f "$matrix_file" ]; then
    log_info "  [OK] Matriz de trazabilidad encontrada"
  else
    log_error "  [FAIL] Falta matriz de trazabilidad"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
}

# Check: README actualizado
check_readme() {
  log_info "Verificando README principal..."
  local readme="${DOCS_DIR}/../README.md"
  if [ -f "$readme" ]; then
    # Verificar que tenga secciones clave
    local has_prereqs=false
    local has_params=false
    local has_deploy=false
    
    if grep -qE "Prerrequisitos|Prerequisites|Requisitos previos" "$readme" 2>/dev/null; then
      has_prereqs=true
    fi
    if grep -qE "Par[aá]metros|Parameters|Variables de entorno" "$readme" 2>/dev/null; then
      has_params=true
    fi
    if grep -qE "Despliegue|Deployment|Gu[ií]a de ejecuci" "$readme" 2>/dev/null; then
      has_deploy=true
    fi
    
    if [ "$has_prereqs" = true ] && [ "$has_params" = true ] && [ "$has_deploy" = true ]; then
      log_info "  [OK] README tiene secciones requeridas"
    else
      log_error "  [WARN] README falta algunas secciones"
    fi
  else
    log_error "  [FAIL] Falta README"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
}

# Check: Documentos no tienen soluciones Semana 2
check_no_week2_solutions() {
  log_info "Verificando que no haya soluciones de Semana 2..."
  local forbidden_patterns=(
    "Azure SQL"
    "Cosmos DB"
    "Event Hub"
    "Application Insights"
    "Traffic Manager"
  )
  
  local found_solution=false
  for pattern in "${forbidden_patterns[@]}"; do
    if grep -r "$pattern" "$DOCS_DIR" 2>/dev/null | grep -v "OPEN_DECISIONS\|Semana 2\|ABIERTO" >/dev/null 2>&1; then
      log_warn "  [WARN] Posible solucion Semana 2 mencionada: $pattern"
      found_solution=true
    fi
  done
  
  if [ "$found_solution" = false ]; then
    log_info "  [OK] No se encontraron soluciones prematuretas"
  fi
}

# Main
main() {
  log_info "========================================"
  log_info "  Validacion de Documentacion (TEST-S1-025)"
  log_info "========================================"
  
  check_architecture
  check_adrs
  check_evidence_index
  check_open_decisions
  check_traceability_matrix
  check_readme
  check_no_week2_solutions
  
  log_info "========================================"
  
  if [ $FAILED_CHECKS -eq 0 ]; then
    log_info "VALIDACION PASADA: Toda la documentacion requerida existe"
    exit 0
  else
    log_error "VALIDACION FALLIDA: $FAILED_CHECKS checks fallidos"
    exit 1
  fi
}

main
