#!/usr/bin/env bash
#
# scripts/local/simulate-scoring.sh — hace en local lo que el motor haria en Azure.
#
# Uso: simulate-scoring.sh <transactionId> [score] [umbral]
#      (score por defecto 82, umbral por defecto 60)
#
# POR QUE EXISTE
# --------------
# No hay emulador local de Event Grid, asi que el salto API -> motor no ocurre en
# docker-compose. Este script reproduce EXACTAMENTE los dos efectos observables
# del motor cuando una transaccion supera el umbral:
#
#   1. Persiste el registro de scoring en Mongo (lo que el explicador leera).
#   2. Encola flagged-case-v1 en Azurite (lo que abre el caso).
#
# Los datos simulados respetan los contratos reales — flagged-case-v1 con su
# traceparent, y observedValues con las claves que las reglas registran — porque
# un simulador que se desvia del contrato prueba un sistema que no existe.
#
# LIMITE HONESTO: esto NO ejecuta las reglas. El score es el que se pida, no el
# que las reglas calcularian. Sirve para ejercitar caso, explicador, documentos y
# consulta; NO para validar la deteccion, que se prueba con las suites del motor.

set -euo pipefail

TRANSACTION_ID="${1:?Uso: simulate-scoring.sh <transactionId> [score] [umbral]}"
SCORE="${2:-82}"
THRESHOLD="${3:-60}"
ACCOUNT_ID="${SIMULATE_ACCOUNT_ID:-acc-local-simulada}"

# Compose fija el nombre de proyecto 'centinela', asi que los contenedores son
# deterministas: centinela-mongo-1, centinela-azurite-1.
MONGO_CONTAINER="${MONGO_CONTAINER:-centinela-mongo-1}"
NETWORK="${COMPOSE_NETWORK:-centinela_default}"

note() { printf '[simulate-scoring] %s\n' "$*"; }
die()  { printf '[simulate-scoring] ERROR: %s\n' "$*" >&2; exit 1; }

# La cadena de Azurite vive en UN solo archivo (docker-compose.yml, excluido del
# barrido de secretos con su justificacion) y se extrae de la configuracion
# resuelta. Duplicarla aqui obligaria a una segunda exclusion del escaner, y cada
# exclusion nueva es un punto ciego nuevo: el propio escaner detecto la copia.
resolve_azurite_connection() {
  docker compose config 2>/dev/null \
    | grep -m1 'CENTINELA_STORAGE_CONNECTION_STRING' \
    | sed 's/^[[:space:]]*CENTINELA_STORAGE_CONNECTION_STRING:[[:space:]]*//'
}

command -v docker >/dev/null 2>&1 || die "Docker no disponible."
docker inspect "$MONGO_CONTAINER" >/dev/null 2>&1 \
  || die "El entorno local no esta levantado. Ejecuta primero: bash start.sh"

AZURITE_CONN="$(resolve_azurite_connection)"
[ -n "$AZURITE_CONN" ] || die "No se pudo resolver la conexion de Azurite desde docker-compose.yml."

NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TRACEPARENT="00-$(openssl rand -hex 16 2>/dev/null || echo 4bf92f3577b34da6a3ce929d0e0e4736)-$(openssl rand -hex 8 2>/dev/null || echo 00f067aa0ba902b7)-01"

# --- 1. Registro de scoring en Mongo (la fuente del explicador) --------------
note "Escribiendo el registro de scoring en Mongo..."
docker exec -i "$MONGO_CONTAINER" mongosh --quiet centinela <<MONGOSH
db.transactions.replaceOne(
  { transactionId: "${TRANSACTION_ID}" },
  {
    transactionId: "${TRANSACTION_ID}",
    accountId: "${ACCOUNT_ID}",
    amount: 4200000,
    currency: "COP",
    occurredAt: new Date("${NOW_UTC}"),
    traceparent: "${TRACEPARENT}",
    location: { countryCode: "ES", city: "Madrid", latitude: 40.4168, longitude: -3.7038 },
    merchant: { name: "Joyeria Serrano", category: "jewelry" },
    score: {
      total: ${SCORE},
      threshold: ${THRESHOLD},
      flagged: ${SCORE} >= ${THRESHOLD},
      scoredAt: new Date("${NOW_UTC}"),
      triggeredRules: [
        {
          ruleId: "atypical-amount",
          ruleName: "Monto Atípico",
          points: 45,
          observedValues: {
            currentAmount: 4200000, averageAmount: 50000,
            multiplierThreshold: 3, observedMultiplier: 84,
            historySampleSize: 12, currency: "COP"
          }
        },
        {
          ruleId: "geo-impossible",
          ruleName: "Geo-Imposible",
          points: ${SCORE} - 45,
          observedValues: {
            distanceKm: 8000, timeMinutes: 11, calculatedSpeedKmh: 43636.36,
            maxSpeedKmh: 800,
            previousCity: "Medellín", previousCountryCode: "CO",
            previousTransactionId: "tx-local-anterior",
            previousOccurredAt: "${NOW_UTC}",
            currentCity: "Madrid", currentCountryCode: "ES"
          }
        }
      ]
    }
  },
  { upsert: true }
)
MONGOSH

# --- 2. flagged-case-v1 a la cola (lo que abre el caso) ----------------------
if [ "$SCORE" -ge "$THRESHOLD" ]; then
  note "Encolando flagged-case-v1 en Azurite..."
  MENSAJE="$(printf '{"transactionId":"%s","accountId":"%s","score":%s,"triggeredRules":[{"ruleId":"atypical-amount","points":45},{"ruleId":"geo-impossible","points":%s}],"occurredAt":"%s","scoredAt":"%s","traceparent":"%s"}' \
    "$TRANSACTION_ID" "$ACCOUNT_ID" "$SCORE" "$((SCORE - 45))" "$NOW_UTC" "$NOW_UTC" "$TRACEPARENT")"

  docker run --rm --network "$NETWORK" mcr.microsoft.com/azure-cli:2.67.0 \
    az storage message put \
      --queue-name flagged-cases-production \
      --content "$MENSAJE" \
      --connection-string "$AZURITE_CONN" \
      --output none

  note "Caso encolado. El consumidor de la API lo abrira en segundos."
  note "Consultar:  curl http://localhost:8080/api/v1/cases/${TRANSACTION_ID}"
else
  note "Score ${SCORE} < umbral ${THRESHOLD}: no se encola caso (transaccion limpia)."
  note "Consultar:  curl http://localhost:8080/api/v1/transactions/${TRANSACTION_ID}/analysis"
fi
