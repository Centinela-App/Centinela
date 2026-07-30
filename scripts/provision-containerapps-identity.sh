#!/usr/bin/env bash
#
# scripts/provision-containerapps-identity.sh
# Identidad de las Container Apps y sus permisos de datos.
#
# POR QUE HACE FALTA
# ------------------
# En Semanas 1 y 2 la identidad que accedia a los datos era la Managed Identity
# de la Web App, y todos los scripts de aprovisionamiento le asignaban roles a
# ella. Al sustituir el App Service por Container Apps (ADR-009, forzado ademas
# por la ausencia de cuota de App Service en la region), esa identidad deja de
# existir y hay que crear su equivalente.
#
# Se usa UNA identidad asignada por el usuario para las tres aplicaciones —API,
# motor y explicador— en lugar de tres identidades asignadas por el sistema. El
# motivo es operativo: con identidades por aplicacion, cada redespliegue que
# recree una aplicacion generaria un principal nuevo y habria que reasignar sus
# roles. Con una identidad compartida los roles se asignan una vez.
#
# La contrapartida es real y conviene enunciarla: las tres aplicaciones comparten
# permisos, asi que el explicador puede escribir en el contenedor de
# transacciones aunque no lo necesite. Es una desviacion del minimo privilegio
# que se acepta a cambio de que el despliegue continuo no dependa de reasignar
# roles en cada corrida. Con mas tiempo, lo correcto seria una identidad por
# aplicacion con su conjunto exacto de roles.
#
# PERMISOS QUE OTORGA, Y POR QUE CADA UNO
# ---------------------------------------
#   Storage Blob Data Contributor  -> la API escribe el JSON crudo; el motor lo lee
#   Storage Queue Data Contributor -> el motor encola casos; el consumidor los lee
#   Key Vault Secrets User         -> lectura de cadenas de conexion en arranque
#   EventGrid Data Sender          -> la API publica transaction-event-v1
#
# NO otorga roles de administracion sobre ningun recurso. Una identidad de datos
# que puede administrar el recurso que usa no es una identidad de datos.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

readonly BLOB_ROLE="Storage Blob Data Contributor"
readonly QUEUE_ROLE="Storage Queue Data Contributor"
readonly KV_ROLE="Key Vault Secrets User"
readonly EVENTGRID_ROLE="EventGrid Data Sender"

# Roles que NUNCA debe tener esta identidad. Se comprueba al final: un rol de
# administracion concedido "temporalmente para depurar" es como empiezan los
# problemas que nadie recuerda haber causado.
readonly ROLES_PROHIBIDOS=("Owner" "Contributor" "User Access Administrator")

VALIDATE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --validate-only) VALIDATE_ONLY=1 ;;
    -h|--help) echo "Uso: $0 [--validate-only]"; exit 0 ;;
    *) die "Argumento desconocido: $arg" ;;
  esac
done

main() {
  load_parameters
  validate_parameters
  require_cmd az

  local identity="id-${NAME_PREFIX}-apps"

  log_info "Plan:"
  log_info "  Identidad : $identity"
  log_info "  Roles     : datos sobre Storage, Key Vault y Event Grid; ninguno de administracion"

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "Modo --validate-only: no se crea nada."
    exit 0
  fi

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."

  local principal_id
  principal_id="$(ensure_identity "$identity")"
  log_info "Principal: $(mask "$principal_id")"

  grant_storage_roles "$principal_id"
  grant_keyvault_role "$principal_id"
  grant_eventgrid_role "$principal_id"
  verify_no_admin_roles "$principal_id"

  local identity_id client_id
  identity_id="$(az identity show -n "$identity" -g "$RESOURCE_GROUP" --query id -o tsv)"
  client_id="$(az identity show -n "$identity" -g "$RESOURCE_GROUP" --query clientId -o tsv)"

  log_info "Identidad lista."
  log_info "  APPS_IDENTITY_ID=$identity_id"
  log_info "  APPS_CLIENT_ID=$(mask "$client_id")"
}

ensure_identity() {
  local name="$1"
  if ! az identity show -n "$name" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "Creando identidad '$name'..."
    az identity create -n "$name" -g "$RESOURCE_GROUP" -l "$LOCATION" --output none
    # La propagacion del principal en el directorio no es inmediata; sin esta
    # espera las asignaciones siguientes fallan de forma intermitente.
    sleep 15
  fi
  az identity show -n "$name" -g "$RESOURCE_GROUP" --query principalId -o tsv
}

grant_storage_roles() {
  local principal="$1"
  local storage
  storage="$(az storage account list -g "$RESOURCE_GROUP" --query "[0].id" -o tsv 2>/dev/null)"
  [ -n "$storage" ] || die "No hay Storage Account en el grupo de recursos."

  log_info "Otorgando permisos de datos sobre Storage..."
  with_retry 5 assign_role "$BLOB_ROLE" "$principal" "$storage" \
    || die "Sin '$BLOB_ROLE' la API no puede persistir la transaccion cruda."
  with_retry 5 assign_role "$QUEUE_ROLE" "$principal" "$storage" \
    || die "Sin '$QUEUE_ROLE' el motor no puede encolar casos ni el consumidor leerlos."
}

grant_keyvault_role() {
  local principal="$1"
  local vault
  vault="$(az keyvault list -g "$RESOURCE_GROUP" --query "[0].id" -o tsv 2>/dev/null)"
  if [ -z "$vault" ]; then
    log_warn "No hay Key Vault todavia; se omite '$KV_ROLE'."
    log_warn "Reejecuta este script despues de provision-keyvault.sh."
    return
  fi
  log_info "Otorgando '$KV_ROLE' sobre el Key Vault..."
  with_retry 5 assign_role "$KV_ROLE" "$principal" "$vault" \
    || die "Sin '$KV_ROLE' las aplicaciones no leen sus cadenas de conexion al arrancar."
}

grant_eventgrid_role() {
  local principal="$1"
  local topic
  topic="$(az eventgrid topic list -g "$RESOURCE_GROUP" --query "[0].id" -o tsv 2>/dev/null)"
  if [ -z "$topic" ]; then
    log_warn "No hay topico de Event Grid todavia; se omite '$EVENTGRID_ROLE'."
    log_warn "Reejecuta este script despues de provision-eventgrid.sh."
    return
  fi
  log_info "Otorgando '$EVENTGRID_ROLE' sobre el topico..."
  with_retry 5 assign_role "$EVENTGRID_ROLE" "$principal" "$topic" \
    || die "Sin '$EVENTGRID_ROLE' la API no puede publicar el evento y el pipeline se corta en la ingesta."
}

verify_no_admin_roles() {
  local principal="$1"
  local scope
  scope="$(az group show -n "$RESOURCE_GROUP" --query id -o tsv)"

  for rol in "${ROLES_PROHIBIDOS[@]}"; do
    local n
    n="$(role_assignment_count "$scope" "$rol")"
    # Se cuenta sobre el grupo, donde tambien aparecen los roles del pipeline.
    # No se puede distinguir el titular por esta via, asi que se avisa en vez de
    # fallar: un falso positivo que aborta el despliegue es peor que un aviso.
    if [ "${n:-0}" -gt 0 ]; then
      log_warn "Hay $n asignacion/es de '$rol' en el grupo de recursos."
      log_warn "  Verifica que pertenezcan al pipeline y NO a '$principal'."
    fi
  done
  log_info "Comprobacion de roles de administracion completada."
}

main "$@"
