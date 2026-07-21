#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
OPENAPI_FILE="$REPO_ROOT/docs/1_Requisitos_y_Contrato/openapi-centinela-semana1.yaml"

cd "$REPO_ROOT"

run_and_capture() {
  local output_file="$1"
  shift
  printf 'Command:' | tee "$output_file"
  printf ' %q' "$@" | tee -a "$output_file"
  printf '\n\n' | tee -a "$output_file"
  "$@" 2>&1 | tee -a "$output_file"
}

run_and_capture "$SCRIPT_DIR/01-required-tests.txt" \
  mvn -Dtest=TransactionControllerValidationTest,OpenApiContractTest,TransactionRequestValidationTest,TransactionWebMapperTest test

run_and_capture "$SCRIPT_DIR/02-full-test-suite.txt" mvn test
run_and_capture "$SCRIPT_DIR/03-openapi-lint.txt" \
  npx --yes @redocly/cli lint "$OPENAPI_FILE"
run_and_capture "$SCRIPT_DIR/04-diff-check.txt" git diff --check

{
  echo "Commit: $(git rev-parse HEAD)"
  echo
  echo "Working tree files:"
  git status --short
} > "$SCRIPT_DIR/05-files-reviewed.txt"

printf 'Evidence captured in %s\n' "$SCRIPT_DIR"
