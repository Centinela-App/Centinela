#!/usr/bin/env bash
#
# scripts/deploy-containers.sh
# ISS-S3-008 / ISS-S3-012 — Crea o actualiza las tres Container Apps.
#
# Lo invoca el pipeline de despliegue continuo tras publicar las imagenes, y
# tambien puede ejecutarse a mano para reconstruir el entorno desde cero. Es
# idempotente: la primera corrida crea, las siguientes actualizan la imagen.
#
# Las tres aplicaciones salen de DOS imagenes:
#   - centinela-api        (imagen de la aplicacion, papel: API + consulta)
#   - centinela-explainer  (misma imagen, papel: explicador + extractor documental)
#   - centinela-scoring    (imagen del motor de scoring)
#
# Que el explicador sea la misma imagen con otros interruptores es lo que hace
# trivial el escenario de fallo obligatorio de la sustentacion: detenerlo es
# `az containerapp update --min-replicas 0 --max-replicas 0`, sin tocar la API.
#
# NINGUN secreto viaja en este script. Las cadenas de conexion se referencian
# desde Key Vault mediante la identidad administrada de cada aplicacion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

IMAGE_TAG="${IMAGE_TAG:-latest}"

readonly API_CONCURRENT_REQUESTS="${CENTINELA_API_CONCURRENCY:-10}"
readonly API_MIN_REPLICAS="${CENTINELA_API_MIN_REPLICAS:-1}"
readonly API_MAX_REPLICAS="${CENTINELA_API_MAX_REPLICAS:-10}"
readonly SCORING_MIN_REPLICAS="${CENTINELA_SCORING_MIN_REPLICAS:-0}"
readonly SCORING_MAX_REPLICAS="${CENTINELA_SCORING_MAX_REPLICAS:-8}"
readonly EXPLAINER_MIN_REPLICAS="${CENTINELA_EXPLAINER_MIN_REPLICAS:-0}"
readonly EXPLAINER_MAX_REPLICAS="${CENTINELA_EXPLAINER_MAX_REPLICAS:-3}"
readonly CPU_PER_REPLICA="0.5"
readonly MEMORY_PER_REPLICA="1.0Gi"

usage() {
  cat <<'EOF'
Uso: deploy-containers.sh [--tag <etiqueta>] [--only api|scoring|explainer]

  --tag        Etiqueta de imagen a desplegar (por defecto: $IMAGE_TAG o 'latest').
  --only       Despliega una sola aplicacion.
EOF
}

ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) IMAGE_TAG="${2:?--tag requiere valor}"; shift 2 ;;
    --only) ONLY="${2:?--only requiere valor}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

main() {
  load_parameters
  validate_parameters
  require_cmd az

  local environment_name="cae-${NAME_PREFIX}"
  local registry_name="${NAME_PREFIX}acr"
  local identity_name="id-${NAME_PREFIX}-acrpull"

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa."

  local registry_server identity_id
  registry_server="$(az acr show -n "$registry_name" -g "$RESOURCE_GROUP" --query loginServer -o tsv)" \
    || die "Falta el registro. Ejecuta provision-container-registry.sh."
  identity_id="$(az identity show -n "$identity_name" -g "$RESOURCE_GROUP" --query id -o tsv)" \
    || die "Falta la identidad de pull."

  az containerapp env show -g "$RESOURCE_GROUP" -n "$environment_name" >/dev/null 2>&1 \
    || die "Falta el entorno '$environment_name'. Ejecuta provision-container-apps.sh."

  resolve_runtime_configuration

  log_info "Desplegando etiqueta '$IMAGE_TAG' desde $registry_server"

  [ -z "$ONLY" ] || [ "$ONLY" = "api" ] \
    && deploy_api "$environment_name" "$registry_server" "$identity_id"
  [ -z "$ONLY" ] || [ "$ONLY" = "scoring" ] \
    && deploy_scoring "$environment_name" "$registry_server" "$identity_id"
  [ -z "$ONLY" ] || [ "$ONLY" = "explainer" ] \
    && deploy_explainer "$environment_name" "$registry_server" "$identity_id"

  log_info "Despliegue completado."
}

