#!/usr/bin/env bash
#
# scripts/deploy-platform.sh
# Despliegue completo de la topologia FINAL (Container Apps, ADR-009) con un solo
# comando, sobre una suscripcion limpia.
#
# POR QUE EXISTE ADEMAS DE deploy-all.sh
# --------------------------------------
# deploy-all.sh orquesta las Semanas 1 y 2, cuya topologia es App Service. ADR-009
# sustituyo el App Service por Container Apps —forzado ademas por la ausencia de
# cuota de App Service en la region— y desde entonces la secuencia real solo
# existia como una lista de comandos en el README. Eso tiene tres consecuencias
# que se pagan en cada despliegue nuevo:
#
#   1. La lista del README OMITIA dos pasos imprescindibles: crear el grupo de
#      recursos (solo lo creaba deploy-week1.sh, que ya no se ejecuta) y
#      provision-storage.sh. Sin el segundo,
#      provision-containerapps-identity.sh aborta con "No hay Storage Account en
#      el grupo de recursos" — un error correcto que apunta al script equivocado.
#   2. provision-containerapps-identity.sh concede permisos sobre recursos que
#      quiza no existan aun y AVISA en vez de fallar. Ejecutado una sola vez en el
#      orden del README, la identidad queda sin el rol de Event Grid y la ingesta
#      se corta con un 403 en el primer envio. Aqui se ejecuta DOS VECES a
#      proposito: la segunda recoge lo que en la primera no existia.
#   3. Nadie asignaba el app role SERVICE, asi que ningun cliente de servicio
#      podia usar la API (ver scripts/assign-app-role.sh).
#
# Este script es la secuencia real, en el orden que las dependencias imponen, y es
# idempotente: volver a ejecutarlo converge sin duplicar nada.
#
# SIN DOCKER LOCAL
# ----------------
# Las imagenes se construyen con `az acr build`, es decir DENTRO de Azure. No es
# una comodidad: es lo que hace que "desplegar desde cualquier equipo" sea cierto.
# Un `docker build` local exige un demonio de Docker corriendo, ~2 GB de descarga
# de imagenes base y, en Windows, WSL2 configurado. `az acr build` solo exige la
# CLI de Azure, que ya es requisito. Con --local-docker se fuerza el camino
# clasico si se prefiere.
#
# Uso:
#   bash scripts/deploy-platform.sh [opciones]
#
#     --validate-only   Solo preflight. No crea nada, no cuesta nada.
#     --yes             Sin confirmacion interactiva.
#     --skip-infra      Asume la infraestructura creada; solo construye y despliega.
#     --skip-images     No construye imagenes; despliega la etiqueta indicada.
#     --tag <etiqueta>  Etiqueta de imagen (por defecto: el SHA corto de HEAD).
#     --local-docker    Construye con el Docker local en lugar de `az acr build`.
#     --with-lab        Despliega tambien el banco de pruebas (repo centinela-lab).
#     --env-file <ruta> Archivo de parametros alternativo.
#
# Parametros obligatorios (.env o entorno): ver .env.example.
# Opcional pero recomendado: CENTINELA_ALERT_EMAIL (destinatario de la alerta).
#
# AVISO DE COSTOS: crea recursos que facturan. Al terminar la sesion,
# `bash scripts/shutdown-daily.sh` apaga lo que factura por tiempo, y
# `bash scripts/destroy-week1.sh --wait` elimina todo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

VALIDATE_ONLY=0
ASSUME_YES=0
SKIP_INFRA=0
SKIP_IMAGES=0
LOCAL_DOCKER=0
WITH_LAB=0
IMAGE_TAG=""

usage() { sed -n '3,55p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --validate-only) VALIDATE_ONLY=1; shift ;;
    --yes|--force)   ASSUME_YES=1; shift ;;
    --skip-infra)    SKIP_INFRA=1; shift ;;
    --skip-images)   SKIP_IMAGES=1; shift ;;
    --local-docker)  LOCAL_DOCKER=1; shift ;;
    --with-lab)      WITH_LAB=1; shift ;;
    --tag)           IMAGE_TAG="${2:?--tag requiere valor}"; shift 2 ;;
    --env-file)      export ENV_FILE="${2:?Falta la ruta para --env-file}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) die "Argumento desconocido: $1. Usa --help." ;;
  esac
done

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$REPO_ROOT/deploy-run/$RUN_ID"

STEP_NUMBER=0
declare -a STEP_RESULTS=()

# --- Ejecucion de pasos ---------------------------------------------------------

