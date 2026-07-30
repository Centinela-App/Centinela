#!/usr/bin/env bash
#
# scripts/provision-keyvault.sh
# ISS-S2-003 - Provisionar Azure Key Vault + migrar el secreto real de Semana 2.
#
# Alcance ESTRICTO de la Issue S2-003:
#   - Crear/asegurar 1 Key Vault con:
#       * RBAC en el plano de datos (--enable-rbac-authorization true).
#       * soft-delete (siempre activo) + purge protection.
#   - Migrar al vault el UNICO secreto inevitable de Semana 2: la connection string
#     de Cosmos DB for MongoDB (la API Mongo NO soporta Entra ID en el data plane,
#     por eso su key es un secreto real — ver revision de ADR-005 y ADR-007).
#       * Postgres (ISS-S2-002) NO aporta secreto: usa Entra ID exclusiva.
#       * Event Grid (ISS-S2-005/006) publica por Managed Identity: sin secreto.
#   - Otorgar 'Key Vault Secrets User' a las Managed Identities de la Web App y su
#     slot 'staging' (la identidad de la Function se agrega en ISS-S2-007).
#   - Referenciar el secreto desde el App Service por @Microsoft.KeyVault(...).
#   - Idempotente: reejecutar converge al mismo estado.
#
# El valor del secreto NUNCA se imprime ni se versiona.
#
# Prerequisitos: Resource Group, App Service + slot (Semana 1) y Cosmos (ISS-S2-001).
#
# Variables (ver scripts/lib/parameters.sh):
#   SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX
#
# Variables opcionales (con defaults):
#   KEYVAULT_RETENTION_DAYS   dias de soft-delete (default: 90)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parameters.sh"

# --- Constantes de la Issue S2-003 ---------------------------------------------

readonly SLOT_NAME="staging"
readonly COSMOS_SECRET_NAME="cosmos-mongo-connection-string"
readonly APP_SETTING_NAME="CENTINELA_COSMOS_CONNECTION_STRING"
readonly SECRETS_USER_ROLE="Key Vault Secrets User"      # solo lectura de secretos
readonly SECRETS_OFFICER_ROLE="Key Vault Secrets Officer" # gestion (para SET, deployer)
readonly RETENTION_DAYS="${KEYVAULT_RETENTION_DAYS:-90}"

readonly TAGS=(
  "project=centinela"
  "week=2"
  "team=celula-centinela"
  "issue=ISS-S2-003"
)

DEPLOYER_OFFICER_GRANTED=0
DEPLOYER_OID=""
DEPLOYER_VAULT_SCOPE=""

# --- Helpers de nombrado (deterministas, iguales al resto de la infra) ----------

compute_keyvault_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-kv-%s' "$prefix" "$hash"
}
compute_cosmos_account_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-cosmos-%s' "$prefix" "$hash"
}
compute_web_app_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-app-%s' "$prefix" "$hash"
}
compute_function_app_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-scoring-fn-%s' "$prefix" "$hash"
}

assert_keyvault_name_valid() {
  local name="$1"
  [ "${#name}" -ge 3 ] && [ "${#name}" -le 24 ] \
    || die "Nombre de Key Vault invalido (longitud fuera de 3..24): '$name'"
  [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]] \
    || die "Nombre de Key Vault invalido (debe iniciar con letra, [a-zA-Z0-9-]): '$name'"
  [[ "$name" == *--* ]] && die "Nombre de Key Vault invalido (guiones consecutivos): '$name'"
  return 0
}

# --- Asignacion RBAC idempotente -----------------------------------------------