# --- Configuracion de ejecucion ----------------------------------------------
#
# Todos los nombres se derivan del mismo hash determinista que usan los scripts
# de aprovisionamiento (prefijo|suscripcion|grupo): no hay nada que copiar a
# mano entre scripts, y por tanto nada que pueda copiarse mal.
resolve_runtime_configuration() {
  local hash
  hash="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)"

  STORAGE_ACCOUNT="${NAME_PREFIX}st${hash}"
  PG_HOST="${NAME_PREFIX}-pg-${hash}.postgres.database.azure.com"
  KEY_VAULT="${NAME_PREFIX}-kv-${hash}"
  EVENTGRID_TOPIC="${NAME_PREFIX}-egt-${hash}"

  APPS_IDENTITY_ID="$(az identity show -n "id-${NAME_PREFIX}-apps" -g "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null)" \
    || die "Falta la identidad de datos. Ejecuta provision-containerapps-identity.sh."
  # AZURE_CLIENT_ID selecciona QUE identidad usa DefaultAzureCredential y el
  # plugin JDBC cuando el contenedor tiene mas de una asignada. Sin el, la
  # eleccion es ambigua y el fallo es un 403 intermitente dificil de rastrear.
  APPS_CLIENT_ID="$(az identity show -n "id-${NAME_PREFIX}-apps" -g "$RESOURCE_GROUP" --query clientId -o tsv)"

  EVENTGRID_ENDPOINT="$(az eventgrid topic show -n "$EVENTGRID_TOPIC" -g "$RESOURCE_GROUP" --query endpoint -o tsv 2>/dev/null)" \
    || die "Falta el topico de Event Grid. Ejecuta provision-eventgrid.sh."

  INSIGHTS_CONNECTION="$(az monitor app-insights component show -g "$RESOURCE_GROUP" -a "appi-${NAME_PREFIX}" \
    --query connectionString -o tsv 2>/dev/null || true)"
  [ -n "$INSIGHTS_CONNECTION" ] || log_warn "Sin Application Insights: se despliega sin telemetria de agente."

  # Del registro de Entra solo hacen falta el appId y el tenant; el secreto de
  # Cosmos se referencia desde Key Vault y nunca pasa por este script.
  #
  # CENTINELA_ENTRA_APP_ID permite fijarlo por entorno: el service principal del
  # pipeline puede no tener permiso de lectura sobre Microsoft Graph, y 'az ad
  # app list' fallaria alli aunque el appId sea un identificador publico que el
  # pipeline puede recibir como variable sin comprometer nada.
  ENTRA_APP_ID="${CENTINELA_ENTRA_APP_ID:-$(az ad app list --display-name "${NAME_PREFIX}-api-week1" --query '[0].appId' -o tsv 2>/dev/null)}"
  [ -n "$ENTRA_APP_ID" ] && [ "$ENTRA_APP_ID" != "null" ] \
    || die "Falta el registro '${NAME_PREFIX}-api-week1'. Ejecuta provision-entra-app.sh, o define CENTINELA_ENTRA_APP_ID."
  # La audiencia que la API valida es el appId PELADO: con tokens v2
  # (requestedAccessTokenVersion=2, fijado por provision-entra-app.sh) el claim
  # 'aud' no lleva el prefijo 'api://'. Validar contra la forma con prefijo
  # rechaza todo token con un 401 que no menciona el motivo — se descubrio en
  # despliegue real, no en teoria.
  TENANT_ID="$(az account show --query tenantId -o tsv)"

  COSMOS_SECRET_URI="https://${KEY_VAULT}.vault.azure.net/secrets/cosmos-mongo-connection-string"
  PG_JDBC_URL="jdbc:postgresql://${PG_HOST}:5432/centinela?sslmode=require&authenticationPluginClassName=com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin"
}