run_step() {
  local label="$1"; shift
  STEP_NUMBER=$((STEP_NUMBER + 1))
  local slug log_file started elapsed status
  slug="$(printf '%02d-%s' "$STEP_NUMBER" "$(printf '%s' "$label" | tr ' /' '--' | tr -cd 'A-Za-z0-9._-')")"
  log_file="$RUN_DIR/${slug}.log"

  log_info "──────────────────────────────────────────────────────────────"
  log_info "PASO $STEP_NUMBER: $label"
  started="$(date +%s)"
  set +e
  "$@" 2>&1 | tee "$log_file"
  status="${PIPESTATUS[0]}"
  set -e
  elapsed=$(( $(date +%s) - started ))

  if [ "$status" -ne 0 ]; then
    STEP_RESULTS+=("FALLO   $label (${elapsed}s) -> $log_file")
    log_error "El paso '$label' fallo con codigo $status. Registro: $log_file"
    print_summary
    die "Despliegue detenido. Corrige la causa y vuelve a ejecutar: el script es idempotente."
  fi
  STEP_RESULTS+=("OK      $label (${elapsed}s)")
  log_info "PASO $STEP_NUMBER completado en ${elapsed}s."
}

# run_soft — como run_step pero no aborta. Para pasos cuyo fallo no invalida el
# despliegue (la alerta de observabilidad, el banco de pruebas): perder la alerta
# no es motivo para tirar una plataforma que funciona.
run_soft() {
  local label="$1"; shift
  STEP_NUMBER=$((STEP_NUMBER + 1))
  local slug log_file status
  slug="$(printf '%02d-%s' "$STEP_NUMBER" "$(printf '%s' "$label" | tr ' /' '--' | tr -cd 'A-Za-z0-9._-')")"
  log_file="$RUN_DIR/${slug}.log"

  log_info "──────────────────────────────────────────────────────────────"
  log_info "PASO $STEP_NUMBER (no bloqueante): $label"
  set +e
  "$@" 2>&1 | tee "$log_file"
  status="${PIPESTATUS[0]}"
  set -e
  if [ "$status" -ne 0 ]; then
    STEP_RESULTS+=("REVISAR $label -> $log_file")
    log_warn "'$label' no completo (codigo $status). El despliegue continua."
  else
    STEP_RESULTS+=("OK      $label")
  fi
}

print_summary() {
  local line
  log_info "══════════════ RESUMEN DE LA CORRIDA $RUN_ID ══════════════"
  for line in "${STEP_RESULTS[@]}"; do log_info "  $line"; done
  log_info "Registros completos en: $RUN_DIR"
}

# --- Preflight ------------------------------------------------------------------

assert_java_21() {
  local java_bin="java"
  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    java_bin="$JAVA_HOME/bin/java"
  elif [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java.exe" ]; then
    java_bin="$JAVA_HOME/bin/java.exe"
  else
    require_cmd java
  fi
  local version
  version="$("$java_bin" -version 2>&1 | head -n 1 | sed -E 's/.*version "([0-9]+).*/\1/')"
  case "$version" in
    ''|*[!0-9]*) log_warn "No se pudo determinar la version de Java; se requiere 21." ;;
    *) [ "$version" -ge 21 ] \
         || die "Java 21 o superior es obligatorio (detectado: $version en '$java_bin')." ;;
  esac
  log_info "JDK del build: $version ($java_bin)"
}

# Una suscripcion nueva no tiene registrados los proveedores que nunca uso, y el
# 'create' falla con MissingSubscriptionRegistration: un error que parece de
# permisos y no lo es. Se registra aqui en vez de documentarlo como paso manual,
# porque un paso manual imprescindible es un paso que se olvida.
ensure_providers() {
  local providers=(
    Microsoft.App Microsoft.ContainerRegistry Microsoft.OperationalInsights
    Microsoft.Insights Microsoft.KeyVault Microsoft.EventGrid Microsoft.DocumentDB
    Microsoft.DBforPostgreSQL Microsoft.ManagedIdentity Microsoft.Storage
    Microsoft.Network
  )
  local p estado pendientes=()
  for p in "${providers[@]}"; do
    estado="$(az provider show --namespace "$p" --query registrationState -o tsv 2>/dev/null || echo Unknown)"
    [ "$estado" = "Registered" ] || pendientes+=("$p")
  done

  if [ "${#pendientes[@]}" -eq 0 ]; then
    log_info "Proveedores de recursos: todos registrados."
    return 0
  fi

  log_warn "Proveedores sin registrar: ${pendientes[*]}"
  [ "$VALIDATE_ONLY" -eq 0 ] || { log_warn "--validate-only: no se registran."; return 0; }

  for p in "${pendientes[@]}"; do
    log_info "  registrando $p (puede tardar un minuto)..."
    az provider register --namespace "$p" --wait --output none \
      || log_warn "  no se pudo registrar $p; puede requerir permisos de suscripcion."
  done
}

