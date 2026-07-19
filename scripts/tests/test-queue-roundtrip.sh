#!/bin/bash
set -euo pipefail

# Uso: ./test-queue-roundtrip.sh <staging|production>
ENVIRONMENT="${1:?Uso: test-queue-roundtrip.sh <staging|production>}"

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
  echo "Error: el ambiente debe ser 'staging' o 'production'." >&2
  exit 1
fi

# Cuenta de almacenamiento y cola por ambiente (variables de entorno no secretas)
if [[ "$ENVIRONMENT" == "staging" ]]; then
  STORAGE_ACCOUNT="${STAGING_STORAGE_ACCOUNT:?Define la variable STAGING_STORAGE_ACCOUNT}"
  QUEUE_NAME="${STAGING_QUEUE_NAME:-centinela-queue-test-staging}"
else
  STORAGE_ACCOUNT="${PRODUCTION_STORAGE_ACCOUNT:?Define la variable PRODUCTION_STORAGE_ACCOUNT}"
  QUEUE_NAME="${PRODUCTION_QUEUE_NAME:-centinela-queue-test-production}"
fi

MAX_RETRIES="${MAX_RETRIES:-5}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-2}"

EVIDENCE_DIR="docs/evidence/queue"
mkdir -p "$EVIDENCE_DIR"

TEST_RUN_ID=$(date +%s)
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Mensaje técnico (sin campos de negocio/scoring), construido con printf para evitar
# problemas de escapado de comillas
MESSAGE_BODY=$(printf '{"testRunId":"%s","environment":"%s","createdAt":"%s"}' \
  "$TEST_RUN_ID" "$ENVIRONMENT" "$CREATED_AT")

EVIDENCE_FILE="$EVIDENCE_DIR/run-${TEST_RUN_ID}.json"

cleanup_and_record() {
  local status="$1"
  cat > "$EVIDENCE_FILE" <<EOF
{
  "testRunId": "$TEST_RUN_ID",
  "environment": "$ENVIRONMENT",
  "queue": "$QUEUE_NAME",
  "status": "$status",
  "finishedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
  echo "Evidencia registrada en $EVIDENCE_FILE"
}

echo "Preparando mensaje técnico para ambiente '$ENVIRONMENT' en cola '$QUEUE_NAME'..."
echo "Cuerpo del mensaje: $MESSAGE_BODY"

echo "Enviando mensaje a la cola..."
if ! az storage message put \
  --queue-name "$QUEUE_NAME" \
  --content "$MESSAGE_BODY" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login >/dev/null; then
  echo "Error: no se pudo enviar el mensaje." >&2
  cleanup_and_record "send_failed"
  exit 1
fi
echo "Mensaje enviado (testRunId=$TEST_RUN_ID)."

echo "Intentando recibir y validar el mensaje (máximo $MAX_RETRIES intentos)..."
FOUND=0
MESSAGE_ID=""
POP_RECEIPT=""

for attempt in $(seq 1 "$MAX_RETRIES"); do
  RESPUESTA=$(az storage message get \
    --queue-name "$QUEUE_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login -o json)

  # El contenido del mensaje viene como string dentro del JSON de respuesta;
  # se parsea aparte para comparar el testRunId real.
  RECEIVED_RUN_ID=$(echo "$RESPUESTA" | jq -r '.[0].content // empty' \
    | jq -r '.testRunId // empty' 2>/dev/null || echo "")

  if [[ "$RECEIVED_RUN_ID" == "$TEST_RUN_ID" ]]; then
    MESSAGE_ID=$(echo "$RESPUESTA" | jq -r '.[0].id')
    POP_RECEIPT=$(echo "$RESPUESTA" | jq -r '.[0].popReceipt')
    FOUND=1
    echo "Mensaje encontrado y validado en el intento $attempt (testRunId coincide)."
    break
  fi

  echo "Intento $attempt: aún no coincide el testRunId, reintentando en ${RETRY_DELAY_SECONDS}s..."
  sleep "$RETRY_DELAY_SECONDS"
done

if [[ "$FOUND" -ne 1 ]]; then
  echo "Error: no se pudo recuperar el mensaje esperado tras $MAX_RETRIES intentos." >&2
  cleanup_and_record "not_found"
  exit 1
fi

echo "Eliminando mensaje para no dejar residuos..."
if ! az storage message delete \
  --queue-name "$QUEUE_NAME" \
  --id "$MESSAGE_ID" \
  --pop-receipt "$POP_RECEIPT" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login; then
  echo "Error: no se pudo eliminar el mensaje." >&2
  cleanup_and_record "delete_failed"
  exit 1
fi
echo "Mensaje eliminado."

echo "Verificando que no queden residuos del run en la cola..."
RESULTADO_POST_LIMPIEZA=$(az storage message peek \
  --queue-name "$QUEUE_NAME" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login -o json)

if [[ "$RESULTADO_POST_LIMPIEZA" == "[]" ]]; then
  echo "Éxito: la cola está vacía, no hay residuos del run."
  cleanup_and_record "success"
else
  echo "Alerta: aún hay mensajes en la cola tras la limpieza." >&2
  cleanup_and_record "residual_messages"
  exit 1
fi

# Revocación de asignación RBAC temporal, solo si se creó exclusivamente para esta prueba
if [[ -n "${TEMP_RBAC_ASSIGNMENT_ID:-}" ]]; then
  echo "Revocando asignación RBAC temporal..."
  if [[ -x "./scripts/assign-rbac.sh" ]]; then
    ./scripts/assign-rbac.sh --revoke "$TEMP_RBAC_ASSIGNMENT_ID"
  else
    echo "Aviso: TEMP_RBAC_ASSIGNMENT_ID definido pero scripts/assign-rbac.sh no existe o no es ejecutable." >&2
  fi
fi

exit 0