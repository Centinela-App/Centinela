#!/usr/bin/env bash
#
# scripts/deploy-all.sh — despliegue completo y reproducible de Semana 1 + Semana 2.
#
# Un solo comando levanta TODA la infraestructura entregada hasta el momento, en el
# orden correcto de dependencias, sobre una maquina limpia. Es idempotente: volver a
# ejecutarlo converge al mismo estado sin duplicar recursos.
#
#   Fase 0  Preflight   verifica herramientas, sesion, parametros, region y SKU.
#   Fase 1  Semana 1    Storage, App Service + slot, VNet/PE, Entra ID, RBAC minimo.
#   Fase 2  Semana 2    Cosmos, PostgreSQL, Key Vault, Event Grid, host de Function,
#                       principales de BD, despliegue de la app (prod + staging) y de
#                       la Function de scoring, y suscripcion de Event Grid.
#   Fase 3  Validacion  validadores por recurso (opcional, --with-tests).
#
# Uso:
#   bash scripts/deploy-all.sh [opciones]
#
#     --validate-only    Solo Fase 0 + planes en seco. No crea nada en Azure.
#     --skip-week1       Omite la Fase 1 (la infraestructura base ya existe).
#     --skip-week2       Omite la Fase 2.
#     --with-tests       Ejecuta la Fase 3 (validadores de solo lectura).
#     --env-file <ruta>  Archivo de parametros alternativo (por defecto ./.env).
#     --yes              No pide confirmacion antes de crear recursos con costo.
#
# Parametros obligatorios (en .env o exportados; ver .env.example):
#   SUBSCRIPTION_ID  LOCATION  RESOURCE_GROUP  NAME_PREFIX  APP_SERVICE_SKU
#
# Requisitos de ejecucion:
#   - az, mvn, java 21, git, sha1sum (Azure Cloud Shell ya los trae).
#   - psql, SOLO si no se omite la Fase 2: el bootstrap de principales de PostgreSQL
#     se conecta al Private Endpoint del servidor.
#   - Conectividad PRIVADA a la VNet del proyecto (Cloud Shell inyectado en la VNet,
#     una VM jumpbox o VPN). Storage, Cosmos, Key Vault y PostgreSQL tienen el acceso
#     publico deshabilitado por diseno; sin ese camino privado la Fase 2 no puede
#     crear los principales de base de datos ni validar los flujos.
#
# AVISO DE COSTOS: consume el credito compartido de la suscripcion. Al terminar la
# demostracion ejecuta scripts/destroy-week1.sh (elimina el Resource Group completo).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/parameters.sh
source "$SCRIPT_DIR/lib/parameters.sh"

VALIDATE_ONLY=0
SKIP_WEEK1=0
SKIP_WEEK2=0
WITH_TESTS=0
ASSUME_YES=0

usage() {
  sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --validate-only) VALIDATE_ONLY=1; shift ;;
    --skip-week1)    SKIP_WEEK1=1; shift ;;
    --skip-week2)    SKIP_WEEK2=1; shift ;;
    --with-tests)    WITH_TESTS=1; shift ;;
    --yes|--force)   ASSUME_YES=1; shift ;;
    --env-file)      export ENV_FILE="${2:?Falta la ruta para --env-file}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) die "Argumento desconocido: $1. Usa --help." ;;
  esac
done

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$REPO_ROOT/deploy-run/$RUN_ID"

# --- Ejecucion de pasos con registro y cronometro -------------------------------

STEP_NUMBER=0
declare -a STEP_RESULTS=()

# run_step <etiqueta> <comando...> — ejecuta, cronometra y guarda la salida.
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
    STEP_RESULTS+=("FALLO  $label (${elapsed}s) -> $log_file")
    log_error "El paso '$label' fallo con codigo $status. Registro: $log_file"
    print_summary
    die "Despliegue detenido. Corrige la causa y vuelve a ejecutar: el script es idempotente."
  fi
  STEP_RESULTS+=("OK     $label (${elapsed}s)")
  log_info "PASO $STEP_NUMBER completado en ${elapsed}s."
}

