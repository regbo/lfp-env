#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/tests/unix"

log() {
  local message="$1"
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "${message}"
}

if [[ ! -d "${TEST_DIR}" ]]; then
  echo "Missing test directory: ${TEST_DIR}" >&2
  exit 1
fi

shopt -s nullglob
test_files=("${TEST_DIR}"/test_*.sh)
if [[ "${#test_files[@]}" -eq 0 ]]; then
  echo "No unix test scripts found in ${TEST_DIR}" >&2
  exit 1
fi

for test_file in "${test_files[@]}"; do
  log "RUN: ${test_file##*/}"
  bash "${test_file}"
done

log "All pixi-init tests passed."
