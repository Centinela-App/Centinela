#!/usr/bin/env bash
#
# scripts/verify/verify-deployment-health.sh
# Comprueba que lo desplegado responde de verdad.
#
# El criterio de exito de un despliegue no es "az devolvio cero", sino "la
# aplicacion contesta". Un contenedor que arranca, falla al conectar con la base
# de datos y se reinicia en bucle produce un despliegue "exitoso" segun el plano
# de control durante varios minutos. Esta comprobacion cierra ese hueco.

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:?RESOURCE_GROUP es obligatorio}"
NAME_PREFIX="${NAME_PREFIX:?NAME_PREFIX es obligatorio}"

INTENTOS="${CENTINELA_HEALTH_ATTEMPTS:-30}"
ESPERA="${CENTINELA_HEALTH_INTERVAL:-10}"

note() { printf '[verify-deployment-health] %s\n' "$*"; }

api_app="ca-${NAME_PREFIX}-api"

note "Resolviendo la direccion publica de '$api_app'..."
fqdn="$(az containerapp show -g "$RESOURCE_GROUP" -n "$api_app" \
  --query properties.configuration.ingress.fqdn -o tsv)"
[ -n "$fqdn" ] || { echo "::error::La aplicacion '$api_app' no tiene ingreso configurado."; exit 1; }

url="https://${fqdn}/actuator/health/readiness"
note "Sondeando $url (hasta $((INTENTOS * ESPERA)) s)"

# El arranque incluye Spring Boot, Flyway y la primera conexion a PostgreSQL por
# Private Endpoint: unos 3-4 minutos en frio. Un timeout corto reportaria un
# fallo que no existe.
for intento in $(seq 1 "$INTENTOS"); do
  codigo="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || echo 000)"
  if [ "$codigo" = "200" ]; then
    note "OK: la aplicacion responde 200 tras $((intento * ESPERA)) s."

    revision="$(az containerapp revision list -g "$RESOURCE_GROUP" -n "$api_app" \
      --query "[?properties.active].name | [0]" -o tsv)"
    note "Revision activa: ${revision:-desconocida}"

    replicas="$(az containerapp replica list -g "$RESOURCE_GROUP" -n "$api_app" \
      --revision "$revision" --query 'length(@)' -o tsv 2>/dev/null || echo '?')"
    note "Replicas en ejecucion: $replicas"
    exit 0
  fi
  note "  intento $intento/$INTENTOS -> HTTP $codigo"
  sleep "$ESPERA"
done

echo "::error::La aplicacion no respondio 200 tras $((INTENTOS * ESPERA)) segundos."
note "Ultimos registros de la aplicacion:"
az containerapp logs show -g "$RESOURCE_GROUP" -n "$api_app" --tail 50 2>/dev/null || true
exit 1