# run_check <etiqueta> <comando...> — como run_step pero no aborta el despliegue.
run_check() {
  local label="$1"; shift
  STEP_NUMBER=$((STEP_NUMBER + 1))
  local slug log_file status
  slug="$(printf '%02d-%s' "$STEP_NUMBER" "$(printf '%s' "$label" | tr ' /' '--' | tr -cd 'A-Za-z0-9._-')")"
  log_file="$RUN_DIR/${slug}.log"

  log_info "VALIDACION $STEP_NUMBER: $label"
  set +e
  "$@" 2>&1 | tee "$log_file"
  status="${PIPESTATUS[0]}"
  set -e
  if [ "$status" -ne 0 ]; then
    STEP_RESULTS+=("REVISAR $label -> $log_file")
    log_warn "La validacion '$label' no paso (codigo $status). Registro: $log_file"
  else
    STEP_RESULTS+=("OK     $label")
  fi
}

print_summary() {
  local line
  log_info "══════════════════ RESUMEN DE LA CORRIDA $RUN_ID ══════════════════"
  for line in "${STEP_RESULTS[@]}"; do
    log_info "  $line"
  done
  log_info "Registros completos en: $RUN_DIR"
}

# --- Fase 0: preflight ----------------------------------------------------------

assert_java_21() {
  # Maven usa JAVA_HOME si esta definido, no el 'java' del PATH: se valida el
  # mismo JDK que hara el build, no el primero que aparezca en el PATH.
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
         || die "Java 21 o superior es obligatorio (detectado: $version en '$java_bin'). Apunta JAVA_HOME a un JDK 21." ;;
  esac
  log_info "JDK del build: $version ($java_bin)"
}

preflight() {
  load_parameters
  validate_parameters               # falla offline antes de tocar Azure

  require_cmd az
  require_cmd git
  require_cmd sha1sum
  if [ "$SKIP_WEEK2" -eq 0 ] || [ "$SKIP_WEEK1" -eq 0 ]; then
    require_cmd mvn
    assert_java_21
  fi
  if [ "$SKIP_WEEK2" -eq 0 ] && [ "$VALIDATE_ONLY" -eq 0 ]; then
    # Se valida ahora y no a mitad de la Fase 2: el bootstrap de principales de
    # PostgreSQL necesita psql. En Windows el instalador no toca el PATH, asi que
    # primero se intenta localizarlo en las rutas estandar.
    ensure_psql_on_path
    command -v psql >/dev/null 2>&1 \
      || die "Falta 'psql'. La Fase 2 crea los principales Entra de PostgreSQL. Instala postgresql-client (Linux) o PostgreSQL (Windows), o ejecuta con --skip-week2."
  fi

  az account show >/dev/null 2>&1 || die "No hay sesion de Azure activa. Ejecuta 'az login'."
  local active_sub
  active_sub="$(az account show --query id -o tsv)"
  [ "$active_sub" = "$SUBSCRIPTION_ID" ] \
    || die "Suscripcion activa ($(mask "$active_sub")) != SUBSCRIPTION_ID ($(mask "$SUBSCRIPTION_ID")). Ejecuta: az account set --subscription \"\$SUBSCRIPTION_ID\"."

  local loc_display
  loc_display="$(az account list-locations --query "[?name=='$LOCATION'] | [0].displayName" -o tsv)"
  [ -n "$loc_display" ] || die "Region '$LOCATION' no valida/disponible."
  # appservice list-locations responde con el nombre display ("East US 2").
  az appservice list-locations --sku "$APP_SERVICE_SKU" \
      --query "[?name=='$loc_display'] | [0].name" -o tsv | grep -q . \
    || die "SKU '$APP_SERVICE_SKU' no disponible en '$LOCATION' o sin soporte de slots/escala."

  local hash
  hash="$(printf '%s|%s|%s' "$NAME_PREFIX" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP" | sha1sum | cut -c1-6)"

  log_info "Plan de despliegue completo (Semana 1 + Semana 2):"
  log_info "  Suscripcion    : $(mask "$SUBSCRIPTION_ID")"
  log_info "  Region         : $LOCATION ($loc_display)"
  log_info "  Resource Group : $RESOURCE_GROUP"
  log_info "  Name prefix    : $NAME_PREFIX   ·   App SKU: $APP_SERVICE_SKU"
  log_info "  Nombres deterministas (hash=$hash):"
  log_info "    Storage      : ${NAME_PREFIX}st${hash}"
  log_info "    Web App      : ${NAME_PREFIX}-app-${hash}  (+ slot staging)"
  log_info "    VNet         : ${NAME_PREFIX}-vnet-week1"
  log_info "    Cosmos       : ${NAME_PREFIX}-cosmos-${hash}"
  log_info "    PostgreSQL   : ${NAME_PREFIX}-pg-${hash}"
  log_info "    Key Vault    : ${NAME_PREFIX}-kv-${hash}"
  log_info "    Event Grid   : ${NAME_PREFIX}-egt-${hash}"
  log_info "    Function     : ${NAME_PREFIX}-scoring-fn-${hash}"
  log_info "    App Entra    : ${NAME_PREFIX}-api-week1"
  log_warn "AVISO DE COSTOS: los recursos consumen el credito compartido. Ejecuta scripts/destroy-week1.sh al terminar."
  log_warn "La Fase 2 requiere camino PRIVADO a la VNet (Cloud Shell inyectado, jumpbox o VPN)."
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

