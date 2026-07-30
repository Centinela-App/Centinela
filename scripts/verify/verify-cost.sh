#!/usr/bin/env bash
#
# scripts/verify/verify-cost.sh
# Reporte de credito consumido y de lo que esta facturando ahora mismo.
#
# SOBRE LA LATENCIA DE COST MANAGEMENT
# ------------------------------------
# Los datos de consumo tardan entre 8 y 24 horas en consolidarse. Un total de
# 0,00 recien creado un recurso NO significa que sea gratis: significa que
# todavia no se ha facturado. Este script lo dice explicitamente en vez de dejar
# que el cero se lea como buena noticia.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

load_parameters
require_cmd az

TOPE_USD="${CENTINELA_BUDGET_USD:-60}"

note() { printf '[verify-cost] %s\n' "$*"; }

az account show >/dev/null 2>&1 || { note "Sin sesion de Azure. Nada que verificar."; exit 0; }

inicio="$(date -u -d "$(date -u +%Y-%m-01)" +%Y-%m-%d 2>/dev/null || date -u +%Y-%m-01)"
fin="$(date -u +%Y-%m-%d)"

note "Periodo: $inicio a $fin"
note "Tope del proyecto: ${TOPE_USD} USD"
echo ""

# --- 1. Consumo acumulado ----------------------------------------------------
consumo="$(az consumption usage list --start-date "$inicio" --end-date "$fin" \
  --query "[].{costo:pretaxCost, categoria:meterDetails.meterCategory}" -o tsv 2>/dev/null)"

if [ -z "$consumo" ]; then
  note "Cost Management no devolvio registros para el periodo."
  note "Causa habitual: latencia de consolidacion (8-24 h) o suscripcion sin consumo facturable."
else
  printf '%s\n' "$consumo" | awk -F'\t' '
    { total += $1; por_categoria[$2] += $1; registros++ }
    END {
      printf "  Registros de uso        : %d\n", registros
      printf "  Consumo acumulado       : %.4f USD\n\n", total
      if (total > 0) {
        print "  Desglose por servicio:"
        for (k in por_categoria)
          if (por_categoria[k] > 0) printf "    %-32s %.4f USD\n", k, por_categoria[k]
      } else {
        print "  Todos los registros tienen costo cero."
        print "  ATENCION: cero no es lo mismo que gratis. Los cargos de un recurso"
        print "  recien creado tardan entre 8 y 24 horas en aparecer aqui."
      }
    }'
fi

echo ""
# --- 2. Que esta facturando ahora mismo -------------------------------------
note "Recursos activos en '$RESOURCE_GROUP':"
az resource list -g "$RESOURCE_GROUP" --query "[].{tipo:type, nombre:name}" -o tsv 2>/dev/null \
  | sed 's/Microsoft\.//' | sort | while IFS=$'\t' read -r tipo nombre; do
      printf '    %-45s %s\n' "$tipo" "$nombre"
    done

echo ""
note "Lo que factura por tiempo y conviene apagar al cerrar la jornada:"
cat <<'EOF'
    Container Registry Basic     ~0,167 USD/dia   (ACR no tiene nivel gratuito)
    Container Apps (Consumption) solo si hay replicas activas; 180.000 vCPU-s/mes gratis
    Log Analytics                5 GB/mes gratis; tope diario fijado en 1 GB
    Application Insights         ingesta contra la misma cuota de Log Analytics

    App Service Plan y PostgreSQL facturan por hora y son el gasto principal
    cuando estan desplegados. Apagarlos: bash scripts/shutdown-daily.sh
EOF

echo ""
note "RESULTADO: OK (reporte generado)"
