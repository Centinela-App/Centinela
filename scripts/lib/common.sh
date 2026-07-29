#!/usr/bin/env bash
# common.sh — utilidades compartidas: logging, errores, reintentos, mask de secretos.
# Se hace "source" desde los demas scripts. No conoce Azure ni parametros de negocio.

# --- Compatibilidad con Git Bash / MSYS2 en Windows -----------------------------
# En Windows la CLI de Azure imprime CRLF, asi que todo "$(az ... -o tsv)" arrastra
# un \r final y las comparaciones de ids (suscripcion, principalId) fallan siempre.
# Ademas MSYS reescribe como ruta de Windows cualquier argumento que empiece por
# '/', lo que corrompe los --scope de RBAC ('/subscriptions/...').
# En Linux y en Azure Cloud Shell este bloque no se activa y el comportamiento es
# byte a byte el mismo de antes.
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    # Se excluyen SOLO los ids de recurso de Azure. Desactivar la conversion por
    # completo romperia los --template-file, que si necesitan ruta de Windows.
    export MSYS2_ARG_CONV_EXCL='/subscriptions/;/providers/'
    az() { command az "$@" | tr -d '\r'; }
    ;;
esac

if [ -t 2 ]; then
  _C_RED=$'\033[31m'; _C_YELLOW=$'\033[33m'; _C_GREEN=$'\033[32m'; _C_RESET=$'\033[0m'
else
  _C_RED=''; _C_YELLOW=''; _C_GREEN=''; _C_RESET=''
fi

log_info()  { printf '%s[INFO]%s  %s\n'  "$_C_GREEN"  "$_C_RESET" "$*" >&2; }
log_warn()  { printf '%s[WARN]%s  %s\n'  "$_C_YELLOW" "$_C_RESET" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "$_C_RED"    "$_C_RESET" "$*" >&2; }

die() { log_error "$*"; exit 1; }

