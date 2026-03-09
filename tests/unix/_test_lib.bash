#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() {
  local message="$1"
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "${message}"
}

require_exec() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "Required command not found on PATH: ${name}" >&2
    exit 1
  fi
}

check_base_dependencies() {
  require_exec bash
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "Either curl or wget must be available on PATH." >&2
    exit 1
  fi
}

run_setup_test() {
  local test_name="$1"
  local test_body="$2"
  log "START: ${test_name}"
  check_base_dependencies
  (
    set -euo pipefail
    cd "${TEST_ROOT_DIR}"
    echo "[runner] test body:"
    if ! eval "${test_body}"; then
      printf '%s\n' "${test_body}"
      echo "test failed" >&2
      exit 1
    fi
  )
  log "PASS: ${test_name}"
}

run_install_and_eval() {
  local install_output=""
  if ! install_output="$(sh ./install.sh)"; then
    printf '%s\n' "${install_output}"
    echo "install.sh failed" >&2
    return 1
  fi
  if ! eval "${install_output}"; then
    printf '%s\n' "${install_output}"
    echo "install.sh eval failed" >&2
    return 1
  fi
}
