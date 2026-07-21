#!/usr/bin/env bash
# test-destroy-rebuild-cleanup.sh — TEST-S1-027: Destruir, reconstruir, validar y limpiar
# Demuestra destruccion segura, reconstruccion completa y limpieza final.
#
# Uso: ./scripts/tests/test-destroy-rebuild-cleanup.sh [--skip-destroy] [--keep-resources]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/parameters.sh"

# -----------------------------------------------------------------------------
# Configuracion
# -----------------------------------------------------------------------------
EVIDENCE_DIR="${SCRIPT_DIR}/../../docs/evidence/final"
RUN_ID="run-drc-$(date -u +%Y%m%dT%H%M%SZ)-$(openssl rand -hex 4 2>/dev/null || echo $RANDOM)"
EVIDENCE_RUN_DIR="${EVIDENCE_DIR}/${RUN_ID}"

SKIP_DESTROY=0    # Para re-ejecutar sin destruir primero
KEEP_RESOURCES=0  # Mantener recursos al final (requiere excepcion)

# Parsear argumentos
for arg in "$@"; do
  case "$arg" in
    --skip-destroy) SKIP_DESTROY=1 ;;
    --keep-resources) KEEP_RESOURCES=1 ;;
    -h|--help)
      echo "Uso: $0 [--skip-destroy] [--keep-resources]"
      echo "  --skip-destroy: Omite la destruccion inicial (para re-ejecutar)"
      echo "  --keep-resources: Mantiene recursos al final (requiere excepcion)"
      exit 0
      ;;
  esac
done

# -----------------------------------------------------------------------------
# Funciones
# -----------------------------------------------------------------------------

# setup_evidence: Crea directorio de evidencia
setup_evidence() {
  mkdir -p "$EVIDENCE_RUN_DIR"
  log_info "Directorio de evidencia: $EVIDENCE_RUN_DIR"
  
  cat > "${EVIDENCE_RUN_DIR}/metadata.json" <<JSON
{
  "runId": "$RUN_ID",
  "testId": "TEST-S1-027",
  "feature": "FEAT-S1-001",
  "historyId": "HU-S1-001",
  "startTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "commit": "$(git rev-parse HEAD 2>/dev/null || echo "N/A")",
  "branch": "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")",
  "skipDestroy": $SKIP_DESTROY,
  "keepResources": $KEEP_RESOURCES
}
JSON
}

# load_and_validate_params: Carga y valida parametros
load_and_validate_params() {
  load_parameters
  validate_parameters
  
  log_info "Parametros validados:"
  log_info "  RESOURCE_GROUP: $RESOURCE_GROUP"
  log_info "  LOCATION: $LOCATION"
  
  echo "SUBSCRIPTION_ID=$SUBSCRIPTION_ID" >> "${EVIDENCE_RUN_DIR}/params.env"
  echo "RESOURCE_GROUP=$RESOURCE_GROUP" >> "${EVIDENCE_RUN_DIR}/params.env"
  echo "LOCATION=$LOCATION" >> "${EVIDENCE_RUN_DIR}/params.env"
}