preflight() {
  load_parameters
  validate_parameters

  require_cmd az
  require_cmd git
  require_cmd sha1sum
  require_cmd curl

  if [ "$SKIP_IMAGES" -eq 0 ] && [ "$LOCAL_DOCKER" -eq 1 ]; then
    require_cmd docker
    docker info >/dev/null 2>&1 \
      || die "--local-docker pero el demonio de Docker no responde. Arrancalo, o quita la opcion para construir en Azure."
  fi

  # Maven y el JDK solo hacen falta si algo se compila en local. Con `az acr build`
  # la compilacion ocurre dentro del contenedor de construccion en Azure, asi que
  # exigirlos seria inventar un requisito.
  if [ "$LOCAL_DOCKER" -eq 1 ]; then
    require_cmd mvn
    assert_java_21
  fi

  # psql SOLO para el bootstrap de PostgreSQL, que es parte de la infraestructura.
  if [ "$SKIP_INFRA" -eq 0 ] && [ "$VALIDATE_ONLY" -eq 0 ]; then
    ensure_psql_on_path
    command -v psql >/dev/null 2>&1 \
      || die "Falta 'psql': el bootstrap de PostgreSQL crea el principal Entra de la base de datos. Instala PostgreSQL (Windows) o postgresql-client (Linux)."
  fi

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  local active_sub
  active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID")). Ejecuta: az account set --subscription \"$SUBSCRIPTION_ID\"."

  local loc_display
  loc_display="$(az account list-locations --query "[?name=='$LOCATION'] | [0].displayName" -o tsv)"
  [ -n "$loc_display" ] || die "Region '$LOCATION' no valida o no disponible en la suscripcion."

  # A diferencia de deploy-all.sh, NO se valida el SKU de App Service: esta
  # topologia no crea ninguno. Validarlo abortaria el despliegue por la falta de
  # una cuota que el despliegue no usa — que es exactamente el problema que
  # ADR-009 resolvio.
  ensure_providers

  [ -n "$IMAGE_TAG" ] || IMAGE_TAG="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo latest)"

  HASH="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)"
  REGISTRY_NAME="$(derive_registry_name)"

  log_info "Plan de despliegue (topologia Container Apps, ADR-009):"
  log_info "  Suscripcion    : $(mask "$SUBSCRIPTION_ID")"
  log_info "  Region         : $LOCATION ($loc_display)"
  log_info "  Resource Group : $RESOURCE_GROUP"
  log_info "  Name prefix    : $NAME_PREFIX      hash: $HASH"
  log_info "  Etiqueta imagen: $IMAGE_TAG"
  log_info "  Construccion   : $([ "$LOCAL_DOCKER" -eq 1 ] && echo 'docker local' || echo 'az acr build (en Azure, sin Docker local)')"
  log_info "  Banco de pruebas: $([ "$WITH_LAB" -eq 1 ] && echo 'si (--with-lab)' || echo 'no')"
  log_info "  Recursos:"
  log_info "    Storage      : ${NAME_PREFIX}st${HASH}"
  log_info "    Cosmos       : ${NAME_PREFIX}-cosmos-${HASH}"
  log_info "    PostgreSQL   : ${NAME_PREFIX}-pg-${HASH}"
  log_info "    Key Vault    : ${NAME_PREFIX}-kv-${HASH}"
  log_info "    Event Grid   : ${NAME_PREFIX}-egt-${HASH}"
  log_info "    Registro     : ${REGISTRY_NAME}.azurecr.io"
  log_info "    Entorno ACA  : cae-${NAME_PREFIX}"
  log_info "    Aplicaciones : ca-${NAME_PREFIX}-{api,scoring,explainer}$([ "$WITH_LAB" -eq 1 ] && echo ',lab')"
  [ -n "${CENTINELA_ALERT_EMAIL:-}" ] \
    || log_warn "CENTINELA_ALERT_EMAIL sin definir: se omitira la alerta de observabilidad."
  log_warn "AVISO DE COSTOS: estos recursos facturan. Al terminar: scripts/shutdown-daily.sh"
}

confirm_or_abort() {
  [ "$ASSUME_YES" -eq 1 ] && { log_warn "--yes: confirmacion automatica."; return 0; }
  [ -t 0 ] || die "Sesion no interactiva: vuelve a ejecutar con --yes para confirmar la creacion de recursos."
  printf 'Se crearan recursos con costo en la suscripcion %s. Escribe "si" para continuar: ' "$(mask "$SUBSCRIPTION_ID")" >&2
  local answer; read -r answer
  case "$answer" in
    si|SI|Si|s|S|yes|y) return 0 ;;
    *) die "Abortado por el operador. No se creo ningun recurso." ;;
  esac
}

