#!/usr/bin/env bash
#
# stop.sh — desmonta el entorno local POR COMPLETO.
#
#   bash stop.sh          detiene y elimina contenedores, red y volumenes
#   bash stop.sh --keep   conserva los volumenes (los datos sobreviven)
#
# El defecto elimina los volumenes a proposito: el entorno local es un banco de
# pruebas, y un banco de pruebas que acumula estado entre sesiones produce
# resultados que dependen de que se probo ayer. Quien quiera conservar datos lo
# pide explicitamente con --keep.

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

note() { printf '[stop] %s\n' "$*"; }

command -v docker >/dev/null 2>&1 || { note "Docker no esta en el PATH; nada que detener."; exit 0; }
docker info >/dev/null 2>&1 || { note "El daemon de Docker no responde; nada que detener."; exit 0; }

VOLUME_ARGS=(--volumes)
for arg in "$@"; do
  case "$arg" in
    --keep) VOLUME_ARGS=() ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) note "Argumento desconocido: $arg (usa --keep o --help)"; exit 1 ;;
  esac
done

# --remove-orphans cubre contenedores de versiones anteriores del compose que ya
# no figuran en el archivo: sin el, un servicio renombrado queda corriendo
# huerfano y nadie vuelve a mirarlo.
note "Desmontando el entorno local..."
docker compose down "${VOLUME_ARGS[@]}" --remove-orphans

if [ "${#VOLUME_ARGS[@]}" -gt 0 ]; then
  note "Entorno desmontado. Contenedores, red y volumenes eliminados."
else
  note "Entorno desmontado. Volumenes conservados (--keep)."
fi

# Verificacion honesta: se comprueba que no quedo nada, en vez de afirmarlo.
restantes="$(docker compose ps -q 2>/dev/null | wc -l)"
if [ "${restantes:-0}" -gt 0 ]; then
  note "AVISO: quedan $restantes contenedor/es del proyecto. Revisar: docker compose ps"
  exit 1
fi
note "Verificado: ningun contenedor del proyecto sigue corriendo."
