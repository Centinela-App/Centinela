#!/usr/bin/env bash
#
# scripts/watch-deploy.sh — barra de avance en vivo de un despliegue en curso.
#
# Un despliegue completo tarda 30-40 minutos y hay pasos (Cosmos, PostgreSQL, el
# build de Maven) que pasan varios minutos sin escribir nada. Sin una senal de
# avance es imposible distinguir "trabajando" de "colgado". Esto lee el registro
# y pinta que paso va, cuantos faltan y cuanto lleva el paso actual.
#
# Uso:
#   bash scripts/watch-deploy.sh                 # toma el registro mas reciente
#   bash scripts/watch-deploy.sh <ruta-al-log>   # un registro concreto
#
# Es de SOLO LECTURA: no toca Azure ni el despliegue. Cortalo con Ctrl-C cuando
# quieras; el despliegue sigue corriendo en su propia terminal.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Localizar el registro ------------------------------------------------------

LOG="${1:-}"
if [ -z "$LOG" ]; then
  LOG="$(ls -t "$REPO_ROOT"/deploy-run/*/*.log 2>/dev/null | head -n 1)"
fi
if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
  echo "No encuentro ningun registro de despliegue." >&2
  echo "Pasa la ruta a mano: bash scripts/watch-deploy.sh <ruta-al-log>" >&2
  exit 1
fi

# --- Pasos esperados, en orden de ejecucion -------------------------------------
# Cada entrada es 'patron-en-el-log|etiqueta legible'. El patron se busca tal cual.

STEPS=(
  "Ejecutando paso: provision-storage.sh|S1 Storage + contenedores"
  "Ejecutando paso: provision-app-service.sh|S1 App Service + slot staging"
  "Ejecutando paso: provision-network.sh|S1 VNet + subredes + DNS privado"
  "Ejecutando paso: configure-private-endpoints.sh|S1 Private Endpoints"
  "Ejecutando paso: provision-entra-app.sh|S1 App Registration (Entra)"
  "Ejecutando paso: assign-rbac.sh|S1 RBAC de minimo privilegio"
  "Ejecutando paso: provision-cosmos.sh|S2 Cosmos DB (Mongo)"
  "Ejecutando paso: provision-postgres.sh|S2 PostgreSQL privado"
  "Ejecutando paso: provision-keyvault.sh|S2 Key Vault"
  "Ejecutando paso: provision-eventgrid.sh|S2 Event Grid + colas"
  "Ejecutando paso: configure-function-host-storage.sh|S2 Host Storage de la Function"
  "Ejecutando paso: configure-postgres-managed-identity.sh|S2 Principales de PostgreSQL"
  "Verificando la app principal antes de desplegar|S2 Build Maven (mvn verify)"
  "Desplegando primero en produccion|S2 Deploy en produccion"
  "Reaplicando grants sobre las tablas|S2 Grants de Flyway"
  "Desplegando el mismo artefacto corregido en staging|S2 Deploy en staging"
  "Desplegando la Function de scoring|S2 Deploy de la Function"
)
TOTAL="${#STEPS[@]}"

BAR_WIDTH=42

# --- Pintado --------------------------------------------------------------------

draw() {
  local done_count="$1" label="$2" elapsed="$3" finished="$4"
  local filled empty pct i bar=""
  pct=$(( done_count * 100 / TOTAL ))
  filled=$(( done_count * BAR_WIDTH / TOTAL ))
  empty=$(( BAR_WIDTH - filled ))
  for ((i = 0; i < filled; i++)); do bar="${bar}#"; done
  for ((i = 0; i < empty;  i++)); do bar="${bar}."; done

  # \r + limpieza de linea: se reescribe en el sitio en vez de inundar la consola.
  printf '\r\033[K[%s] %3d%%  %2d/%d  %s' "$bar" "$pct" "$done_count" "$TOTAL" "$label"
  [ "$finished" -eq 0 ] && printf '  (%s)' "$(fmt_time "$elapsed")"
}

fmt_time() {
  local s="$1"
  if [ "$s" -lt 60 ]; then printf '%ds' "$s"; else printf '%dm%02ds' $(( s / 60 )) $(( s % 60 )); fi
}

# --- Bucle principal ------------------------------------------------------------

echo "Registro: $LOG"
echo "Ctrl-C para dejar de mirar (el despliegue no se detiene)."
echo

last_index=-1
step_started="$(date +%s)"

while true; do
  current=0
  label="preparando..."
  for i in "${!STEPS[@]}"; do
    pattern="${STEPS[$i]%%|*}"
    if grep -qF "$pattern" "$LOG" 2>/dev/null; then
      current=$(( i + 1 ))
      label="${STEPS[$i]##*|}"
    fi
  done

  # Al cambiar de paso se reinicia el cronometro del paso.
  if [ "$current" -ne "$last_index" ]; then
    step_started="$(date +%s)"
    last_index="$current"
  fi

  if grep -qE "^\[ERROR\]|EXIT=1" "$LOG" 2>/dev/null; then
    draw "$current" "$label" 0 1
    printf '\n\nFALLO. Ultimas lineas del registro:\n\n'
    grep -E "^\[ERROR\]|^ERROR:" "$LOG" | tail -5
    printf '\nRegistro completo: %s\n' "$LOG"
    exit 1
  fi

  if grep -qF "Despliegue de Semana 2 completado" "$LOG" 2>/dev/null \
     || grep -qF "Despliegue completo de Semana 1 + Semana 2 finalizado" "$LOG" 2>/dev/null; then
    draw "$TOTAL" "COMPLETADO" 0 1
    printf '\n\nDespliegue terminado sin errores.\n'
    exit 0
  fi

  draw "$current" "$label" $(( $(date +%s) - step_started )) 0
  sleep 2
done
