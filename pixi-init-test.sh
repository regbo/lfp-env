#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${PIXI_INIT_TEST_IMAGE:-debian:stable-slim}"

log() {
  local message="$1"
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "${message}"
}

resolve_container_runtime() {
  if [[ -n "${CONTAINER_RUNTIME:-}" ]]; then
    if command -v "${CONTAINER_RUNTIME}" >/dev/null 2>&1; then
      echo "${CONTAINER_RUNTIME}"
      return 0
    fi
    echo "Configured CONTAINER_RUNTIME not found: ${CONTAINER_RUNTIME}" >&2
    exit 1
  fi

  if command -v docker >/dev/null 2>&1; then
    echo "docker"
    return 0
  fi

  if command -v podman >/dev/null 2>&1; then
    echo "podman"
    return 0
  fi

  echo "Neither docker nor podman is available on PATH." >&2
  exit 1
}

CONTAINER_RUNTIME="$(resolve_container_runtime)"
log "Using container runtime: ${CONTAINER_RUNTIME}"
log "Using image: ${IMAGE}"

run_in_container() {
  local test_name="$1"
  local test_body="$2"
  log "START: ${test_name}"
  if "${CONTAINER_RUNTIME}" run --rm \
    -v "${SCRIPT_DIR}:/work" \
    -w /work \
    "${IMAGE}" \
    bash -lc "${test_body}"; then
    log "PASS: ${test_name}"
  else
    log "FAIL: ${test_name}"
    return 1
  fi
}

run_in_container "bootstrap and core tools" '
  set -euo pipefail
  echo "[container] installing base dependencies"
  apt-get update -y >/dev/null
  apt-get install -y ca-certificates curl wget git bash >/dev/null

  echo "[container] running pixi-init.sh"
  eval "$(sh ./pixi-init.sh)"

  echo "[container] validating resolved environment and binaries"
  [ -n "${TEMP:-}" ]
  [ -n "${HOME:-}" ]
  [ -n "${LOCAL_BIN:-}" ]
  [ -n "${PIXI_HOME:-}" ]
  command -v pixi >/dev/null
  echo "[container] verified: pixi is installed"
  command -v git >/dev/null
  echo "[container] verified: git is installed"
  command -v python >/dev/null || command -v python3 >/dev/null
  echo "[container] verified: python is installed"
'

run_in_container "installs argument tools" '
  set -euo pipefail
  echo "[container] installing base dependencies"
  apt-get update -y >/dev/null
  apt-get install -y ca-certificates curl wget git bash >/dev/null

  echo "[container] running pixi-init.sh with jq"
  eval "$(sh ./pixi-init.sh jq)"
  echo "[container] validating jq exists"
  command -v jq >/dev/null
'

run_in_container "idempotent repeated eval" '
  set -euo pipefail
  echo "[container] installing base dependencies"
  apt-get update -y >/dev/null
  apt-get install -y ca-certificates curl wget git bash >/dev/null

  echo "[container] running pixi-init.sh twice"
  eval "$(sh ./pixi-init.sh)"
  eval "$(sh ./pixi-init.sh)"
  echo "[container] validating pixi still exists"
  command -v pixi >/dev/null
'

log "All pixi-init tests passed."
