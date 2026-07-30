#!/usr/bin/env bash
#
# scripts/assign-app-role.sh
# Concede uno de los app roles de la API a una identidad de aplicacion.
#
# POR QUE HACIA FALTA ESTE SCRIPT
# -------------------------------
# provision-entra-app.sh DEFINE los cuatro app roles (SERVICE, ANALYST,
# ADMINISTRATOR, AUDITOR) y crea el service principal que los expone. Definir un
# rol no lo concede a nadie: hasta que existe una asignacion, el claim 'roles'
# del token va vacio y la API responde 403 a todo. Nada en el arbol de scripts
# creaba esa asignacion, asi que el banco de pruebas —y cualquier otro cliente de
# servicio— se autenticaba correctamente contra Entra y era rechazado por
# Centinela sin motivo aparente. El fallo se presenta como un 403 despues de un
# login exitoso, que es el sintoma que peor apunta a su causa.
#
# POR QUE POR MICROSOFT GRAPH Y NO POR 'az role assignment'
# ---------------------------------------------------------
# No son la misma cosa y se confunden con facilidad. 'az role assignment' opera
# sobre RBAC de Azure: quien puede administrar o leer RECURSOS. Un app role vive
# en el directorio y describe que puede hacer un llamante DENTRO de una
# aplicacion. Ningun rol de RBAC sobre el grupo de recursos hace que un token
# lleve 'roles: [SERVICE]'. La asignacion se crea sobre
# /servicePrincipals/{id}/appRoleAssignedTo.
#
# ROLES DE APLICACION FRENTE A ROLES DE USUARIO
# ---------------------------------------------
# SERVICE es el unico con allowedMemberTypes=["Application"]: es el que puede
# concederse a una Managed Identity o a un service principal. ANALYST,
# ADMINISTRATOR y AUDITOR son de tipo "User" y se conceden a personas desde el
# portal (Enterprise Applications -> Users and groups). Este script rechaza la
# combinacion incoherente en vez de dejar que Graph devuelva un error opaco.
#
# Uso:
#   bash scripts/assign-app-role.sh --principal <object-id> [--role SERVICE]
#   bash scripts/assign-app-role.sh --identity id-cent-lab [--role SERVICE]
#
#   --principal  Object id (no el client id) del principal que recibe el rol.
#   --identity   Nombre de una Managed Identity del grupo; resuelve su principalId.
#   --role       Valor del app role. Por defecto SERVICE.
#   --revoke     Elimina la asignacion en lugar de crearla.
#
# Requiere permiso de directorio para leer y escribir asignaciones de app role
# (Application Administrator, Cloud Application Administrator o el propietario de
# la aplicacion).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

PRINCIPAL_ID=""
IDENTITY_NAME=""
ROLE_VALUE="SERVICE"
REVOKE=0

usage() { sed -n '3,45p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --principal) PRINCIPAL_ID="${2:?--principal requiere un object id}"; shift 2 ;;
    --identity)  IDENTITY_NAME="${2:?--identity requiere un nombre}"; shift 2 ;;
    --role)      ROLE_VALUE="${2:?--role requiere un valor}"; shift 2 ;;
    --revoke)    REVOKE=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) die "Argumento desconocido: $1. Usa --help." ;;
  esac
done

GRAPH="https://graph.microsoft.com/v1.0"

main() {
  load_parameters
  validate_parameters
  require_cmd az

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."

  [ -n "$PRINCIPAL_ID" ] || [ -n "$IDENTITY_NAME" ] \
    || die "Indica --principal <object-id> o --identity <nombre-de-managed-identity>."

  if [ -z "$PRINCIPAL_ID" ]; then
    PRINCIPAL_ID="$(az identity show -n "$IDENTITY_NAME" -g "$RESOURCE_GROUP" \
      --query principalId -o tsv 2>/dev/null || true)"
    [ -n "$PRINCIPAL_ID" ] \
      || die "No existe la Managed Identity '$IDENTITY_NAME' en '$RESOURCE_GROUP'."
    log_info "Identidad '$IDENTITY_NAME' -> principal $(mask "$PRINCIPAL_ID")"
  fi

  local display_name api_app_id resource_sp_id role_id
  display_name="${ENTRA_APP_DISPLAY_NAME:-${NAME_PREFIX}-api-week1}"

  api_app_id="$(az ad app list --display-name "$display_name" --query '[0].appId' -o tsv 2>/dev/null || true)"
  [ -n "$api_app_id" ] && [ "$api_app_id" != "None" ] \
    || die "No existe el registro '$display_name'. Ejecuta provision-entra-app.sh primero."

  # El destino de la asignacion es el SERVICE PRINCIPAL de la API, no la
  # aplicacion: los app roles se conceden sobre la instancia del directorio.
  resource_sp_id="$(az ad sp list --filter "appId eq '$api_app_id'" --query '[0].id' -o tsv 2>/dev/null || true)"
  [ -n "$resource_sp_id" ] && [ "$resource_sp_id" != "None" ] \
    || die "El registro '$display_name' no tiene service principal. Ejecuta provision-entra-app.sh."

  role_id="$(az ad app show --id "$api_app_id" \
    --query "appRoles[?value=='$ROLE_VALUE' && isEnabled].id | [0]" -o tsv 2>/dev/null || true)"
  [ -n "$role_id" ] && [ "$role_id" != "None" ] \
    || die "El app role '$ROLE_VALUE' no existe o esta deshabilitado en '$display_name'."

  assert_role_admits_applications "$api_app_id"

  log_info "Plan:"
  log_info "  Aplicacion destino : $display_name"
  log_info "  App role           : $ROLE_VALUE"
  log_info "  Principal          : $(mask "$PRINCIPAL_ID")"
  log_info "  Operacion          : $([ "$REVOKE" -eq 1 ] && echo revocar || echo conceder)"

  local existing
  existing="$(find_assignment "$resource_sp_id" "$role_id")"

  if [ "$REVOKE" -eq 1 ]; then
    revoke_assignment "$resource_sp_id" "$existing"
  else
    grant_assignment "$resource_sp_id" "$role_id" "$existing"
  fi
}