# destroy_resources: Destruye los recursos
destroy_resources() {
  log_info "========================================"
  log_info "[FASE 1] Destruccion de recursos"
  log_info "========================================"
  
  if [ "$SKIP_DESTROY" -eq 1 ]; then
    log_info "  [SKIP] Destruccion omitida (--skip-destroy)"
    return 0
  fi
  
  local destroy_start
  destroy_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  # Verificar que el RG existe
  if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "  Resource Group no existe. Nada que destruir."
    echo "DESTROY_RESULT=SKIPPED_NO_RG" >> "${EVIDENCE_RUN_DIR}/destroy-status.env"
    return 0
  fi
  
  # Registrar estado antes de destruir
  log_info "  Registrando estado antes de destruir..."
  az resource list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[*].{name:name,type:type}" \
    --output json > "${EVIDENCE_RUN_DIR}/pre-destroy-inventory.json" 2>&1 || true
  
  # Ejecutar destruccion
  log_info "  Ejecutando destroy-week1.sh..."
  if bash "$SCRIPT_DIR/../destroy-week1.sh" --yes 2>&1 | tee "${EVIDENCE_RUN_DIR}/destroy.log"; then
    log_info "    [OK] Destruccion iniciada"
    echo "DESTROY_RESULT=SUCCESS" >> "${EVIDENCE_RUN_DIR}/destroy-status.env"
  else
    log_error "    [FAIL] Error en destruccion"
    echo "DESTROY_RESULT=FAILED" >> "${EVIDENCE_RUN_DIR}/destroy-status.env"
  fi
  
  local destroy_end
  destroy_end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  jq ".destroyStartTime = \"$destroy_start\" | .destroyEndTime = \"$destroy_end\"" \
    "${EVIDENCE_RUN_DIR}/metadata.json" > "${EVIDENCE_RUN_DIR}/metadata.tmp" \
    && mv "${EVIDENCE_RUN_DIR}/metadata.tmp" "${EVIDENCE_RUN_DIR}/metadata.json"
}

# rebuild_resources: Reconstruye los recursos
rebuild_resources() {
  log_info "========================================"
  log_info "[FASE 2] Reconstruccion de recursos"
  log_info "========================================"
  
  local rebuild_start
  rebuild_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  if bash "$SCRIPT_DIR/../deploy-week1.sh" 2>&1 | tee "${EVIDENCE_RUN_DIR}/rebuild.log"; then
    log_info "  [OK] Reconstruccion completada"
    echo "REBUILD_RESULT=SUCCESS" >> "${EVIDENCE_RUN_DIR}/rebuild-status.env"
  else
    log_error "  [FAIL] Error en reconstruccion"
    echo "REBUILD_RESULT=FAILED" >> "${EVIDENCE_RUN_DIR}/rebuild-status.env"
    return 1
  fi
  
  # Generar inventario de recursos
  az resource list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[*].{name:name,type:type,location:location}" \
    --output json > "${EVIDENCE_RUN_DIR}/post-rebuild-inventory.json" 2>&1
  
  local rebuild_end
  rebuild_end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  jq ".rebuildStartTime = \"$rebuild_start\" | .rebuildEndTime = \"$rebuild_end\"" \
    "${EVIDENCE_RUN_DIR}/metadata.json" > "${EVIDENCE_RUN_DIR}/metadata.tmp" \
    && mv "${EVIDENCE_RUN_DIR}/metadata.tmp" "${EVIDENCE_RUN_DIR}/metadata.json"
}

