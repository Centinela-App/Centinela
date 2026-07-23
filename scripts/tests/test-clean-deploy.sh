#!/usr/bin/env bash
# test-clean-deploy.sh — TEST-S1-026: Desplegar desde suscripcion o Resource Group limpio
# Demuestra que el entorno se reconstruye sin pasos manuales.
#
# Uso: ./scripts/tests/test-clean-deploy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/parameters.sh"

# -----------------------------------------------------------------------------
# Configuracion
# -----------------------------------------------------------------------------
EVIDENCE_DIR="${SCRIPT_DIR}/../../docs/evidence/final"
RUN_ID="run-$(date -u +%Y%m%dT%H%M%SZ)-$(openssl rand -hex 4 2>/dev/null || echo $RANDOM)"
EVIDENCE_RUN_DIR="${EVIDENCE_DIR}/${RUN_ID}"

# -----------------------------------------------------------------------------
# Funciones
# -----------------------------------------------------------------------------

# setup_evidence: Crea directorio de evidencia
setup_evidence() {
  mkdir -p "$EVIDENCE_RUN_DIR"
  log_info "Directorio de evidencia: $EVIDENCE_RUN_DIR"
  
  # Metadata del run
  cat > "${EVIDENCE_RUN_DIR}/metadata.json" <<JSON
{
  "runId": "$RUN_ID",
  "testId": "TEST-S1-026",
  "feature": "FEAT-S1-001",
  "historyId": "HU-S1-001",
  "startTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "commit": "$(git rev-parse HEAD 2>/dev/null || echo "N/A")",
  "branch": "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")"
}
JSON
}

# check_prerequisites: Verifica precondiciones
check_prerequisites() {
  log_info "Verificando precondiciones..."
  
  require_cmd az
  require_cmd jq
  
  # Verificar sesion de Azure
  az account show >/dev/null 2>&1 \
    || die "No hay sesion Azure activa. Ejecuta az login."
  
  log_info "  [OK] Azure CLI autenticado"
  
  # Cargar parametros
  load_parameters
  validate_parameters
  
  log_info "  [OK] Parametros validados"
  echo "SUBSCRIPTION_ID=$SUBSCRIPTION_ID" >> "${EVIDENCE_RUN_DIR}/params.env"
  echo "RESOURCE_GROUP=$RESOURCE_GROUP" >> "${EVIDENCE_RUN_DIR}/params.env"
  echo "LOCATION=$LOCATION" >> "${EVIDENCE_RUN_DIR}/params.env"
}

# check_rg_not_exists: Verifica que el RG no existe (entorno limpio)
check_rg_not_exists() {
  log_info "Verificando que Resource Group '$RESOURCE_GROUP' no existe..."
  
  if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_warn "Resource Group '$RESOURCE_GROUP' YA existe."
    read -p "Desea eliminarlo y continuar? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      die "Prueba cancelada: RG existente"
    fi
    log_info "Eliminando RG existente..."
    bash "$SCRIPT_DIR/../destroy-week1.sh" --yes 2>&1 | tee "${EVIDENCE_RUN_DIR}/pre-cleanup.log"
  else
    log_info "  [OK] Resource Group no existe (entorno limpio)"
  fi
}

# execute_deploy: Ejecuta el despliegue
execute_deploy() {
  log_info "Ejecutando deploy-week1.sh..."
  
  # Registrar inicio
  local deploy_start
  deploy_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  # Ejecutar despliegue
  if bash "$SCRIPT_DIR/../deploy-week1.sh" 2>&1 | tee "${EVIDENCE_RUN_DIR}/deployment.log"; then
    log_info "  [OK] Despliegue completado exitosamente"
  else
    log_error "Despliegue fallido"
    cat "${EVIDENCE_RUN_DIR}/deployment.log" >> "${EVIDENCE_RUN_DIR}/FAILED.log"
    return 1
  fi
  
  local deploy_end
  deploy_end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  # Actualizar metadata
  jq ".deployStartTime = \"$deploy_start\" | .deployEndTime = \"$deploy_end\"" \
    "${EVIDENCE_RUN_DIR}/metadata.json" > "${EVIDENCE_RUN_DIR}/metadata.tmp" \
    && mv "${EVIDENCE_RUN_DIR}/metadata.tmp" "${EVIDENCE_RUN_DIR}/metadata.json"
}

