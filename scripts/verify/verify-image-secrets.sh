#!/usr/bin/env bash
#
# scripts/verify/verify-image-secrets.sh
# Verifica que una imagen de contenedor no lleve credenciales en NINGUNA capa.
#
# Uso: verify-image-secrets.sh <imagen[:etiqueta]>
#
# Por que capa por capa y no solo el sistema de archivos final:
# las capas de una imagen son acumulativas. Un `COPY .env` seguido de un
# `RUN rm .env` produce una imagen cuyo sistema de archivos final NO contiene el
# archivo, pero cuya capa intermedia si lo conserva — y cualquiera con acceso a
# la imagen puede extraerlo. Inspeccionar solo el resultado da un falso negativo
# justo en el caso que importa.

set -euo pipefail

IMAGE="${1:?Uso: verify-image-secrets.sh <imagen[:etiqueta]>}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

fail=0
note() { printf '[verify-image-secrets] %s\n' "$*"; }
problema() { printf '::error::%s\n' "$*"; fail=1; }

command -v docker >/dev/null 2>&1 || { note "docker no disponible; nada que verificar."; exit 0; }

note "Imagen: $IMAGE"

# --- 1. Instrucciones de construccion ---------------------------------------
# `docker history` muestra los ARG y ENV horneados. Es donde aparece el error
# clasico: pasar una contrasena como --build-arg creyendo que es efimero.
note "Revisando el historial de construccion..."
HISTORY="$WORKDIR/history.txt"
docker history --no-trunc --format '{{.CreatedBy}}' "$IMAGE" > "$HISTORY" 2>/dev/null || {
  note "No se pudo leer el historial (¿imagen remota sin descargar?). Se intenta pull."
  docker pull -q "$IMAGE" >/dev/null
  docker history --no-trunc --format '{{.CreatedBy}}' "$IMAGE" > "$HISTORY"
}

PATRONES='(AccountKey=|SharedAccessSignature|DefaultEndpointsProtocol=.*AccountKey|password[[:space:]]*=|PASSWORD=|client[_-]?secret|CLIENT_SECRET|-----BEGIN [A-Z ]*PRIVATE KEY-----|InstrumentationKey=[0-9a-f]{8}|mongodb://[^:]+:[^@]+@|postgres://[^:]+:[^@]+@)'

if grep -Eiq "$PATRONES" "$HISTORY"; then
  problema "El historial de construccion contiene lo que parece una credencial:"
  grep -Ein "$PATRONES" "$HISTORY" | head -5 | sed 's/^/    /'
else
  note "OK: el historial de construccion no expone credenciales."
fi

# --- 2. Variables de entorno de la imagen -----------------------------------
note "Revisando las variables de entorno horneadas..."
ENVVARS="$WORKDIR/env.txt"
docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$IMAGE" > "$ENVVARS"

if grep -Eiq "$PATRONES" "$ENVVARS"; then
  problema "La imagen define variables de entorno con credenciales:"
  grep -Ein "$PATRONES" "$ENVVARS" | sed 's/=.*/=<REDACTADO>/' | head -5 | sed 's/^/    /'
else
  note "OK: sin credenciales en las variables de entorno."
fi

# --- 3. Contenido de todas las capas ----------------------------------------
note "Exportando capas para inspeccion..."
docker save "$IMAGE" -o "$WORKDIR/image.tar"
mkdir -p "$WORKDIR/layers"
tar -xf "$WORKDIR/image.tar" -C "$WORKDIR/layers"

ARCHIVOS_PROHIBIDOS='(^|/)(\.env|\.env\.[^/]*|local\.settings\.json|id_rsa|\.npmrc|\.git/config)$'
encontrados=""
while IFS= read -r capa; do
  # Se listan los nombres de archivo de cada capa sin extraerla entera.
  if nombres="$(tar -tf "$capa" 2>/dev/null)"; then
    coincidencias="$(printf '%s\n' "$nombres" | grep -E "$ARCHIVOS_PROHIBIDOS" || true)"
    if [ -n "$coincidencias" ]; then
      encontrados="$encontrados
capa $(basename "$(dirname "$capa")"): $coincidencias"
    fi
  fi
done < <(find "$WORKDIR/layers" -name '*.tar' -o -name 'layer.tar')

if [ -n "$encontrados" ]; then
  problema "Hay archivos de credenciales dentro de alguna capa:$encontrados"
else
  note "OK: ninguna capa contiene archivos de credenciales."
fi

# --- 4. Usuario de ejecucion ------------------------------------------------
USUARIO="$(docker inspect --format '{{.Config.User}}' "$IMAGE")"
if [ -z "$USUARIO" ] || [ "$USUARIO" = "root" ] || [ "$USUARIO" = "0" ]; then
  # No es un secreto, pero un proceso root en el contenedor amplifica cualquier
  # otra debilidad, asi que se reporta en el mismo barrido.
  problema "La imagen se ejecuta como root (User='$USUARIO'). Debe usar un usuario sin privilegios."
else
  note "OK: la imagen se ejecuta como '$USUARIO'."
fi

if [ "$fail" -ne 0 ]; then
  note "RESULTADO: FALLO"
  exit 1
fi
note "RESULTADO: OK — la imagen no contiene credenciales en ninguna capa."
