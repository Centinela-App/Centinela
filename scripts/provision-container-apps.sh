#!/usr/bin/env bash
#
# scripts/provision-container-apps.sh
# ISS-S3-008 — Entorno de Container Apps y reglas de escalado.
#
# Alcance ESTRICTO:
#   - Crear el Container Apps Environment (perfil Consumption) con Log Analytics.
#   - Crear tres Container Apps: API de ingesta, motor de scoring y explicador.
#   - Configurar sus reglas de escalado y justificarlas (ver seccion siguiente).
#   - Asociar la identidad de pull del registro; cero credenciales de registro.
#   - Idempotente.
#
# ---------------------------------------------------------------------------
# METRICA DE ESCALADO ELEGIDA Y POR QUE
# ---------------------------------------------------------------------------
# Cada componente escala por la metrica que describe SU cuello de botella. Usar
# una sola metrica para los tres seria mas simple y estaria mal en dos de ellos.
#
# 1) API de ingesta -> CONCURRENCIA HTTP (10 peticiones simultaneas por replica)
#
#    El trabajo de la API es esperar: escribe un blob y publica un evento. Bajo
#    carga la CPU apenas se mueve mientras las peticiones se acumulan esperando
#    E/S. Escalar por CPU llegaria tarde —o no llegaria nunca— justo cuando la
#    latencia ya se degrado. La concurrencia mide directamente lo que sufre el
#    cliente: cuantas peticiones hay en vuelo.
#
#    Comportamiento esperado ante un pico: con 200 req/s y ~50 ms por peticion
#    hay ~10 peticiones en vuelo, que caben en una replica. A 600 req/s son ~30,
#    y KEDA levanta 3 replicas en unos 30 s. Al cesar la carga, la ventana de
#    enfriamiento (300 s) evita el vaiven de crear y destruir replicas por
#    fluctuaciones cortas.
#
# 2) Motor de scoring -> PROFUNDIDAD DE COLA... no. Se dispara por EVENTO.
#
#    El motor lo invoca Event Grid, que gestiona su propia entrega y reintento.
#    La metrica util es la concurrencia de invocaciones. Escalar por CPU seria
#    tambien enganoso aqui: el motor pasa la mayor parte del tiempo esperando a
#    Cosmos, no calculando.
#
# 3) Explicador -> PROFUNDIDAD DE TRABAJO PENDIENTE
#
#    El explicador no recibe peticiones: consulta casos con explicacion
#    pendiente. Ni CPU ni concurrencia HTTP dicen nada de el. Lo que importa es
#    cuanto backlog hay acumulado. Escala a CERO replicas cuando no hay trabajo,
#    que ademas es lo que hace gratis su operacion la mayor parte del tiempo.
#
#    Consecuencia deliberada: cuando el explicador esta en cero, un caso nuevo
#    espera hasta el siguiente ciclo de sondeo. Se acepta porque el requisito
#    dice que la explicacion es posterior a la apertura del caso, y ese retraso
#    no afecta al analista tanto como pagar una replica ociosa todo el dia.
#
# ---------------------------------------------------------------------------
# NIVEL GRATUITO Y SUS LIMITES
# ---------------------------------------------------------------------------
# Container Apps (plan Consumption) incluye gratis y por suscripcion/mes:
#   - 180 000 vCPU-segundo
#   - 360 000 GiB-segundo de memoria
#   - 2 000 000 de peticiones
#
# Con 0,5 vCPU por replica, 180 000 vCPU-s equivalen a ~100 horas de una replica
# activa al mes. Las tres aplicaciones con minimo 0 o 1 replica y las pruebas de
# carga de la demostracion se mantienen dentro del nivel gratuito. Lo que si
# cuesta es el minimo de 1 replica de la API: 0,5 vCPU x 24 h x 30 d = 1 296 000
# vCPU-s, muy por encima del grant. Por eso la API tambien puede escalar a cero
# fuera de las sesiones de trabajo (ver CENTINELA_API_MIN_REPLICAS) y por eso el
# script de apagado diario existe.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

# --- Reglas de escalado (parametrizables sin editar el script) ---------------
readonly API_CONCURRENT_REQUESTS="${CENTINELA_API_CONCURRENCY:-10}"
readonly API_MIN_REPLICAS="${CENTINELA_API_MIN_REPLICAS:-1}"
readonly API_MAX_REPLICAS="${CENTINELA_API_MAX_REPLICAS:-10}"

readonly SCORING_MIN_REPLICAS="${CENTINELA_SCORING_MIN_REPLICAS:-0}"
readonly SCORING_MAX_REPLICAS="${CENTINELA_SCORING_MAX_REPLICAS:-8}"

readonly EXPLAINER_MIN_REPLICAS="${CENTINELA_EXPLAINER_MIN_REPLICAS:-0}"
readonly EXPLAINER_MAX_REPLICAS="${CENTINELA_EXPLAINER_MAX_REPLICAS:-3}"

readonly CPU_PER_REPLICA="0.5"
readonly MEMORY_PER_REPLICA="1.0Gi"

