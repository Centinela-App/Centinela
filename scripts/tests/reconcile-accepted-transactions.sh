#!/usr/bin/env bash
# reconcile-accepted-transactions.sh — Reconcilia respuestas 202 con Blobs en Storage
# Parte de la prueba HA (HU-S1-005 / FEAT-S1-005)
#
# Para cada respuesta 202 en el log de carga, verifica que exista el Blob correspondiente.
# Genera un reporte JSON con metricas y detalles de discrepancias.
#
# Uso: ./scripts/tests/reconcile-accepted-transactions.sh \
#        --load-log /path/to/load-results.csv \
#        --output /path/to/reconciliation.json \
#        --storage-account mystorageaccount \
#        --container raw-transactions
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# -----------------------------------------------------------------------------
# Configuracion
# -----------------------------------------------------------------------------
LOAD_LOG_FILE=""
OUTPUT_FILE=""
STORAGE_ACCOUNT=""
CONTAINER_NAME=""
TMP_DIR=""

# -----------------------------------------------------------------------------
# Funciones
# -----------------------------------------------------------------------------

# parse_args: Parsea argumentos de linea de comandos
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --load-log)
        LOAD_LOG_FILE="$2"
        shift 2
        ;;
      --output)
        OUTPUT_FILE="$2"
        shift 2
        ;;
      --storage-account)
        STORAGE_ACCOUNT="$2"
        shift 2
        ;;
      --container)
        CONTAINER_NAME="$2"
        shift 2
        ;;
      --help|-h)
        echo "Uso: $0 [OPTIONS]"
        echo "Options:"
        echo "  --load-log FILE        Archivo CSV con resultados de carga"
        echo "  --output FILE          Archivo JSON con reporte de reconciliacion"
        echo "  --storage-account NAME Cuenta de Azure Storage"
        echo "  --container NAME       Nombre del contenedor de blobs"
        echo "  --help, -h             Muestra esta ayuda"
        exit 0
        ;;
      *)
        log_error "Argumento desconocido: $1"
        exit 1
        ;;
    esac
  done
  
  # Validar argumentos requeridos
  [ -z "$LOAD_LOG_FILE" ] && die "Debe especificar --load-log"
  [ -z "$OUTPUT_FILE" ] && die "Debe especificar --output"
  [ -z "$STORAGE_ACCOUNT" ] && die "Debe especificar --storage-account"
  [ -z "$CONTAINER_NAME" ] && die "Debe especificar --container"
  
  # Validar que existe el archivo de log
  [ -f "$LOAD_LOG_FILE" ] || die "Archivo de log no encontrado: $LOAD_LOG_FILE"
}

# check_blob_exists: Verifica si existe un blob para la transaccion
check_blob_exists() {
  local transaction_id="$1"
  local container="$2"
  local account="$3"
  
  # Buscar blobs que contengan el transactionId
  local blob_name
  blob_name="$(az storage blob list \
    --account-name "$account" \
    --container-name "$container" \
    --auth-mode login \
    --query "[?contains(name, '$transaction_id')].name | [0]" \
    --output tsv \
    --only-show-errors 2>/dev/null || echo "")"
  
  if [ -n "$blob_name" ]; then
    echo "$blob_name"
    return 0
  else
    return 1
  fi
}

# get_blob_content: Obtiene el contenido de un blob
get_blob_content() {
  local blob_name="$1"
  local container="$2"
  local account="$3"
  local output_file="$4"
  
  az storage blob download \
    --account-name "$account" \
    --container-name "$container" \
    --name "$blob_name" \
    --file "$output_file" \
    --auth-mode login \
    --overwrite true \
    --only-show-errors >/dev/null 2>&1
}

