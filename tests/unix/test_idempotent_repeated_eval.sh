#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_test_lib.bash"

run_setup_test "idempotent repeated eval" '
echo "[runner] running install.sh twice"
eval "$(sh ./install.sh)"
eval "$(sh ./install.sh)"
echo "[runner] validating mise still exists"
command -v mise >/dev/null
'
