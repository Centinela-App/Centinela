#!/usr/bin/env bash
#
# start.sh — levanta el entorno local completo con un solo comando.
#
#   bash start.sh            construye, levanta y espera a que la API responda
#   bash start.sh --rebuild  fuerza la reconstruccion de la imagen
#
# Que queda corriendo: Azurite (Blob+Queue), PostgreSQL, Mongo, la API
# (http://localhost:8080) y el explicador. Que NO: Event Grid ni el motor de
# scoring — ese tramo se simula con scripts/local/simulate-scoring.sh.
#
# El desmontaje completo es stop.sh. Este script es idempotente: relanzarlo
# converge sin duplicar nada.

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

note() { printf '[start] %s\n' "$*"; }
die()  { printf '[start] ERROR: %s\n' "$*" >&2; exit 1; }

# --- Requisitos --------------------------------------------------------------
command -v docker >/dev/null 2>&1 || die "Docker no esta instalado o no esta en el PATH."
docker info >/dev/null 2>&1 || die "El daemon de Docker no responde. ¿Docker Desktop esta arrancado?"
docker compose version >/dev/null 2>&1 || die "Se requiere Docker Compose v2 (comando 'docker compose')."

REBUILD_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD_ARGS=(--build) ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Argumento desconocido: $arg (usa --rebuild o --help)" ;;
  esac
done

# --- Arranque ----------------------------------------------------------------
note "Levantando el entorno (la primera vez compila la aplicacion: varios minutos)..."
docker compose up -d "${REBUILD_ARGS[@]}"

# --- Espera activa por la API ------------------------------------------------
# El arranque incluye Flyway contra un PostgreSQL recien creado. Se sondea la
# readiness real en vez de dormir un numero magico de segundos: el criterio de
# "esta arriba" es que la aplicacion CONTESTE, no que el contenedor exista.
note "Esperando a que la API responda en http://localhost:8080 ..."
for intento in $(seq 1 60); do
  codigo="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
    "http://localhost:8080/actuator/health/readiness" 2>/dev/null || echo 000)"
  if [ "$codigo" = "200" ]; then
    echo ""
    note "Entorno listo."
    note ""
    note "  API           : http://localhost:8080"
    note "  Salud         : http://localhost:8080/actuator/health"
    note "  PostgreSQL    : localhost:5432 (centinela / ver docker-compose.yml)"
    note "  Mongo         : localhost:27017"
    note "  Azurite       : localhost:10000 (blob) · localhost:10001 (queue)"
    note ""
    note "  Flujo completo local:"
    note "    1. POST http://localhost:8080/api/v1/transactions   (sin token: perfil local)"
    note "    2. bash scripts/local/simulate-scoring.sh <transactionId>"
    note "    3. GET  http://localhost:8080/api/v1/cases/<transactionId>"
    note ""
    note "  Ensayo del escenario de fallo del explicador:"
    note "    docker compose stop explainer && docker compose start explainer"
    exit 0
  fi
  printf '.'
  sleep 5
done

echo ""
die "La API no respondio tras 5 minutos. Diagnostico: docker compose logs api | tail -50"
