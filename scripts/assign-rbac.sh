#!/usr/bin/env bash
#
# scripts/assign-rbac.sh
# ISS-S1-006 - Asignar Azure RBAC de MINIMO PRIVILEGIO (plano de control/datos).
#
# Alcance ESTRICTO de la Issue 6 (plano de Azure):
#   - Managed Identity de produccion y staging -> "Storage Blob Data Contributor"
#     acotado a los CONTENEDORES que usa la API (no a toda la cuenta):
#       * prod    -> raw-transactions-production, verification-documents-production
#       * staging -> raw-transactions-staging,    verification-documents-staging
#   - La aplicacion NO recibe ningun rol de Queue (la cola no participa del negocio S1).
#   - (Opcional) Analista/Auditor de demostracion -> "Reader" en el Resource Group.
#   - (Opcional) Identidad de prueba de cola -> rol minimo de Queue TEMPORAL,
#     registrado para revocacion; y su revocacion con --revoke-queue-test.
#
# Regla dura: NUNCA asigna "Contributor" ni "Owner" (guard explicito).
#
# Uso:
#   scripts/assign-rbac.sh
#     [--analyst-principal <objectId|UPN>]  -> Reader (RG) para el Analista demo
#     [--auditor-principal <objectId|UPN>]  -> Reader (RG) para el Auditor demo
#     [--queue-test-principal <objectId>]   -> roles Queue TEMPORALES (cuenta Storage)
#     [--queue-test-principal-type <tipo>]  -> User o ServicePrincipal
#     [--revoke-queue-test <objectId>]      -> revoca ambos roles Queue y sale
#
# Variables (ver scripts/lib/parameters.sh):
#   SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX, APP_SERVICE_SKU
# Alternativa por entorno: ANALYST_PRINCIPAL_ID, AUDITOR_PRINCIPAL_ID.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parameters.sh"

# --- Constantes de la Issue 6 --------------------------------------------------

readonly SLOT_NAME="staging"
readonly BLOB_DATA_ROLE="Storage Blob Data Contributor"   # datos, NO administracion
readonly KV_SECRETS_USER_ROLE="Key Vault Secrets User"    # ISS-S2-003: lectura de secretos
readonly READER_ROLE="Reader"
readonly QUEUE_TEST_ROLES=(
  "Storage Queue Data Message Sender"
  "Storage Queue Data Message Processor"
) # combinacion minima para enviar, recibir y eliminar el mensaje tecnico
readonly PROD_CONTAINERS=("raw-transactions-production" "verification-documents-production")
readonly STAGING_CONTAINERS=("raw-transactions-staging" "verification-documents-staging")
# Roles de administracion prohibidos por la regla dura de minimo privilegio.
readonly FORBIDDEN_ROLES=("Owner" "Contributor" "User Access Administrator")

ANALYST_PRINCIPAL="${ANALYST_PRINCIPAL_ID:-}"
AUDITOR_PRINCIPAL="${AUDITOR_PRINCIPAL_ID:-}"
QUEUE_TEST_PRINCIPAL=""
QUEUE_TEST_PRINCIPAL_TYPE="${QUEUE_TEST_PRINCIPAL_TYPE:-ServicePrincipal}"
REVOKE_QUEUE_TEST=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --analyst-principal)    ANALYST_PRINCIPAL="${2:?}"; shift 2 ;;
    --auditor-principal)    AUDITOR_PRINCIPAL="${2:?}"; shift 2 ;;
    --queue-test-principal) QUEUE_TEST_PRINCIPAL="${2:?}"; shift 2 ;;
    --queue-test-principal-type) QUEUE_TEST_PRINCIPAL_TYPE="${2:?}"; shift 2 ;;
    --revoke-queue-test)    REVOKE_QUEUE_TEST="${2:?}"; shift 2 ;;
    -h|--help)
      echo "Uso: $0 [--analyst-principal ID] [--auditor-principal ID] [--queue-test-principal ID] [--queue-test-principal-type User|ServicePrincipal] [--revoke-queue-test ID]"; exit 0 ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

# --- Helpers de nombrado (deterministas, iguales a ISS-S1-003/004) -------------

compute_storage_account_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%sst%s' "$prefix" "$hash"
}
compute_web_app_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-app-%s' "$prefix" "$hash"
}
compute_keyvault_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-kv-%s' "$prefix" "$hash"
}

# --- Guard de minimo privilegio ------------------------------------------------

