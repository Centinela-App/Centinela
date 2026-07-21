#!/usr/bin/env bash
#
# scan-repository.sh — detecta secretos o cadenas de conexion versionadas.
#
# Sale con codigo != 0 si encuentra un patron sensible, para poder usarse como
# gate en CI (capa 4). Excluye:
#   - .git, target, .idea  -> ruido de build/VCS/IDE
#   - *.md, *.html         -> la documentacion menciona estos patrones como ejemplo
#   - los scripts de escaneo -> contienen los patrones que buscan como cadenas
# El escaneo profundo de secretos reales lo hace gitleaks en CI (capa 4).
#
set -euo pipefail

PATTERNS='AccountKey=|DefaultEndpointsProtocol=|client-secret|BEGIN PRIVATE KEY'

if grep -RInE "${PATTERNS}" . \
        --exclude-dir=.git \
        --exclude-dir=target \
        --exclude-dir=.idea \
        --exclude='*.md' \
        --exclude='*.html' \
        --exclude='scan-repository.sh' \
        --exclude='validate-week1-scope.sh'; then
    echo "ERROR: posible secreto o cadena de conexion detectada arriba." >&2
    exit 1
fi

echo "OK: no se detectaron secretos ni cadenas de conexion."
