#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_test_lib.bash"

run_pixi_test "idempotent repeated eval" '
echo "[runner] running pixi-setup.sh twice"
eval "$(sh ./pixi-setup.sh)"
eval "$(sh ./pixi-setup.sh)"
echo "[runner] validating pixi still exists"
command -v pixi >/dev/null
'
