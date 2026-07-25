#!/usr/bin/env bash
# TEST-S1-026/027: destruir, reconstruir, validar Queue/HA y limpiar Semana 1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

KEEP_RESOURCES=0
KEEP_ENTRA_FINAL=0
SKIP_TEST_RBAC=0
TEST_PRINCIPAL_ID="${WEEK1_TEST_PRINCIPAL_ID:-}"
TEST_PRINCIPAL_TYPE="${WEEK1_TEST_PRINCIPAL_TYPE:-User}"
RBAC_PROPAGATION_SECONDS="${RBAC_PROPAGATION_SECONDS:-60}"
CONFIRM_RESOURCE_GROUP=""
SERVICE_TOKEN_COMMAND="${CENTINELA_SERVICE_TOKEN_COMMAND:-}"

usage() {
  cat <<USAGE
Uso: $0 [opciones]

  --keep-resources             Conserva recursos con excepcion documentada.
  --keep-entra-final           Elimina el RG pero conserva la App Registration al final.
  --skip-test-rbac             No crea roles temporales para Queue/Blob.
  --test-principal ID          Object ID de la identidad que ejecuta las pruebas.
  --test-principal-type TIPO   User o ServicePrincipal (default: User).
  --confirm-resource-group RG   Debe coincidir exactamente con RESOURCE_GROUP.
  --service-token-command CMD   Comando que imprime un token SERVICE despues del deploy.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --keep-resources) KEEP_RESOURCES=1; shift ;;
    --keep-entra-final) KEEP_ENTRA_FINAL=1; shift ;;
    --skip-test-rbac) SKIP_TEST_RBAC=1; shift ;;
    --test-principal) TEST_PRINCIPAL_ID="${2:?Falta ID}"; shift 2 ;;
    --test-principal-type) TEST_PRINCIPAL_TYPE="${2:?Falta tipo}"; shift 2 ;;
    --confirm-resource-group) CONFIRM_RESOURCE_GROUP="${2:?Falta RG}"; shift 2 ;;
    --service-token-command) SERVICE_TOKEN_COMMAND="${2:?Falta comando}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

RUN_ID="run-drc-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
EVIDENCE_DIR="$SCRIPT_DIR/../../docs/evidence/final/$RUN_ID"
CREATED_RBAC_FILE=""
START_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TEST_RBAC_MANAGED=0
FINAL_CLEANUP_DONE=0
FINAL_RESULT="FAILED"

QUEUE_ROLES=(
  "Storage Queue Data Message Sender"
  "Storage Queue Data Message Processor"
)
BLOB_TEST_ROLE="Storage Blob Data Contributor"

compute_hash() {
  printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6
}

storage_account_name() {
  printf '%sst%s' "$NAME_PREFIX" "$(compute_hash)"
}

webapp_name() {
  printf '%s-app-%s' "$NAME_PREFIX" "$(compute_hash)"
}

storage_account_id() {
  az storage account show \
    --name "$(storage_account_name)" \
    --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv
}

blob_container_scope() {
  printf '%s/blobServices/default/containers/raw-transactions-production' "$(storage_account_id)"
}

wait_for_health() {
  local url="https://$(webapp_name).azurewebsites.net/actuator/health"
  local attempts="${HEALTH_MAX_ATTEMPTS:-30}" status
  for attempt in $(seq 1 "$attempts"); do
    if ! status="$(curl --silent --output "$EVIDENCE_DIR/health-response.json" --write-out '%{http_code}' --max-time 15 "$url")"; then
      status="000"
    fi
    if [ "$status" = "200" ]; then
      log_info "Health check disponible en el intento $attempt."
      return 0
    fi
    log_warn "Health check HTTP $status; reintento $attempt/$attempts."
    sleep 10
  done
  die "La aplicacion no alcanzo estado saludable en $url."
}

resolve_service_token() {
  if [ -n "$SERVICE_TOKEN_COMMAND" ]; then
    CENTINELA_SERVICE_TOKEN="$(bash -lc "$SERVICE_TOKEN_COMMAND")"
  fi
  [ -n "${CENTINELA_SERVICE_TOKEN:-}" ] \
    || die "Falta token SERVICE. Define CENTINELA_SERVICE_TOKEN o --service-token-command."
  export CENTINELA_SERVICE_TOKEN
}

run_base_validations() {
  local validators=(
    validate-storage.sh
    validate-app-service.sh
    validate-network.sh
    validate-entra-roles.sh
    validate-rbac.sh
    validate-managed-identity.sh
    validate-documentation.sh
    validate-week1-scope.sh
  )
  local validator
  for validator in "${validators[@]}"; do
    log_info "Ejecutando $validator..."
    "$SCRIPT_DIR/$validator" > "$EVIDENCE_DIR/${validator%.sh}.log" 2>&1
  done
}

