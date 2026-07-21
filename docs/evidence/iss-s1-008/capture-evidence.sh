#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

: "${CENTINELA_RUN_AZURE_IT:?Define CENTINELA_RUN_AZURE_IT=true para demostrar TEST-S1-015}"
[ "${CENTINELA_RUN_AZURE_IT,,}" = "true" ] \
  || { printf 'CENTINELA_RUN_AZURE_IT debe ser true.\n' >&2; exit 1; }
: "${CENTINELA_STORAGE_ACCOUNT:?Define CENTINELA_STORAGE_ACCOUNT}"
: "${CENTINELA_RAW_TRANSACTIONS_CONTAINER:?Define CENTINELA_RAW_TRANSACTIONS_CONTAINER}"

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="docs/evidence/iss-s1-008/runs/$run_id"
mkdir -p "$out_dir"

{
  printf 'issue=ISS-S1-008\n'
  printf 'runId=%s\n' "$run_id"
  printf 'timestampUtc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'commit=%s\n' "$(git rev-parse HEAD)"
  printf 'environmentContainer=%s\n' "$CENTINELA_RAW_TRANSACTIONS_CONTAINER"
  printf 'storageAccount=%s\n' "${CENTINELA_STORAGE_ACCOUNT:0:4}****"
} > "$out_dir/00-run-metadata.txt"

mvn -Dtest=IngestTransactionServiceTest test \
  > "$out_dir/01-service-unit-test.txt" 2>&1

mvn -Dtest=TransactionApiIT,TransactionApiValidationIT test \
  > "$out_dir/02-api-integration-tests.txt" 2>&1

mvn -Dtest=AzureRawTransactionBlobAdapterIT verify \
  > "$out_dir/03-azure-blob-integration-test.txt" 2>&1

if grep -Eq 'Tests run:.*Skipped: [1-9]' "$out_dir/03-azure-blob-integration-test.txt"; then
  printf 'La prueba Azure fue omitida; la evidencia no es valida para cerrar.\n' >&2
  exit 1
fi

mvn test > "$out_dir/04-full-test-suite.txt" 2>&1
git diff --check > "$out_dir/05-diff-check.txt" 2>&1

git status --short > "$out_dir/06-files-reviewed.txt"

if grep -RInE 'connection[-_ ]?string|DefaultAzureCredential.*token|score|decision|caseId' \
    src/main/java/com/centinela/transactioningestion \
    --exclude='*.class' > "$out_dir/07-scope-scan.txt"; then
  # DefaultAzureCredential and the documented prohibition names may appear in
  # comments/tests; the reviewer must inspect this report rather than treating
  # every textual occurrence as a secret.
  true
else
  printf 'No suspicious scope text found.\n' > "$out_dir/07-scope-scan.txt"
fi

printf 'Evidencia creada en %s\n' "$out_dir"