assert_not_forbidden_role() {
  local role="$1" f
  for f in "${FORBIDDEN_ROLES[@]}"; do
    [ "$role" = "$f" ] && die "REGLA DURA violada: intento de asignar rol prohibido '$role'."
  done
}

# --- Asignacion idempotente ----------------------------------------------------

assign_role_scope() {
  local principal="$1" ptype="$2" role="$3" scope="$4"
  assert_not_forbidden_role "$role"
  local n
  n="$(az role assignment list --assignee "$principal" --scope "$scope" --role "$role" \
        --query "length(@)" -o tsv 2>/dev/null || echo 0)"
  if [ "${n:-0}" -ge 1 ] 2>/dev/null; then
    log_info "  YA asignado: '$role' a $(mask "$principal") en scope acotado."
    return 0
  fi
  with_retry 3 az role assignment create \
    --assignee-object-id "$principal" \
    --assignee-principal-type "$ptype" \
    --role "$role" \
    --scope "$scope" >/dev/null
  log_info "  OK: '$role' -> $(mask "$principal") en scope acotado."
}

# --- Revocacion de la prueba de cola (sale al terminar) ------------------------

revoke_queue_test() {
  local principal="$1" sa_id="$2" role remaining
  for role in "${QUEUE_TEST_ROLES[@]}"; do
    log_warn "Revocando rol temporal '$role' para $(mask "$principal")..."
    az role assignment delete \
      --assignee "$principal" --role "$role" --scope "$sa_id" >/dev/null 2>&1 || true
  done

  remaining="$(az role assignment list --assignee "$principal" --scope "$sa_id" \
    --query "[?roleDefinitionName=='Storage Queue Data Message Sender' || roleDefinitionName=='Storage Queue Data Message Processor'] | length(@)" \
    -o tsv 2>/dev/null || echo 0)"
  [ "${remaining:-0}" = "0" ] || die "La revocacion temporal de Queue no quedo completa."
  log_info "Roles temporales de Queue revocados y verificados."
}

# --- Main ----------------------------------------------------------------------