assign_role_scope() {
  local principal="$1" ptype="$2" role="$3" scope="$4" n
  n="$(az role assignment list --assignee "$principal" --scope "$scope" --role "$role" \
        --query "length(@)" -o tsv 2>/dev/null || echo 0)"
  if [ "${n:-0}" -ge 1 ] 2>/dev/null; then
    log_info "  YA asignado: '$role' a $(mask "$principal")."
    return 0
  fi
  with_retry 3 az role assignment create \
    --assignee-object-id "$principal" \
    --assignee-principal-type "$ptype" \
    --role "$role" \
    --scope "$scope" >/dev/null
  log_info "  OK: '$role' -> $(mask "$principal")."
}

# --- Side effects (Azure) -------------------------------------------------------

create_vault() {
  local vault="$1" rg="$2"
  if az keyvault show --name "$vault" --resource-group "$rg" >/dev/null 2>&1; then
    log_info "Key Vault '$vault' ya existe."
    return 0
  fi

  # REPRODUCIBILIDAD TRAS destroy-week1.sh: borrar el Resource Group deja el vault
  # en estado "soft-deleted", y con purge protection activa NO se puede purgar: el
  # nombre queda reservado durante todo el periodo de retencion. Sin este bloque,
  # el segundo despliegue con el mismo NAME_PREFIX fallaria para siempre con
  # "vault name is already in use". Recuperarlo es la unica salida valida y ademas
  # devuelve el vault con su configuracion original.
  if az keyvault show-deleted --name "$vault" --location "$LOCATION" >/dev/null 2>&1; then
    log_warn "Existe un Key Vault BORRADO llamado '$vault' (purge protection impide purgarlo)."
    log_info "Recuperandolo en lugar de crear uno nuevo..."
    with_retry 3 az keyvault recover --name "$vault" --location "$LOCATION" \
      --resource-group "$rg" --output none \
      || die "No se pudo recuperar el Key Vault borrado '$vault'."
    # La recuperacion es asincrona: el vault tarda unos segundos en ser consultable.
    retry_until 10 az keyvault show --name "$vault" --resource-group "$rg" \
      || die "El Key Vault '$vault' se recupero pero no responde todavia."
    log_info "Key Vault '$vault' recuperado."
    return 0
  fi

  log_info "Creando Key Vault '$vault' (RBAC, soft-delete ${RETENTION_DAYS}d, purge protection)..."
  with_retry 3 az keyvault create \
    --name "$vault" \
    --resource-group "$rg" \
    --location "$LOCATION" \
    --enable-rbac-authorization true \
    --enable-purge-protection true \
    --retention-days "$RETENTION_DAYS" \
    --sku standard \
    --tags "${TAGS[@]}" \
    --output none
  log_info "Key Vault creado."
}

# El deployer necesita 'Secrets Officer' para poder SET el secreto (vault RBAC).
grant_deployer_officer() {
  local vault_id="$1" oid existing
  oid="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")"
  [ -n "$oid" ] || { log_warn "No se pudo resolver el usuario Entra actual; omito grant de Officer."; return 0; }
  existing="$(az role assignment list --assignee "$oid" --scope "$vault_id" \
    --role "$SECRETS_OFFICER_ROLE" --query 'length(@)' -o tsv 2>/dev/null || echo 0)"
  if [ "${existing:-0}" -ge 1 ] 2>/dev/null; then
    log_info "El deployer ya tenia '$SECRETS_OFFICER_ROLE'; no se revocara al final."
    return 0
  fi
  log_info "Otorgando '$SECRETS_OFFICER_ROLE' al deployer para poder cargar el secreto..."
  assign_role_scope "$oid" "User" "$SECRETS_OFFICER_ROLE" "$vault_id"
  DEPLOYER_OFFICER_GRANTED=1
  DEPLOYER_OID="$oid"
  DEPLOYER_VAULT_SCOPE="$vault_id"
}

revoke_temporary_deployer_officer() {
  [ "$DEPLOYER_OFFICER_GRANTED" -eq 1 ] || return 0
  log_info "Revocando permiso temporal '$SECRETS_OFFICER_ROLE' del deployer..."
  az role assignment delete --assignee "$DEPLOYER_OID" \
    --role "$SECRETS_OFFICER_ROLE" --scope "$DEPLOYER_VAULT_SCOPE" >/dev/null 2>&1 || \
    log_warn "No se pudo revocar automaticamente el permiso temporal; revisalo manualmente."
  DEPLOYER_OFFICER_GRANTED=0
}