write_metadata() {
  jq -n \
    --arg runId "$RUN_ID" \
    --arg startTime "$START_TIME" \
    --arg commit "$(git rev-parse HEAD 2>/dev/null || echo N/A)" \
    --arg branch "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo N/A)" \
    --arg resourceGroup "$RESOURCE_GROUP" \
    --arg subscription "$(mask "$SUBSCRIPTION_ID")" \
    '{runId:$runId,testIds:["TEST-S1-026","TEST-S1-027"],startTime:$startTime,commit:$commit,branch:$branch,resourceGroup:$resourceGroup,subscription:$subscription}' \
    > "$EVIDENCE_DIR/metadata.json"
}

update_metadata_result() {
  local result="$1"
  jq \
    --arg endTime "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg result "$result" \
    --argjson resourcesKept "$KEEP_RESOURCES" \
    --argjson entraKept "$KEEP_ENTRA_FINAL" \
    '. + {endTime:$endTime,result:$result,resourcesKept:($resourcesKept == 1),entraKept:($entraKept == 1)}' \
    "$EVIDENCE_DIR/metadata.json" > "$EVIDENCE_DIR/metadata.tmp"
  mv "$EVIDENCE_DIR/metadata.tmp" "$EVIDENCE_DIR/metadata.json"
}

assign_role_if_missing() {
  local role="$1" scope="$2"
  local count
  count="$(az role assignment list \
    --assignee "$TEST_PRINCIPAL_ID" \
    --role "$role" \
    --scope "$scope" \
    --query 'length(@)' -o tsv 2>/dev/null || echo 0)"

  if [ "${count:-0}" -eq 0 ]; then
    az role assignment create \
      --assignee-object-id "$TEST_PRINCIPAL_ID" \
      --assignee-principal-type "$TEST_PRINCIPAL_TYPE" \
      --role "$role" \
      --scope "$scope" \
      --only-show-errors >/dev/null
    printf '%s\t%s\n' "$role" "$scope" >> "$CREATED_RBAC_FILE"
    printf 'CREATED role=%s scope=%s\n' "$role" "$(mask "$scope")" >> "$EVIDENCE_DIR/temporary-rbac.log"
  else
    printf 'EXISTING role=%s scope=%s\n' "$role" "$(mask "$scope")" >> "$EVIDENCE_DIR/temporary-rbac.log"
  fi
}

assign_test_roles() {
  [ "$SKIP_TEST_RBAC" -eq 1 ] && {
    log_warn "--skip-test-rbac: se asume que la identidad ya tiene permisos de Queue y Blob."
    return 0
  }

  case "$TEST_PRINCIPAL_TYPE" in
    User|ServicePrincipal) ;;
    *) die "--test-principal-type debe ser User o ServicePrincipal." ;;
  esac

  if [ -z "$TEST_PRINCIPAL_ID" ]; then
    TEST_PRINCIPAL_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
    TEST_PRINCIPAL_TYPE="User"
  fi
  [ -n "$TEST_PRINCIPAL_ID" ] \
    || die "No se pudo resolver la identidad de prueba. Usa --test-principal y --test-principal-type."

  : > "$EVIDENCE_DIR/temporary-rbac.log"
  : > "$CREATED_RBAC_FILE"
  local sa_id role
  sa_id="$(storage_account_id)"
  for role in "${QUEUE_ROLES[@]}"; do
    assign_role_if_missing "$role" "$sa_id"
  done
  assign_role_if_missing "$BLOB_TEST_ROLE" "$(blob_container_scope)"
  TEST_RBAC_MANAGED=1

  log_info "Esperando ${RBAC_PROPAGATION_SECONDS}s por propagacion RBAC..."
  sleep "$RBAC_PROPAGATION_SECONDS"
}

revoke_test_roles() {
  [ "$SKIP_TEST_RBAC" -eq 1 ] && return 0
  [ "$TEST_RBAC_MANAGED" -eq 1 ] || return 0
  [ -s "$CREATED_RBAC_FILE" ] || return 0

  local role scope
  while IFS=$'\t' read -r role scope; do
    [ -n "$role" ] || continue
    az role assignment delete \
      --assignee "$TEST_PRINCIPAL_ID" \
      --role "$role" \
      --scope "$scope" >/dev/null 2>&1 || true
    printf 'REVOKED role=%s scope=%s\n' "$role" "$(mask "$scope")" >> "$EVIDENCE_DIR/temporary-rbac.log"
  done < "$CREATED_RBAC_FILE"

  printf 'REVOKED_AT=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$EVIDENCE_DIR/temporary-rbac.log"
  TEST_RBAC_MANAGED=0
}

