#!/usr/bin/env bash
#
# scripts/verify/generate-load.sh
# Genera carga HTTP sostenida contra la API desplegada, para provocar el escalado.
#
# Uso: generate-load.sh [--rate N] [--duration S] [--concurrency C]
#      (por defecto 20 req/s durante 180 s, 20 en vuelo)
#
# Se ejecuta EN PARALELO con verify-scaling.sh, que observa las replicas. La
# regla de la API escala por concurrencia HTTP (ADR-010): lo que hay que forzar
# es peticiones simultaneas, no CPU. Por eso el disparo es concurrente y la tasa
# se controla por lotes.
#
# Las transacciones son INOCUAS a proposito: monto y ciudad normales, cuenta
# distinta cada una. Si generaran casos, miles de registros de prueba
# ensuciarian PostgreSQL y la demostracion de escalado contaminaria la de
# deteccion. Un 429 aqui NO es error: es el limitador de tasa de Centinela
# haciendo su trabajo, y se cuenta aparte.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

RATE=20
DURATION=180
CONCURRENCY=20
while [ $# -gt 0 ]; do
  case "$1" in
    --rate) RATE="${2:?}"; shift 2 ;;
    --duration) DURATION="${2:?}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

load_parameters
require_cmd az
require_cmd curl

BASE_URL="${CENTINELA_BASE_URL:-https://$(az containerapp show -g "$RESOURCE_GROUP" \
  -n "ca-${NAME_PREFIX}-api" --query properties.configuration.ingress.fqdn -o tsv)}"
APP_ID="$(az ad app list --display-name "${NAME_PREFIX}-api-week1" --query '[0].appId' -o tsv)"
TOKEN="$(az account get-access-token --resource "api://${APP_ID}" --query accessToken -o tsv)"
[ -n "$TOKEN" ] || die "Sin token para la API."

note() { printf '[generate-load] %s\n' "$*"; }

note "Destino    : $BASE_URL"
note "Carga      : ${RATE} req/s durante ${DURATION}s, ${CONCURRENCY} en vuelo"
note "Transacciones inocuas (no generan casos)."
note ""
note "AHORA, en OTRA terminal:  bash scripts/verify/verify-scaling.sh"
note "Empezando en 5 s..."
sleep 5

CUERPO_BASE='{"accountId":"__ACC__","amount":48000,"currency":"COP","occurredAt":"__TS__","location":{"countryCode":"CO","city":"Bogota","latitude":4.71,"longitude":-74.07},"merchant":{"name":"Supermercado La Esquina","category":"grocery"}}'

enviar_una() {
  local n="$1"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local id="tx-load-$$-${n}"
  local cuerpo="${CUERPO_BASE/__ACC__/acc-load-$$-${n}}"
  cuerpo="${cuerpo/__TS__/$ts}"
  cuerpo="{\"transactionId\":\"${id}\",${cuerpo#\{}"
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 20 \
    -X POST "${BASE_URL}/api/v1/transactions" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$cuerpo" 2>/dev/null || echo "000"
}
export -f enviar_una
export BASE_URL TOKEN CUERPO_BASE

inicio=$(date +%s)
total=0
CODIGOS=$(mktemp)
while [ $(($(date +%s) - inicio)) -lt "$DURATION" ]; do
  segundo_inicio=$(date +%s%N)
  # Rafaga concurrente de RATE peticiones, en tandas de CONCURRENCY.
  for lote in $(seq 1 "$RATE"); do
    total=$((total + 1))
    enviar_una "$total" >> "$CODIGOS" &
    if [ $((lote % CONCURRENCY)) -eq 0 ]; then wait; fi
  done
  wait
  # Ritmo: completar el segundo si sobro tiempo.
  transcurrido_ms=$(( ($(date +%s%N) - segundo_inicio) / 1000000 ))
  restante=$(( 1000 - transcurrido_ms ))
  [ "$restante" -gt 0 ] && sleep "$(awk "BEGIN{print $restante/1000}")"
  printf '.'
done
echo

aceptadas=$(grep -c '^202' "$CODIGOS" 2>/dev/null || echo 0)
limitadas=$(grep -c '^429' "$CODIGOS" 2>/dev/null || echo 0)
errores=$(grep -cvE '^(202|429)' "$CODIGOS" 2>/dev/null || echo 0)
rm -f "$CODIGOS"

note ""
note "Total enviadas : $total"
note "  202 aceptadas: $aceptadas"
note "  429 limitadas: $limitadas   (el limitador de tasa funcionando, NO error)"
note "  otros        : $errores"
note ""
note "Revisa la curva de replicas en la terminal de verify-scaling.sh."
