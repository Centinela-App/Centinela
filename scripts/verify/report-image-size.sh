#!/usr/bin/env bash
#
# scripts/verify/report-image-size.sh
# Reporte de tamano de las imagenes, con el desglose por capa.
#
# Uso: report-image-size.sh <servidor-de-registro> <etiqueta>
#
# El tamano importa por dos razones concretas y no por estetica: cada arranque
# en frio de una replica descarga la imagen —y el escalado bajo carga crea
# replicas justo cuando la latencia ya esta sufriendo—, y el registro Basic
# incluye 10 GiB, que se llenan antes de lo que parece con una imagen por commit.

set -euo pipefail

# El registro puede venir vacio: en ese caso se inspeccionan las imagenes locales,
# que es lo que hay disponible antes de publicarlas por primera vez.
REGISTRY="${1-}"
TAG="${2:?Uso: report-image-size.sh <servidor-de-registro|''> <etiqueta>}"

command -v docker >/dev/null 2>&1 || { echo "docker no disponible."; exit 0; }

# referencia <nombre> -> "registro/nombre:etiqueta" o "nombre:etiqueta"
referencia() {
  if [ -n "$REGISTRY" ]; then
    printf '%s/%s:%s' "$REGISTRY" "$1" "$TAG"
  else
    printf '%s:%s' "$1" "$TAG"
  fi
}

imagenes=("centinela-api" "centinela-scoring")

printf '\n%-24s %12s %10s\n' "IMAGEN" "TAMANO" "CAPAS"
printf '%s\n' "-------------------------------------------------"

for nombre in "${imagenes[@]}"; do
  ref="$(referencia "$nombre")"
  docker image inspect "$ref" >/dev/null 2>&1 || docker pull -q "$ref" >/dev/null 2>&1 || {
    printf '%-24s %12s %10s\n' "$nombre" "no disponible" "-"
    continue
  }

  bytes="$(docker image inspect "$ref" --format '{{.Size}}')"
  megas="$(awk -v b="$bytes" 'BEGIN { printf "%.0f MB", b/1024/1024 }')"
  capas="$(docker image inspect "$ref" --format '{{len .RootFS.Layers}}')"
  printf '%-24s %12s %10s\n' "$nombre" "$megas" "$capas"
done

printf '\n%s\n' "Capas mas pesadas de centinela-api:"
docker history --human --format '  {{.Size}}\t{{.CreatedBy}}' "$(referencia centinela-api)" 2>/dev/null \
  | grep -v '0B' | head -8 || true

cat <<'EOF'

Medidas aplicadas para reducir el tamano
---------------------------------------
1. Construccion multietapa. El JDK completo, Maven y el repositorio de
   dependencias (~700 MB juntos) viven en la etapa de build y no se copian a la
   imagen final. Es la unica forma efectiva: borrarlos en una capa posterior los
   deja igualmente dentro de la imagen.
2. Imagen base JRE Alpine en vez de JDK Debian: ~180 MB menos, y solo se pierde
   el compilador, que en produccion no hace falta.
3. .dockerignore que excluye docs/, target/, .git/ y evidencias. Ademas de peso,
   evita que un COPY amplio arrastre el historial del repositorio a una capa.
4. El agente de telemetria se descarga en su propia etapa, de modo que no
   reintroduce herramientas de descarga en la imagen final.

Lo que NO se hizo y por que
---------------------------
No se uso jlink para un runtime a medida. Habria bajado otros ~40 MB a cambio de
tener que recalcular el conjunto de modulos cada vez que cambia una dependencia,
con fallos que solo aparecen en ejecucion. La relacion coste/beneficio no lo
justifica en un proyecto de tres semanas.

Por que el motor de scoring pesa mucho mas que la API
------------------------------------------------------
La diferencia no es descuido: son puntos de partida distintos.

La API parte de eclipse-temurin:21-jre-alpine (~165 MB de base) y le suma su JAR
(~90 MB) y el agente de telemetria (~47 MB).

El motor parte de mcr.microsoft.com/azure-functions/java:4-java21, que trae el
host de Functions, su runtime de .NET y el worker de Java. Esa base ronda los
500 MB y NO es reducible sin abandonar el runtime de Functions — que es
justamente lo que se decidio no hacer: el disparador de Event Grid, el reintento
y la concurrencia ya estaban validados en Semana 2, y reescribirlos como
servicio HTTP habria consumido la semana para llegar al mismo comportamiento
observable.

Es un coste asumido a cambio de no rehacer un componente que funcionaba. Se
mitiga con el hecho de que el motor escala desde cero replicas y sus descargas
son poco frecuentes, no con un intento de adelgazar una imagen base ajena.
EOF
