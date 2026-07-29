#!/usr/bin/env bash
#
# scripts/verify/run-load-burst.sh — rafaga de carga autenticada para la
# evidencia de escalado (ISS-S3-010).
#
# Uso: run-load-burst.sh [trabajadores] [duracion-segundos]
#      (por defecto 25 trabajadores durante 150 s)
#
# POR QUE TRABAJADORES EN PARALELO Y NO UNA TASA
# ----------------------------------------------
# La regla de escalado de la API es CONCURRENCIA HTTP (10 en vuelo por replica).
# Lo que la dispara no es cuantas peticiones llegan por segundo sino cuantas
# estan EN VUELO a la vez. Con ~25 trabajadores sincronos cuya peticion tarda
# ~1-2 s, la concurrencia sostenida ronda 25: por encima del umbral de una
# replica y suficiente para que KEDA levante 2-3. Al terminar, la ventana de
# enfriamiento las retira — que es la mitad "y posterior reduccion" del criterio.
#
# Las transacciones son inocuas (montos normales, cuentas unicas) a proposito:
# la evidencia de escalado no debe ensuciar la base de casos con miles de
# registros de prueba.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=../lib/parameters.sh
source "$SCRIPT_DIR/../lib/parameters.sh"

load_parameters
require_cmd az
require_cmd curl

TRABAJADORES="${1:-25}"
DURACION="${2:-150}"

BASE_URL="https://$(az containerapp show -g "$RESOURCE_GROUP" -n "ca-${NAME_PREFIX}-api" \
  --query properties.configuration.ingress.fqdn -o tsv)"
APP_ID="$(az ad app list --display-name "${NAME_PREFIX}-api-week1" --query '[0].appId' -o tsv)"
TOKEN="$(az account get-access-token --resource "api://${APP_ID}" --query accessToken -o tsv)"

note() { printf '[load-burst] %s\n' "$*"; }

note "Destino      : $BASE_URL"
note "Trabajadores : $TRABAJADORES concurrentes"
note "Duracion     : ${DURACION}s"

FIN=$(( $(date +%s) + DURACION ))
CONTADOR_DIR="$(mktemp -d)"
trap 'rm -rf "$CONTADOR_DIR"' EXIT

trabajador() {
  local id="$1" enviadas=0 aceptadas=0 rechazadas=0
  while [ "$(date +%s)" -lt "$FIN" ]; do
    local tx="tx-carga-${id}-${enviadas}-$(date +%s%N | tail -c 8)"
    printf '{"transactionId":"%s","accountId":"acc-carga-%s-%s","amount":48000,"currency":"CO