# Migra la connection string de Cosmos al vault. NUNCA imprime el valor.
store_cosmos_secret() {
  local vault="$1" rg="$2" cosmos="$3"
  az cosmosdb show --name "$cosmos" --resource-group "$rg" >/dev/null 2>&1 \
    || die "Cosmos '$cosmos' no existe (ISS-S2-001). Provisiona Cosmos antes de migrar su secreto."

  log_info "Recuperando connection string de Cosmos '$cosmos' (valor NO se imprime)..."
  local conn
  conn="$(az cosmosdb keys list --name "$cosmos" --resource-group "$rg" \
    --type connection-strings \
    --query "connectionStrings[0].connectionString" -o tsv 2>/dev/null || echo "")"
  [ -n "$conn" ] || die "No se pudo obtener la connection string de Cosmos '$cosmos'."

  log_info "Guardando secreto '$COSMOS_SECRET_NAME' en el vault..."
  # RBAC recien asignado puede tardar en propagar: reintentamos el SET.
  local attempt=1
  until az keyvault secret set --vault-name "$vault" \
          --name "$COSMOS_SECRET_NAME" --value "$conn" --output none 2>/dev/null; do
    if [ "$attempt" -ge 5 ]; then
      unset conn
      die "No se pudo guardar el secreto tras 5 intentos (¿propagacion RBAC o permisos?)."
    fi
    log_warn "SET del secreto fallo (intento $attempt/5); esperando propagacion RBAC..."
    sleep $((attempt * 5)); attempt=$((attempt + 1))
  done
  unset conn
  log_info "Secreto '$COSMOS_SECRET_NAME' almacenado (valor oculto)."
}

# Otorga 'Secrets User' a las MI de la Web App y su slot (Function -> ISS-S2-007).
grant_app_identities() {
  local vault_id="$1" rg="$2" app="$3"
  local prod_pid staging_pid
  prod_pid="$(az webapp identity show --name "$app" --resource-group "$rg" \
    --query principalId -o tsv 2>/dev/null || echo "")"
  staging_pid="$(az webapp identity show --name "$app" --resource-group "$rg" \
    --slot "$SLOT_NAME" --query principalId -o tsv 2>/dev/null || echo "")"

  if [ -n "$prod_pid" ]; then
    log_info "Otorgando '$SECRETS_USER_ROLE' a la MI de PRODUCCION..."
    assign_role_scope "$prod_pid" "ServicePrincipal" "$SECRETS_USER_ROLE" "$vault_id"
  else
    log_warn "Web App de produccion sin Managed Identity (ISS-S1-004); omito grant."
  fi
  if [ -n "$staging_pid" ]; then
    log_info "Otorgando '$SECRETS_USER_ROLE' a la MI de STAGING..."
    assign_role_scope "$staging_pid" "ServicePrincipal" "$SECRETS_USER_ROLE" "$vault_id"
  else
    log_warn "Slot 'staging' sin Managed Identity (ISS-S1-004); omito grant."
  fi
  # Mensaje condicional: era un log_warn fijo que afirmaba "aun no existe" incluso
  # cuando la Function ya estaba desplegada, lo que confunde al leer el registro.
  local fn_name fn_pid
  fn_name="${SCORING_FUNCTION_APP_NAME:-$(compute_function_app_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$rg")}"
  fn_pid="$(az functionapp identity show --name "$fn_name" --resource-group "$rg" \
    --query principalId -o tsv 2>/dev/null || true)"
  if [ -n "$fn_pid" ]; then
    log_info "Otorgando '$SECRETS_USER_ROLE' a la MI de la Function '$fn_name'..."
    assign_role_scope "$fn_pid" "ServicePrincipal" "$SECRETS_USER_ROLE" "$vault_id"
  else
    log_info "La Function aun no existe; su grant se aplicara en ISS-S2-007."
  fi
}