# --- API de ingesta y consulta ----------------------------------------------
deploy_api() {
  local environment="$1" registry="$2" identity="$3"
  local app="ca-${NAME_PREFIX}-api"
  local image="${registry}/centinela-api:${IMAGE_TAG}"

  # Un solo juego de variables para create Y update: si solo se fijaran en el
  # create, cambiar la configuracion (audiencia, endpoint, umbral) exigiria
  # borrar y recrear la app — y el pipeline usa siempre la ruta de update.
  local -a env_vars=(
    AZURE_CLIENT_ID="$APPS_CLIENT_ID"
    CENTINELA_STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
    CENTINELA_RAW_TRANSACTIONS_CONTAINER=raw-transactions-production
    CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER=verification-documents-production
    CENTINELA_FLAGGED_CASES_QUEUE=flagged-cases-production
    CENTINELA_EVENTGRID_TOPIC_ENDPOINT="$EVENTGRID_ENDPOINT"
    CENTINELA_POSTGRES_JDBC_URL="$PG_JDBC_URL"
    CENTINELA_POSTGRES_USER="${NAME_PREFIX}_apps"
    CENTINELA_COSMOS_MONGO_CONNECTION_STRING=secretref:cosmos-mongo
    CENTINELA_ENTRA_ISSUER_URI="https://login.microsoftonline.com/${TENANT_ID}/v2.0"
    CENTINELA_ENTRA_AUDIENCE="${ENTRA_APP_ID}"
    CENTINELA_ENTRA_JWK_SET_URI="https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys"
    APPLICATIONINSIGHTS_CONNECTION_STRING="$INSIGHTS_CONNECTION"
    CENTINELA_SCORING_RECORD_ENABLED=true
    CENTINELA_INQUIRY_ENABLED=true
    CENTINELA_EXPLAINER_ENABLED=false
    CENTINELA_DOCUMENT_VERIFICATION_ENABLED=false
    CENTINELA_ROLE_NAME=centinela-api
  )

  if app_exists "$app"; then
    log_info "Actualizando '$app' a $image"
    az containerapp secret set -g "$RESOURCE_GROUP" -n "$app" \
      --secrets "cosmos-mongo=keyvaultref:${COSMOS_SECRET_URI},identityref:${APPS_IDENTITY_ID}" \
      --output none
    az containerapp update -g "$RESOURCE_GROUP" -n "$app" --image "$image" \
      --set-env-vars "${env_vars[@]}" \
      --output none
  else
    log_info "Creando '$app'"
    az containerapp create \
      -g "$RESOURCE_GROUP" -n "$app" --environment "$environment" \
      --image "$image" \
      --user-assigned "$identity" "$APPS_IDENTITY_ID" \
      --registry-server "$registry" --registry-identity "$identity" \
      --target-port 8080 --ingress external \
      --cpu "$CPU_PER_REPLICA" --memory "$MEMORY_PER_REPLICA" \
      --min-replicas "$API_MIN_REPLICAS" --max-replicas "$API_MAX_REPLICAS" \
      --secrets "cosmos-mongo=keyvaultref:${COSMOS_SECRET_URI},identityref:${APPS_IDENTITY_ID}" \
      --env-vars "${env_vars[@]}" \
      --output none
  fi

  # Regla de escalado por concurrencia HTTP. Ver la justificacion completa en
  # provision-container-apps.sh: la API espera E/S, asi que la CPU no refleja su
  # saturacion y escalar por ella llegaria tarde.
  az containerapp update -g "$RESOURCE_GROUP" -n "$app" \
    --min-replicas "$API_MIN_REPLICAS" --max-replicas "$API_MAX_REPLICAS" \
    --scale-rule-name http-concurrency \
    --scale-rule-type http \
    --scale-rule-http-concurrency "$API_CONCURRENT_REQUESTS" \
    --output none

  log_info "  FQDN: $(az containerapp show -g "$RESOURCE_GROUP" -n "$app" --query properties.configuration.ingress.fqdn -o tsv)"
}

