#!/usr/bin/env bash
#
# scripts/verify/run-e2e-fraud.sh
# Recorrido completo de una transaccion fraudulenta sobre el sistema DESPLEGADO.
#
# Siembra historial normal en una cuenta nueva, lanza la transaccion anomala
# (monto 84x + salto Medellin->Madrid en 11 minutos) y espera el veredicto del
# motor y la explicacion del caso. Imprime el transactionId y el trace-id, que
# son las entradas de verify-trace.sh y verify-explainer-correspondence.sh.
#
# Por que siembra historial: las reglas comparan contra el pasado de la cuenta.
# Un monto desmedido sobre una cuenta sin historial no activa nada — la anomalia
# solo existe en relacion con lo habitual, y lo habitual hay que construirlo.
#
# Requiere: sesion az del operador con el app role SERVICE asignado.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

load_parameters
require_cmd az
require_cmd curl

BASE_URL="${CENTINELA_BASE_URL:-}"
if [ -z "$BASE_URL" ]; then
  BASE_URL="https://$(az containerapp show -g "$RESOURCE_GROUP" -n "ca-${NAME_PREFIX}-api" \
    --query properties.configuration.ingress.fqdn -o tsv)"
fi

APP_ID="$(az ad app list --display-name "${NAME_PREFIX}-api-week1" --query '[0].appId' -o tsv)"
TOKEN="$(az account get-access-token --resource "api://${APP_ID}" --query accessToken -o tsv)"
[ -n "$TOKEN" ] || die "Sin token para la API."

SELLO="$(date -u +%H%M%S)"
ACCOUNT="acc-e2e-${SELLO}"
TX_FRAUDE="tx-e2e-fraude-${SELLO}"
TRACEPARENT="00-$(openssl rand -hex 16)-$(openssl rand -hex 8)-01"
TRACE_ID="${TRACEPARENT:3:32}"

note() { printf '[e2e-fraud] %s\n' "$*"; }

# enviar <transactionId> <monto> <minutosAtras> <ciudad> <lat> <lon> <comercio> <categoria>
enviar() {
  local id="$1" monto="$2" hace="$3" ciudad="$4" lat="$5" lon="$6" comercio="$7" categoria="$8"
  local instante
  instante="$(date -u -d "-${hace} minutes" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u +%Y-%m-%dT%H:%M:%SZ)"

  printf '{"transactionId":"%s","accountId":"%s","amount":%s,"currency":"COP","occurredAt":"%s","location":{"countryCode":"%s","city":"%s","latitude":%s,"longitude":%s},"merchant":{"name":"%s","category":"%s"}}' \
    "$id" "$ACCOUNT" "$monto" "$instante" \
    "$([ "$ciudad" = "Madrid" ] && echo ES || echo CO)" "$ciudad" "$lat" "$lon" \
    "$comercio" "$categoria" > /tmp/e2e-tx.json

  local codigo
  codigo="$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${BASE_URL}/api/v1/transactions" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "traceparent: $TRACEPARENT" \
    --data-binary @/tmp/e2e-tx.json)"
  [ "$codigo" = "202" ] || die "La ingesta de $id devolvio HTTP $codigo (esperado 202)."
  note "  202 $id (${monto} COP, ${ciudad}, hace ${hace} min)"
}

note "Cuenta nueva: $ACCOUNT"
note "Trace-id del recorrido: $TRACE_ID"
note ""
note "1/3 Sembrando historial normal (6 transacciones, cadencia de horas)..."
for i in 6 5 4 3 2 1; do
  enviar "tx-e2e-hist-${SELLO}-${i}" "5$((i))000" "$((i * 360))" "Bogota" 4.71 -74.07 \
    "Supermercado La Esquina" "grocery"
done

note "2/3 Transaccion previa en Medellin (hace 11 minutos)..."
enviar "tx-e2e-medellin-${SELLO}" "58000" "11" "Medellin" 6.2442 -75.5812 \
  "Almacen Poblado" "retail"

# Pausa deliberada: el motor procesa por evento y el historial debe estar
# persistido en Cosmos ANTES de evaluar la transaccion anomala. Sin esta espera,
# la carrera entre la escritura del historial y la lectura de las reglas produce
# scores distintos entre corridas — el peor tipo de evidencia.
note "    esperando 30 s a que el motor persista el historial..."
sleep 30

note "3/3 Transaccion anomala: 4.200.000 COP en Madrid..."
enviar "$TX_FRAUDE" "4200000" "0" "Madrid" 40.4168 -3.7038 "Joyeria Serrano" "jewelry"

note ""
note "Esperando el veredicto del motor (hasta 4 min: incluye arranque en frio)..."
VEREDICTO=""
for intento in $(seq 1 24); do
  VEREDICTO="$(curl -s -H "Authorization: Bearer $TOKEN" \
    "${BASE_URL}/api/v1/transactions/${TX_FRAUDE}/analysis" 2>/dev/null || true)"
  if printf '%s' "$VEREDICTO" | grep -q '"flagged"'; then
    break
  fi
  sleep 10
  VEREDICTO=""
done
[ -n "$VEREDICTO" ] || die "El motor no puntuo la transaccion en 4 minutos. Revisar la suscripcion de Event Grid y los registros del motor."

note "Analisis del motor:"
printf '%s\n' "$VEREDICTO" | python -m json.tool 2>/dev/null || printf '%s\n' "$VEREDICTO"

note ""
note "Esperando el caso con su explicacion (hasta 3 min)..."
CASO=""
for intento in $(seq 1 18); do
  CASO="$(curl -s -H "Authorization: Bearer $TOKEN" \
    "${BASE_URL}/api/v1/cases/${TX_FRAUDE}" 2>/dev/null || true)"
  if printf '%s' "$CASO" | grep -q '"explanationState":"GENERATED"'; then
    break
  fi
  sleep 10
done

if printf '%s' "$CASO" | grep -q '"caseId"'; then
  note "Caso:"
  printf '%s\n' "$CASO" | python -m json.tool 2>/dev/null || printf '%s\n' "$CASO"
else
  note "AVISO: el caso aun no aparece. Puede que el explicador este arrancando; reintentar:"
  note "  curl -H \"Authorization: Bearer \$TOKEN\" ${BASE_URL}/api/v1/cases/${TX_FRAUDE}"
fi

note ""
note "================================================================"
note "  transactionId : $TX_FRAUDE"
note "  trace-id      : $TRACE_ID"
note ""
note "  Siguientes verificaciones:"
note "    bash scripts/verify/verify-trace.sh $TX_FRAUDE"
note "    CENTINELA_BASE_URL=$BASE_URL \\"
note "      CENTINELA_ACCESS_TOKEN=<token> \\"
note "      bash scripts/verify/verify-explainer-correspondence.sh $TX_FRAUDE"
note "================================================================"