# Referencia el secreto como app setting (@Microsoft.KeyVault) en app + slot.
wire_app_settings() {
  local vault="$1" rg="$2" app="$3"
  local secret_uri="@Microsoft.KeyVault(SecretUri=https://${vault}.vault.azure.net/secrets/${COSMOS_SECRET_NAME}/)"

  if az webapp show --name "$app" --resource-group "$rg" >/dev/null 2>&1; then
    log_info "Referenciando el secreto en app settings (prod + slot) por @Microsoft.KeyVault..."
    with_retry 3 az webapp config appsettings set --name "$app" --resource-group "$rg" \
      --settings "${APP_SETTING_NAME}=${secret_uri}" --output none
    with_retry 3 az webapp config appsettings set --name "$app" --resource-group "$rg" \
      --slot "$SLOT_NAME" --settings "${APP_SETTING_NAME}=${secret_uri}" --output none
    log_info "App settings de referencia configurados (sin valor de secreto versionado)."
  else
    log_warn "Web App '$app' no existe; omito el wiring de app settings."
  fi
}

verify_all_resources() {
  local vault="$1" rg="$2"
  log_info "Verificando Key Vault y secreto..."
  local rbac purge secret_present
  rbac="$(az keyvault show --name "$vault" --resource-group "$rg" \
    --query 'properties.enableRbacAuthorization' -o tsv 2>/dev/null || echo "?")"
  purge="$(az keyvault show --name "$vault" --resource-group "$rg" \
    --query 'properties.enablePurgeProtection' -o tsv 2>/dev/null || echo "?")"
  secret_present="$(az keyvault secret list --vault-name "$vault" \
    --query "length([?name=='$COSMOS_SECRET_NAME'])" -o tsv 2>/dev/null || echo 0)"

  log_info "  OK vault:           $vault"
  log_info "  RBAC authorization: $rbac"
  log_info "  Purge protection:   $purge"
  log_info "  Secreto presente:   $([ "$secret_present" = "1" ] && echo "si ($COSMOS_SECRET_NAME)" || echo "NO")"
}

# --- Main ----------------------------------------------------------------------

main() {
  load_parameters
  validate_parameters

  require_cmd az
  az account show >/dev/null 2>&1 \
    || die "No hay sesion de Azure activa. Ejecuta 'az login' primero."
  local active_sub; active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID"))."
  az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 \
    || die "Resource Group '$RESOURCE_GROUP' no existe. Ejecuta primero deploy-platform.sh."

  local vault cosmos app vault_id
  vault="$(compute_keyvault_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  assert_keyvault_name_valid "$vault"
  cosmos="$(compute_cosmos_account_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  app="$(compute_web_app_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"

  log_info "Key Vault objetivo: $vault (longitud: ${#vault})"
  log_info "Secreto a migrar:   $COSMOS_SECRET_NAME (desde Cosmos '$cosmos')"

  create_vault "$vault" "$RESOURCE_GROUP"
  vault_id="$(az keyvault show --name "$vault" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"

  grant_deployer_officer "$vault_id"
  trap revoke_temporary_deployer_officer EXIT
  store_cosmos_secret    "$vault" "$RESOURCE_GROUP" "$cosmos"
  grant_app_identities   "$vault_id" "$RESOURCE_GROUP" "$app"
  wire_app_settings      "$vault" "$RESOURCE_GROUP" "$app"
  verify_all_resources   "$vault" "$RESOURCE_GROUP"
  revoke_temporary_deployer_officer
  trap - EXIT

  log_info "ISS-S2-003 OK: Key Vault '$vault' con secreto de Cosmos y acceso por Managed Identity."
}

main "$@"