# --- Motor de scoring --------------------------------------------------------
#
# El motor es el runtime de Azure Functions dentro de un contenedor, y eso trae
# dos necesidades que la API no tiene:
#
#   1. Storage de host (locks, leases, checkpoints). Se accede por Managed
#      Identity; el host exige Blob Data Owner, un escalon por encima del
#      Contributor que ya tiene la identidad de datos.
#   2. System keys. El webhook de Event Grid exige la clave del host, y esa
#      clave tiene que sobrevivir reinicios y ser la misma en todas las
#      replicas. Se persiste en el Key Vault del proyecto
#      (AzureWebJobsSecretStorageType=keyvault): mismo almacen de secretos que
#      todo lo demas, nada nuevo que auditar.
#
# INGRESO EXTERNO, Y POR QUE. La version anterior declaraba ingreso interno
# "porque lo invoca Event Grid". Eso era un error de modelo: Event Grid entrega
# desde la infraestructura de Azure, FUERA de la VNet, asi que un webhook
# interno es inalcanzable y la suscripcion ni siquiera valida. El endpoint
# publico no es anonimo — exige la system key — pero es publico. Es la
# contrapartida real de usar el disparador de Event Grid en contenedores.
deploy_scoring() {
  local environment="$1" registry="$2" identity="$3"
  local app="ca-${NAME_PREFIX}-scoring"
  local image="${registry}/centinela-scoring:${IMAGE_TAG}"

  local storage_id vault_id apps_principal
  storage_id="$(az storage account show -n "$STORAGE_ACCOUNT" -g "$RESOURCE_GROUP" --query id -o tsv)"
  vault_id="$(az keyvault show -n "$KEY_VAULT" -g "$RESOURCE_GROUP" --query id -o tsv)"
  apps_principal="$(az identity show -n "id-${NAME_PREFIX}-apps" -g "$RESOURCE_GROUP" --query principalId -o tsv)"

  log_info "Permisos de host de Functions para la identidad de datos..."
  with_retry 5 assign_role "Storage Blob Data Owner" "$apps_principal" "$storage_id" \
    || die "El host de Functions no puede operar sin Blob Data Owner sobre su Storage."
  with_retry 5 assign_role "Key Vault Secrets Officer" "$apps_principal" "$vault_id" \
    || die "El host no puede persistir sus system keys sin Secrets Officer en el vault."

  # Mismo patron que deploy_api: un solo juego de variables para create y
  # update. El default del umbral es 50, alineado con DEFAULT_THRESHOLD del
  # motor y con local.settings.json; antes aqui decia 60 y lo desplegado
  # puntuaba distinto que lo probado.
  local -a env_vars=(
    FUNCTIONS_WORKER_RUNTIME=java
    AzureWebJobsStorage__accountName="$STORAGE_ACCOUNT"
    AzureWebJobsStorage__credential=managedidentity
    AzureWebJobsStorage__clientId="$APPS_CLIENT_ID"
    AzureWebJobsSecretStorageType=keyvault
    AzureWebJobsSecretStorageKeyVaultUri="https://${KEY_VAULT}.vault.azure.net/"
    AzureWebJobsSecretStorageKeyVaultClientId="$APPS_CLIENT_ID"
    AZURE_CLIENT_ID="$APPS_CLIENT_ID"
    KEY_VAULT_URI="https://${KEY_VAULT}.vault.azure.net/"
    CENTINELA_STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
    CENTINELA_RAW_TRANSACTIONS_CONTAINER_PRODUCTION=raw-transactions-production
    CENTINELA_RAW_TRANSACTIONS_CONTAINER_STAGING=raw-transactions-staging
    CENTINELA_FLAGGED_CASES_QUEUE_PRODUCTION=flagged-cases-production
    CENTINELA_FLAGGED_CASES_QUEUE_STAGING=flagged-cases-staging
    COSMOS_DATABASE=centinela
    COSMOS_COLLECTION=transactions
    SCORING_THRESHOLD="${SCORING_THRESHOLD:-50}"
    RISKY_MERCHANTS="${RISKY_MERCHANTS:-Casino Royale,BetCrypto}"
    RISKY_CATEGORIES="${RISKY_CATEGORIES:-gambling,crypto,pawn_shop}"
    APPLICATIONINSIGHTS_CONNECTION_STRING="$INSIGHTS_CONNECTION"
    CENTINELA_ROLE_NAME=centinela-scoring
  )

  if app_exists "$app"; then
    log_info "Actualizando '$app' a $image"
    az containerapp update -g "$RESOURCE_GROUP" -n "$app" --image "$image" \
      --set-env-vars "${env_vars[@]}" \
      --output none
  else
    log_info "Creando '$app'"
    az containerapp create \
      -g "$RESOURCE_GROUP" -n "$app" --environment "$environment" \
      --image "$image" \
      --user-assigned "$identity" "$APPS_IDENTITY_ID" \
      --registry-server "$registry" --registry-identity "$identity" \
      --target-port 80 --ingress external \
      --cpu "$CPU_PER_REPLICA" --memory "$MEMORY_PER_REPLICA" \
      --min-replicas "$SCORING_MIN_REPLICAS" --max-replicas "$SCORING_MAX_REPLICAS" \
      --env-vars "${env_vars[@]}" \
      --output none
  fi

  az containerapp update -g "$RESOURCE_GROUP" -n "$app" \
    --min-replicas "$SCORING_MIN_REPLICAS" --max-replicas "$SCORING_MAX_REPLICAS" \
    --scale-rule-name event-concurrency \
    --scale-rule-type http \
    --scale-rule-http-concurrency 20 \
    --output none

  wire_eventgrid_subscription "$app"
}