# mask <valor> -> primeros/ultimos 4 chars; oculta el resto. Evita filtrar secretos.
mask() {
  local v="${1:-}"; local n=${#v}
  if [ "$n" -le 8 ]; then printf '****'; else printf '%s…%s' "${v:0:4}" "${v: -4}"; fi
}

# discover_tool <nombre> — en Windows varios instaladores (PostgreSQL, winget,
# chocolatey, scoop) dejan el binario fuera del PATH de la sesion, asi que la
# herramienta existe pero es invisible para 'command -v'. Se recorren las rutas
# estandar y, si aparece, se anexa su directorio al PATH de esta corrida.
# Devuelve 0 solo si tras la busqueda la herramienta quedo disponible.
discover_tool() {
  local tool="$1" dir
  command -v "$tool" >/dev/null 2>&1 && return 0

  # Array, NO lista sin comillas: varias de estas rutas contienen espacios
  # ("Program Files") y el word splitting las partiria en pedazos inservibles.
  # Los globs se expanden solos; si no hay coincidencia el patron literal no
  # existe como directorio y el '[ -d ]' lo descarta.
  local -a candidates=()
  # Version mas nueva primero (17 antes que 9): 'sort -Vr' sobre lineas completas.
  local versioned
  while IFS= read -r versioned; do
    [ -n "$versioned" ] && candidates+=("$versioned")
  done < <(
    { ls -d "/c/Program Files/PostgreSQL/"*/bin \
           "/c/Program Files (x86)/PostgreSQL/"*/bin \
           "/usr/lib/postgresql/"*/bin 2>/dev/null || true; } | sort -Vr
  )
  candidates+=("$HOME/AppData/Local/Microsoft/WinGet/Links")
  while IFS= read -r dir; do
    [ -n "$dir" ] && candidates+=("$dir")
  done < <(ls -d "$HOME/AppData/Local/Microsoft/WinGet/Packages/"*/ 2>/dev/null || true)
  candidates+=("/c/ProgramData/chocolatey/bin" "$HOME/scoop/shims")

  for dir in "${candidates[@]}"; do
    [ -d "$dir" ] || continue
    if [ -x "$dir/$tool" ] || [ -x "$dir/$tool.exe" ]; then
      export PATH="$PATH:$dir"
      log_info "'$tool' localizado en '$dir' (agregado al PATH de esta corrida)."
      return 0
    fi
  done
  return 1
}

# require_cmd — falla si la dependencia no existe, pero antes intenta descubrirla:
# en una maquina Windows recien preparada 'jq' y 'psql' suelen estar instalados y
# aun asi invisibles hasta reiniciar la terminal. Esto mantiene el despliegue
# replicable sin pedirle al operador que toque el PATH a mano.
require_cmd() {
  command -v "$1" >/dev/null 2>&1 && return 0
  discover_tool "$1" && return 0
  die "Falta la dependencia requerida: '$1'. Instalala y reintenta."
}

# Compatibilidad: los scripts que ya la invocaban siguen funcionando.
ensure_psql_on_path() { discover_tool psql || true; }

# pe_dns_zone_group_exists <private-endpoint> <resource-group>
# OJO: 'az network private-endpoint dns-zone-group show' devuelve EXIT 0 con un
# cuerpo '{}' cuando el grupo NO existe. Por eso 'if az ... show; then' siempre
# da verdadero y el grupo nunca llega a crearse: el Private Endpoint queda vivo
# pero sin registro A, y el servicio resulta irresoluble por nombre dentro de la
# VNet. Aqui se cuenta el contenido real en vez de confiar en el codigo de salida.
pe_dns_zone_group_exists() {
  local pe="$1" rg="$2" n
  n="$(az network private-endpoint dns-zone-group list \
        --endpoint-name "$pe" --resource-group "$rg" \
        --query 'length(@)' -o tsv 2>/dev/null || echo 0)"
  [ "${n:-0}" -ge 1 ] 2>/dev/null
}

# private_dns_has_a_records <zona> <resource-group> — el registro A que publica un
# Private Endpoint es asincrono: existe segundos despues de crear el zone group.
private_dns_has_a_records() {
  local zone="$1" rg="$2" n
  n="$(az network private-dns record-set a list \
        --zone-name "$zone" --resource-group "$rg" \
        --query 'length(@)' -o tsv 2>/dev/null || echo 0)"
  [ "${n:-0}" -ge 1 ] 2>/dev/null
}

# Varios validadores leen JSON con 'jq' sin declararlo antes con require_cmd. Si
# falta, no fallan: devuelven vacio y reportan FAIL sobre recursos que en realidad
# estan bien. Se descubre aqui, en silencio, para que eso no pueda ocurrir.
discover_tool jq >/dev/null 2>&1 || true

# retry_until <n> <cmd...> -> reintenta en silencio hasta que el comando tenga
# exito, con backoff lineal (1s, 2s, 3s...). Pensado para VERIFICAR recursos
# recien creados: un deployment ARM puede reportar exito antes de que sus recursos
# hijo (contenedores, colas, slots, subredes) sean consultables, y el registro DNS
# de un Private Endpoint es asincrono por diseno. Sin esto la verificacion falla
# por carrera aunque la infraestructura sea correcta.
retry_until() {
  local max="$1"; shift; local attempt=1
  while true; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    [ "$attempt" -ge "$max" ] && return 1
    sleep "$attempt"
    attempt=$((attempt + 1))
  done
}

# with_retry <n> <cmd...> -> reintenta hasta n veces con backoff lineal.
with_retry() {
  local max="$1"; shift; local attempt=1
  until "$@"; do
    if [ "$attempt" -ge "$max" ]; then return 1; fi
    log_warn "Intento $attempt/$max fallo; reintentando en ${attempt}s..."
    sleep "$attempt"; attempt=$((attempt + 1))
  done
  return 0
}
