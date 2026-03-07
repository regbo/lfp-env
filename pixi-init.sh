#!/bin/sh
set -eu

PATH_MODIFIED=0
EXPORTS=""

# Append an export statement to the buffered EXPORTS output
append_export() {
  name="$1"
  value="$2"
  # shell-safe single-quote escaping
  escaped=$(printf "%s" "$value" | sed "s/'/'\\\\''/g")
  EXPORTS="${EXPORTS}export ${name}='${escaped}'\n"
}


# Return true if a string is empty or only whitespace
is_blank() {
  value="${1-}"
  case "${value}" in
    "")
      return 0
      ;;
    *[![:space:]]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

# Check if a directory exists in PATH
is_in_path() {
    case ":$PATH:" in
        *":$1:"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if a command exists on PATH
is_exec() {
  name="${1-}"
  if is_blank "${name}"; then
    return 1
  fi
  command -v "${name}" >/dev/null 2>&1
}

# Fetch a URL using curl or wget
http_get() {
  url="${1-}"

  if is_exec "curl"; then
    curl -fsSL "${url}"
    return $?
  fi

  if is_exec "wget"; then
    wget -qO- "${url}"
    return $?
  fi

  echo "ERROR: neither curl nor wget is available on PATH." >&2
  exit 1
}

# Ensure a directory exists and is writable (creating it if needed)
is_writable_dir() {
  location="${1-}"
  if is_blank "${location}"; then
    return 1
  fi

  # If location is set, ensure it exists (or can be created) and is writable.
  if ! mkdir -p "${location}" 2>/dev/null; then
    return 1
  fi
  if [ ! -d "${location}" ] || [ ! -w "${location}" ]; then
    return 1
  fi

  probe_file="$(mktemp "${location}/.write-probe-XXXXXX" 2>/dev/null || true)"
  if is_blank "${probe_file}"; then
    probe_file="${location}/.write-probe.$$"
    if ! : > "${probe_file}" 2>/dev/null; then
      return 1
    fi
  fi
  rm -f "${probe_file}"
  return 0
}

# Assign and export a variable name dynamically using eval
eval_export() {
  env_name="${1-}"
  value="${2-}"
  eval "$env_name=\$value"
  export "$env_name"
}

# Resolve an environment directory from candidate locations
ensure_env_dir() {
  env_name="${1-}"
  shift || true
  soft_fail=0
  if [ "${1-}" = "-" ]; then
    soft_fail=1
    shift || true
  fi

  eval "env_value=\${${env_name}-}"
  if is_writable_dir "${env_value}"; then
    eval_export "${env_name}" "${env_value}"
    return 0
  fi

  for location in "$@"; do
    if is_writable_dir "${location}"; then
      eval_export "${env_name}" "${location}"
      append_export "${env_name}" "${location}"
      return 0
    fi
  done

  if [ "${soft_fail}" -eq 1 ]; then
    return 0
  fi

  echo "ERROR: could not resolve a writable ${env_name} directory." >&2
  exit 1
}

# Ensure a directory exists in PATH
ensure_path_dir() {
    dir="${1-}"
    case ":$PATH:" in
        *":$dir:"*) ;;
        *)  
            PATH_MOD="$dir:$PATH"
            PATH_MODIFIED=1
            append_export "PATH" "${PATH_MOD}"
            PATH="${PATH_MOD}"
            export PATH
            ;;
    esac
}

# Resolve TEMP and align TMP/TMPDIR
{
    ensure_env_dir "TEMP" "${TEMP-}" "${TMPDIR-}" "${TMP-}" "/tmp" "./.tmp"
    export TMPDIR="${TEMP}"
    export TMP="${TEMP}"
}

# Resolve HOME with Databricks special-case
{
    if ! is_blank "${DATABRICKS_APP_NAME-}" && ! is_blank "${DATABRICKS_APP_PORT-}"; then
        ensure_env_dir "HOME" "-" "/home/app"
    fi
    ensure_env_dir "HOME" "/home" "./home" "${TEMP}/home"
}

# Resolve LOCAL_BIN and ensure it is on PATH
{
    ensure_env_dir "LOCAL_BIN" "${HOME}/.local/bin"
    ensure_path_dir "${LOCAL_BIN}"
}

# Ensure pixi exists and is on PATH
{
    ensure_env_dir "PIXI_HOME" "${HOME}/.pixi"
    ensure_path_dir "${PIXI_HOME}/bin"
    if ! is_exec "pixi"; then
        mkdir -p "${PIXI_HOME}/bin"
        http_get "https://pixi.sh/install.sh" | sh 1>&2
        if ! is_exec "pixi"; then
            echo "ERROR: pixi installation failed." >&2
            exit 1
        fi
    fi
}

# Install a tool globally via pixi if missing
ensure_installed(){
    tool="${1-}"
    if ! is_exec "${tool}"; then
        pixi global install "${tool}" 1>&2
        if ! is_exec "${tool}"; then
            echo "ERROR: ${tool} not found." >&2
            exit 1
        fi
    fi
    return 0
}

ensure_installed python
ensure_installed git

# Install additional tools passed as arguments
if [ "$#" -gt 0 ]; then
    for tool in "$@"; do
        ensure_installed "${tool}"
    done
fi


# Emit accumulated exports (including PATH) for evaluation by caller if any exist
if [ -n "$EXPORTS" ]; then
  if [ "${PATH_MODIFIED}" -eq 0 ]; then 
    append_export "PATH" "${PATH}"
  fi
  printf "%b" "$EXPORTS"
fi

