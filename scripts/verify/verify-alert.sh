#!/usr/bin/env bash
#
# scripts/verify/verify-alert.sh
# Verifica la alerta configurada: condicion, umbral, ventana y destinatario.
#
# LO QUE ESTE SCRIPT NO DEMUESTRA
# --------------------------------
# Que la alerta se dispare. Eso exige provocar la condicion sobre el sistema en
# ejecucion y se comprueba aparte. La distincion no es formal: una alerta bien
# configurada cuya consulta no devuelve nunca lo que se espera esta, a efectos
# practicos, apagada — y se ve exactamente igual que una que funciona.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

load_parameters
require_cmd az

ALERTA="alert-${NAME_PREFIX}-transacciones-sin-scoring"
GRUPO="ag-${NAME_PREFIX}-oncall"
fail=0

note() { printf '[verify-alert] %s\n' "$*"; }
ok()   { printf '[verify-alert]   OK — %s\n' "$*"; }
bad()  { printf '::error::%s\n' "$*"; fail=1; }

az account show >/dev/null 2>&1 || { note "Sin sesion de Azure. Nada que verificar."; exit 0; }

az extension show --name scheduled-query >/dev/null 2>&1 \
  || az extension add --name scheduled-query --upgrade --only-show-errors --output none 2>/dev/null

# --- 1. La alerta existe y esta habilitada ----------------------------------
datos="$(az monitor scheduled-query show -g "$RESOURCE_GROUP" -n "$ALERTA" \
  --query "{habilitada:enabled, severidad:severity, ventana:windowSize, frecuencia:evaluationFrequency}" \
  -o tsv 2>/dev/null)" || { bad "La alerta '$ALERTA' no existe."; exit 1; }

habilitada="$(echo "$datos" | cut -f1)"
severidad="$(echo "$datos" | cut -f2)"
ventana="$(echo "$datos" | cut -f3)"
frecuencia="$(echo "$datos" | cut -f4)"

ok "alerta '$ALERTA' existe"

if [ "$habilitada" = "True" ] || [ "$habilitada" = "true" ]; then
  ok "habilitada"
else
  bad "La alerta existe pero esta DESHABILITADA: no notificara nada."
fi

ok "severidad $severidad, ventana $ventana, evaluacion cada $frecuencia"

# Severidad 0-1 significa "requiere intervencion humana". Una alerta de
# severidad 3 o 4 se archiva sin leer, que es lo mismo que no tenerla.
if [ "${severidad:-4}" -le 1 ]; then
  ok "severidad adecuada para una condicion que exige intervencion humana"
else
  note "  aviso: severidad $severidad — las alertas de baja severidad tienden a ignorarse"
fi

# --- 2. Tiene destinatario ---------------------------------------------------
# Una alerta sin grupo de accion se dispara en silencio. Es el fallo mas comun y
# el mas dificil de notar, porque el recurso existe y parece configurado.
grupos="$(az monitor scheduled-query show -g "$RESOURCE_GROUP" -n "$ALERTA" \
  --query "actions.actionGroups | length(@)" -o tsv 2>/dev/null || echo 0)"
if [ "${grupos:-0}" -ge 1 ]; then
  ok "tiene $grupos grupo/s de accion asociado/s"
else
  bad "La alerta no tiene grupo de accion: se dispararia en silencio."
fi

correos="$(az monitor action-group show -g "$RESOURCE_GROUP" -n "$GRUPO" \
  --query "emailReceivers | length(@)" -o tsv 2>/dev/null || echo 0)"
if [ "${correos:-0}" -ge 1 ]; then
  ok "grupo '$GRUPO' con $correos destinatario/s de correo"
else
  bad "El grupo de accion no tiene destinatarios: una alerta sin destinatario no alerta a nadie."
fi

# --- 3. La condicion es la esperada -----------------------------------------
consulta="$(az monitor scheduled-query show -g "$RESOURCE_GROUP" -n "$ALERTA" \
  --query "criteria.allOf[0].query" -o tsv 2>/dev/null)"
umbral="$(az monitor scheduled-query show -g "$RESOURCE_GROUP" -n "$ALERTA" \
  --query "criteria.allOf[0].threshold" -o tsv 2>/dev/null)"

if printf '%s' "$consulta" | grep -q "EVENT_PUBLISH" && printf '%s' "$consulta" | grep -q "SCORING"; then
  ok "la condicion compara transacciones publicadas contra transacciones puntuadas"
else
  bad "La consulta de la alerta no compara EVENT_PUBLISH contra SCORING: no detecta la condicion documentada."
fi

ok "umbral: mas de ${umbral:-?} en la ventana"

echo ""
note "PENDIENTE, POR DISENO: el disparo real de la alerta exige provocar la"
note "condicion sobre el sistema en ejecucion. Se demuestra deteniendo el motor"
note "de scoring y enviando trafico."

echo ""
if [ "$fail" -eq 0 ]; then
  note "RESULTADO: OK (configuracion)"
else
  note "RESULTADO: FALLO"
fi
exit "$fail"
