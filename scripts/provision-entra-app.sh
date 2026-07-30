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

# ALLOWEDMEMBERTYPES: QUIEN PUEDE SOSTENER CADA ROL
# -------------------------------------------------
# No confundir con QUE permite cada rol. La matriz de permisos
# (docs/3_Seguridad/2_Matriz_Roles_Permisos.md) no cambia: SERVICE sigue pudiendo
# SOLO enviar transacciones y sigue recibiendo 403 en la carga de documentos.
# Aqui se decide unicamente si un rol puede concederse a una identidad de
# aplicacion o solo a una persona.
#
# ANALYST admite ademas "Application" por un motivo concreto: el banco de pruebas
# ejercita el escenario de documento ilegible, que es una accion de analista, y una
# Managed Identity no puede sostener un rol de tipo solo-User. Con la version
# anterior ese escenario devolvia 403 sin remedio posible — no habia forma de
# concederle el rol— y uno de los seis escenarios del banco de pruebas no podia
# funcionar nunca.
#
# La alternativa era dejar que SERVICE cargara documentos. Se descarto: contradice
# una decision de seguridad explicita y documentada, y ampliaria los permisos del
# rol que corre desatendido, que es justo el que menos debe tener. Relajar QUIEN
# puede sostener ANALYST conserva la frontera; ampliar lo que puede SERVICE la
# borraria.
#
# ADMINISTRATOR y AUDITOR siguen siendo solo de personas: ninguna automatizacion
# del sistema necesita administrar ni auditar, y un rol concedible a una aplicacion
# sin que nada lo necesite es superficie de ataque a cambio de nada.
role_member_types() {
  case "$1" in
    SERVICE) printf '"Application"' ;;              # identidad de servicio, corre desatendido
    ANALYST) printf '"User","Application"' ;;       # personas y clientes automatizados del lado analista
    *)       printf '"User"' ;;                     # ADMINISTRATOR / AUDITOR: solo personas
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


compute_web_app_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-app-%s' "$prefix" "$hash"
}

configure_resource_server_settings() {
  local app_id="$1" tenant_id="$2" app_name
  app_name="$(compute_web_app_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"

  local settings=(
    "CENTINELA_ENTRA_ISSUER_URI=https://login.microsoftonline.com/${tenant_id}/v2.0"
    # appId pelado, NO 'api://<appId>': con tokens v2 (ensure_v2_tokens) el claim
    # 'aud' viene sin el prefijo, y validar contra la forma con prefijo rechaza
    # todo token con un 401 que no explica el motivo.
    "CENTINELA_ENTRA_AUDIENCE=${app_id}"
    "CENTINELA_ENTRA_JWK_SET_URI=https://login.microsoftonline.com/${tenant_id}/discovery/v2.0/keys"
  )

  # Topologia de contenedores (ADR-009): sin Web App estos valores no tienen
  # donde escribirse como app settings; viajan como variables de entorno de la
  # Container App en su despliegue. Se imprimen para que el operador no tenga
  # que reconstruirlos (el issuer con /v2.0 y el audience con api:// son los dos
  # detalles que siempre se escriben mal de memoria).
  if ! az webapp show --name "$app_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_warn "Web App '$app_name' no existe; valores para las Container Apps:"
    local s; for s in "${settings[@]}"; do log_warn "  $s"; done
    return 0
  fi

  log_info "Configurando Resource Server OAuth2 en produccion y staging..."
  az webapp config appsettings set \
    --name "$app_name" \
    --resource-group "$RESOURCE_GROUP" \
    --settings "${settings[@]}" \
    --only-show-errors >/dev/null
  az webapp config appsettings set \
    --name "$app_name" \
    --resource-group "$RESOURCE_GROUP" \
    --slot staging \
    --settings "${settings[@]}" \
    --only-show-errors >/dev/null

  local slot slot_args actual_issuer actual_audience actual_jwk
  for slot in production staging; do
    slot_args=()
    [ "$slot" = "staging" ] && slot_args=(--slot staging)
    actual_issuer="$(az webapp config appsettings list --name "$app_name" --resource-group "$RESOURCE_GROUP" "${slot_args[@]}" --query "[?name=='CENTINELA_ENTRA_ISSUER_URI'].value | [0]" -o tsv)"
    actual_audience="$(az webapp config appsettings list --name "$app_name" --resource-group "$RESOURCE_GROUP" "${slot_args[@]}" --query "[?name=='CENTINELA_ENTRA_AUDIENCE'].value | [0]" -o tsv)"
    actual_jwk="$(az webapp config appsettings list --name "$app_name" --resource-group "$RESOURCE_GROUP" "${slot_args[@]}" --query "[?name=='CENTINELA_ENTRA_JWK_SET_URI'].value | [0]" -o tsv)"
    [ "$actual_issuer" = "https://login.microsoftonline.com/${tenant_id}/v2.0" ] \
      || die "Issuer de $slot no quedo configurado."
    # Se compara contra el appId PELADO, que es lo que el bloque 'settings' de
    # arriba escribe. La version anterior comprobaba "api://${app_id}" y por tanto
    # abortaba SIEMPRE que existiera una Web App, con el mensaje "Audience no
    # quedo configurado" sobre un valor que si estaba escrito y era el correcto.
    # Quedo latente porque la topologia de contenedores no crea Web App y la
    # funcion retorna antes de llegar aqui.
    [ "$actual_audience" = "${app_id}" ] \
      || die "Audience de $slot quedo como '$actual_audience'; se esperaba el appId pelado."
    [ "$actual_jwk" = "https://login.microsoftonline.com/${tenant_id}/discovery/v2.0/keys" ] \
      || die "JWK URI de $slot no quedo configurado."
  done
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

  ensure_v2_tokens "$app_id"
  printf '%s' "$app_id"
}

