#!/usr/bin/env bash
#
# scripts/verify/verify-scaling.sh
# Evidencia de escalado bajo carga: observa replicas antes, durante y despues.
#
# El enunciado es explicito: una configuracion de escalado documentada NO es
# evidencia de que el escalado ocurra. Este script no configura nada; solo mira
# y registra lo que pasa mientras alguien genera carga.
#
# Uso:
#   1. Ejecutar este script (empieza a muestrear cada 10 s).
#   2. Lanzar la carga desde la app de pruebas (boton "carga sostenida").
#   3. Detener la carga y esperar a que el script termine.
#
# El resultado se guarda en docs/evidence/iss-s3-009/ para adjuntarlo como
# evidencia.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RESOURCE_GROUP="${RESOURCE_GROUP:?RESOURCE_GROUP es obligatorio}"
NAME_PREFIX="${NAME_PREFIX:?NAME_PREFIX es obligatorio}"

DURACION_MIN="${CENTINELA_SCALING_OBSERVATION_MINUTES:-12}"
INTERVALO_S="${CENTINELA_SCALING_SAMPLE_INTERVAL:-10}"

app="ca-${NAME_PREFIX}-api"
sello="$(date -u +%Y%m%dT%H%M%SZ)"
destino="$REPO_ROOT/docs/evidence/iss-s3-010/run-$sello"
mkdir -p "$destino"
salida="$destino/replicas.tsv"

note() { printf '[verify-scaling] %s\n' "$*"; }

note "Observando '$app' durante $DURACION_MIN minutos, cada $INTERVALO_S s."
note "Evidencia: $salida"
note ""
note "AHORA: lanza la carga desde la app de pruebas y detenla a mitad del periodo."
note ""

printf 'instante_utc\treplicas\trevision\n' > "$salida"

muestras=$(( DURACION_MIN * 60 / INTERVALO_S ))
maximo=0
minimo=999

for i in $(seq 1 "$muestras"); do
  instante="$(date -u +%H:%M:%S)"
  revision="$(az containerapp revision list -g "$RESOURCE_GROUP" -n "$app" \
    --query "[?properties.active].name | [0]" -o tsv 2>/dev/null || echo '')"
  replicas="$(az containerapp replica list -g "$RESOURCE_GROUP" -n "$app" \
    --revision "$revision" --query 'length(@)' -o tsv 2>/dev/null || echo 0)"

  printf '%s\t%s\t%s\n' "$instante" "$replicas" "$revision" >> "$salida"

  [ "$replicas" -gt "$maximo" ] && maximo="$replicas"
  [ "$replicas" -lt "$minimo" ] && minimo="$replicas"

  # Barra visual para que el aumento y la bajada se vean en vivo durante la
  # sustentacion, sin tener que abrir el portal.
  barra=""
  for _ in $(seq 1 "$replicas"); do barra="${barra}#"; done
  printf '  %s  %2s %s\n' "$instante" "$replicas" "$barra"

  sleep "$INTERVALO_S"
done

{
  echo "Observacion de escalado — $app"
  echo "Inicio (UTC): $sello"
  echo "Duracion: $DURACION_MIN min, muestreo cada $INTERVALO_S s"
  echo "Replicas minimas observadas: $minimo"
  echo "Replicas maximas observadas: $maximo"
  echo ""
  if [ "$maximo" -gt "$minimo" ]; then
    echo "RESULTADO: se observo aumento y posterior reduccion del numero de instancias."
  else
    echo "RESULTADO: NO se observo variacion. La carga generada fue insuficiente para"
    echo "superar el umbral de concurrencia configurado, o la observacion termino antes"
    echo "de que KEDA reaccionara."
  fi
} | tee "$destino/resumen.txt"
