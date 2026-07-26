#!/usr/bin/env bash
# ISS-S2-013 / TEST-S2-014: cambia SCORING_THRESHOLD mediante App Settings,
# sin desplegar un artefacto nuevo, y demuestra el cambio de comportamiento.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-decoupling.sh
source "$SCRIPT_DIR/test-decoupling.sh"
run_threshold_hot_reload "$@"