final_cleanup() {
  if [ "$KEEP_RESOURCES" -eq 1 ]; then
    cat > "$EVIDENCE_DIR/KEEP_RESOURCES_EXCEPTION.md" <<EXCEPTION
# Excepcion temporal de limpieza

- Responsable: $(whoami)
- Fecha UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Fecha maxima de retiro: $(date -u -d '+7 days' +%Y-%m-%d 2>/dev/null || echo 'definir manualmente')
- Comando de retiro: `bash scripts/destroy-week1.sh --yes --wait`
EXCEPTION
    FINAL_CLEANUP_DONE=1
    return 0
  fi

  if [ "$(az group exists --name "$RESOURCE_GROUP" -o tsv 2>/dev/null || echo false)" = "true" ]; then
    local destroy_args=(--yes --wait)
    if [ "$KEEP_ENTRA_FINAL" -eq 1 ]; then
      destroy_args+=(--keep-entra)
      cat > "$EVIDENCE_DIR/KEEP_ENTRA_EXCEPTION.md" <<EXCEPTION
# Excepcion de limpieza tenant-level

La App Registration se conserva porque fue solicitado con `--keep-entra-final`.
El Resource Group y los recursos con costo sí deben quedar eliminados. Esta excepción se
usa cuando la misma identidad continúa siendo requerida por una semana posterior.
EXCEPTION
    fi
    "$SCRIPT_DIR/../destroy-week1.sh" "${destroy_args[@]}" 2>&1 | tee "$EVIDENCE_DIR/cleanup.log"
  else
    printf 'Resource Group ya ausente.\n' > "$EVIDENCE_DIR/cleanup.log"
  fi

  [ "$(az group exists --name "$RESOURCE_GROUP" -o tsv)" = "false" ] \
    || die "La limpieza final no elimino el Resource Group."
  FINAL_CLEANUP_DONE=1
}

write_summary() {
  local result="$1" detail="$2"
  cat > "$EVIDENCE_DIR/validation-summary.md" <<SUMMARY
# Cierre verificable de Semana 1

- **Run ID:** $RUN_ID
- **Pruebas:** TEST-S1-020, TEST-S1-024, TEST-S1-026 y TEST-S1-027
- **Resultado:** $result
- **Commit:** $(git rev-parse HEAD 2>/dev/null || echo N/A)
- **Fecha UTC:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Resultado por bloque

- Reconstruccion desde Resource Group inexistente: $(test -f "$EVIDENCE_DIR/deployment.log" && echo EJECUTADA || echo NO_COMPLETADA)
- Validacion Azure: $(test -f "$EVIDENCE_DIR/validate-week1.log" && echo EJECUTADA || echo NO_COMPLETADA)
- Maven: $(grep -q 'BUILD SUCCESS' "$EVIDENCE_DIR/maven-verify.log" 2>/dev/null && echo PASSED || echo NO_CONFIRMADO)
- Queue staging: $(test -f "$EVIDENCE_DIR/queue-staging.log" && echo EJECUTADA || echo NO_COMPLETADA)
- Queue production: $(test -f "$EVIDENCE_DIR/queue-production.log" && echo EJECUTADA || echo NO_COMPLETADA)
- Alta disponibilidad: $(test -f "$EVIDENCE_DIR/ha.log" && echo EJECUTADA || echo NO_COMPLETADA)
- Limpieza final del RG: $([ "$FINAL_CLEANUP_DONE" -eq 1 ] && echo CONFIRMADA || echo NO_CONFIRMADA)
- App Registration final: $([ "$KEEP_ENTRA_FINAL" -eq 1 ] && echo CONSERVADA_CON_EXCEPCION || echo ELIMINADA)

## Detalle

$detail
SUMMARY
  update_metadata_result "$result"
}

on_exit() {
  local rc=$?
  trap - EXIT

  revoke_test_roles || true
  if [ "$FINAL_CLEANUP_DONE" -eq 0 ]; then
    final_cleanup || rc=1
  fi

  if [ "$rc" -ne 0 ] && [ ! -f "$EVIDENCE_DIR/validation-summary.md" ]; then
    write_summary "FAILED" "El cierre fallo. Se intento revocar RBAC temporal y limpiar los recursos."
  fi
  [ -n "$CREATED_RBAC_FILE" ] && rm -f "$CREATED_RBAC_FILE"
  exit "$rc"
}