# --- Fases ----------------------------------------------------------------------

ensure_resource_group() {
  if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log_info "El grupo de recursos '$RESOURCE_GROUP' ya existe."
    return 0
  fi
  log_info "Creando el grupo de recursos '$RESOURCE_GROUP' en '$LOCATION'..."
  with_retry 3 az group create --name "$RESOURCE_GROUP" --location "$LOCATION" \
    --tags proyecto=centinela topologia=container-apps --output none \
    || die "No se pudo crear el grupo de recursos."
  az group show --name "$RESOURCE_GROUP" >/dev/null \
    || die "El grupo de recursos no existe tras crearlo."
}

infraestructura() {
  run_step "grupo-de-recursos"          ensure_resource_group
  run_step "red-privada"                bash "$SCRIPT_DIR/provision-network-containerapps.sh"

  # Storage ANTES de la identidad: provision-containerapps-identity.sh busca la
  # cuenta y aborta si no existe. Este es el paso que faltaba en el README.
  run_step "storage-contenedores-colas" bash "$SCRIPT_DIR/provision-storage.sh"
  run_step "cosmos-mongo"               bash "$SCRIPT_DIR/provision-cosmos.sh"
  run_step "postgresql-privado"         bash "$SCRIPT_DIR/provision-postgres.sh"
  run_step "key-vault"                  bash "$SCRIPT_DIR/provision-keyvault.sh"

  # Primera pasada: crea la identidad y le concede Storage y Key Vault (ambos ya
  # existen). Event Grid todavia no, y el script lo AVISA sin fallar.
  run_step "identidad-de-datos"         bash "$SCRIPT_DIR/provision-containerapps-identity.sh"

  local apps_pid
  apps_pid="$(az identity show -n "id-${NAME_PREFIX}-apps" -g "$RESOURCE_GROUP" --query principalId -o tsv)"
  [ -n "$apps_pid" ] || die "La identidad de datos no tiene principalId."

  run_step "event-grid-y-colas" bash "$SCRIPT_DIR/provision-eventgrid.sh" \
    --publisher-principal "$apps_pid" \
    --consumer-principal  "$apps_pid" \
    --function-principal  "$apps_pid"

  # Segunda pasada: ahora SI existe el topico, y la identidad recibe
  # 'EventGrid Data Sender'. Sin esta repeticion la API publica el evento con un
  # 403 y el pipeline se corta en la ingesta, sin sintoma en el plano de control.
  run_step "identidad-de-datos-recheck" bash "$SCRIPT_DIR/provision-containerapps-identity.sh"

  run_step "storage-privado-del-host-functions" bash "$SCRIPT_DIR/configure-function-host-storage.sh"
  run_step "registro-entra-y-app-roles" bash "$SCRIPT_DIR/provision-entra-app.sh"
  run_step "bootstrap-postgresql"       bash "$SCRIPT_DIR/configure-postgres-managed-identity.sh"
  run_step "registro-de-contenedores"   bash "$SCRIPT_DIR/provision-container-registry.sh"
  run_step "entorno-container-apps"     bash "$SCRIPT_DIR/provision-container-apps.sh"

  # La alerta exige destinatario. Sin el, el script falla a proposito; se degrada
  # a aviso porque una plataforma sin alerta sigue siendo una plataforma.
  if [ -n "${CENTINELA_ALERT_EMAIL:-}" ]; then
    run_soft "observabilidad" bash "$SCRIPT_DIR/provision-observability.sh"
  else
    log_warn "Sin CENTINELA_ALERT_EMAIL: se omite provision-observability.sh."
    log_warn "  Ejecutalo despues con: CENTINELA_ALERT_EMAIL=tu@correo bash scripts/provision-observability.sh"
  fi
}