# Conecta el topico de Event Grid al webhook del motor. Se hace aqui y no en
# provision-eventgrid.sh porque necesita dos cosas que solo existen tras el
# despliegue: la URL publica del contenedor y la system key que el host genero
# en su primer arranque.
wire_eventgrid_subscription() {
  local app="$1"
  local topic_id fqdn

  topic_id="$(az eventgrid topic show -n "$EVENTGRID_TOPIC" -g "$RESOURCE_GROUP" --query id -o tsv)"
  fqdn="$(az containerapp show -g "$RESOURCE_GROUP" -n "$app" \
    --query properties.configuration.ingress.fqdn -o tsv)"
  [ -n "$fqdn" ] || die "El motor no tiene ingreso configurado."

  # El host tarda en arrancar y en escribir sus claves en el vault. Se espera a
  # que el runtime responda antes de buscar la clave: buscarla antes produce un
  # "no existe" que es en realidad un "todavia no".
  log_info "Esperando el arranque del host de Functions en $fqdn..."
  local intento
  for intento in $(seq 1 30); do
    if curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${fqdn}/" | grep -qE '^(200|204)$'; then
      break
    fi
    [ "$intento" -lt 30 ] || die "El host de Functions no respondio tras 5 minutos."
    sleep 10
  done
  log_info "Host arriba."

  # La clave del webhook de Event Grid la genera el host y la guarda en el
  # vault. El nombre exacto del secreto depende de la convencion del repositorio
  # de secretos del host, asi que se localiza por patron en vez de adivinarlo.
  # El deployer necesita lectura temporal: mismo patron conceder-usar-revocar
  # que ya usa provision-keyvault.sh.
  local deployer_oid vault_id key_secret system_key
  # 'az ad signed-in-user' solo funciona con usuario interactivo. Bajo el service
  # principal del pipeline no hay "signed-in user": alli la suscripcion de Event
  # Grid ya existe de un despliegue anterior (es idempotente y la clave del host
  # no cambia entre imagenes), asi que se comprueba y se sale en vez de fallar
  # con un error de Graph que no explica nada.
  deployer_oid="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
  if [ -z "$deployer_oid" ]; then
    if az eventgrid event-subscription show \
         --source-resource-id "$(az eventgrid topic show -n "$EVENTGRID_TOPIC" -g "$RESOURCE_GROUP" --query id -o tsv)" \
         --name "${NAME_PREFIX}-scoring" >/dev/null 2>&1; then
      log_info "Ejecucion no interactiva y la suscripcion ya existe: nada que hacer."
      return 0
    fi
    # Antes esto era un warn + return 0: el pipeline quedaba "verde" con el
    # motor sordo (ningun evento le llegaba). Es un fallo real: que falle.
    die "Ejecucion no interactiva SIN suscripcion de Event Grid previa: el cableado
requiere una corrida interactiva inicial de este script (lectura temporal del
vault para obtener la system key). Ejecuta deploy-containers.sh como usuario
antes de delegar los despliegues al pipeline."
  fi
  vault_id="$(az keyvault show -n "$KEY_VAULT" -g "$RESOURCE_GROUP" --query id -o tsv)"

  log_info "Concediendo lectura temporal del vault al deployer..."
  # El deployer interactivo es un User, no un ServicePrincipal: el tipo importa.
  with_retry 5 assign_role "Key Vault Secrets User" "$deployer_oid" "$vault_id" "User" || true
  # La asignacion RBAC tarda en propagar al plano de datos del vault.
  sleep 30

  key_secret=""
  for intento in $(seq 1 12); do
    key_secret="$(az keyvault secret list --vault-name "$KEY_VAULT" \
      --query "[?contains(name, 'eventgrid')].name | [0]" -o tsv 2>/dev/null || true)"
    [ -n "$key_secret" ] && [ "$key_secret" != "null" ] && break
    log_info "  claves del host aun no publicadas (intento $intento/12)..."
    sleep 15
    key_secret=""
  done

  if [ -z "$key_secret" ]; then
    log_error "El host no publico su clave de Event Grid en el vault."
    log_error "Revisar: az containerapp logs show -g $RESOURCE_GROUP -n $app --tail 50"
    die "Sin la system key no se puede crear la suscripcion del topico."
  fi

  system_key="$(az keyvault secret show --vault-name "$KEY_VAULT" --name "$key_secret" \
    --query value -o tsv)"

  local endpoint="https://${fqdn}/runtime/webhooks/eventgrid?functionName=ScoreTransaction&code=${system_key}"

  log_info "Creando la suscripcion del topico hacia el motor..."
  if az eventgrid event-subscription show --source-resource-id "$topic_id" \
       --name "${NAME_PREFIX}-scoring" >/dev/null 2>&1; then
    log_info "La suscripcion ya existe."
  else
    az eventgrid event-subscription create \
      --source-resource-id "$topic_id" \
      --name "${NAME_PREFIX}-scoring" \
      --endpoint-type webhook \
      --endpoint "$endpoint" \
      --output none
    log_info "Suscripcion creada: el topico entrega al motor."
  fi

  # La clave ya viajo a Event Grid; el deployer no la necesita mas.
  unset system_key
  log_info "Revocando la lectura temporal del deployer..."
  az role assignment delete --assignee "$deployer_oid" \
    --role "Key Vault Secrets User" --scope "$vault_id" --output none 2>/dev/null \
    || log_warn "No se pudo revocar por CLI; revisar en el portal (defecto conocido de 'az role assignment')."
}

