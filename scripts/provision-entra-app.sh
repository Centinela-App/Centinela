#!/usr/bin/env bash
#
# scripts/provision-entra-app.sh
# ISS-S1-006 - Crear/configurar la aplicacion de Entra ID que representa la API,
#              con los 4 app roles funcionales (sin convertirlos en roles de infra).
#
# Alcance ESTRICTO de la Issue 6 (plano de aplicacion / Entra ID):
#   - Crear/asegurar 1 App Registration para la API (idempotente por displayName).
#   - Definir exactamente los app roles: SERVICE, ANALYST, ADMINISTRATOR, AUDITOR.
#       * SERVICE -> allowedMemberTypes ["Application"] (corre desatendido).
#       * ANALYST/ADMINISTRATOR/AUDITOR -> ["User"].
#   - Asegurar el Service Principal (Enterprise App) para poder asignar los roles.
#   - identifierUri = api://<appId>.
#
# NO implementa Spring Security ni conversion de claims (eso es ISS-S1-011),
# NO crea secretos de cliente, NO otorga permisos de infraestructura.
#
# Prerequisitos:
#   - Azure CLI con sesion activa (Cloud Shell).
#   - El ejecutor necesita rol de directorio para crear App Registrations
#     (p.ej. Application Administrator o Cloud Application Administrator).
#
# Variables (ver scripts/lib/parameters.sh):
#   SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX, APP_SERVICE_SKU
# Opcional:
#   ENTRA_APP_DISPLAY_NAME (default "<NAME_PREFIX>-api-week1")

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parameters.sh"

# --- Constantes de la Issue 6 --------------------------------------------------

readonly APP_ROLES=("SERVICE" "ANALYST" "ADMINISTRATOR" "AUDITOR")

# GUID determinista por rol: misma entrada -> mismo id (idempotencia del ARM/CLI).
approle_guid() {
  local name="$1" h
  h="$(printf 'centinela-approle-%s' "$name" | sha1sum | tr -d ' -' | cut -c1-32)"
  printf '%s-%s-5%s-%s%s-%s' "${h:0:8}" "${h:8:4}" "${h:13:3}" "9" "${h:18:3}" "${h:20:12}"
}

role_member_types() {
  case "$1" in
    SERVICE) printf '"Application"' ;;   # identidad de servicio, corre desatendido
    *)       printf '"User"' ;;          # ANALYST / ADMINISTRATOR / AUDITOR
  esac
}

role_description() {
  case "$1" in
    SERVICE)       printf 'Identidad de servicio: unica autorizada a enviar transacciones.' ;;
    ANALYST)       printf 'Analista de fraude: unica autorizada a cargar documentos de verificacion.' ;;
    ADMINISTRATOR) printf 'Administrador: sin escritura de negocio en Semana 1 (config/usuarios en semanas posteriores).' ;;
    AUDITOR)       printf 'Auditor: solo lectura, sin operaciones de escritura.' ;;
  esac
}

render_app_roles_json() {
  local first=1 r
  printf '['
  for r in "${APP_ROLES[@]}"; do
    if [ "$first" -eq 1 ]; then first=0; else printf ','; fi
    printf '{'
    printf '"allowedMemberTypes":[%s],' "$(role_member_types "$r")"
    printf '"description":"%s",' "$(role_description "$r")"
    printf '"displayName":"%s",' "$r"
    printf '"id":"%s",' "$(approle_guid "$r")"
    printf '"isEnabled":true,'
    printf '"value":"%s"' "$r"
    printf '}'
  done
  printf ']'
}

# --- Side effects (Entra ID) ---------------------------------------------------

