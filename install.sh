#!/bin/sh
set -eu

ENV_TOOL_SPEC="${ENV_TOOL_SPEC:-github:regbo/lfp-env}"
ENV_LOCAL_INSTALL="${ENV_LOCAL_INSTALL:-FALSE}"
ENV_ARGS=""

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

# Return true when value is "1" or "true" (case-insensitive)
is_true_flag() {
  value="${1-}"
  normalized="$(printf "%s" "${value}" | tr '[:upper:]' '[:lower:]')"
  [ "${normalized}" = "1" ] || [ "${normalized}" = "true" ]
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
  ENV_ARGS="${ENV_ARGS}${env_name}:${value}
"
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
    return 0
  fi

  for location in "$@"; do
    if is_writable_dir "${location}"; then
      eval_export "${env_name}" "${location}"
      return 0
    fi
  done

  if [ "${soft_fail}" -eq 1 ]; then
    return 0
  fi

  echo "ERROR: could not resolve a writable ${env_name} directory." >&2
  exit 1
}

# Resolve the first executable binary path for mise from `type -a`.
resolve_mise_bin() {
  type_path="$(type -a mise 2>/dev/null | awk '/ is \// { sub(/^.* is /, "", $0); print; exit }')"
  if [ -n "${type_path}" ] && [ -f "${type_path}" ] && [ -x "${type_path}" ]; then
    printf "%s\n" "${type_path}"
    return 0
  fi
  which_path="$(which mise 2>/dev/null || true)"
  if [ -n "${which_path}" ] && [ -f "${which_path}" ] && [ -x "${which_path}" ]; then
    printf "%s\n" "${which_path}"
    return 0
  fi
  return 1
}

# Resolve HOME
ensure_env_dir "HOME" "/home" "./.home"

# Resolve TEMP on nix
OS_NAME="$(uname -s | tr '[:upper:]' '[:lower:]')"
if [ "${OS_NAME}" != "darwin" ]; then
  ensure_env_dir "TMPDIR" "${TEMP-}" "${TMP-}" "/tmp" "./.tmp"
fi


# Ensure mise exists and resolve an executable binary path.
MISE_BIN="$(resolve_mise_bin || true)"
if is_blank "${MISE_BIN}"; then
  http_get "https://mise.run" | sh 1>&2
  MISE_BIN="$(resolve_mise_bin || true)"
fi
if is_blank "${MISE_BIN}" || [ ! -x "${MISE_BIN}" ]; then
  echo "ERROR: mise installation failed." >&2
  exit 1
fi

set -- "--mise_bin" "${MISE_BIN}" "$@"
if [ -n "${ENV_ARGS}" ]; then
  OLD_IFS="${IFS}"
  IFS='
'
  for pair in ${ENV_ARGS}; do
    if [ -n "${pair}" ]; then
      set -- "$@" "--env" "${pair}"
    fi
  done
  IFS="${OLD_IFS}"
fi

if is_true_flag "${ENV_LOCAL_INSTALL}"; then
  "${MISE_BIN}" exec rust -- cargo install --path "." --bin lfp-env --root "${HOME}/.local" --force 1>&2
  "${HOME}/.local/bin/lfp-env" "$@"
else
  "${MISE_BIN}" use -g "${ENV_TOOL_SPEC}" 1>&2
  "${MISE_BIN}" x "${ENV_TOOL_SPEC}" -- lfp-env "$@"
fi