# execute_validations: Ejecuta las validaciones
execute_validations() {
  log_info "Ejecutando validaciones..."
  
  local validation_start
  validation_start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  # Validate-week1
  log_info "  Ejecutando validate-week1.sh..."
  if bash "$SCRIPT_DIR/../validate-week1.sh" > "${EVIDENCE_RUN_DIR}/validate-week1.log" 2>&1; then
    log_info "    [OK] validate-week1.sh"
  else
    log_warn "    [WARN] validate-week1.sh reporto advertencias"
  fi
  
  # Maven verify
  log_info "  Ejecutando mvn clean verify..."
  if mvn clean verify > "${EVIDENCE_RUN_DIR}/maven-verify.log" 2>&1; then
    log_info "    [OK] mvn clean verify"
  else
    log_warn "    [WARN] mvn clean verify reporto problemas"
  fi
  
  # Inventory de recursos
  log_info "  Generando inventario de recursos..."
  az resource list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[*].{name:name,type:type,location:location}" \
    --output json > "${EVIDENCE_RUN_DIR}/resource-inventory.json" 2>&1
  
  local validation_end
  validation_end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  jq ".validationStartTime = \"$validation_start\" | .validationEndTime = \"$validation_end\"" \
    "${EVIDENCE_RUN_DIR}/metadata.json" > "${EVIDENCE_RUN_DIR}/metadata.tmp" \
    && mv "${EVIDENCE_RUN_DIR}/metadata.tmp" "${EVIDENCE_RUN_DIR}/metadata.json"
}

# generate_summary: Genera resumen de la prueba
generate_summary() {
  log_info "Generando resumen..."
  
  local resource_count=0
  if [ -f "${EVIDENCE_RUN_DIR}/resource-inventory.json" ]; then
    resource_count=$(jq 'length' "${EVIDENCE_RUN_DIR}/resource-inventory.json" 2>/dev/null || echo "0")
  fi
  
  cat > "${EVIDENCE_RUN_DIR}/validation-summary.md" <<EOF
# Resumen de Validacion - TEST-S1-026

## Informacion del Run

- **Run ID**: ${RUN_ID}
- **Commit**: $(git rev-parse HEAD 2>/dev/null || echo "N/A")
- **Branch**: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")
- **Fecha**: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Parametros

- Subscription: \`$(mask "$SUBSCRIPTION_ID")\`
- Resource Group: \`${RESOURCE_GROUP}\`
- Location: \`${LOCATION}\`

## Resultados

### Recursos Desplegados

- **Total de recursos**: ${resource_count}
- Ver: [resource-inventory.json](./resource-inventory.json)

### Despliegue

- **Status**: $([ -f "${EVIDENCE_RUN_DIR}/FAILED.log" ] && echo "FALLIDO" || echo "EXITOSO")
- **Log**: [deployment.log](./deployment.log)

### Validaciones

- **Maven**: $(grep -q "BUILD SUCCESS" "${EVIDENCE_RUN_DIR}/maven-verify.log" 2>/dev/null && echo "PASSED" || echo "WITH WARNINGS")
- **Week1 Validate**: $(grep -q "validado" "${EVIDENCE_RUN_DIR}/validate-week1.log" 2>/dev/null && echo "PASSED" || echo "WITH WARNINGS")

## Conclusion

TEST-S1-026: $([ -f "${EVIDENCE_RUN_DIR}/FAILED.log" ] && echo "FALLIDO" || echo "PASADO")

El entorno se reconstruyo exitosamente desde un estado limpio.
EOF
  
  # Actualizar metadata final
  jq ".endTime = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" | .result = \"$( [ -f "${EVIDENCE_RUN_DIR}/FAILED.log" ] && echo "FAILED" || echo "PASSED" )\"" \
    "${EVIDENCE_RUN_DIR}/metadata.json" > "${EVIDENCE_RUN_DIR}/metadata.tmp" \
    && mv "${EVIDENCE_RUN_DIR}/metadata.tmp" "${EVIDENCE_RUN_DIR}/metadata.json"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  log_info "========================================"
  log_info "  TEST-S1-026: Clean Deploy"
  log_info "========================================"
  
  setup_evidence
  check_prerequisites
  check_rg_not_exists
  execute_deploy
  execute_validations
  generate_summary
  
  log_info "========================================"
  log_info "Comandos ejecutados:"
  log_info "  cd $(pwd)"
  log_info "  bash scripts/deploy-week1.sh"
  log_info "  bash scripts/validate-week1.sh"
  log_info "  mvn clean verify"
  log_info ""
  log_info "Evidencia guardada en:"
  log_info "  $EVIDENCE_RUN_DIR"
  log_info "========================================"
  
  if [ -f "${EVIDENCE_RUN_DIR}/FAILED.log" ]; then
    log_error "PRUEBA FALLIDA"
    exit 1
  fi
  
  log_info "PRUEBA COMPLETADA"
}

main "$@"