# Un app role de tipo "User" concedido a una aplicacion falla en Graph con un
# mensaje que no menciona allowedMemberTypes. Se comprueba antes para poder
# explicar el motivo real y el camino correcto.
assert_role_admits_applications() {
  local api_app_id="$1" tipos
  tipos="$(az ad app show --id "$api_app_id" \
    --query "appRoles[?value=='$ROLE_VALUE'].allowedMemberTypes | [0]" -o json 2>/dev/null || echo '[]')"
  if ! printf '%s' "$tipos" | grep -q 'Application'; then
    log_error "El app role '$ROLE_VALUE' solo admite miembros de tipo User ($tipos)."
    log_error "Un rol de usuario no puede concederse a una Managed Identity."
    die "Concede '$ROLE_VALUE' a una persona desde Entra ID -> Enterprise applications -> Users and groups."
  fi
}

# Devuelve el id de la asignacion existente, o vacio. Idempotencia: repetir el
# script no debe crear una segunda asignacion equivalente.
find_assignment() {
  local resource_sp_id="$1" role_id="$2"
  az rest --method get \
    --url "${GRAPH}/servicePrincipals/${resource_sp_id}/appRoleAssignedTo" \
    --query "value[?principalId=='${PRINCIPAL_ID}' && appRoleId=='${role_id}'].id | [0]" \
    -o tsv 2>/dev/null | grep -v '^None$' || true
}

grant_assignment() {
  local resource_sp_id="$1" role_id="$2" existing="$3"

  if [ -n "$existing" ]; then
    log_info "La asignacion ya existe (id $(mask "$existing")). Nada que hacer."
    verify_assignment "$resource_sp_id" "$role_id"
    return 0
  fi

  log_info "Creando la asignacion de app role..."
  local body salida codigo
  body="$(printf '{"principalId":"%s","resourceId":"%s","appRoleId":"%s"}' \
    "$PRINCIPAL_ID" "$resource_sp_id" "$role_id")"

  set +e
  salida="$(az rest --method post \
    --url "${GRAPH}/servicePrincipals/${resource_sp_id}/appRoleAssignedTo" \
    --headers 'Content-Type=application/json' \
    --body "$body" --output none 2>&1)"
  codigo=$?
  set -e

  if [ "$codigo" -ne 0 ]; then
    # Una identidad recien creada tarda en propagarse al directorio y Graph
    # responde que el principal no existe. Es una carrera, no un error de datos.
    if printf '%s' "$salida" | grep -qi 'does not exist\|not found\|ResourceNotFound'; then
      log_warn "El principal aun no ha propagado en el directorio; reintentando..."
      sleep 20
      set +e
      salida="$(az rest --method post \
        --url "${GRAPH}/servicePrincipals/${resource_sp_id}/appRoleAssignedTo" \
        --headers 'Content-Type=application/json' \
        --body "$body" --output none 2>&1)"
      codigo=$?
      set -e
    fi
  fi

  if [ "$codigo" -ne 0 ]; then
    if printf '%s' "$salida" | grep -qi 'Permission being assigned already exists\|already exists'; then
      log_info "La asignacion ya existia."
    else
      log_error "No se pudo conceder '$ROLE_VALUE'. Error real de Graph:"
      printf '%s\n' "$salida" | head -5 >&2
      log_error "Causa habitual: la cuenta que ejecuta no tiene rol de directorio para"
      log_error "escribir asignaciones. Necesita Application Administrator, Cloud"
      log_error "Application Administrator, o ser propietario de la aplicacion."
      die "Sin la asignacion, el token del cliente llega sin 'roles' y la API responde 403."
    fi
  fi

  verify_assignment "$resource_sp_id" "$role_id"
}

revoke_assignment() {
  local resource_sp_id="$1" existing="$2"
  if [ -z "$existing" ]; then
    log_info "No hay asignacion que revocar."
    return 0
  fi
  log_info "Revocando la asignacion $(mask "$existing")..."
  az rest --method delete \
    --url "${GRAPH}/servicePrincipals/${resource_sp_id}/appRoleAssignedTo/${existing}" \
    --output none
  log_info "Asignacion revocada."
}

# No se confia en el codigo de salida del POST: se vuelve a consultar el
# directorio. Un 201 sobre un objeto que despues no aparece es exactamente el
# tipo de exito aparente que hace perder una tarde.
verify_assignment() {
  local resource_sp_id="$1" role_id="$2" found
  found="$(find_assignment "$resource_sp_id" "$role_id")"
  [ -n "$found" ] || die "La asignacion no aparece en el directorio tras crearla."
  log_info "Verificado: el principal tiene el app role '$ROLE_VALUE' sobre la API."
  log_info "Su proximo token para esta API llevara el claim roles=[\"$ROLE_VALUE\"]."
  # El token en curso no cambia: Entra lo emitio antes de existir la asignacion y
  # sigue siendo valido hasta que caduque. Decirlo evita el diagnostico erroneo de
  # "la asignacion no funciono" durante la primera hora.
  log_warn "Un token ya emitido NO adquiere el rol: hay que pedir uno nuevo."
}

main "$@"
