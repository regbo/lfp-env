#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_test_lib.bash"

run_pixi_test "bootstrap and core tools" '
echo "[runner] running pixi-init.sh"
eval "$(sh ./pixi-init.sh)"

echo "[runner] validating resolved environment and binaries"
[ -n "${TEMP:-}" ]
[ -n "${HOME:-}" ]
[ -n "${LOCAL_BIN:-}" ]
[ -n "${PIXI_HOME:-}" ]
command -v pixi >/dev/null
echo "[runner] verified: pixi is installed"
command -v git >/dev/null
echo "[runner] verified: git is installed"
command -v python >/dev/null || command -v python3 >/dev/null
echo "[runner] verified: python is installed"
'
