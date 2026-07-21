#!/usr/bin/env bash
# send-transaction-load.sh — Genera solicitudes validas continuas con IDs unicos
# Parte de la prueba HA (HU-S1-005 / FEAT-S1-005)
#
# Uso: ./scripts/tests/send-transaction-load.sh --duration 120 --interval 0.5 --output /path/to/log.log
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# -----------------------------------------------------------------------------
# Configuracion
# -----------------------------------------------------------------------------
DURATION=120          # Duracion total de la prueba en segundos
INTERVAL=0.5          # Intervalo base entre solicitudes (segundos)
MAX_RANDOM_DELAY=0.3  # Variabilidad aleatoria maxima (segundos)
OUTPUT_FILE=""         # Archivo de salida para logs
LOAD_LOG_FILE=""       # Archivo CSV para resultados

# -----------------------------------------------------------------------------
# Variables de la API
# -----------------------------------------------------------------------------
: "${CENTINELA_API_BASE_URL:?Define CENTINELA_API_BASE_URL}"
: "${CENTINELA_SERVICE_TOKEN:?Define CENTINELA_SERVICE_TOKEN}"

# -----------------------------------------------------------------------------
# Funciones
# -----------------------------------------------------------------------------

# parse_args: Parsea argumentos de linea de comandos
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --duration)
        DURATION="$2"
        shift 2
        ;;
      --interval)
        INTERVAL="$2"
        shift 2
        ;;
      --max-random-delay)
        MAX_RANDOM_DELAY="$2"
        shift 2
        ;;
      --output)
        OUTPUT_FILE="$2"
        shift 2
        ;;
      --load-log)
        LOAD_LOG_FILE="$2"
        shift 2
        ;;
      --help|-h)
        echo "Uso: $0 [OPTIONS]"
        echo "Options:"
        echo "  --duration SECONDS      Duracion de la prueba (default: 120)"
        echo "  --interval SECONDS      Intervalo entre solicitudes (default: 0.5)"
        echo "  --max-random-delay SECONDS  Variabilidad aleatoria (default: 0.3)"
        echo "  --output FILE           Archivo de log principal"
        echo "  --load-log FILE         Archivo CSV con resultados"
        echo "  --help, -h              Muestra esta ayuda"
        exit 0
        ;;
      *)
        log_error "Argumento desconocido: $1"
        exit 1
        ;;
    esac
  done
  
  # Validar que tenemos archivos de salida
  if [ -z "$OUTPUT_FILE" ]; then
    log_error "Debe especificar --output"
    exit 1
  fi
  
  if [ -z "$LOAD_LOG_FILE" ]; then
    LOAD_LOG_FILE="${OUTPUT_FILE%.log}.csv"
  fi
}

# generate_transaction_payload: Genera un payload JSON para la transaccion
generate_transaction_payload() {
  local transaction_id="$1"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  # Generar datos pseudo-aleatorios pero consistentes
  local account_id="acct-ha-$(printf '%04d' $((RANDOM % 10000)))"
  local amount_int=$((RANDOM % 1000000 + 1000))
  local amount_dec=$((RANDOM % 100))
  local currencies=("COP" "USD" "EUR")
  local currency="${currencies[$((RANDOM % 3))]}"
  local countries=("CO" "US" "MX" "AR")
  local country="${countries[$((RANDOM % 4))]}"
  local cities=("Bogota" "New York" "Mexico City" "Buenos Aires")
  local city="${cities[$((RANDOM % 4))]}"
  local merchants=("Tienda HA Test" "Comercio Resiliencia" "Demo HA" "Test Load")
  local merchant="${merchants[$((RANDOM % 4))]}"
  local categories=("RETAIL" "FOOD" "TRAVEL" "SERVICES")
  local category="${categories[$((RANDOM % 4))]}"
  
  cat <<JSON
{
  "transactionId": "$transaction_id",
  "accountId": "$account_id",
  "amount": ${amount_int}.${amount_dec},
  "currency": "$currency",
  "occurredAt": "$timestamp",
  "location": {
    "countryCode": "$country",
    "city": "$city"
  },
  "merchant": {
    "name": "$merchant",
    "category": "$category"
  }
}
JSON
}

