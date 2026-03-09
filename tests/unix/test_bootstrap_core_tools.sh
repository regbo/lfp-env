#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_test_lib.bash"

run_setup_test "bootstrap and core tools" '
echo "[runner] running setup.sh"
eval "$(sh ./setup.sh)"

echo "[runner] validating resolved environment and binaries"
[ -n "${TEMP:-}" ]
[ -n "${HOME:-}" ]
[ -n "${LOCAL_BIN:-}" ]
[ -n "${MISE_DATA_DIR:-}" ]
command -v mise >/dev/null
echo "[runner] verified: mise is installed"
command -v git >/dev/null
echo "[runner] verified: git is installed"
command -v python >/dev/null || command -v python3 >/dev/null
echo "[runner] verified: python is installed"
'
