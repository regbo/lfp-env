#!/bin/sh
# Exit on command errors and unset variables.
set -eu

TOOL_SPEC="${LFP_ENV_TOOL_SPEC:-github:regbo/lfp-env}"
ACTIVATE_PROFILE="${LFP_ACTIVATE_PROFILE:-1}"
DISABLE_RUN="${LFP_ENV_DISABLE_RUN:-0}"
CARGO_INSTALL="${LFP_ENV_CARGO_INSTALL:-0}"
LOG_ENABLED="${LFP_ENV_LOG_ENABLED:-1}"
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)

ACTIVATE=""

# Log a message to stderr for lightweight tracing.
log() {
    if [ "${LOG_ENABLED}" = "1" ]; then
        printf "%s\n" "$*" >&2
    fi
}

# Evaluate a command now and append it to the activation snippet.
append_activate() {
    cmd=$1
    eval "$cmd"
    log "Activation output: $cmd"
    ACTIVATE="${ACTIVATE}${cmd};"
}


# Return success when a path is an executable regular file.
is_exec() {
    FILE_PATH="${1:-}"
    [ -n "${FILE_PATH}" ] && [ -f "${FILE_PATH}" ] && [ -x "${FILE_PATH}" ]
}

# Return the first writable directory from the provided candidates.
writable_dir() {
    create="$1"
    shift

    for dir in "$@"; do
        [ -n "$dir" ] || continue
        [ -f "$dir" ] && continue

        if [ "$create" = "1" ]; then
            mkdir -p "$dir" 2>/dev/null || true
        fi

        if [ -d "$dir" ] && [ -w "$dir" ]; then
            printf "%s\n" "$dir"
            return 0
        fi
    done

    return 1
}

