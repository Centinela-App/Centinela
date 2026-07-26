#!/usr/bin/env bash
# Validacion local de ISS-S2-014. No ejecuta Azure ni elimina recursos.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET="scripts/tests/test-week2-closeout.sh"
PASS=0
FAIL=0

pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
check_file() { [ -f "$REPO_ROOT/$1" ] && pass "Existe $1." || fail "Falta $1."; }
check_grep() {
  local pattern="$1" file="$2" description="$3"
  grep -Eq -- "$pattern" "$REPO_ROOT/$file" && pass "$description" || fail "$description"
}

check_file "$TARGET"
check_file "docs/evidence/iss-s2-014/.gitkeep"
check_file "docs/evidence/iss-s2-014/README.md"

if bash -n "$REPO_ROOT/$TARGET"; then
  pass "El script de cierre tiene sintaxis Bash valida."
else
  fail "El script de cierre tiene errores de sintaxis Bash."
fi

check_grep 'START_DATE=""' "$TARGET" "La fecha inicial debe proporcionarse explicitamente."
check_grep '--destroy' "$TARGET" "La eliminacion usa una opcion explicita."
check_grep 'CONFIRMED=1|--yes' "$TARGET" "La eliminacion exige confirmacion adicional."
check_grep 'DESTROY.*CONFIRMED|CONFIRMED.*DESTROY' "$TARGET" "El script bloquea destruccion sin doble confirmacion."
check_grep 'az resource list' "$TARGET" "Se captura inventario antes del cierre."
check_grep 'az role assignment list' "$TARGET" "Se captura RBAC antes del cierre."
check_grep 'Microsoft.CostManagement/query' "$TARGET" "Se consulta Cost Management en el Resource Group."
check_grep 'cost-summary.json' "$TARGET" "Se genera un resumen de costos versionable."
check_grep 'gsub\(\$subscription; "<subscription-id>"\)' "$TARGET" "La evidencia sanitiza el identificador de suscripcion."
check_grep 'sha256sum' "$TARGET" "La evidencia incluye checksums."
check_grep 'if \[ "\$DESTROY" -eq 0 \]' "$TARGET" "El modo predeterminado no elimina recursos."
check_grep 'az group delete' "$TARGET" "El cierre destructivo elimina el Resource Group completo."
check_grep 'az group exists' "$TARGET" "Se confirma la ausencia del Resource Group."
check_grep 'resource-group-exists-after.txt' "$TARGET" "La comprobacion posterior queda como evidencia."

if bash "$REPO_ROOT/scripts/tests/scan-repository.sh"; then
  pass "El escaneo de secretos permanece en verde."
else
  fail "El escaneo de secretos fallo."
fi

printf '\nResultado: %s PASS / %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
