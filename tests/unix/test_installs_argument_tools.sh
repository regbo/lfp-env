#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_test_lib.bash"

run_pixi_test "installs argument tools" '
echo "[runner] running pixi-init.sh with jq"
eval "$(sh ./pixi-init.sh jq)"
echo "[runner] validating jq exists"
command -v jq >/dev/null
'
