#!/usr/bin/env bash
# TEST-S1-026: desplegar Semana 1 desde un Resource Group inexistente.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

REPLACE_EXISTING=0
CONFIRM_RESOURCE_GROUP=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --replace-existing) REPLACE_EXISTING=1; shift ;;
    --confirm-resource-group) CONFIRM_RESOURCE_GROUP="${2:?Falta RG}"; shift 2 ;;
    -h|--help)
      echo "Uso: $0 [--replace-existing --confirm-resource-group <RG>]"
      exit 0
      ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

RUN_ID="run-clean-$(date -u +%Y%m%dT%H%M%SZ)-$RANDOM"
EVIDENCE_DIR="$SCRIPT_DIR/../../docs/evidence/final/$RUN_ID"
RESULT="FAILED"

webapp_name() {
  local hash
  hash="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)"
  printf '%s-app-%s' "$NAME_PREFIX" "$hash"
}

wait_for_health() {
  local url="https://$(webapp_name).azurewebsites.net/actuator/health"
  local attempts="${HEALTH_MAX_ATTEMPTS:-30}" status
  for attempt in $(seq 1 "$attempts"); do
    if ! status="$(curl --silent --output "$EVIDENCE_DIR/health-response.json" --write-out '%{http_code}' --max-time 15 "$url")"; then
      status="000"
    fi
    [ "$status" = "200" ] && return 0
    sleep 10
  done
  die "La aplicacion no alcanzo estado saludable en $url."
}


run_resource_validations() {
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
    "$SCRIPT_DIR/$validator" > "$EVIDENCE_DIR/${validator%.sh}.log" 2>&1
  done
}

write_metadata() {
  jq -n \
    --arg runId "$RUN_ID" \
    --arg testId "TEST-S1-026" \
    --arg startTime "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg commit "$(git rev-parse HEAD 2>/dev/null || echo N/A)" \
    --arg branch "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo N/A)" \
    '{runId:$runId,testId:$testId,startTime:$startTime,commit:$commit,branch:$branch}' \
    > "$EVIDENCE_DIR/metadata.json"
}

write_summary() {
  local result="$1" detail="$2"
  cat > "$EVIDENCE_DIR/validation-summary.md" <<SUMMARY
# Resumen TEST-S1-026

- **Run ID:** $RUN_ID
- **Resultado:** $result
- **Commit:** $(git rev-parse HEAD 2>/dev/null || echo N/A)
- **Resource Group:** $RESOURCE_GROUP
- **Fecha UTC:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Detalle

$detail

## Evidencias

- `deployment.log`
- `validate-week1.log`
- `maven-verify.log`
- `application-deploy.log`
- `health-response.json`
- `resource-inventory.json`
SUMMARY

  jq \
    --arg endTime "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg result "$result" \
    '. + {endTime:$endTime,result:$result}' \
    "$EVIDENCE_DIR/metadata.json" > "$EVIDENCE_DIR/metadata.tmp"
  mv "$EVIDENCE_DIR/metadata.tmp" "$EVIDENCE_DIR/metadata.json"
}

on_exit() {
  local rc=$?
  trap - EXIT
  if [ "$rc" -ne 0 ] && [ ! -f "$EVIDENCE_DIR/validation-summary.md" ]; then
    write_summary "FAILED" "La prueba termino antes de completar todas las validaciones."
  fi
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
  az account show >/dev/null 2>&1 || die "No hay sesion Azure activa. Ejecuta az login."

  local active_sub
  active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."

  mkdir -p "$EVIDENCE_DIR"
  write_metadata
  trap on_exit EXIT

  if [ "$(az group exists --name "$RESOURCE_GROUP" -o tsv)" = "true" ]; then
    [ "$REPLACE_EXISTING" -eq 1 ] \
      || die "El Resource Group '$RESOURCE_GROUP' ya existe. Usa --replace-existing para eliminarlo de forma controlada."
    [ "$CONFIRM_RESOURCE_GROUP" = "$RESOURCE_GROUP" ] \
      || die "Proteccion destructiva: agrega --confirm-resource-group '$RESOURCE_GROUP'."
    "$SCRIPT_DIR/../destroy-week1.sh" --yes --wait 2>&1 | tee "$EVIDENCE_DIR/pre-cleanup.log"
  fi

  [ "$(az group exists --name "$RESOURCE_GROUP" -o tsv)" = "false" ] \
    || die "El Resource Group debe estar ausente antes del despliegue."

  "$SCRIPT_DIR/../deploy-week1.sh" 2>&1 | tee "$EVIDENCE_DIR/deployment.log"
  (cd "$REPO_ROOT" && mvn clean verify) > "$EVIDENCE_DIR/maven-verify.log" 2>&1
  "$SCRIPT_DIR/../deploy-application.sh" --swap 2>&1 | tee "$EVIDENCE_DIR/application-deploy.log"
  wait_for_health
  "$SCRIPT_DIR/../validate-week1.sh" > "$EVIDENCE_DIR/validate-week1.log" 2>&1
  run_resource_validations

  az resource list \
    --resource-group "$RESOURCE_GROUP" \
    --query '[].{name:name,type:type,location:location}' \
    -o json > "$EVIDENCE_DIR/resource-inventory.json"

  [ "$(jq 'length' "$EVIDENCE_DIR/resource-inventory.json")" -gt 0 ] \
    || die "El despliegue termino sin recursos inventariados."

  RESULT="PASSED"
  write_summary "$RESULT" "El entorno se creo desde cero; validate-week1 y mvn clean verify terminaron con codigo 0."
  log_info "TEST-S1-026 PASSED. Evidencia: $EVIDENCE_DIR"
}

main "$@"
