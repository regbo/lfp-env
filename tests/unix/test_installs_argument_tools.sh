#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_test_lib.bash"

run_setup_test "runs setup script" '
echo "[runner] running setup.sh"
eval "$(sh ./setup.sh)"
echo "[runner] validating mise exists"
command -v mise >/dev/null
'
