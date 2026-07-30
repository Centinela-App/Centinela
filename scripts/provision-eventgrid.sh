#!/usr/bin/env bash
#
# scripts/provision-eventgrid.sh
# ISS-S2-005 - Provisionar Event Grid Topic + cola de casos + RBAC de mensajeria.
#
# Alcance ESTRICTO de la Issue (FEAT-S2-003, mensajeria desacoplada):
#   - Crear/asegurar 1 Event Grid Topic (custom topic) para 'transaction-event'
#     (idempotente, nombre determinista por ambiente).
#   - Crear/asegurar las colas de casos 'flagged-cases-{staging,production}' en la
#     Storage Account de Semana 1 (control plane / ARM, idempotente).
#   - Asignar RBAC de MINIMO PRIVILEGIO de mensajeria:
#       * "EventGrid Data Sender" a la Managed Identity de la Web App (prod + slot
#         staging) SOBRE EL TOPICO -> habilita a la API a publicar (ISS-S2-006).
#       * (opcional) "Storage Queue Data Message Sender" a la identidad de la
#         Function sobre las colas de casos (encolar; ISS-S2-009).
#       * "Storage Queue Data Message Processor" a las identidades de la Web App
#         sobre su cola de ambiente (procesar; ISS-S2-011).
#   - Aplicar tags de trazabilidad. Idempotente: reejecutar converge sin duplicar.
#
# FUERA de alcance (no lo hace este script, por diseno):
#   - La SUSCRIPCION del topico -> la crea quien conecta la Function (ISS-S2-007),
#     para evitar dependencia circular.
#   - Publicar el evento desde la API (ISS-S2-006).
#   - El consumidor de negocio de la cola (ISS-S2-011) ni la logica de scoring.
#
# Regla dura de minimo privilegio: NUNCA asigna Owner/Contributor/User Access
# Administrator (guard explicito).
#
# Uso:
#   scripts/provision-eventgrid.sh
#     [--function-principal <objectId>]  -> Queue Data Message Sender (colas de casos)
#     [--consumer-principal <objectId>]  -> Queue Data Message Processor (colas de casos)
#
# Prerequisitos (validados al inicio):
#   - Azure CLI disponible (Azure Cloud Shell), sesion activa y suscripcion correcta.
#   - Resource Group y Storage Account de Semana 1 ya creados (ISS-S1-001/003).
#   - Web App con Managed Identity de Semana 1 (ISS-S1-004) para el rol de publicar.
#
# Variables (ver scripts/lib/parameters.sh):
#   SUBSCRIPTION_ID, LOCATION, RESOURCE_GROUP, NAME_PREFIX, APP_SERVICE_SKU

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/parameters.sh"

# --- Constantes de la Issue ----------------------------------------------------

readonly SLOT_NAME="staging"
readonly EVENT_TYPE="transaction-event"

# Colas de casos DEDICADAS (se separa de la cola de ingesta de Semana 1 para no
# mezclar propositos; ver docs/2_Arquitectura/6_Mensajeria_Eventos_vs_Colas.md).
readonly CASE_QUEUES=(
  "flagged-cases-staging"
  "flagged-cases-production"
)

# Roles de datos de mensajeria (minimo privilegio; NO son roles de administracion).
readonly EVENTGRID_SENDER_ROLE="EventGrid Data Sender"
readonly QUEUE_SENDER_ROLE="Storage Queue Data Message Sender"
readonly QUEUE_PROCESSOR_ROLE="Storage Queue Data Message Processor"
readonly FORBIDDEN_ROLES=("Owner" "Contributor" "User Access Administrator")

readonly TAGS=(
  "project=centinela"
  "week=2"
  "team=celula-centinela"
  "issue=ISS-S2-005"
)