# Fija requestedAccessTokenVersion=2. Descubierto en despliegue real, no en
# teoria: sin esto Entra emite tokens v1 cuyo issuer es sts.windows.net, mientras
# la API valida login.microsoftonline.com/<tenant>/v2.0 — todo token es rechazado
# con 401 y el mensaje no menciona versiones de token por ninguna parte.
#
# CONSECUENCIA QUE NO ES OBVIA: en tokens v2 el claim 'aud' es el appId PELADO,
# no 'api://<appId>'. La audiencia que la API debe validar cambia con esta
# decision. Quien configure CENTINELA_ENTRA_AUDIENCE debe usar el appId a secas.
ensure_v2_tokens() {
  local app_id="$1" object_id
  object_id="$(az ad app show --id "$app_id" --query id -o tsv)"
  with_retry 3 az rest --method patch \
    --url "https://graph.microsoft.com/v1.0/applications/${object_id}" \
    --body '{"api":{"requestedAccessTokenVersion":2}}' --output none
  log_info "Tokens de acceso v2 configurados (aud = appId pelado)."
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
  tmp_dir="$(mktemp -d)"; trap "rm -rf '$tmp_dir'" EXIT
  roles_file="$tmp_dir/app-roles.json"
  render_app_roles_json > "$roles_file"

  local app_id sp_id tenant_id
  app_id="$(ensure_app_registration "$display_name" "$roles_file")"
  [ -n "$app_id" ] || die "No se pudo obtener el appId."
  ensure_identifier_uri "$app_id"
  sp_id="$(ensure_service_principal "$app_id")"

  verify_app_roles "$app_id"
  tenant_id="$(az account show --query tenantId -o tsv)"
  configure_resource_server_settings "$app_id" "$tenant_id"

  # Registro sanitizado (sin secretos) para trazabilidad de RBAC posterior.
  local record="$SCRIPT_DIR/../docs/evidence/identity/entra-app.record.txt"
  if [ -d "$(dirname "$record")" ]; then
    # Los identificadores van ENMASCARADOS. No son secretos, pero la regla de la
    # celula (desde el hallazgo de ISS-S1-003, reincidente en Semana 3) es que
    # ningun GUID real se versiona: facilitan el reconocimiento del tenant y el
    # barrido scan-repository.sh los bloquea. La evidencia solo necesita poder
    # correlacionar, y '86c7…fd35' correlaciona igual que el valor completo.
    {
      printf 'appDisplayName=%s\n' "$display_name"
      printf 'appId=%s\n' "$(mask "$app_id")"
      printf 'servicePrincipalObjectId=%s\n' "$(mask "$sp_id")"
      printf 'appRoles=%s\n' "${APP_ROLES[*]}"
      printf 'issuerUri=https://login.microsoftonline.com/%s/v2.0\n' "$(mask "$tenant_id")"
      printf 'audience=api://%s\n' "$(mask "$app_id")"
      printf 'note=sin secreto de cliente; identificadores enmascarados por politica de evidencias\n'
    } > "$record"
    log_info "Registro sanitizado escrito: docs/evidence/identity/entra-app.record.txt"
  fi

  log_info "ISS-S1-006 (Entra) OK: App '$display_name' con 4 app roles y Service Principal."
  log_info "appId=$(mask "$app_id")  spObjectId=$(mask "$sp_id")"
  log_info "Siguiente paso: scripts/assign-rbac.sh (RBAC minimo de datos Blob a la Managed Identity)."
}

main "$@"
