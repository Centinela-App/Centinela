#!/usr/bin/env bash
# common.sh — utilidades compartidas: logging, errores, reintentos, mask de secretos.
# Se hace "source" desde los demas scripts. No conoce Azure ni parametros de negocio.

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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Falta la dependencia requerida: '$1'. Instalala y reintenta."
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