FUNCTION_PRINCIPAL=""
CONSUMER_PRINCIPAL=""
# Semana 3: en la topologia de Container Apps no existe la Web App, asi que el
# publicador tambien se pasa explicito (la identidad compartida id-<prefijo>-apps).
PUBLISHER_PRINCIPAL=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --function-principal)  FUNCTION_PRINCIPAL="${2:?}"; shift 2 ;;
    --consumer-principal)  CONSUMER_PRINCIPAL="${2:?}"; shift 2 ;;
    --publisher-principal) PUBLISHER_PRINCIPAL="${2:?}"; shift 2 ;;
    -h|--help)
      echo "Uso: $0 [--function-principal ID] [--consumer-principal ID] [--publisher-principal ID]"; exit 0 ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

# --- Helpers de nombrado (deterministas, iguales a ISS-S1-003/004/006) ---------

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
# Topico de Event Grid: 3-50 chars, [a-zA-Z0-9-]. Determinista por ambiente.
compute_eventgrid_topic_name() {
  local prefix="$1" sub_id="$2" rg="$3" hash
  hash="$(printf '%s|%s|%s' "$prefix" "$sub_id" "$rg" | sha1sum | cut -c1-6)"
  printf '%s-egt-%s' "$prefix" "$hash"
}

# --- Guard de minimo privilegio ------------------------------------------------

assert_not_forbidden_role() {
  local role="$1" f
  for f in "${FORBIDDEN_ROLES[@]}"; do
    if [ "$role" = "$f" ]; then
      die "REGLA DURA violada: intento de asignar rol prohibido '$role'."
    fi
  done
  # 'return 0' explicito: sin el, el ultimo '[ ... ]' falso deja estado 1 y
  # 'set -e' aborta el script en silencio al validar un rol permitido.
  return 0
}

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

# --- Event Grid Topic (control plane, idempotente) -----------------------------

ensure_eventgrid_topic() {
  local topic="$1" rg="$2"
  if az eventgrid topic show --name "$topic" --resource-group "$rg" >/dev/null 2>&1; then
    log_info "Event Grid Topic '$topic' ya existe. Sin cambios."
  else
    log_info "Creando Event Grid Topic '$topic' para '$EVENT_TYPE'..."
    with_retry 3 az eventgrid topic create \
      --name "$topic" \
      --resource-group "$rg" \
      --location "$LOCATION" \
      --tags "${TAGS[@]}" \
      >/dev/null
    log_info "Event Grid Topic creado."
  fi
}

# --- Colas de casos (control plane / ARM, idempotente) -------------------------

render_queues_arm_template() {
  local queues_json
  queues_json="$(printf '"%s",' "${CASE_QUEUES[@]}" | sed 's/,$//')"
  cat <<JSON
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "storageAccountName": { "type": "string", "minLength": 3, "maxLength": 24 }
  },
  "variables": {
    "queues": [ ${queues_json} ]
  },
  "resources": [
    {
      "type": "Microsoft.Storage/storageAccounts/queueServices/queues",
      "apiVersion": "2023-01-01",
      "name": "[concat(parameters('storageAccountName'), '/default/', variables('queues')[copyIndex('caseQueuesCopy')])]",
      "copy": {
        "name": "caseQueuesCopy",
        "count": "[length(variables('queues'))]"
      },
      "properties": {}
    }
  ]
}
JSON
}

ensure_case_queues() {
  local sa_name="$1" rg="$2"
  log_info "Asegurando colas de casos: ${CASE_QUEUES[*]}"
  local tmp_dir template_file
  tmp_dir="$(mktemp -d)"
  trap "rm -rf '$tmp_dir'" RETURN
  template_file="$tmp_dir/case-queues.template.json"
  render_queues_arm_template > "$template_file"
  with_retry 3 az deployment group create \
    --resource-group "$rg" \
    --template-file "$template_file" \
    --parameters storageAccountName="$sa_name" \
    --name "iss-s2-005-case-queues" \
    >/dev/null
  log_info "Colas de casos aseguradas."
}

# --- RBAC de mensajeria --------------------------------------------------------

