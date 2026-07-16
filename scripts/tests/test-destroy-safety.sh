#!/usr/bin/env bash
# test-destroy-safety.sh — TEST-S1-004
# destroy-week1.sh debe RECHAZAR el borrado si la confirmacion tecleada no coincide
# con el nombre del RG, sin llamar a Azure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTROY="$SCRIPT_DIR/../destroy-week1.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

out="$(printf 'nombre-equivocado\n' | env -i PATH="/usr/bin:/bin" ENV_FILE=/dev/null \
    SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000" LOCATION="eastus2" \
    RESOURCE_GROUP="rg-centinela-week1" NAME_PREFIX="cent" APP_SERVICE_SKU="S1" \
    bash "$DESTROY" 2>&1)" && fail "no aborto con confirmacion equivocada"
echo "$out" | grep -qi "no coincide" || fail "no explico la falta de coincidencia"
echo "PASS caso 1: rechaza confirmacion equivocada sin borrar"

echo "TEST-S1-004 OK"