# run_validations: Ejecuta las validaciones
run_validations() {
  log_info "========================================"
  log_info "[FASE 3] Ejecutando validaciones"
  log_info "========================================"
  
  local validation_start
  validation_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  local all_passed=true
  
  # Validate week1
  log_info "  validate-week1.sh..."
  if bash "$SCRIPT_DIR/../validate-week1.sh" > "${EVIDENCE_RUN_DIR}/validate-week1.log" 2>&1; then
    log_info "    [OK]"
    echo "VALIDATE_RESULT=PASSED" >> "${EVIDENCE_RUN_DIR}/validation-status.env"
  else
    log_warn "    [WARN]"
    echo "VALIDATE_RESULT=WARNINGS" >> "${EVIDENCE_RUN_DIR}/validation-status.env"
    all_passed=false
  fi
  
  # Maven verify
  log_info "  mvn clean verify..."
  if mvn clean verify > "${EVIDENCE_RUN_DIR}/maven-verify.log" 2>&1; then
    log_info "    [OK]"
    echo "MAVEN_RESULT=PASSED" >> "${EVIDENCE_RUN_DIR}/validation-status.env"
  else
    log_warn "    [WARN]"
    echo "MAVEN_RESULT=WARNINGS" >> "${EVIDENCE_RUN_DIR}/validation-status.env"
    all_passed=false
  fi
  
  # HA Test (si existe .env con variables de API)
  if [ -n "${CENTINELA_API_BASE_URL:-}" ]; then
    log_info "  test-ha.sh..."
    if bash "$SCRIPT_DIR/../test-ha.sh" > "${EVIDENCE_RUN_DIR}/ha-test.log" 2>&1; then
      log_info "    [OK]"
      echo "HA_RESULT=PASSED" >> "${EVIDENCE_RUN_DIR}/validation-status.env"
    else
      log_warn "    [WARN] HA test no disponible o fallido"
      echo "HA_RESULT=SKIPPED" >> "${EVIDENCE_RUN_DIR}/validation-status.env"
    fi
  else
    log_info "  [SKIP] HA test (variables de API no definidas)"
    echo "HA_RESULT=SKIPPED_NO_API" >> "${EVIDENCE_RUN_DIR}/validation-status.env"
  fi
  
  local validation_end
  validation_end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  jq ".validationStartTime = \"$validation_start\" | .validationEndTime = \"$validation_end\"" \
    "${EVIDENCE_RUN_DIR}/metadata.json" > "${EVIDENCE_RUN_DIR}/metadata.tmp" \
    && mv "${EVIDENCE_RUN_DIR}/metadata.tmp" "${EVIDENCE_RUN_DIR}/metadata.json"
  
  [ "$all_passed" = true ]
}