assign_publisher_roles() {
  local topic_id="$1" app_name="$2" rg="$3"

  # Topologia de Semana 3: el publicador es la identidad de las Container Apps,
  # pasada explicitamente. La Web App puede no existir y no es un error.
  if [ -n "$PUBLISHER_PRINCIPAL" ]; then
    log_info "Asignando '$EVENTGRID_SENDER_ROLE' al publicador explicito..."
    assign_role_scope "$PUBLISHER_PRINCIPAL" "ServicePrincipal" "$EVENTGRID_SENDER_ROLE" "$topic_id"
    return
  fi

  local prod_pid staging_pid
  prod_pid="$(az webapp identity show --name "$app_name" --resource-group "$rg" \
    --query principalId -o tsv 2>/dev/null || true)"
  staging_pid="$(az webapp identity show --name "$app_name" --resource-group "$rg" \
    --slot "$SLOT_NAME" --query principalId -o tsv 2>/dev/null || true)"
  [ -n "$prod_pid" ]    || die "Web App de produccion sin Managed Identity (ISS-S1-004). En la topologia de contenedores, pasa --publisher-principal."
  [ -n "$staging_pid" ] || die "Slot staging sin Managed Identity (ISS-S1-004)."

  log_info "Asignando '$EVENTGRID_SENDER_ROLE' a la MI de la Web App (publicar evento)..."
  assign_role_scope "$prod_pid"    "ServicePrincipal" "$EVENTGRID_SENDER_ROLE" "$topic_id"
  assign_role_scope "$staging_pid" "ServicePrincipal" "$EVENTGRID_SENDER_ROLE" "$topic_id"
}

assign_queue_roles() {
  local sa_id="$1" app_name="$2" rg="$3" q scope prod_pid staging_pid
  if [ -n "$FUNCTION_PRINCIPAL" ]; then
    log_info "Asignando '$QUEUE_SENDER_ROLE' a la Function sobre las colas de casos..."
    for q in "${CASE_QUEUES[@]}"; do
      scope="${sa_id}/queueServices/default/queues/${q}"
      assign_role_scope "$FUNCTION_PRINCIPAL" "ServicePrincipal" "$QUEUE_SENDER_ROLE" "$scope"
    done
  else
    # Si la Function ya existe (redespliegue), se resuelve su identidad aqui en vez
    # de avisar de un diferimiento que no corresponde: el mensaje fijo afirmaba
    # "aun no existe" incluso con la Function desplegada y confundia al leer el log.
    local fn_name fn_pid
    fn_name="${SCORING_FUNCTION_APP_NAME:-$(printf '%s-scoring-fn-%s' "$NAME_PREFIX" "$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)")}"
    fn_pid="$(az functionapp identity show --name "$fn_name" --resource-group "$RESOURCE_GROUP" \
      --query principalId -o tsv 2>/dev/null || true)"
    if [ -n "$fn_pid" ]; then
      log_info "Function '$fn_name' ya existe: asignando '$QUEUE_SENDER_ROLE' sobre las colas..."
      for q in "${CASE_QUEUES[@]}"; do
        scope="${sa_id}/queueServices/default/queues/${q}"
        assign_role_scope "$fn_pid" "ServicePrincipal" "$QUEUE_SENDER_ROLE" "$scope"
      done
    else
      log_info "La Function aun no existe; su rol de encolado se aplicara en ISS-S2-007/009."
    fi
  fi

  if [ -n "$CONSUMER_PRINCIPAL" ]; then
    log_info "Asignando '$QUEUE_PROCESSOR_ROLE' al consumidor explicito sobre ambas colas..."
    for q in "${CASE_QUEUES[@]}"; do
      scope="${sa_id}/queueServices/default/queues/${q}"
      assign_role_scope "$CONSUMER_PRINCIPAL" "ServicePrincipal" "$QUEUE_PROCESSOR_ROLE" "$scope"
    done
  else
    prod_pid="$(az webapp identity show --name "$app_name" --resource-group "$rg" \
      --query principalId -o tsv 2>/dev/null || true)"
    staging_pid="$(az webapp identity show --name "$app_name" --resource-group "$rg" \
      --slot "$SLOT_NAME" --query principalId -o tsv 2>/dev/null || true)"
    [ -n "$prod_pid" ] || die "Web App de produccion sin Managed Identity para consumir Queue."
    [ -n "$staging_pid" ] || die "Slot staging sin Managed Identity para consumir Queue."

    log_info "Asignando '$QUEUE_PROCESSOR_ROLE' por ambiente..."
    assign_role_scope "$prod_pid" "ServicePrincipal" "$QUEUE_PROCESSOR_ROLE" \
      "${sa_id}/queueServices/default/queues/flagged-cases-production"
    assign_role_scope "$staging_pid" "ServicePrincipal" "$QUEUE_PROCESSOR_ROLE" \
      "${sa_id}/queueServices/default/queues/flagged-cases-staging"
  fi
}