# send_request: Envia una solicitud y registra el resultado
send_request() {
  local transaction_id="$1"
  local payload="$2"
  local response_file="$3"
  local status_file="$4"
  
  local start_time
  start_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  local http_status
  local error_msg=""
  
  # Enviar la solicitud
  if http_status="$(curl --silent --show-error \
    --output "$response_file" \
    --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $CENTINELA_SERVICE_TOKEN" \
    --header 'Content-Type: application/json' \
    --data-binary "$payload" \
    --max-time 30 \
    "${CENTINELA_API_BASE_URL%/}/api/v1/transactions" 2>&1)"; then
    # La solicitud se completo
    :
  else
    http_status="000"
    error_msg="$http_status"
  fi
  
  local end_time
  end_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  
  # Escribir resultado en formato CSV
  # transactionId,httpStatus,startTime,endTime,hasResponse,errorMsg
  printf '%s,%s,%s,%s,%s,%s\n' \
    "$transaction_id" \
    "$http_status" \
    "$start_time" \
    "$end_time" \
    "$( [ -f "$response_file" ] && echo "true" || echo "false" )" \
    "$(echo "$error_msg" | tr ',' ';')" \
    >> "$LOAD_LOG_FILE"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  parse_args "$@"
  
  require_cmd curl
  require_cmd jq
  
  log_info "========================================"
  log_info "  Generador de Carga HA"
  log_info "========================================"
  log_info "Duracion: ${DURATION}s"
  log_info "Intervalo: ${INTERVAL}s (+ hasta ${MAX_RANDOM_DELAY}s aleatorio)"
  log_info "Log de carga: $LOAD_LOG_FILE"
  log_info "========================================"
  
  # Crear archivo CSV con headers
  echo "transactionId,httpStatus,startTime,endTime,hasResponse,errorMsg" > "$LOAD_LOG_FILE"
  
  # Archivos temporales
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local payload_file="${tmp_dir}/payload.json"
  local response_file="${tmp_dir}/response.json"
  
  # Cleanup
  cleanup_load() {
    rm -rf "$tmp_dir" 2>/dev/null || true
  }
  trap cleanup_load EXIT
  
  local start_time
  start_time="$(date +%s)"
  local request_count=0
  local transaction_prefix="ha-$(date -u +%Y%m%dT%H%M%SZ)"
  
  # Bucle principal de carga
  while true; do
    local current_time
    current_time="$(date +%s)"
    local elapsed=$((current_time - start_time))
    
    # Verificar si termino el tiempo
    if [ "$elapsed" -ge "$DURATION" ]; then
      log_info "Tiempo de prueba completado (${elapsed}s)"
      break
    fi
    
    # Generar transaction ID unico
    local transaction_id="${transaction_prefix}-${request_count}-${RANDOM}"
    
    # Generar payload
    generate_transaction_payload "$transaction_id" > "$payload_file"
    
    # Enviar solicitud
    send_request "$transaction_id" "$(cat "$payload_file")" "$response_file" "$LOAD_LOG_FILE"
    
    request_count=$((request_count + 1))
    
    # Log de progreso periodico
    if [ $((request_count % 10)) -eq 0 ]; then
      log_info "Solicitudes enviadas: $request_count (${elapsed}s/${DURATION}s)"
    fi
    
    # Esperar intervalo + variabilidad
    local wait_time
    wait_time="$(echo "$INTERVAL + $(awk -v max="$MAX_RANDOM_DELAY" 'BEGIN{srand(); print rand()*max}')" | bc -l 2>/dev/null || echo "$INTERVAL")"
    
    # Evitar espera innecesaria si ya terminamos
    if [ $((current_time + $(echo "$wait_time" | tr -d '.'))) -lt $((start_time + DURATION)) ]; then
      sleep "$wait_time" 2>/dev/null || sleep 1
    fi
  done
  
  log_info "========================================"
  log_info "  Resumen de Carga"
  log_info "========================================"
  log_info "Total solicitudes: $request_count"
  log_info "Log guardado en: $LOAD_LOG_FILE"
  log_info "========================================"
  
  # Guardar metadata
  cat > "${LOAD_LOG_FILE%.csv}-metadata.json" <<JSON
{
  "script": "send-transaction-load.sh",
  "startTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ -d "@$start_time")",
  "endTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "durationSeconds": $DURATION,
  "intervalSeconds": $INTERVAL,
  "maxRandomDelay": $MAX_RANDOM_DELAY,
  "totalRequests": $request_count,
  "prefix": "$transaction_prefix"
}
JSON
  
  echo "$LOAD_LOG_FILE"
}

main "$@"
