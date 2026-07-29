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
#     (scan-repository.sh, validate-week1-scope.sh, verify-image-secrets.sh).
#     Es un punto ciego asumido y acotado: son tres archivos concretos, revisables
#     a mano, y la alternativa —ofuscar los patrones para que el escaner no se
#     detecte a si mismo— haria el catalogo ilegible y fragil.
# El escaneo profundo de secretos reales lo hace gitleaks en CI (capa 4).
#
set -euo pipefail

PATTERNS='AccountKey=|DefaultEndpointsProtocol=|client-secret|BEGIN PRIVATE KEY'

# --- Pasada 1: secretos y cadenas de conexion ----------------------------------
if grep -RInE "${PATTERNS}" . \
        --exclude-dir=.git \
        --exclude-dir=target \
        --exclude-dir=.idea \
        --exclude-dir=deploy-run \
        --exclude='*.md' \
        --exclude='*.html' \
        --exclude='.env' \
        --exclude='*.env' \
        --exclude='scan-repository.sh' \
        --exclude='validate-week1-scope.sh' \
        --exclude='verify-image-secrets.sh' \
        --exclude='docker-compose.yml'; then
    # docker-compose.yml contiene la AccountKey de Azurite: la clave PUBLICA y
    # documentada del emulador, identica en toda instalacion del mundo. No es un
    # secreto — no protege nada fuera del emulador local. Se excluye el archivo
    # completo en vez de ofuscar la clave porque la ofuscacion enganaria a este
    # escaner sin proteger nada, y un escaner al que se le puede mentir facil es
    # peor que un punto ciego declarado.
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
        --exclude-dir=deploy-run \
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
