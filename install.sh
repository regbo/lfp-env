#!/bin/sh
set -eu

PYTHON_MIN_VERSION="${LFP_ENV_PYTHON_MIN_VERSION:-3.10}"
UV_MIN_VERSION="${LFP_ENV_UV_MIN_VERSION:-0.9.9}"
GIT_MIN_VERSION="${LFP_ENV_GIT_MIN_VERSION:-}"
PIXI_INSTALL_URL="https://pixi.sh/install.sh"
PROFILE_MARKER="# lfp-env"
HOME_WAS_GENERATED=0

# Write routine installer activity to stderr.
log() {
    printf "%s %s\n" "[lfp-env-install]" "$*" >&2
}

# Fail fast with a consistent error prefix.
fail() {
    printf "ERROR: %s\n" "$*" >&2
    exit 1
}

# Check whether a local path is an executable file.
is_exec() {
    file_path="${1:-}"
    [ -n "$file_path" ] && [ -f "$file_path" ] && [ -x "$file_path" ]
}

# Quote shell values safely before embedding them in activation output.
shell_quote() {
    printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

# Create a directory and confirm the installer can write to it.
ensure_writable_dir() {
    dir_path="$1"
    test_file=""
    mkdir -p "$dir_path" 2>/dev/null || return 1
    test_file="$dir_path/.lfp-env-write-test.$$"
    touch "$test_file" >/dev/null 2>&1 || return 1
    rm -f "$test_file"
}

# Resolve HOME setup, falling back to generated writable directories for bare environments.
resolve_home_setup() {

    for candidate_dir in "${HOME}" "/home" "/home/app" "$(pwd)/home"; do
        if ensure_writable_dir "$candidate_dir"; then
            quoted_home_dir="$(shell_quote "$candidate_dir")"
            home_setup_command="HOME=$quoted_home_dir;export HOME"
            eval "$home_setup_command"
            HOME_WAS_GENERATED=1
            printf '%s\n' "$home_setup_command"
            return 0
        fi
    done

    fail "could not resolve a writable HOME directory."
}

# Resolve the Pixi home directory, honoring PIXI_HOME.
resolve_pixi_home_dir() {
    pixi_home="${PIXI_HOME:-$HOME/.pixi}"
    case "$pixi_home" in
        '~' | '~'/*) pixi_home="${HOME}${pixi_home#\~}" ;;
    esac
    printf "%s\n" "$pixi_home"
}

# Normalize versions so comparisons accept v-prefixed values.
normalize_version() {
    printf "%s\n" "${1#v}"
}

# Compare two dotted versions and return success when the first is >= the second.
version_ge() {
    normalized_a="$(normalize_version "$1")"
    normalized_b="$(normalize_version "$2")"
    [ "$normalized_a" = "$normalized_b" ] && return 0
    first="$(printf "%s\n%s\n" "$normalized_a" "$normalized_b" | sort -V | head -n1)"
    [ "$first" = "$normalized_b" ]
}

# Resolve the Pixi bin directory, honoring PIXI_BIN_DIR.
resolve_pixi_bin_dir() {
    if [ -n "${PIXI_BIN_DIR:-}" ]; then
        printf "%s\n" "${PIXI_BIN_DIR}"
        return 0
    fi
    printf "%s/bin\n" "$1"
}

# Download a file with whichever standard fetcher is available.
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

    fail "neither curl nor wget is available on PATH."
}

# Prepend a PATH entry once so newly installed tools are visible immediately.
prepend_path() {
    path_entry="$1"
    case ":${PATH:-}:" in
        *":$path_entry:"*) ;;
        *)
            if [ -n "${PATH:-}" ]; then
                PATH="$path_entry:$PATH"
            else
                PATH="$path_entry"
            fi
            export PATH
            ;;
    esac
}

# Capture the first dotted version token from common CLI version output.
extract_version_token() {
    printf "%s\n" "$1" | awk 'match($0, /[0-9]+(\.[0-9]+)+/) { print substr($0, RSTART, RLENGTH); exit }'
}

# Inspect a tool once and print its raw version output.
inspect_tool() {
    tool_name="$1"
    if ! command -v "$tool_name" >/dev/null 2>&1; then
        return 1
    fi
    reported_output="$("$tool_name" --version 2>&1 || true)"
    [ -n "$reported_output" ] || return 1
    printf '%s\n' "$reported_output"
}

# Install Pixi if it is not already available on PATH or in PIXI_BIN_DIR.
ensure_pixi() {
    pixi_home_dir="$(resolve_pixi_home_dir)"
    pixi_bin_dir="$(resolve_pixi_bin_dir "$pixi_home_dir")"
    pixi_bin="$pixi_bin_dir/pixi"
    mkdir -p "$pixi_bin_dir"

    if command -v pixi >/dev/null 2>&1; then
        prepend_path "$(dirname "$(command -v pixi)")"
        return 0
    fi

    if is_exec "$pixi_bin"; then
        prepend_path "$pixi_bin_dir"
        return 0
    fi

    log "Installing pixi"
    pixi_install_script="$TEMP_DIR/pixi-install.sh"
    download_file "$PIXI_INSTALL_URL" "$pixi_install_script"
    chmod +x "$pixi_install_script"
    if ! PIXI_HOME="$pixi_home_dir" PIXI_BIN_DIR="$pixi_bin_dir" sh "$pixi_install_script" >&2; then
        fail "pixi installation failed."
    fi
    [ -x "$pixi_bin" ] || fail "pixi installation did not create $pixi_bin."
    prepend_path "$pixi_bin_dir"
}

# Run pixi global install while keeping stdout reserved for activation output.
run_pixi_global_install() {
    if ! pixi global install "$@" >&2; then
        fail "pixi global install failed for: $*"
    fi
}

# Ensure a required global tool exists and optionally meets a minimum version.
ensure_global_tool() {
    tool_name="$1"
    min_version="$2"
    pixi_selector="$3"
    reported_output=""
    reported_version=""

    if reported_output="$(inspect_tool "$tool_name")"; then
        reported_version="$(extract_version_token "$reported_output")"
        if [ -z "$min_version" ]; then
            log "Program '$tool_name' is available (reported: $reported_output)"
            return 0
        fi
        if [ -n "$reported_version" ] && version_ge "$reported_version" "$min_version"; then
            log "Program '$tool_name' meets minimum version $min_version (reported: $reported_output)"
            return 0
        fi
    fi

    log "Installing '$tool_name' with pixi global install: $pixi_selector"
    run_pixi_global_install "$pixi_selector"

    reported_output="$(inspect_tool "$tool_name")" || fail "Program '$tool_name' is still unavailable after pixi install."
    reported_version="$(extract_version_token "$reported_output")"
    if [ -n "$min_version" ] && { [ -z "$reported_version" ] || ! version_ge "$reported_version" "$min_version"; }; then
        fail "Program '$tool_name' is below minimum version $min_version after pixi install (reported: $reported_output)."
    fi
    if [ -n "$min_version" ]; then
        log "Program '$tool_name' meets minimum version $min_version (reported: $reported_output)"
        return 0
    fi
    log "Program '$tool_name' is available (reported: $reported_output)"
}



# Build the stdout activation command for the current shell session.
build_activation_command() {
    pixi_home_dir="$(resolve_pixi_home_dir)"
    pixi_bin_dir="$(resolve_pixi_bin_dir "$pixi_home_dir")"
    quoted_bin_dir="$(shell_quote "$pixi_bin_dir")"
    printf 'PIXI_BIN_DIR=%s;case ":$PATH:" in *":$PIXI_BIN_DIR:"*) ;; *) export PATH="$PIXI_BIN_DIR:$PATH";; esac;hash -r 2>/dev/null || true' "$quoted_bin_dir"
}

# Tag the managed profile line so reruns can avoid duplicates.
build_profile_line() {
    activation_command="$(build_activation_command)"
    printf '%s %s\n' "$activation_command" "$PROFILE_MARKER"
}

# Append the managed activation line to a profile when it is not already present.
write_profile_block() {
    profile_path="$1"
    profile_dir="$(dirname "$profile_path")"
    cleaned_path="$(mktemp "$TEMP_DIR/profile-clean.XXXXXX")"
    rendered_path="$(mktemp "$TEMP_DIR/profile-rendered.XXXXXX")"
    activation_command="$(build_activation_command)"
    activation_line="$(build_profile_line)"

    mkdir -p "$profile_dir"
    if [ -f "$profile_path" ]; then
        if grep -F -x -- "$activation_command" "$profile_path" >/dev/null 2>&1 || grep -F -x -- "$activation_line" "$profile_path" >/dev/null 2>&1; then
            return 0
        fi
        awk -v marker="$PROFILE_MARKER" '
            index($0, marker) > 0 { next }
            { print }
        ' "$profile_path" >"$cleaned_path"
    else
        : >"$cleaned_path"
    fi

    if [ -s "$cleaned_path" ]; then
        cp "$cleaned_path" "$rendered_path"
        printf '\n' >>"$rendered_path"
    else
        : >"$rendered_path"
    fi
    printf '%s\n' "$activation_line" >>"$rendered_path"

    if [ -f "$profile_path" ] && cmp -s "$profile_path" "$rendered_path"; then
        return 0
    fi

    mv "$rendered_path" "$profile_path"
    log "Updated non-interactive profile $profile_path"
}

# Update the common Unix login profiles used by non-interactive shells.
update_shell_profiles() {
    if [ "$HOME_WAS_GENERATED" = "1" ]; then
        return 0
    fi
    write_profile_block "$HOME/.profile"
    for profile_name in ".bash_profile" ".bash_login" ".zprofile"; do
        profile_path="$HOME/$profile_name"
        if [ -f "$profile_path" ]; then
            write_profile_block "$profile_path"
        fi
    done
}

# Print the activation command that callers should eval in the current shell.
print_activation() {
    printf '%s\n' "$(build_activation_command)"
}

resolve_home_setup || true

TEMP_DIR=""

# Remove temporary installer files on exit.
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT HUP INT TERM

TEMP_DIR="${TEMP_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/lfp-env-install.XXXXXX")}"
ensure_pixi
ensure_global_tool "python" "$PYTHON_MIN_VERSION" "python"
ensure_global_tool "uv" "$UV_MIN_VERSION" "uv"
ensure_global_tool "git" "$GIT_MIN_VERSION" "git"
update_shell_profiles

if [ "$#" -gt 0 ]; then
    log "Installing additional packages with pixi global install: $*"
    run_pixi_global_install "$@"
fi
print_activation