wire_topic_endpoint() {
  local topic="$1" rg="$2" app_name="$3" endpoint
  endpoint="$(az eventgrid topic show --name "$topic" --resource-group "$rg" --query endpoint -o tsv)"
  [ -n "$endpoint" ] || die "No se pudo resolver el endpoint del topico '$topic'."

  # Sin Web App no hay app settings que escribir: en la topologia de contenedores
  # el endpoint viaja como variable de entorno de la Container App en su despliegue.
  if ! az webapp show --name "$app_name" --resource-group "$rg" >/dev/null 2>&1; then
    log_warn "Web App '$app_name' no existe; el endpoint se inyecta al desplegar las Container Apps:"
    log_warn "  CENTINELA_EVENTGRID_TOPIC_ENDPOINT=$endpoint"
    return 0
  fi

  log_info "Configurando CENTINELA_EVENTGRID_TOPIC_ENDPOINT en produccion y staging..."
  with_retry 3 az webapp config appsettings set --name "$app_name" --resource-group "$rg" \
    --settings "CENTINELA_EVENTGRID_TOPIC_ENDPOINT=$endpoint" --output none
  with_retry 3 az webapp config appsettings set --name "$app_name" --resource-group "$rg" \
    --slot "$SLOT_NAME" --settings "CENTINELA_EVENTGRID_TOPIC_ENDPOINT=$endpoint" --output none
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

  local sa_name app_name topic_name sa_id topic_id
  sa_name="$(compute_storage_account_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  app_name="$(compute_web_app_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"
  topic_name="$(compute_eventgrid_topic_name "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP")"

  sa_id="$(az storage account show --name "$sa_name" --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv 2>/dev/null || true)"
  [ -n "$sa_id" ] || die "El Storage '$sa_name' no existe (ISS-S1-003)."

  log_info "Topico objetivo: $topic_name | Storage: $sa_name"

  # 1) Event Grid Topic (notifica la ocurrencia; la API no espera).
  ensure_eventgrid_topic "$topic_name" "$RESOURCE_GROUP"
  topic_id="$(az eventgrid topic show --name "$topic_name" --resource-group "$RESOURCE_GROUP" \
    --query id -o tsv)"

  # 2) Colas de casos (garantizan el procesamiento aunque el consumidor este caido).
  ensure_case_queues "$sa_name" "$RESOURCE_GROUP"
  wire_topic_endpoint "$topic_name" "$RESOURCE_GROUP" "$app_name"

  # 3) RBAC de minimo privilegio.
  assign_publisher_roles "$topic_id" "$app_name" "$RESOURCE_GROUP"
  assign_queue_roles "$sa_id" "$app_name" "$RESOURCE_GROUP"

  log_info "NOTA: la SUSCRIPCION del topico NO se crea aqui; la conecta la Function en ISS-S2-007 (evita dependencia circular)."
  log_info "ISS-S2-005 OK: Event Grid Topic + ${#CASE_QUEUES[@]} colas de casos + RBAC de mensajeria listos."
}

main "$@"
