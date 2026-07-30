#!/usr/bin/env bash
#
# scripts/verify/verify-explainer-correspondence.sh
# Verifica que la explicacion de un caso real se corresponde con lo que decidio
# el motor: mismo score, mismo umbral, y una frase por cada regla activada.
#
# Uso: verify-explainer-correspondence.sh <transactionId> [<url-base>]
#
# Por que no basta con las pruebas unitarias: esas verifican la plantilla contra
# datos de prueba. Esto verifica el sistema desplegado contra un caso que ocurrio
# de verdad, que es donde aparece la divergencia entre lo que el motor persistio
# y lo que el explicador leyo.
#
# Requiere un token de acceso en CENTINELA_ACCESS_TOKEN.

set -euo pipefail

TRANSACTION_ID="${1:?Uso: verify-explainer-correspondence.sh <transactionId> [url-base]}"
BASE_URL="${2:-${CENTINELA_BASE_URL:?Define CENTINELA_BASE_URL o pasalo como argumento}}"
TOKEN="${CENTINELA_ACCESS_TOKEN:?Define CENTINELA_ACCESS_TOKEN}"

command -v jq >/dev/null 2>&1 || { echo "::error::jq es necesario para esta verificacion."; exit 1; }

fail=0
note() { printf '[verify-explainer] %s\n' "$*"; }
problema() { printf '::error::%s\n' "$*"; fail=1; }

analysis="$(curl -sS -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v1/transactions/$TRANSACTION_ID/analysis")"
caso="$(curl -sS -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/api/v1/cases/$TRANSACTION_ID")"

echo "$analysis" | jq -e '.transactionId' >/dev/null 2>&1 \
  || { problema "No se obtuvo el analisis de $TRANSACTION_ID."; exit 1; }

score="$(echo "$analysis" | jq -r '.score')"
umbral="$(echo "$analysis" | jq -r '.threshold')"
marcada="$(echo "$analysis" | jq -r '.flagged')"

note "transactionId=$TRANSACTION_ID score=$score umbral=$umbral marcada=$marcada"

if [ "$marcada" != "true" ]; then
  note "La transaccion no fue marcada; no debe existir caso ni explicacion."
  if echo "$caso" | jq -e '.caseId' >/dev/null 2>&1; then
    problema "Existe un caso para una transaccion NO marcada."
  else
    note "OK: no hay caso, como corresponde."
  fi
  exit "$fail"
fi

estado="$(echo "$caso" | jq -r '.explanationState // "AUSENTE"')"
explicacion="$(echo "$caso" | jq -r '.explanation // ""')"

if [ "$estado" = "PENDING" ]; then
  note "El caso existe y esta PENDING: el explicador aun no lo ha procesado."
  note "Esto es correcto por si solo. Reejecutar en unos segundos para verificar"
  note "que la explicacion acaba generandose."
  exit 0
fi

[ -n "$explicacion" ] || problema "El caso esta en estado $estado pero no tiene texto de explicacion."

# --- 1. Encabezado: score y umbral exactos ----------------------------------
esperado="Transacción marcada con score $score (umbral: $umbral)."
if printf '%s' "$explicacion" | head -1 | grep -qF "$esperado"; then
  note "OK: el encabezado declara el score y el umbral registrados."
else
  problema "El encabezado no coincide con el registro. Esperado: '$esperado'"
  printf '    Obtenido: %s\n' "$(printf '%s' "$explicacion" | head -1)"
fi

# --- 2. Una frase por regla activada, con sus puntos exactos ----------------
reglas="$(echo "$analysis" | jq -r '.triggeredRules | length')"
frases="$(printf '%s' "$explicacion" | grep -c '^- ' || true)"

if [ "$reglas" -eq "$frases" ]; then
  note "OK: $frases frases para $reglas reglas activadas."
else
  problema "Hay $reglas reglas activadas pero $frases frases en la explicacion."
fi

while read -r puntos; do
  if printf '%s' "$explicacion" | grep -qF "(+$puntos puntos)"; then
    note "OK: la contribucion de +$puntos puntos aparece en la explicacion."
  else
    problema "La regla que aporto +$puntos puntos no tiene frase en la explicacion."
  fi
done < <(echo "$analysis" | jq -r '.triggeredRules[].points')

# --- 3. Nada afirmado de mas ------------------------------------------------
# La suma de las contribuciones citadas debe dar exactamente el score.
suma="$(echo "$analysis" | jq '[.triggeredRules[].points] | add')"
if [ "$suma" = "$score" ]; then
  note "OK: las contribuciones citadas suman el score total ($suma)."
else
  problema "Las reglas suman $suma pero el score es $score: la explicacion no cuadra."
fi

echo ""
echo "----- Explicacion generada -----"
printf '%s\n' "$explicacion"
echo "--------------------------------"

[ "$fail" -eq 0 ] && note "RESULTADO: OK — correspondencia estricta verificada."
exit "$fail"