main() {
  require_cmd az
  require_cmd jq
  require_cmd mvn
  require_cmd curl
  require_cmd sha1sum

  load_parameters
  validate_parameters
  [ "$CONFIRM_RESOURCE_GROUP" = "$RESOURCE_GROUP" ]     || die "Proteccion destructiva: usa --confirm-resource-group '$RESOURCE_GROUP'."
  if [ -z "${CENTINELA_SERVICE_TOKEN:-}" ] && [ -z "$SERVICE_TOKEN_COMMAND" ]; then
    die "Define CENTINELA_SERVICE_TOKEN o --service-token-command antes de iniciar."
  fi

  az account show >/dev/null 2>&1 || die "No hay sesion Azure activa. Ejecuta az login."
  local active_sub
  active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  mkdir -p "$EVIDENCE_DIR"
  CREATED_RBAC_FILE="$(mktemp)"
  write_metadata
  trap on_exit EXIT

  # Fase 1: estado limpio confirmado.
  if [ "$(az group exists --name "$RESOURCE_GROUP" -o tsv)" = "true" ]; then
    az resource list --resource-group "$RESOURCE_GROUP" \
      --query '[].{name:name,type:type}' -o json > "$EVIDENCE_DIR/pre-destroy-inventory.json"
    "$SCRIPT_DIR/../destroy-week1.sh" --yes --wait --keep-entra 2>&1 | tee "$EVIDENCE_DIR/destroy.log"
  else
    printf 'Resource Group inicialmente ausente.\n' > "$EVIDENCE_DIR/destroy.log"
  fi
  [ "$(az group exists --name "$RESOURCE_GROUP" -o tsv)" = "false" ] \
    || die "No se alcanzo el estado limpio inicial."

  # Fase 2: reconstruccion completa y validaciones base.
  "$SCRIPT_DIR/../deploy-week1.sh" 2>&1 | tee "$EVIDENCE_DIR/deployment.log"
  (cd "$REPO_ROOT" && mvn clean verify) > "$EVIDENCE_DIR/maven-verify.log" 2>&1
  "$SCRIPT_DIR/../deploy-application.sh" --swap 2>&1 | tee "$EVIDENCE_DIR/application-deploy.log"
  wait_for_health
  "$SCRIPT_DIR/../validate-week1.sh" > "$EVIDENCE_DIR/validate-week1.log" 2>&1
  run_base_validations
  resolve_service_token

  az resource list --resource-group "$RESOURCE_GROUP" \
    --query '[].{name:name,type:type,location:location}' -o json > "$EVIDENCE_DIR/resource-inventory.json"
  [ "$(jq 'length' "$EVIDENCE_DIR/resource-inventory.json")" -gt 0 ] \
    || die "No se inventariaron recursos despues de reconstruir."

  # Fase 3: permisos temporales y pruebas Azure pendientes.
  assign_test_roles

  export STAGING_STORAGE_ACCOUNT="$(storage_account_name)"
  export PRODUCTION_STORAGE_ACCOUNT="$(storage_account_name)"
  export CENTINELA_STORAGE_ACCOUNT="$(storage_account_name)"
  export CENTINELA_RAW_TRANSACTIONS_CONTAINER="raw-transactions-production"
  export CENTINELA_API_BASE_URL="https://$(webapp_name).azurewebsites.net"

  "$SCRIPT_DIR/../validate-queue.sh" staging > "$EVIDENCE_DIR/queue-staging.log" 2>&1
  "$SCRIPT_DIR/../validate-queue.sh" production > "$EVIDENCE_DIR/queue-production.log" 2>&1
  "$SCRIPT_DIR/../test-ha.sh" > "$EVIDENCE_DIR/ha.log" 2>&1

  revoke_test_roles

  # Fase 4: una instancia final y limpieza.
  local final_capacity
  final_capacity="$(az appservice plan show \
    --resource-group "$RESOURCE_GROUP" \
    --name "${NAME_PREFIX}-asp-week1" \
    --query sku.capacity -o tsv)"
  [ "$final_capacity" = "1" ] || die "La capacidad previa a limpieza no es 1 (actual: $final_capacity)."

  final_cleanup
  FINAL_RESULT="PASSED"
  write_summary "$FINAL_RESULT" "El entorno fue destruido, reconstruido, validado, probado en Queue y HA, y limpiado sin aceptar advertencias como exito."
  log_info "CIERRE SEMANA 1 PASSED. Evidencia: $EVIDENCE_DIR"
}

main "$@"
