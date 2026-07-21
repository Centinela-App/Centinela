#!/bin/bash
set -euo pipefail

# Uso: ./validate-queue.sh <staging|production>
ENVIRONMENT="${1:-}"

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
  echo "Error: debes especificar 'staging' o 'production'." >&2
  exit 1
fi

echo "Iniciando validación para el ambiente: $ENVIRONMENT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if "$SCRIPT_DIR/tests/test-queue-roundtrip.sh" "$ENVIRONMENT"; then
  echo "Prueba exitosa. El ambiente $ENVIRONMENT está operativo."
  exit 0
else
  echo "La prueba falló. Revisa los logs y la evidencia en docs/evidence/queue/." >&2
  exit 1
fi