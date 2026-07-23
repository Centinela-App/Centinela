#!/usr/bin/env bash
#
# scan-repository.sh — detecta secretos, cadenas de conexion o GUIDs reales versionados.
#
# Sale con codigo != 0 si encuentra un patron sensible, para poder usarse como
# gate en CI (capa 4). Dos pasadas:
#   1. Patrones de secreto / cadena de conexion.
#   2. GUIDs con forma de subscription/tenant/objectId de Azure (excepto el
#      placeholder all-zeros 00000000-... usado en fixtures y pruebas).
#      Esta pasada se agrego tras el hallazgo de ISS-S1-003 (subscription real
#      sin enmascarar en evidencia), que la pasada 1 no detectaba.
# Excluye:
#   - .git, target, .idea    -> ruido de build/VCS/IDE
#   - *.md, *.html (pasada 1) -> la documentacion menciona estos patrones como ejemplo
#   - los scripts de escaneo -> contienen los patrones que buscan como cadenas
# El escaneo profundo de secretos reales lo hace gitleaks en CI (capa 4).
#
set -euo pipefail

PATTERNS='AccountKey=|DefaultEndpointsProtocol=|client-secret|BEGIN PRIVATE KEY'

# --- Pasada 1: secretos y cadenas de conexion ----------------------------------
if grep -RInE "${PATTERNS}" . \
        --exclude-dir=.git \
        --exclude-dir=target \
        --exclude-dir=.idea \
        --exclude='*.md' \
        --exclude='*.html' \
        --exclude='.env' \
        --exclude='*.env' \
        --exclude='scan-repository.sh' \
        --exclude='validate-week1-scope.sh'; then
    echo "ERROR: posible secreto o cadena de conexion detectada arriba." >&2
    exit 1
fi

# --- Pasada 2: GUIDs reales (subscription / tenant / objectId) ------------------
# El placeholder all-zeros (00000000-...) es legitimo en fixtures/tests y se ignora.
# Las evidencias deben enmascarar GUIDs reales como '9d3b…da5e' o '<...-redactado>'.
GUID_RE='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
guid_hits="$(grep -RInE "${GUID_RE}" . \
        --exclude-dir=.git \
        --exclude-dir=target \
        --exclude-dir=.idea \
        --exclude='.env' \
        --exclude='*.env' \
        --exclude='scan-repository.sh' \
        --exclude='validate-week1-scope.sh' \
        | grep -vE '00000000-0000' || true)"
if [ -n "${guid_hits}" ]; then
    printf '%s\n' "${guid_hits}" >&2
    echo "ERROR: posible GUID real (subscription/tenant/objectId) versionado arriba. Enmascaralo antes de commitear." >&2
    exit 1
fi

echo "OK: no se detectaron secretos, cadenas de conexion ni GUIDs reales."