# --- Main -----------------------------------------------------------------------

main() {
  preflight

  if [ "$VALIDATE_ONLY" -eq 1 ]; then
    mkdir -p "$RUN_DIR"
    log_info "--validate-only: ejecutando los planes en seco de cada fase."
    [ "$SKIP_WEEK1" -eq 1 ] || run_step "week1-plan" bash "$SCRIPT_DIR/deploy-week1.sh" --validate-only
    [ "$SKIP_WEEK2" -eq 1 ] || run_step "week2-plan" bash "$SCRIPT_DIR/deploy-week2.sh" --validate-only
    [ "$SKIP_WEEK2" -eq 1 ] || run_step "scoring-plan" bash "$SCRIPT_DIR/deploy-scoring-function.sh" --validate-only
    print_summary
    log_info "Entorno valido. No se creo ningun recurso."
    return 0
  fi

  confirm_or_abort
  mkdir -p "$RUN_DIR"
  log_info "Registros de esta corrida: $RUN_DIR"

  # Fase 1 — infraestructura base. deploy-week1.sh crea el Resource Group.
  if [ "$SKIP_WEEK1" -eq 1 ]; then
    log_warn "--skip-week1: se asume que la infraestructura base ya existe."
  else
    run_step "week1-infraestructura-base" bash "$SCRIPT_DIR/deploy-week1.sh"
  fi

  # Fase 2 — datos, mensajeria, secretos, aplicacion y motor de scoring.
  # deploy-week2.sh ya encadena: provisiones -> mvn verify -> deploy prod ->
  # grants de Flyway -> deploy staging -> deploy de la Function -> Event Grid.
  if [ "$SKIP_WEEK2" -eq 1 ]; then
    log_warn "--skip-week2: no se despliegan datos, mensajeria ni scoring."
  else
    run_step "week2-datos-mensajeria-y-scoring" bash "$SCRIPT_DIR/deploy-week2.sh"
  fi

  # Fase 3 — validadores de solo lectura.
  if [ "$WITH_TESTS" -eq 1 ]; then
    log_info "──────────────────────────────────────────────────────────────"
    log_info "Fase 3: validaciones de solo lectura."
    local check checks=()
    if [ "$SKIP_WEEK1" -eq 0 ]; then
      checks+=(validate-storage validate-app-service validate-network
               validate-managed-identity validate-entra-roles validate-rbac)
    fi
    if [ "$SKIP_WEEK2" -eq 0 ]; then
      checks+=(validate-cosmos validate-postgres validate-keyvault
               validate-eventgrid validate-decoupling)
    fi
    for check in "${checks[@]}"; do
      if [ -f "$SCRIPT_DIR/tests/$check.sh" ]; then
        run_check "$check" bash "$SCRIPT_DIR/tests/$check.sh"
      else
        log_warn "Validador no disponible en este arbol: tests/$check.sh"
      fi
    done
  else
    log_info "Sin --with-tests: se omite la Fase 3 de validacion."
  fi

  print_summary
  log_info "Despliegue completo de Semana 1 + Semana 2 finalizado."
  log_warn "Recuerda apagar/destruir al terminar: bash scripts/destroy-week1.sh --wait"
}

main