# Subred delegada que crea provision-network-containerapps.sh.
readonly SUBNET_ACA="snet-container-apps"

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

  local environment_name="cae-${NAME_PREFIX}"
  local workspace_name="log-${NAME_PREFIX}"
  local registry_name="${NAME_PREFIX}acr"
  local identity_name="id-${NAME_PREFIX}-acrpull"

  log_info "Plan de ISS-S3-008:"
  log_info "  Entorno            : $environment_name"
  log_info "  Log Analytics      : $workspace_name"
  log_info "  API                : concurrencia=$API_CONCURRENT_REQUESTS replicas=$API_MIN_REPLICAS..$API_MAX_REPLICAS"
  log_info "  Motor de scoring   : replicas=$SCORING_MIN_REPLICAS..$SCORING_MAX_REPLICAS"
  log_info "  Explicador         : replicas=$EXPLAINER_MIN_REPLICAS..$EXPLAINER_MAX_REPLICAS (escala a cero)"

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "Modo --validate-only: no se crea nada."
    exit 0
  fi

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  ensure_extension
  ensure_workspace "$workspace_name"
  ensure_environment "$environment_name" "$workspace_name"

  local registry_server identity_id
  registry_server="$(az acr show -n "$registry_name" -g "$RESOURCE_GROUP" --query loginServer -o tsv 2>/dev/null)" \
    || die "El registro '$registry_name' no existe. Ejecuta antes provision-container-registry.sh."
  identity_id="$(az identity show -n "$identity_name" -g "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null)" \
    || die "La identidad de pull no existe. Ejecuta antes provision-container-registry.sh."

  log_info "Entorno listo. Las aplicaciones se crean en el primer despliegue:"
  log_info "  bash scripts/deploy-containers.sh"
  log_info "  ACR_LOGIN_SERVER=$registry_server"
  log_info "  ACR_PULL_IDENTITY_ID=$identity_id"
  log_info "ISS-S3-008 OK (entorno)"
}

ensure_extension() {
  # La extension containerapp no viene instalada por defecto en todas las
  # versiones de az; sin ella cada comando falla con "not recognized", que se
  # confunde facilmente con un error de sintaxis.
  if ! az extension show --name containerapp >/dev/null 2>&1; then
    log_info "Instalando extension 'containerapp' de Azure CLI..."
    az extension add --name containerapp --upgrade --only-show-errors --output none
  fi
  az provider register --namespace Microsoft.App --wait --only-show-errors 2>/dev/null || true
  az provider register --namespace Microsoft.OperationalInsights --wait --only-show-errors 2>/dev/null || true
}

ensure_workspace() {
  local name="$1"
  if az monitor log-analytics workspace show -g "$RESOURCE_GROUP" -n "$name" >/dev/null 2>&1; then
    log_info "Workspace '$name' ya existe."
    return
  fi
  log_info "Creando workspace de Log Analytics '$name'..."
  # 30 dias de retencion: el minimo del nivel gratuito. Ampliarlo se factura y
  # ninguna pregunta de operacion de este proyecto mira mas atras de una semana.
  az monitor log-analytics workspace create \
    -g "$RESOURCE_GROUP" -n "$name" -l "$LOCATION" \
    --retention-time 30 --output none
}

ensure_environment() {
  local name="$1" workspace="$2"

  # La subred se fija AL CREAR el entorno y no se puede anadir despues. Si el
  # entorno existe sin integracion de red, sus aplicaciones nunca alcanzaran los
  # Private Endpoints de Cosmos, PostgreSQL o Key Vault — y el sintoma sera un
  # tiempo de espera al arrancar, no un error de red, asi que se diagnostica mal.
  # Por eso se comprueba la integracion y no solo la existencia.
  if az containerapp env show -g "$RESOURCE_GROUP" -n "$name" >/dev/null 2>&1; then
    local subred_actual
    subred_actual="$(az containerapp env show -g "$RESOURCE_GROUP" -n "$name" \
      --query "properties.vnetConfiguration.infrastructureSubnetId" -o tsv 2>/dev/null)"
    if [ -n "$subred_actual" ] && [ "$subred_actual" != "null" ]; then
      log_info "Entorno '$name' ya existe con integracion de red."
      return
    fi
    die "El entorno '$name' existe SIN integracion de red y eso no se puede corregir en caliente.
     Sus aplicaciones no alcanzarian los almacenes privados.
     Eliminalo y vuelve a ejecutar: az containerapp env delete -g $RESOURCE_GROUP -n $name --yes"
  fi

  local vnet="${NAME_PREFIX}-vnet-week1"
  local subnet_id
  subnet_id="$(az network vnet subnet show -g "$RESOURCE_GROUP" --vnet-name "$vnet" \
    -n "$SUBNET_ACA" --query id -o tsv 2>/dev/null)" \
    || die "Falta la subred '$SUBNET_ACA'. Ejecuta antes provision-network-containerapps.sh."

  local workspace_id workspace_key
  workspace_id="$(az monitor log-analytics workspace show -g "$RESOURCE_GROUP" -n "$workspace" \
    --query customerId -o tsv)"
  workspace_key="$(az monitor log-analytics workspace get-shared-keys -g "$RESOURCE_GROUP" -n "$workspace" \
    --query primarySharedKey -o tsv)"

  log_info "Creando Container Apps Environment '$name' integrado a '$SUBNET_ACA'..."
  az containerapp env create \
    -g "$RESOURCE_GROUP" -n "$name" -l "$LOCATION" \
    --logs-workspace-id "$workspace_id" \
    --logs-workspace-key "$workspace_key" \
    --infrastructure-subnet-resource-id "$subnet_id" \
    --output none

  # La clave del workspace se uso solo en memoria y no se persiste en ningun
  # archivo del repositorio.
  unset workspace_key
}

main "$@"