main() {
  load_parameters
  validate_parameters

  require_cmd az
  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login' primero."
  local active_sub; active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."
  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "Resource Group '$RESOURCE_GROUP' no existe."

  local sa_name app_name sa_id rg_id
  sa_name="$(compute_storage_account_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  app_name="$(compute_web_app_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  sa_id="$(az storage account show --name "$sa_name" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || true)"
  [ -n "$sa_id" ] || die "El Storage '$sa_name' no existe (ISS-S1-003)."
  rg_id="$(az group show --name "$RESOURCE_GROUP" --query id -o tsv)"

  # Modo revocacion aislado (documentado para TEST-S1-010 / limpieza).
  if [ -n "$REVOKE_QUEUE_TEST" ]; then
    revoke_queue_test "$REVOKE_QUEUE_TEST" "$sa_id"
    log_info "ISS-S1-006 (RBAC): revocacion de prueba de cola completada."
    return 0
  fi

  # 1) Managed Identity de produccion y staging -> Blob Data Contributor por contenedor.
  local prod_pid staging_pid c scope
  prod_pid="$(az webapp identity show --name "$app_name" --resource-group "$RESOURCE_GROUP" \
    --query principalId -o tsv 2>/dev/null || true)"
  staging_pid="$(az webapp identity show --name "$app_name" --resource-group "$RESOURCE_GROUP" \
    --slot "$SLOT_NAME" --query principalId -o tsv 2>/dev/null || true)"
  [ -n "$prod_pid" ]    || die "Produccion sin Managed Identity (ISS-S1-004)."
  [ -n "$staging_pid" ] || die "Staging sin Managed Identity (ISS-S1-004)."

  log_info "Asignando '$BLOB_DATA_ROLE' a la MI de PRODUCCION en sus contenedores..."
  for c in "${PROD_CONTAINERS[@]}"; do
    scope="${sa_id}/blobServices/default/containers/${c}"
    assign_role_scope "$prod_pid" "ServicePrincipal" "$BLOB_DATA_ROLE" "$scope"
  done
  log_info "Asignando '$BLOB_DATA_ROLE' a la MI de STAGING en sus contenedores..."
  for c in "${STAGING_CONTAINERS[@]}"; do
    scope="${sa_id}/blobServices/default/containers/${c}"
    assign_role_scope "$staging_pid" "ServicePrincipal" "$BLOB_DATA_ROLE" "$scope"
  done
  log_info "La aplicacion NO recibe ningun rol de Queue (por diseño de Semana 1)."

  # 1.5) ISS-S2-003 / ISS-S2-007: 'Key Vault Secrets User' a la MI de prod, staging y Function App, SI el vault
  #      ya existe. Idempotente y no bloqueante.
  local kv_name kv_id fn_app_name fn_pid
  kv_name="$(compute_keyvault_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  kv_id="$(az keyvault show --name "$kv_name" --resource-group "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || true)"
  if [ -n "$kv_id" ]; then
    log_info "Key Vault '$kv_name' presente: asignando '$KV_SECRETS_USER_ROLE' a prod y staging..."
    assign_role_scope "$prod_pid"    "ServicePrincipal" "$KV_SECRETS_USER_ROLE" "$kv_id"
    assign_role_scope "$staging_pid" "ServicePrincipal" "$KV_SECRETS_USER_ROLE" "$kv_id"
    
    fn_app_name="${SCORING_FUNCTION_APP_NAME:-${NAME_PREFIX}-scoring-fn}"
    fn_pid="$(az functionapp identity show --name "$fn_app_name" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv 2>/dev/null || true)"
    if [ -n "$fn_pid" ]; then
      log_info "Asignando '$KV_SECRETS_USER_ROLE' a la MI de Function App ($fn_app_name)..."
      assign_role_scope "$fn_pid" "ServicePrincipal" "$KV_SECRETS_USER_ROLE" "$kv_id"
    fi
  else
    log_info "Sin Key Vault todavia (ISS-S2-003 aun no ejecutada): se omite el rol de secretos."
  fi

  # 2) Analista / Auditor demo -> Reader en el RG (solo si se proporcionan).
  if [ -n "$ANALYST_PRINCIPAL" ]; then
    log_info "Asignando '$READER_ROLE' al Analista demo en el Resource Group..."
    assign_role_scope "$ANALYST_PRINCIPAL" "User" "$READER_ROLE" "$rg_id"
  else
    log_warn "Sin --analyst-principal / ANALYST_PRINCIPAL_ID: se omite Reader del Analista (documentado)."
  fi
  if [ -n "$AUDITOR_PRINCIPAL" ]; then
    log_info "Asignando '$READER_ROLE' al Auditor demo en el Resource Group..."
    assign_role_scope "$AUDITOR_PRINCIPAL" "User" "$READER_ROLE" "$rg_id"
  else
    log_warn "Sin --auditor-principal / AUDITOR_PRINCIPAL_ID: se omite Reader del Auditor (documentado)."
  fi

  # 3) Prueba de cola: asignacion TEMPORAL minima, registrada para revocacion.
  if [ -n "$QUEUE_TEST_PRINCIPAL" ]; then
    case "$QUEUE_TEST_PRINCIPAL_TYPE" in
      User|ServicePrincipal) ;;
      *) die "QUEUE_TEST_PRINCIPAL_TYPE debe ser User o ServicePrincipal." ;;
    esac

    local queue_role
    for queue_role in "${QUEUE_TEST_ROLES[@]}"; do
      log_warn "Asignando rol temporal '$queue_role' para la prueba ISS-S1-010..."
      assign_role_scope "$QUEUE_TEST_PRINCIPAL" "$QUEUE_TEST_PRINCIPAL_TYPE" "$queue_role" "$sa_id"
    done

    local record="$SCRIPT_DIR/../docs/evidence/identity/temp-queue-assignment.record.txt"
    if [ -d "$(dirname "$record")" ]; then
      {
        printf 'TEMPORAL - REVOCAR AL TERMINAR LA PRUEBA DE COLA (ISS-S1-010)\n'
        printf 'principalId=%s\n' "$QUEUE_TEST_PRINCIPAL"
        printf 'principalType=%s\n' "$QUEUE_TEST_PRINCIPAL_TYPE"
        printf 'roles=Storage Queue Data Message Sender; Storage Queue Data Message Processor\n'
        printf 'scope=%s\n' "$sa_id"
        printf 'revocar_con=scripts/assign-rbac.sh --revoke-queue-test %s\n' "$QUEUE_TEST_PRINCIPAL"
      } > "$record"
      log_warn "Asignacion temporal registrada para revocacion: docs/evidence/identity/temp-queue-assignment.record.txt"
    fi
  fi

  log_info "ISS-S1-006 (RBAC) OK: minimo privilegio aplicado. Ningun Contributor/Owner asignado."
}

main "$@"
