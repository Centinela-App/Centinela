#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

: "${CENTINELA_RUN_AZURE_DOCUMENT_IT:?Define CENTINELA_RUN_AZURE_DOCUMENT_IT=true}"
: "${CENTINELA_STORAGE_ACCOUNT:?Define CENTINELA_STORAGE_ACCOUNT}"
: "${CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER:?Define CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER}"

if [[ ! "$CENTINELA_RUN_AZURE_DOCUMENT_IT" =~ ^([Tt][Rr][Uu][Ee])$ ]]; then
  printf 'CENTINELA_RUN_AZURE_DOCUMENT_IT debe ser true.\n' >&2
  exit 1
fi

run_id="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="docs/evidence/iss-s1-009/runs/$run_id"
mkdir -p "$out_dir"

{
  printf 'runId=%s\n' "$run_id"
  printf 'timestampUtc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'commit=%s\n' "$(git rev-parse HEAD)"
  printf 'branch=%s\n' "$(git branch --show-current)"
  printf 'java=%s\n' "$(java -version 2>&1 | head -n 1)"
  printf 'maven=%s\n' "$(mvn -version 2>&1 | head -n 1)"
  printf 'storageAccount=%s\n' "$CENTINELA_STORAGE_ACCOUNT"
  printf 'container=%s\n' "$CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER"
} > "$out_dir/00-run-metadata.txt"

mvn -Dtest=StoreVerificationDocumentServiceTest test \
  > "$out_dir/01-document-service-test.txt" 2>&1

mvn -Dtest=VerificationDocumentApiIT,VerificationDocumentOpenApiContractTest test \
  > "$out_dir/02-document-api-and-contract-tests.txt" 2>&1

mvn -Dtest=AzureVerificationDocumentBlobAdapterIT verify \
  > "$out_dir/03-azure-document-blob-integration-test.txt" 2>&1

if grep -Eq 'Tests run:.*Skipped: [1-9]' \
  "$out_dir/03-azure-document-blob-integration-test.txt"; then
  printf 'La prueba real de Azure fue omitida; la evidencia no es valida.\n' >&2
  exit 1
fi

mvn test > "$out_dir/04-full-test-suite.txt" 2>&1
git diff --check > "$out_dir/05-diff-check.txt" 2>&1
git status --short > "$out_dir/06-files-reviewed.txt"

if grep -RInE \
  'caseId|score|decision|rules|ocr|antivirus|connection[-_ ]?string|account[-_ ]?key|sas[-_ ]?token' \
  src/main/java/com/centinela/documentstorage \
  > "$out_dir/07-scope-scan.txt"; then
  printf 'El escaneo encontro terminos prohibidos o fuera de alcance.\n' >&2
  exit 1
else
  printf 'PASS: no se encontraron terminos prohibidos en la implementacion.\n' \
    > "$out_dir/07-scope-scan.txt"
fi

printf 'Evidencia ISS-S1-009 creada en %s\n' "$out_dir"