# --- Explicador y extractor documental ---------------------------------------
deploy_explainer() {
  local environment="$1" registry="$2" identity="$3"
  local app="ca-${NAME_PREFIX}-explainer"
  local image="${registry}/centinela-api:${IMAGE_TAG}"

  # Mismo patron que deploy_api: un solo juego de variables para create y update.
  local -a env_vars=(
    AZURE_CLIENT_ID="$APPS_CLIENT_ID"
    CENTINELA_STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
    CENTINELA_RAW_TRANSACTIONS_CONTAINER=raw-transactions-production
    CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER=verification-documents-production
    CENTINELA_FLAGGED_CASES_QUEUE=flagged-cases-production
    CENTINELA_EVENTGRID_TOPIC_ENDPOINT="$EVENTGRID_ENDPOINT"
    CENTINELA_POSTGRES_JDBC_URL="$PG_JDBC_URL"
    CENTINELA_POSTGRES_USER="${NAME_PREFIX}_apps"
    CENTINELA_COSMOS_MONGO_CONNECTION_STRING=secretref:cosmos-mongo
    CENTINELA_ENTRA_ISSUER_URI="https://login.microsoftonline.com/${TENANT_ID}/v2.0"
    CENTINELA_ENTRA_AUDIENCE="${ENTRA_APP_ID}"
    CENTINELA_ENTRA_JWK_SET_URI="https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys"
    APPLICATIONINSIGHTS_CONNECTION_STRING="$INSIGHTS_CONNECTION"
    CENTINELA_SCORING_RECORD_ENABLED=true
    CENTINELA_INQUIRY_ENABLED=false
    CENTINELA_EXPLAINER_ENABLED=true
    CENTINELA_DOCUMENT_VERIFICATION_ENABLED=true
    CENTINELA_QUEUE_AUTO_START=false
    CENTINELA_ROLE_NAME=centinela-explainer
  )

  if app_exists "$app"; then
    log_info "Actualizando '$app' a $image"
    az containerapp secret set -g "$RESOURCE_GROUP" -n "$app" \
      --secrets "cosmos-mongo=keyvaultref:${COSMOS_SECRET_URI},identityref:${APPS_IDENTITY_ID}" \
      --output none
    az containerapp update -g "$RESOURCE_GROUP" -n "$app" --image "$image" \
      --set-env-vars "${env_vars[@]}" \
      --output none
  else
    log_info "Creando '$app' (misma imagen que la API, otro papel)"
    # Sin ingreso: no atiende peticiones, consulta trabajo pendiente.
    az containerapp create \
      -g "$RESOURCE_GROUP" -n "$app" --environment "$environment" \
      --image "$image" \
      --user-assigned "$identity" "$APPS_IDENTITY_ID" \
      --registry-server "$registry" --registry-identity "$identity" \
      --ingress internal --target-port 8080 \
      --cpu "$CPU_PER_REPLICA" --memory "$MEMORY_PER_REPLICA" \
      --min-replicas "$EXPLAINER_MIN_REPLICAS" --max-replicas "$EXPLAINER_MAX_REPLICAS" \
      --secrets "cosmos-mongo=keyvaultref:${COSMOS_SECRET_URI},identityref:${APPS_IDENTITY_ID}" \
      --env-vars "${env_vars[@]}" \
      --output none
  fi

  az containerapp update -g "$RESOURCE_GROUP" -n "$app" \
    --min-replicas "$EXPLAINER_MIN_REPLICAS" --max-replicas "$EXPLAINER_MAX_REPLICAS" \
    --output none
}

app_exists() {
  az containerapp show -g "$RESOURCE_GROUP" -n "$1" >/dev/null 2>&1
}

main "$@"
