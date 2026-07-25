#!/usr/bin/env bash
# Static guard for the corrective integration of ISS-S2-001..011.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
contains() {
  local file="$1" pattern="$2" message="$3"
  if grep -Eq -- "$pattern" "$ROOT/$file"; then pass "$message"; else fail "$message"; fi
}
not_contains_tree() {
  local path="$1" pattern="$2" message="$3"
  if grep -R -E -- "$pattern" "$ROOT/$path" --include='*.java' --include='pom.xml' >/dev/null 2>&1; then
    fail "$message"
  else
    pass "$message"
  fi
}

not_contains_tree scoring-function 'com\.azure\.cosmos|azure-cosmos' \
  'Scoring usa MongoDB y no Cosmos NoSQL.'
contains scoring-function/src/main/java/com/centinela/scoring/domain/model/TransactionEventNotification.java \
  'String blobPath' 'El contrato recibido contiene blobPath.'
contains scoring-function/src/main/java/com/centinela/scoring/infrastructure/function/ScoreTransactionFunction.java \
  'rawTransactionReader\(\)\.read\(notification\)' 'La Function descarga el Blob antes del scoring.'
contains scoring-function/src/main/java/com/centinela/scoring/infrastructure/function/ScoreTransactionFunction.java \
  'servicesByContainer' 'La Function enruta staging/production por el contenedor del blobPath.'
contains scoring-function/src/main/java/com/centinela/scoring/infrastructure/function/ScoreTransactionFunction.java \
  'FAIL_ON_UNKNOWN_PROPERTIES' 'El consumidor de Event Grid rechaza campos fuera del contrato.'
contains scoring-function/src/main/java/com/centinela/scoring/infrastructure/mongo/CosmosMongoTransactionHistoryAdapter.java \
  'eq\("accountId".*lt\("occurredAt"' 'La consulta Mongo es dirigida por cuenta y tiempo.'
contains scoring-function/src/main/java/com/centinela/scoring/infrastructure/config/KeyVaultConnectionStrings.java \
  'cosmos-mongo-connection-string' 'El nombre del secreto Mongo es uniforme.'
contains scoring-function/src/main/java/com/centinela/scoring/infrastructure/queue/StorageQueueFlaggedCasePublisher.java \
  'OffsetDateTime occurredAt' 'El productor incluye occurredAt en flagged-case-v1.'
contains scoring-function/src/main/java/com/centinela/scoring/infrastructure/queue/StorageQueueFlaggedCasePublisher.java \
  'OffsetDateTime scoredAt' 'El productor incluye scoredAt en flagged-case-v1.'
contains src/main/java/com/centinela/casemanagement/infrastructure/messaging/FlaggedCaseQueueListener.java \
  'deleteMessage\(messageId, message\.popReceipt\(\)\)' 'El listener conserva y usa popReceipt.'
contains src/main/java/com/centinela/casemanagement/infrastructure/messaging/FlaggedCaseQueueListener.java \
  'FAIL_ON_UNKNOWN_PROPERTIES' 'El consumidor de Queue rechaza campos fuera de flagged-case-v1.'
contains src/main/java/com/centinela/casemanagement/infrastructure/persistence/JpaCaseRepositoryAdapter.java \
  'saveCaseWithAudit' 'Caso y auditoria usan el adaptador transaccional unico.'
contains src/main/resources/db/migration/V3__align_case_model_and_reject_audit_mutation.sql \
  'BEFORE UPDATE OR DELETE' 'La auditoria rechaza UPDATE y DELETE.'
contains scripts/provision-cosmos.sh 'group-id MongoDB' 'Cosmos Mongo tiene Private Endpoint.'
contains scripts/deploy-scoring-function.sh 'az functionapp create' 'El despliegue crea o reutiliza la Function App.'
contains scripts/deploy-scoring-function.sh 'endpoint-type azurefunction' 'Event Grid queda suscrito a la Function.'
contains scripts/configure-function-host-storage.sh 'privatelink.table.core.windows.net' \
  'El host de Functions tiene DNS privado para Storage Table.'
contains scripts/configure-function-host-storage.sh '--group-id table' \
  'El host de Functions tiene Private Endpoint para Storage Table.'
contains scripts/deploy-scoring-function.sh 'AzureWebJobsStorage__credential=managedidentity' \
  'AzureWebJobsStorage usa explicitamente Managed Identity.'
contains scripts/configure-postgres-managed-identity.sh 'pgaadauth_create_principal_with_oid' \
  'PostgreSQL vincula las Managed Identities por Object ID.'
contains scripts/configure-postgres-managed-identity.sh '--slot-settings' \
  'JDBC y Queue permanecen aislados durante cambios de slot.'
contains scripts/deploy-scoring-function.sh 'CENTINELA_FLAGGED_CASES_QUEUE_STAGING' \
  'La Function tiene rutas de Queue para staging y production.'
contains scripts/deploy-week2.sh 'deploy-application.sh.*--slot production' \
  'Semana 2 despliega el consumidor corregido en produccion.'
contains scripts/deploy-week2.sh 'deploy-application.sh.*--slot staging' \
  'Semana 2 despliega el consumidor corregido en staging.'
contains scripts/provision-keyvault.sh 'revoke_temporary_deployer_officer' \
  'El permiso temporal de Key Vault se revoca.'

printf '\nResultado: %d PASS / %d FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
