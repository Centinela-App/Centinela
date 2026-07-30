#!/usr/bin/env bash
#
# scripts/verify/verify-observability-setup.sh
# Verifica que la infraestructura de telemetria esta creada y acotada.
#
# NO verifica que haya datos: eso depende de que el pipeline genere trafico y se
# comprueba con verify-trace.sh. Separarlo importa — confundir "el recurso
# existe" con "la observabilidad funciona" es como se llega a una demostracion
# en la que el panel esta vacio.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

load_parameters
require_cmd az

INSIGHTS="appi-${NAME_PREFIX}"
WORKSPACE="log-${NAME_PREFIX}"
fail=0

note() { printf '[verify-observability] %s\n' "$*"; }
ok()   { printf '[verify-observability]   OK — %s\n' "$*"; }
bad()  { printf '::error::%s\n' "$*"; fail=1; }

az account show >/dev/null 2>&1 || { note "Sin sesion de Azure. Nada que verificar."; exit 0; }

# --- 1. Application Insights ------------------------------------------------
tipo="$(az monitor app-insights component show -g "$RESOURCE_GROUP" -a "$INSIGHTS" \
  --query "applicationType" -o tsv 2>/dev/null)" \
  || { bad "Application Insights '$INSIGHTS' no existe."; exit 1; }
ok "Application Insights '$INSIGHTS' existe (tipo: $tipo)"

# El recurso debe estar respaldado por el workspace, no ser clasico: los
# recursos clasicos no admiten consultas KQL sobre 'traces' con la misma forma.
workspace_id="$(az monitor app-insights component show -g "$RESOURCE_GROUP" -a "$INSIGHTS" \
  --query "workspaceResourceId" -o tsv 2>/dev/null)"
if [ -n "$workspace_id" ] && [ "$workspace_id" != "null" ]; then
  ok "respaldado por Log Analytics (modo workspace)"
else
  bad "Application Insights no esta respaldado por un workspace: las consultas de operacion no funcionaran igual."
fi

# --- 2. Tope diario de ingesta ----------------------------------------------
# Sin tope, un bucle de reintentos ruidoso puede multiplicar el volumen por
# veinte en una noche. El tope convierte un susto de facturacion en una perdida
# de datos acotada.
cuota="$(az monitor log-analytics workspace show -g "$RESOURCE_GROUP" -n "$WORKSPACE" \
  --query "workspaceCapping.dailyQuotaGb" -o tsv 2>/dev/null)"
retencion="$(az monitor log-analytics workspace show -g "$RESOURCE_GROUP" -n "$WORKSPACE" \
  --query "retentionInDays" -o tsv 2>/dev/null)"

if [ -n "$cuota" ] && [ "$cuota" != "-1.0" ] && [ "$cuota" != "null" ]; then
  ok "tope diario de ingesta: ${cuota} GB"
else
  bad "No hay tope diario de ingesta: el consumo de telemetria no tiene techo."
fi

if [ "${retencion:-0}" -le 31 ]; then
  ok "retencion: ${retencion} dias (dentro del nivel sin costo adicional)"
else
  note "  aviso: retencion de ${retencion} dias — por encima de 31 se factura"
fi

# --- 3. Cadena de conexion disponible ---------------------------------------
# Se comprueba que EXISTE, no se imprime: es el dato que la plataforma inyecta
# en los contenedores y no debe acabar en un archivo de evidencia.
if az monitor app-insights component show -g "$RESOURCE_GROUP" -a "$INSIGHTS" \
     --query connectionString -o tsv >/dev/null 2>&1; then
  ok "cadena de conexion disponible (no se imprime a proposito)"
else
  bad "No se pudo obtener la cadena de conexion."
fi

# --- 4. ¿Hay telemetria ingerida? -------------------------------------------
# No es un fallo que no la haya; es informacion sobre que se puede demostrar.
app_id="$(az monitor app-insights component show -g "$RESOURCE_GROUP" -a "$INSIGHTS" \
  --query appId -o tsv 2>/dev/null)"
filas="$(az monitor app-insights query --app "$app_id" \
  --analytics-query "union * | summarize n = count()" --offset PT24H \
  --query "tables[0].rows[0][0]" -o tsv 2>/dev/null || echo 0)"

if [ "${filas:-0}" -gt 0 ]; then
  ok "telemetria ingerida en las ultimas 24 h: $filas registros"
else
  note "  sin telemetria ingerida todavia — la traza individual (ISS-S3-017) no se puede demostrar hasta que el pipeline genere trafico"
fi

echo ""
if [ "$fail" -eq 0 ]; then
  note "RESULTADO: OK"
else
  note "RESULTADO: FALLO"
fi
exit "$fail"
