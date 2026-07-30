#!/usr/bin/env bash
#
# scripts/verify/verify-trace.sh
# Reconstruye el recorrido completo de UNA transaccion, con tiempos por etapa.
#
# Uso: verify-trace.sh <transactionId>
#
# Es la comprobacion literal del requisito: "dado un identificador de
# transaccion, el sistema debe mostrar su recorrido completo con los tiempos de
# cada etapa". Un panel de metricas agregadas no satisface esto, y por eso la
# consulta filtra por una transaccion concreta en vez de agrupar.

set -euo pipefail

TRANSACTION_ID="${1:?Uso: verify-trace.sh <transactionId>}"
RESOURCE_GROUP="${RESOURCE_GROUP:?RESOURCE_GROUP es obligatorio}"
NAME_PREFIX="${NAME_PREFIX:?NAME_PREFIX es obligatorio}"
VENTANA="${CENTINELA_TRACE_WINDOW:-PT2H}"

insights="appi-${NAME_PREFIX}"

note() { printf '[verify-trace] %s\n' "$*"; }

az extension show --name application-insights >/dev/null 2>&1 \
  || az extension add --name application-insights --upgrade --only-show-errors --output none

app_id="$(az monitor app-insights component show -g "$RESOURCE_GROUP" -a "$insights" \
  --query appId -o tsv)" || { echo "::error::No existe '$insights'."; exit 1; }

note "Traza de $TRANSACTION_ID (ventana $VENTANA)"

consulta=$(cat <<KQL
traces
| where message has "transactionId=$TRANSACTION_ID"
| extend
    etapa       = extract(@"stage=([A-Z_]+)", 1, message),
    duracionMs  = toint(extract(@"durationMs=(\d+)", 1, message)),
    desenlace   = extract(@"outcome=([A-Z]+)", 1, message),
    traceId     = extract(@"traceId=([0-9a-f]+)", 1, message),
    motivo      = extract(@"reason=""([^""]*)""", 1, message)
| where isnotempty(etapa)
| project timestamp, etapa, duracionMs, desenlace, traceId, motivo
| order by timestamp asc
KQL
)

resultado="$(az monitor app-insights query --app "$app_id" --analytics-query "$consulta" \
  --offset "$VENTANA" -o json)"

filas="$(echo "$resultado" | jq -r '.tables[0].rows | length')"
if [ "${filas:-0}" -eq 0 ]; then
  echo "::error::No hay ninguna etapa registrada para $TRANSACTION_ID en la ventana $VENTANA."
  note "Causas habituales: la transaccion no existio, o la telemetria aun no se ingirio"
  note "(Application Insights tarda entre 1 y 3 minutos en indexar)."
  exit 1
fi

printf '\n%-14s %-22s %10s %-10s %s\n' "INSTANTE" "ETAPA" "DURACION" "DESENLACE" "MOTIVO"
printf '%s\n' "--------------------------------------------------------------------------------"
echo "$resultado" | jq -r '.tables[0].rows[] | @tsv' | while IFS=$'\t' read -r ts etapa dur desenlace trace motivo; do
  printf '%-14s %-22s %8s ms %-10s %s\n' \
    "$(echo "$ts" | cut -dT -f2 | cut -d. -f1)" "$etapa" "${dur:-0}" "$desenlace" "${motivo:-}"
done

total="$(echo "$resultado" | jq '[.tables[0].rows[][2] // 0] | add')"
lenta="$(echo "$resultado" | jq -r 'reduce .tables[0].rows[] as $r ({"e":"","d":0}; if ($r[2] // 0) > .d then {"e":$r[1],"d":$r[2]} else . end) | "\(.e) (\(.d) ms)"')"

printf '%s\n' "--------------------------------------------------------------------------------"
note "Etapas registradas : $filas"
note "Tiempo acumulado   : ${total:-0} ms"
note "Etapa mas lenta    : $lenta"

# El fallo se localiza donde aparece el primer desenlace FAILURE; las etapas
# posteriores sencillamente no existen.
fallo="$(echo "$resultado" | jq -r '[.tables[0].rows[] | select(.[3] == "FAILURE")] | first | if . then .[1] else "" end')"
if [ -n "$fallo" ] && [ "$fallo" != "null" ]; then
  note "PUNTO DE FALLO     : $fallo"
fi
