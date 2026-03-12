#!/bin/sh
set -eu

REPO="${LFP_ENV_REPO:-regbo/lfp-env}"
VERSION="${LFP_ENV_VERSION:-}"
MIN_VERSION="${LFP_ENV_MIN_VERSION:-}"
INSTALL_PATH="${LFP_ENV_INSTALL_PATH:-}"

log() {
    printf "%s %s\n" "[lfp-env-install]" "$*" >&2
}

is_exec() {
    file_path="${1:-}"
    [ -n "$file_path" ] && [ -f "$file_path" ] && [ -x "$file_path" ]
}

version_ge() {
    [ "$1" = "$2" ] && return 0
    first="$(printf "%s\n%s\n" "$1" "$2" | sort -V | head -n1)"
    [ "$first" = "$2" ]
}

resolve_home_dir() {
    if [ -n "${HOME:-}" ]; then
        printf "%s\n" "$HOME"
        return 0
    fi
    mkdir -p "./home"
    printf "%s\n" "$(pwd)/home"
}

download_file() {
    url=$1
    destination=$2

    if command -v curl >/dev/null 2>&1; then
        log "Downloading $url"
        curl -fsSL "$url" -o "$destination"
        return 0
    fi

    if command -v wget >/dev/null 2>&1; then
        log "Downloading $url"
        wget -qO "$destination" "$url"
        return 0
    fi

    printf "ERROR: neither curl nor wget is available on PATH.\n" >&2
    exit 1
}

detect_asset_name() {
    kernel_name=$(uname -s)
    machine_name=$(uname -m)

    case "$kernel_name" in
        Linux)  os_target="unknown-linux-musl" ;;
        Darwin) os_target="apple-darwin" ;;
        *) printf "ERROR: unsupported operating system: %s\n" "$kernel_name" >&2; exit 1 ;;
    esac

    case "$machine_name" in
        x86_64|amd64) arch_target="x86_64" ;;
        arm64|aarch64) arch_target="aarch64" ;;
        *) printf "ERROR: unsupported architecture: %s\n" "$machine_name" >&2; exit 1 ;;
    esac

    printf "lfp-env-%s-%s.tar.gz\n" "$arch_target" "$os_target"
}

HOME="$(resolve_home_dir)"
export HOME

DEFAULT_INSTALL_PATH="${HOME}/.local/bin/lfp-env"
LFP_ENV_BIN="${INSTALL_PATH:-$DEFAULT_INSTALL_PATH}"
BIN_DIR="$(dirname "$LFP_ENV_BIN")"

mkdir -p "$BIN_DIR"

log "Repo: $REPO"
log "Version: ${VERSION:-latest}"
log "Install path: $LFP_ENV_BIN"

TEMP_DIR=""

cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT HUP INT TERM

INSTALL_REQUIRED=0

if ! is_exec "$LFP_ENV_BIN"; then
    INSTALL_REQUIRED=1
else
    CURRENT_VERSION="$("$LFP_ENV_BIN" --version 2>/dev/null || true)"

    if [ -n "$VERSION" ] && [ -n "$MIN_VERSION" ]; then
        if ! version_ge "$VERSION" "$MIN_VERSION"; then
            printf "ERROR: VERSION (%s) does not satisfy MIN_VERSION (%s)\n" "$VERSION" "$MIN_VERSION" >&2
            exit 1
        fi
    fi

    if [ -n "$VERSION" ]; then
        [ "$CURRENT_VERSION" = "$VERSION" ] || INSTALL_REQUIRED=1
    elif [ -n "$MIN_VERSION" ]; then
        version_ge "$CURRENT_VERSION" "$MIN_VERSION" || INSTALL_REQUIRED=1
    fi
fi

if [ "$INSTALL_REQUIRED" -eq 1 ]; then
    ASSET_NAME="$(detect_asset_name)"

    if [ -n "$VERSION" ]; then
        RELEASE_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET_NAME}"
    else
        RELEASE_URL="https://github.com/${REPO}/releases/latest/download/${ASSET_NAME}"
    fi

    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lfp-env-install.XXXXXX")"
    ARCHIVE_PATH="${TEMP_DIR}/${ASSET_NAME}"

    download_file "$RELEASE_URL" "$ARCHIVE_PATH"

    tar -xzf "$ARCHIVE_PATH" -C "$BIN_DIR"

    [ -f "$LFP_ENV_BIN" ] || { echo "ERROR: extracted archive did not contain lfp-env" >&2; exit 1; }

    chmod +x "$LFP_ENV_BIN"
fi

export LFP_ENV_INSTALLER_MODE=1
if [ "$#" -gt 0 ]; then
    exec "$LFP_ENV_BIN" "$@"
fi
exec "$LFP_ENV_BIN"