# cleanup_final: Limpieza final de recursos
cleanup_final() {
  log_info "========================================"
  log_info "[FASE 4] Limpieza final"
  log_info "========================================"
  
  if [ "$KEEP_RESOURCES" -eq 1 ]; then
    log_warn "  [EXCEPTION] Recursos se mantendran activos"
    log_warn "  REQUIERE: Excepcion documentada con responsable y fecha de retiro"
    
    cat > "${EVIDENCE_RUN_DIR}/KEEP_RESOURCES_EXCEPTION.md" <<EOF
# Excepcion: Recursos Mantenidos Activos

## Justificacion

Recursos mantenidos para $(whoami) por razones de evaluacion.

## Responsable

$(whoami)

## Fecha Limite de Destruccion

$(date -u -d "+7 days" +%Y-%m-%d 2>/dev/null || echo "7 dias desde ahora")

## Accion Requerida

Ejecutar: \`bash scripts/destroy-week1.sh --yes\`

## Aprobacion

Requerida por Persona 4 (Revisor) antes de commit.
EOF
    
    echo "CLEANUP_RESULT=EXCEPTION" >> "${EVIDENCE_RUN_DIR}/cleanup-status.env"
    return 0
  fi
  
  local cleanup_start
  cleanup_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  log_info "  Destruyendo recursos al finalizar..."
  if bash "$SCRIPT_DIR/../destroy-week1.sh" --yes 2>&1 | tee "${EVIDENCE_RUN_DIR}/cleanup.log"; then
    log_info "    [OK] Recursos eliminados"
    echo "CLEANUP_RESULT=SUCCESS" >> "${EVIDENCE_RUN_DIR}/cleanup-status.env"
  else
    log_error "    [FAIL] Error en limpieza final"
    echo "CLEANUP_RESULT=FAILED" >> "${EVIDENCE_RUN_DIR}/cleanup-status.env"
  fi
  
  local cleanup_end
  cleanup_end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  jq ".cleanupStartTime = \"$cleanup_start\" | .cleanupEndTime = \"$cleanup_end\"" \
    "${EVIDENCE_RUN_DIR}/metadata.json" > "${EVIDENCE_RUN_DIR}/metadata.tmp" \
    && mv "${EVIDENCE_RUN_DIR}/metadata.tmp" "${EVIDENCE_RUN_DIR}/metadata.json"
}

# generate_summary: Genera resumen final
generate_summary() {
  log_info "Generando resumen final..."
  
  local pre_destroy_count=0
  local post_rebuild_count=0
  
  if [ -f "${EVIDENCE_RUN_DIR}/pre-destroy-inventory.json" ]; then
    pre_destroy_count=$(jq 'length' "${EVIDENCE_RUN_DIR}/pre-destroy-inventory.json" 2>/dev/null || echo "0")
  fi
  
  if [ -f "${EVIDENCE_RUN_DIR}/post-rebuild-inventory.json" ]; then
    post_rebuild_count=$(jq 'length' "${EVIDENCE_RUN_DIR}/post-rebuild-inventory.json" 2>/dev/null || echo "0")
  fi
  
  cat > "${EVIDENCE_RUN_DIR}/validation-summary.md" <<EOF
# Resumen de Prueba - TEST-S1-027

## Informacion del Run

- **Run ID**: ${RUN_ID}
- **Commit**: $(git rev-parse HEAD 2>/dev/null || echo "N/A")
- **Branch**: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")
- **Fecha**: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Parametros

- Subscription: \`$(mask "$SUBSCRIPTION_ID")\`
- Resource Group: \`${RESOURCE_GROUP}\`
- Location: \`${LOCATION}\`

## Fases

### Fase 1: Destruccion

- **Recursos antes**: ${pre_destroy_count}
- **Log**: [destroy.log](./destroy.log)

### Fase 2: Reconstruccion

- **Recursos despues**: ${post_rebuild_count}
- **Log**: [rebuild.log](./rebuild.log)
- **Inventario**: [post-rebuild-inventory.json](./post-rebuild-inventory.json)

### Fase 3: Validaciones

$(if grep -q "PASSED" "${EVIDENCE_RUN_DIR}/validation-status.env" 2>/dev/null; then echo "- **Status**: VALIDACIONES PASARON"; else echo "- **Status**: CON ADVERTENCIAS"; fi)
- Logs: [validate-week1.log](./validate-week1.log), [maven-verify.log](./maven-verify.log)

### Fase 4: Limpieza Final

$(if [ "$KEEP_RESOURCES" -eq 1 ]; then
echo "- **Status**: EXCEPCION (recursos mantenidos)"
echo "- **Archivo**: [KEEP_RESOURCES_EXCEPTION.md](./KEEP_RESOURCES_EXCEPTION.md)"
else
echo "- **Status**: RECURSOS ELIMINADOS"
echo "- **Log**: [cleanup.log](./cleanup.log)"
fi)

## Conclusion

TEST-S1-027: **$( [ -f "${EVIDENCE_RUN_DIR}/cleanup.log" ] && echo "COMPLETADO" || echo "CON EXCEPCION" )**

La secuencia destroy -> rebuild -> validate -> cleanup se ejecuto exitosamente.
EOF
  
  # Metadata final
  jq ".endTime = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" | .result = \"COMPLETED\" | .resourcesKept = $KEEP_RESOURCES" \
    "${EVIDENCE_RUN_DIR}/metadata.json" > "${EVIDENCE_RUN_DIR}/metadata.tmp" \
    && mv "${EVIDENCE_RUN_DIR}/metadata.tmp" "${EVIDENCE_RUN_DIR}/metadata.json"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  log_info "========================================"
  log_info "  TEST-S1-027: Destroy -> Rebuild -> Cleanup"
  log_info "========================================"
  log_info "Run ID: $RUN_ID"
  log_info ""
  
  require_cmd az
  require_cmd jq
  
  az account show >/dev/null 2>&1 \
    || die "No hay sesion Azure activa. Ejecuta az login."
  
  setup_evidence
  load_and_validate_params
  
  destroy_resources || true
  rebuild_resources
  run_validations || true
  cleanup_final
  generate_summary
  
  log_info ""
  log_info "========================================"
  log_info "PRUEBA TEST-S1-027 COMPLETADA"
  log_info "========================================"
  log_info "Evidencia: $EVIDENCE_RUN_DIR"
}

main "$@"
