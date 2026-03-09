#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_test_lib.bash"

run_setup_test "runs install script" '
echo "[runner] running install.sh"
run_install_and_eval
echo "[runner] validating mise exists"
command -v mise >/dev/null
'
