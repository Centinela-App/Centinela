#!/usr/bin/env bash
# test-deploy-parameters.sh — TEST-S1-003
# deploy-week1.sh --validate-only debe fallar ANTES de tocar Azure si falta un
# parametro; y validar los parametros offline antes de exigir 'az'.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$SCRIPT_DIR/../deploy-week1.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Caso 1: falta RESOURCE_GROUP -> sale !=0, menciona el faltante, sin usar Azure.
out="$(env -i PATH="/usr/bin:/bin" ENV_FILE=/dev/null \
    SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000" LOCATION="eastus2" \
    NAME_PREFIX="cent" APP_SERVICE_SKU="S1" \
    bash "$DEPLOY" --validate-only 2>&1)" && fail "no fallo con RESOURCE_GROUP faltante"
echo "$out" | grep -qi "RESOURCE_GROUP" || fail "el error no menciona el parametro faltante"
echo "PASS caso 1: falla antes de Azure con parametro faltante"

# Caso 2: todos presentes pero sin 'az' -> valida offline y LUEGO exige az.
out2="$(env -i PATH="/usr/bin:/bin" ENV_FILE=/dev/null \
    SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000" LOCATION="eastus2" \
    RESOURCE_GROUP="rg-centinela-week1" NAME_PREFIX="cent" APP_SERVICE_SKU="S1" \
    bash "$DEPLOY" --validate-only 2>&1)" && fail "esperabamos fallo por falta de az"
echo "$out2" | grep -qi "validados" || fail "no valido parametros antes de az"
echo "$out2" | grep -qi "az" || fail "no fallo por ausencia de az"
echo "PASS caso 2: valida offline y luego exige az"

echo "TEST-S1-003 OK"