# verify_blob_content: Verifica que el blob contenga el transactionId esperado
verify_blob_content() {
  local blob_file="$1"
  local expected_transaction_id="$2"
  
  if [ ! -f "$blob_file" ]; then
    return 1
  fi
  
  local actual_id
  actual_id="$(jq -r '.transactionId // .TransactionId // ""' "$blob_file" 2>/dev/null || echo "")"
  
  [ "$actual_id" = "$expected_transaction_id" ]
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
  parse_args "$@"
  
  require_cmd az
  require_cmd jq
  
  log_info "========================================"
  log_info "  Reconciliacion de Transacciones"
  log_info "========================================"
  log_info "Archivo de carga: $LOAD_LOG_FILE"
  log_info "Cuenta Storage: $STORAGE_ACCOUNT"
  log_info "Contenedor: $CONTAINER_NAME"
  log_info "========================================"
  
  # Verificar sesion de Azure
  az account show >/dev/null 2>&1 || die "No hay sesion Azure activa. Ejecuta az login."
  
  # Crear directorio temporal
  TMP_DIR="$(mktemp -d)"
  
  # Cleanup
  cleanup_reconcile() {
    rm -rf "$TMP_DIR" 2>/dev/null || true
  }
  trap cleanup_reconcile EXIT
  
  # Archivos temporales
  local accepted_file="${TMP_DIR}/accepted.csv"
  local reconciled_file="${TMP_DIR}/reconciled.csv"
  local failed_reconcile_file="${TMP_DIR}/failed-reconcile.csv"
  
  # Headers para archivos de salida
  echo "transactionId,httpStatus,startTime,endTime,blobName,blobVerified,error" > "$accepted_file"
  echo "transactionId,httpStatus,startTime,endTime,blobName,verified,error" > "$reconciled_file"
  echo "transactionId,httpStatus,startTime,endTime,blobName,verified,error" > "$failed_reconcile_file"
  
  # Contadores
  local total_requests=0
  local accepted_requests=0
  local failed_requests=0
  local other_responses=0
  local reconciled_requests=0
  local unreconciled_requests=0
  
  # Procesar archivo CSV de carga
  # Formato: transactionId,httpStatus,startTime,endTime,hasResponse,errorMsg
  
  # Saltar header y procesar cada linea
  local line_number=0
  while IFS=',' read -r transaction_id http_status start_time end_time has_response error_msg; do
    line_number=$((line_number + 1))
    
    # Saltar header
    if [ "$line_number" -eq 1 ] || [ "$transaction_id" = "transactionId" ]; then
      continue
    fi
    
    # Saltar lineas vacias
    [ -z "$transaction_id" ] && continue
    
    total_requests=$((total_requests + 1))
    
    # Clasificar por codigo HTTP
    if [ "$http_status" = "202" ]; then
      accepted_requests=$((accepted_requests + 1))
      
      # Verificar que existe el blob
      local blob_name=""
      local verified="false"
      local verify_error=""
      
      if blob_name="$(check_blob_exists "$transaction_id" "$CONTAINER_NAME" "$STORAGE_ACCOUNT")"; then
        # Blob existe, verificar contenido
        local blob_file="${TMP_DIR}/blob-${transaction_id}.json"
        if get_blob_content "$blob_name" "$CONTAINER_NAME" "$STORAGE_ACCOUNT" "$blob_file"; then
          if verify_blob_content "$blob_file" "$transaction_id"; then
            verified="true"
            reconciled_requests=$((reconciled_requests + 1))
          else
            verify_error="Blob content mismatch"
            unreconciled_requests=$((unreconciled_requests + 1))
          fi
        else
          verify_error="Could not download blob"
          unreconciled_requests=$((unreconciled_requests + 1))
        fi
      else
        verify_error="Blob not found"
        unreconciled_requests=$((unreconciled_requests + 1))
      fi
      
      # Registrar resultado
      printf '%s,%s,%s,%s,%s,%s,%s\n' \
        "$transaction_id" \
        "$http_status" \
        "$start_time" \
        "$end_time" \
        "$blob_name" \
        "$verified" \
        "$verify_error" \
        >> "$accepted_file"
      
      if [ "$verified" = "true" ]; then
        printf '%s,%s,%s,%s,%s,true,\n' \
          "$transaction_id" \
          "$http_status" \
          "$start_time" \
          "$end_time" \
          "$blob_name" \
          >> "$reconciled_file"
      else
        printf '%s,%s,%s,%s,%s,false,%s\n' \
          "$transaction_id" \
          "$http_status" \
          "$start_time" \
          "$end_time" \
          "$blob_name" \
          "$verify_error" \
          >> "$failed_reconcile_file"
      fi
      
    else
      # Error de transporte o 5xx = interrupcion. Otros HTTP prueban que la API respondio.
      if [ "$http_status" = "000" ] || [[ "$http_status" =~ ^5[0-9][0-9]$ ]]; then
        failed_requests=$((failed_requests + 1))
      else
        other_responses=$((other_responses + 1))
      fi
    fi
    
    # Log de progreso
    if [ $((total_requests % 20)) -eq 0 ]; then
      log_info "Procesadas: $total_requests solicitudes, $accepted_requests aceptadas, $reconciled_requests reconciliadas"
    fi
    
  done < "$LOAD_LOG_FILE"
  
  log_info ""
  log_info "========================================"
  log_info "  Resultado de Reconciliacion"
  log_info "========================================"
  log_info "Solicitudes totales:    $total_requests"
  log_info "Solicitudes aceptadas:  $accepted_requests"
  log_info "Errores transporte/5xx: $failed_requests"
  log_info "Otros codigos HTTP:     $other_responses"
  log_info "Transacciones halladas: $reconciled_requests"
  log_info "Transacciones perdidas: $unreconciled_requests"
  log_info "========================================"
  
  # Generar reporte JSON
  local test_passed="true"
  if [ "$unreconciled_requests" -gt 0 ]; then
    test_passed="false"
    log_warn "ADVERTENCIA: $unreconciled_requests transacciones 202 sin blob asociado"
  fi
  
  cat > "$OUTPUT_FILE" <<JSON
{
  "testId": "RECONCILE-HA-$(date -u +%Y%m%dT%H%M%SZ)",
  "feature": "FEAT-S1-005",
  "historyId": "HU-S1-005",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "sourceLog": "$LOAD_LOG_FILE",
  "storageAccount": "$STORAGE_ACCOUNT",
  "container": "$CONTAINER_NAME",
  "metrics": {
    "totalRequests": $total_requests,
    "acceptedRequests": $accepted_requests,
    "failedRequests": $failed_requests,
    "otherHttpResponses": $other_responses,
    "reconciledRequests": $reconciled_requests,
    "unreconciledRequests": $unreconciled_requests
  },
  "files": {
    "acceptedTransactions": "accepted-transactions.csv",
    "reconciledTransactions": "reconciled-transactions.csv",
    "failedReconciliation": "failed-reconciliation.csv"
  },
  "result": {
    "passed": $test_passed,
    "message": $(if [ "$test_passed" = "true" ]; then 
      echo '"All accepted transactions have corresponding blobs"'
    else 
      echo '"Some accepted transactions are missing blobs"'
    fi)
  }
}
JSON
  
  log_info "Reporte guardado en: $OUTPUT_FILE"
  
  # Copiar archivos detallados a la misma carpeta que el reporte
  local output_dir
  output_dir="$(dirname "$OUTPUT_FILE")"
  cp "$accepted_file" "${output_dir}/accepted-transactions.csv"
  cp "$reconciled_file" "${output_dir}/reconciled-transactions.csv"
  cp "$failed_reconcile_file" "${output_dir}/failed-reconciliation.csv"
  
  log_info "Archivos detallados copiados a: $output_dir"
  
  # Retornar codigo de exit basado en el resultado
  if [ "$test_passed" = "true" ]; then
    log_info "RECONCILIACION EXITOSA"
    return 0
  else
    log_error "RECONCILIACION FALLIDA: Transacciones sin blob"
    return 1
  fi
}

main "$@"