# Render a path using ${HOME} when it lives under HOME.
home_relative_path() {
    path_value="${1:-}"

    case "$path_value" in
        "$HOME")
            printf '%s\n' '${HOME}'
            ;;
        "$HOME"/*)
            printf '${HOME}%s\n' "${path_value#"$HOME"}"
            ;;
        *)
            printf '%s\n' "$path_value"
            ;;
    esac
}


# Resolve an executable path by command name.
bin_path() {
    program_name="${1:-}"
    if [ -z "$program_name" ]; then
        return 1
    fi

    # First try POSIX type output.
    type_path="$(type "$program_name" 2>/dev/null | awk '/ is \// { sub(/^.* is /, "", $0); print; exit }' || true)"
    if is_exec "${type_path}"; then
        printf "%s\n" "${type_path}"
        return 0
    fi

    # Fall back to which when available.
    which_path="$(which "$program_name" 2>/dev/null || true)"
    if is_exec "${which_path}"; then
        printf "%s\n" "${which_path}"
        return 0
    fi

    return 1
}


# Fetch a URL with curl or wget.
http_get() {
    url=${1:-}
    if [ -z "$url" ]; then
        printf "ERROR: No URL provided to http_get\n" >&2
        return 1
    fi

    if command -v curl >/dev/null 2>&1; then
        log "Fetching with curl: $url"
        curl -fsSL "$url"
        return $?
    fi

    if command -v wget >/dev/null 2>&1; then
        log "Fetching with wget: $url"
        wget -qO- "$url"
        return $?
    fi

    printf "ERROR: neither curl nor wget is available on PATH.\n" >&2
    exit 1
}





# Resolve and export HOME when needed.
{
    home_dir=$(writable_dir "1" "${HOME:-}" "/home" "/home/app")
    if [ -z "$home_dir" ]; then
        printf "Error: Could not find or create a writable directory for HOME.\n" >&2
        exit 1
    fi
    log "Discovered HOME directory: $home_dir"
    if [ "${HOME:-}" != "$home_dir" ]; then
        ACTIVATE_PROFILE="0"
        log "Setting HOME to $home_dir"
        append_activate "export HOME=${home_dir}"
    fi
}



# Resolve and export TMPDIR when needed.
{
    tmp_dir=$(writable_dir "0" "${TMPDIR:-}" "${TMP:-}" "${TEMP:-}" "${TEMPDIR:-}" "/tmp" "/var/tmp" "/usr/tmp")
    if [ -z "$tmp_dir" ]; then
        home_tmp_dir="${HOME}/.tmp"
        mkdir -p "${home_tmp_dir}"
        log "Created TMPDIR directory: ${home_tmp_dir}"
        log "Setting TMPDIR to ${home_tmp_dir}"
        append_activate 'export TMPDIR=\${HOME}/.tmp'
    else
        log "Discovered TMPDIR directory: $tmp_dir"
    fi
}

# Ensure mise is installed and reachable on PATH.
{
    MISE_INSTALL_DIR=""
    MISE_BIN="$(bin_path "mise")" || {
        log "mise not found on PATH. Installing."
        LOCAL_BIN="${HOME}/.local/bin"
        mkdir -p "${LOCAL_BIN}"
        export MISE_INSTALL_DIR="${LOCAL_BIN}"
        export MISE_INSTALL_PATH="${MISE_INSTALL_DIR}/mise"
        http_get "https://mise.run" | sh >&2

        MISE_BIN="$(bin_path "mise")" || {
            printf "ERROR: mise installation failed\n" >&2
            exit 1
        }
    }

    if [ -z "${MISE_INSTALL_DIR}" ]; then
        MISE_INSTALL_DIR="$(dirname "$MISE_BIN")"
    fi
    MISE_INSTALL_DIR_RENDERED="$(home_relative_path "${MISE_INSTALL_DIR}")"

    log "Discovered mise install directory: $MISE_INSTALL_DIR"
    log "Rendered mise install directory: $MISE_INSTALL_DIR_RENDERED"
    log "mise binary found: $MISE_BIN"
}

append_activate "MISE_INSTALL_DIR=\"${MISE_INSTALL_DIR_RENDERED}\"; case \":\$PATH:\" in *\":\$MISE_INSTALL_DIR:\"*) ;; *) export PATH=\"\$MISE_INSTALL_DIR:\$PATH\";; esac"
append_activate 'eval "$(mise activate --shims bash)"'



if [ "${DISABLE_RUN}" = "0" ]; then
    if [ "${CARGO_INSTALL}" = "1" ]; then
    log "Building and installing ${TOOL_SPEC}"
    mise exec rust -- cargo install --path "${SCRIPT_DIR}" --bin lfp-env --root "${HOME}/.local" --force 1>&2
    "${HOME}/.local/bin/lfp-env" "$@"
    else
    log "Installing ${TOOL_SPEC}"
    mise use -g "${TOOL_SPEC}" 1>&2
    mise x "${TOOL_SPEC}" -- lfp-env "$@"
    fi
fi


# Append activation for a shell into a profile file.
append_profile_line() {
    profile_path=$1
    shell_name=$2
    interactive=$3
    create_if_missing=${4:-0}

    activate_tag="#${TOOL_SPEC}-activate"
    path_line="MISE_INSTALL_DIR=\"${MISE_INSTALL_DIR_RENDERED}\"; case \":\$PATH:\" in *\":\$MISE_INSTALL_DIR:\"*) ;; *) export PATH=\"\$MISE_INSTALL_DIR:\$PATH\";; esac"

    if [ "$interactive" = "1" ]; then
        profile_line="${path_line}; eval \"\$(mise activate ${shell_name})\""
    else
        profile_line="${path_line}; eval \"\$(mise activate --shims bash)\""
    fi

    if [ ! -f "$profile_path" ]; then
        if [ "$create_if_missing" = "1" ]; then
            : > "$profile_path"
            log "Created profile $profile_path"
        else
            return 0
        fi
    fi

    tmp_file="${profile_path}.tmp.$$"

    while IFS= read -r existing_line || [ -n "$existing_line" ]; do
        case "$existing_line" in
            *"$activate_tag")
                continue
                ;;
            *)
                printf '%s\n' "$existing_line"
                ;;
        esac
    done < "$profile_path" > "$tmp_file"

    printf '%s %s\n' "$profile_line" "$activate_tag" >> "$tmp_file"

    if ! cmp -s "$profile_path" "$tmp_file"; then
        mv "$tmp_file" "$profile_path"
        log "Updated activation in $profile_path"
    else
        rm -f "$tmp_file"
        log "No changes to $profile_path"
    fi
}

if [ "${ACTIVATE_PROFILE}" = "1" ]; then
    append_profile_line "${HOME}/.profile" bash 0 1
    append_profile_line "${HOME}/.bash_profile" bash 0
    append_profile_line "${HOME}/.zshenv" zsh 0
    append_profile_line "${HOME}/.zprofile" zsh 0
    append_profile_line "${HOME}/.bashrc" bash 1
    append_profile_line "${HOME}/.zshrc" zsh 1
fi



# Print export statements for caller eval.
printf '%s\n' "$ACTIVATE"