ensure_app_registration() {
  local display_name="$1" roles_file="$2" app_id
  app_id="$(az ad app list --display-name "$display_name" --query "[0].appId" -o tsv 2>/dev/null || true)"
  if [ -z "$app_id" ] || [ "$app_id" = "None" ]; then
    log_info "Creando App Registration '$display_name'..."
    app_id="$(az ad app create \
      --display-name "$display_name" \
      --sign-in-audience AzureADMyOrg \
      --app-roles @"$roles_file" \
      --query appId -o tsv)"
  else
    log_info "App Registration '$display_name' ya existe (appId $(mask "$app_id")). Actualizando app roles..."
    with_retry 3 az ad app update --id "$app_id" --app-roles @"$roles_file" >/dev/null
  fi
  printf '%s' "$app_id"
}

ensure_identifier_uri() {
  local app_id="$1"
  local current
  current="$(az ad app show --id "$app_id" --query "identifierUris[0]" -o tsv 2>/dev/null || true)"
  if [ "$current" = "api://$app_id" ]; then
    log_info "identifierUri ya es api://$(mask "$app_id")."
  else
    log_info "Fijando identifierUri = api://<appId>..."
    with_retry 3 az ad app update --id "$app_id" --identifier-uris "api://$app_id" >/dev/null
  fi
}

ensure_service_principal() {
  local app_id="$1" sp_id
  sp_id="$(az ad sp list --filter "appId eq '$app_id'" --query "[0].id" -o tsv 2>/dev/null || true)"
  if [ -z "$sp_id" ] || [ "$sp_id" = "None" ]; then
    log_info "Creando Service Principal (Enterprise App) para la API..."
    sp_id="$(az ad sp create --id "$app_id" --query id -o tsv)"
  else
    log_info "Service Principal ya existe (objectId $(mask "$sp_id"))."
  fi
  printf '%s' "$sp_id"
}

verify_app_roles() {
  local app_id="$1" r found
  log_info "Verificando los 4 app roles..."
  for r in "${APP_ROLES[@]}"; do
    found="$(az ad app show --id "$app_id" \
      --query "appRoles[?value=='$r' && isEnabled].value | [0]" -o tsv 2>/dev/null || true)"
    [ "$found" = "$r" ] || die "Falta o esta deshabilitado el app role: $r"
    log_info "  OK app role: $r"
  done
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

  local display_name
  display_name="${ENTRA_APP_DISPLAY_NAME:-${NAME_PREFIX}-api-week1}"
  log_info "App Registration objetivo: $display_name"

  local tmp_dir roles_file
  tmp_dir="$(mktemp -d)"; trap 'rm -rf "$tmp_dir"' EXIT
  roles_file="$tmp_dir/app-roles.json"
  render_app_roles_json > "$roles_file"

  local app_id sp_id
  app_id="$(ensure_app_registration "$display_name" "$roles_file")"
  [ -n "$app_id" ] || die "No se pudo obtener el appId."
  ensure_identifier_uri "$app_id"
  sp_id="$(ensure_service_principal "$app_id")"

  verify_app_roles "$app_id"

  # Registro sanitizado (sin secretos) para trazabilidad de RBAC posterior.
  local record="$SCRIPT_DIR/../docs/evidence/identity/entra-app.record.txt"
  if [ -d "$(dirname "$record")" ]; then
    {
      printf 'appDisplayName=%s\n' "$display_name"
      printf 'appId=%s\n' "$app_id"
      printf 'servicePrincipalObjectId=%s\n' "$sp_id"
      printf 'appRoles=%s\n' "${APP_ROLES[*]}"
      printf 'note=sin secreto de cliente; autorizacion HTTP en ISS-S1-011\n'
    } > "$record"
    log_info "Registro sanitizado escrito: docs/evidence/identity/entra-app.record.txt"
  fi

  log_info "ISS-S1-006 (Entra) OK: App '$display_name' con 4 app roles y Service Principal."
  log_info "appId=$(mask "$app_id")  spObjectId=$(mask "$sp_id")"
  log_info "Siguiente paso: scripts/assign-rbac.sh (RBAC minimo de datos Blob a la Managed Identity)."
}

main "$@"