# Construccion de imagenes. Por defecto en Azure.
imagenes() {
  local registry="${REGISTRY_NAME}.azurecr.io"

  if [ "$LOCAL_DOCKER" -eq 1 ]; then
    run_step "login-en-el-registro" az acr login --name "$REGISTRY_NAME"
    run_step "imagen-api-local"     docker build -t "${registry}/centinela-api:${IMAGE_TAG}" "$REPO_ROOT"
    run_step "imagen-scoring-local" docker build -t "${registry}/centinela-scoring:${IMAGE_TAG}" "$REPO_ROOT/scoring-function"
    run_step "publicar-api"         docker push "${registry}/centinela-api:${IMAGE_TAG}"
    run_step "publicar-scoring"     docker push "${registry}/centinela-scoring:${IMAGE_TAG}"
    return 0
  fi

  # `az acr build` sube el contexto, construye en Azure y deja la imagen en el
  # registro. Se etiqueta tambien 'latest' porque deploy-containers.sh usa esa
  # etiqueta cuando se invoca sin --tag.
  run_step "construir-api-en-azure" az acr build \
    --registry "$REGISTRY_NAME" \
    --image "centinela-api:${IMAGE_TAG}" \
    --image "centinela-api:latest" \
    --file Dockerfile "$REPO_ROOT"

  run_step "construir-scoring-en-azure" az acr build \
    --registry "$REGISTRY_NAME" \
    --image "centinela-scoring:${IMAGE_TAG}" \
    --image "centinela-scoring:latest" \
    --file Dockerfile "$REPO_ROOT/scoring-function"
}

aplicaciones() {
  export IMAGE_TAG
  run_step "desplegar-las-tres-aplicaciones" \
    bash "$SCRIPT_DIR/deploy-containers.sh" --tag "$IMAGE_TAG"

  run_step "comprobar-que-responde" \
    env RESOURCE_GROUP="$RESOURCE_GROUP" NAME_PREFIX="$NAME_PREFIX" \
    bash "$SCRIPT_DIR/verify/verify-deployment-health.sh"
}

# El banco de pruebas vive en su propio repositorio. Se despliega desde aqui solo
# si esta clonado al lado, y su fallo no tumba la plataforma: es una herramienta
# de demostracion, no un componente del sistema.
banco_de_pruebas() {
  local lab_dir="${CENTINELA_LAB_DIR:-$REPO_ROOT/../centinela-lab}"
  if [ ! -f "$lab_dir/scripts/deploy-lab.sh" ]; then
    log_warn "No se encontro el banco de pruebas en '$lab_dir'."
    log_warn "  Clonalo al lado de este repositorio y vuelve a ejecutar con --with-lab,"
    log_warn "  o define CENTINELA_LAB_DIR con su ruta."
    STEP_RESULTS+=("OMITIDO banco-de-pruebas (repositorio no encontrado)")
    return 0
  fi
  run_soft "banco-de-pruebas" env \
    SUBSCRIPTION_ID="$SUBSCRIPTION_ID" \
    RESOURCE_GROUP="$RESOURCE_GROUP" \
    LOCATION="$LOCATION" \
    NAME_PREFIX="$NAME_PREFIX" \
    CENTINELA_DIR="$REPO_ROOT" \
    bash "$lab_dir/scripts/deploy-lab.sh" --yes
}

imprimir_direcciones() {
  local api_fqdn lab_fqdn
  api_fqdn="$(az containerapp show -g "$RESOURCE_GROUP" -n "ca-${NAME_PREFIX}-api" \
    --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || true)"
  lab_fqdn="$(az containerapp show -g "$RESOURCE_GROUP" -n "ca-${NAME_PREFIX}-lab" \
    --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || true)"

  log_info "══════════════════════ SISTEMA DESPLEGADO ══════════════════════"
  [ -n "$api_fqdn" ] && log_info "  API de Centinela : https://$api_fqdn"
  [ -n "$api_fqdn" ] && log_info "  Salud            : https://$api_fqdn/actuator/health/readiness"
  [ -n "$lab_fqdn" ] && log_info "  Banco de pruebas : https://$lab_fqdn"
  log_info "  Etiqueta         : $IMAGE_TAG"
  log_info "════════════════════════════════════════════════════════════════"
}

# --- Main -----------------------------------------------------------------------

main() {
  preflight

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    log_info "--validate-only: entorno y parametros validos. No se creo ningun recurso."
    return 0
  fi

  confirm_or_abort
  mkdir -p "$RUN_DIR"
  log_info "Registros de esta corrida: $RUN_DIR"

  if [ "$SKIP_INFRA" -eq 1 ]; then
    log_warn "--skip-infra: se asume la infraestructura ya creada."
  else
    infraestructura
  fi

  if [ "$SKIP_IMAGES" -eq 1 ]; then
    log_warn "--skip-images: se despliega la etiqueta '$IMAGE_TAG' ya existente en el registro."
  else
    imagenes
  fi

  aplicaciones

  [ "$WITH_LAB" -eq 0 ] || banco_de_pruebas

  print_summary
  imprimir_direcciones
  log_warn "Recuerda apagar al terminar: bash scripts/shutdown-daily.sh"
}

main
