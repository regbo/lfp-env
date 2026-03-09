#!/bin/sh
set -eu

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

# Normalize a shell path/command to lowercase shell name
normalize_shell_name() {
  value="${1-}"
  basename "${value}" | tr '[:upper:]' '[:lower:]'
}

# Ensure a line exists in a profile file once.
ensure_profile_line() {
  profile_path="${1-}"
  profile_line="${2-}"
  profile_dir="$(dirname "${profile_path}")"
  mkdir -p "${profile_dir}"
  if [ ! -f "${profile_path}" ]; then
    : > "${profile_path}"
  fi
  if ! grep -Fqx "${profile_line}" "${profile_path}" 2>/dev/null; then
    printf "%s\n" "${profile_line}" >> "${profile_path}"
  fi
}

# Resolve the profile file to update from shell name.
resolve_profile_path() {
  shell_name="${1-}"
  case "${shell_name}" in
    bash) printf "%s\n" "${HOME}/.bashrc" ;;
    zsh) printf "%s\n" "${HOME}/.zshrc" ;;
    fish) printf "%s\n" "${HOME}/.config/fish/config.fish" ;;
    elvish) printf "%s\n" "${HOME}/.elvish/rc.elv" ;;
    nu) printf "%s\n" "${HOME}/.config/nushell/config.nu" ;;
    xonsh) printf "%s\n" "${HOME}/.xonshrc" ;;
    *) printf "%s\n" "${HOME}/.profile" ;;
  esac
}

# Resolve a separate non-interactive/login profile path when one exists.
resolve_non_interactive_profile_path() {
  shell_name="${1-}"
  interactive_profile_path="${2-}"
  case "${shell_name}" in
    bash)
      if [ -f "${HOME}/.bash_profile" ] && [ "${interactive_profile_path}" != "${HOME}/.bash_profile" ]; then
        printf "%s\n" "${HOME}/.bash_profile"
        return 0
      fi
      if [ -f "${HOME}/.profile" ] && [ "${interactive_profile_path}" != "${HOME}/.profile" ]; then
        printf "%s\n" "${HOME}/.profile"
        return 0
      fi
      ;;
    zsh)
      if [ -f "${HOME}/.zprofile" ] && [ "${interactive_profile_path}" != "${HOME}/.zprofile" ]; then
        printf "%s\n" "${HOME}/.zprofile"
        return 0
      fi
      ;;
    *)
      if [ -f "${HOME}/.profile" ] && [ "${interactive_profile_path}" != "${HOME}/.profile" ]; then
        printf "%s\n" "${HOME}/.profile"
        return 0
      fi
      ;;
  esac
  printf "%s" ""
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

# Ensure mise exists
{
    if ! mise -v >/dev/null 2>&1; then
        http_get "https://mise.run" | sh 1>&2
        if ! mise -v >/dev/null 2>&1; then
            echo "ERROR: mise installation failed." >&2
            exit 1
        fi
    fi
}


ensure_env_dir "LOCAL_BIN" "${HOME}/.local/bin"
ENV_SETUP_TOOL_SPEC="github:regbo/lfp-env"
if is_true_flag "${ENV_SETUP_LOCAL-}"; then
  mise exec rust -- cargo install --path "." --bin lfp-env --root "${HOME}/.local" --force 1>&2
  "${LOCAL_BIN}/lfp-env" 1>&2
else
  mise use -g "${ENV_SETUP_TOOL_SPEC}" 1>&2
  mise x "${ENV_SETUP_TOOL_SPEC}" -- lfp-env 1>&2
fi

SHELL_NAME=""
if ! is_blank "${SHELL-}"; then
  SHELL_NAME="$(normalize_shell_name "${SHELL}")"
elif is_exec "ps" && ! is_blank "${PPID-}"; then
  # Fallback for non-interactive sessions where SHELL is not exported.
  parent_shell="$(ps -p "${PPID}" -o comm= 2>/dev/null || true)"
  if ! is_blank "${parent_shell}"; then
    SHELL_NAME="$(normalize_shell_name "${parent_shell}")"
  fi
fi

ACTIVATE_PROFILE_SHIMS_COMMAND="mise activate --shims bash"
ACTIVATE_PROFILE_SHIMS_LINE="eval \"\$(${ACTIVATE_PROFILE_SHIMS_COMMAND})\""
case "${SHELL_NAME}" in
  bash|elvish|fish|nu|xonsh|zsh)
    ACTIVATE_PROFILE_COMMAND="mise activate ${SHELL_NAME}"
    ;;
  *)
    ACTIVATE_PROFILE_COMMAND="${ACTIVATE_PROFILE_SHIMS_COMMAND}"
    ;;
esac
ACTIVATE_PROFILE_LINE="eval \"\$(${ACTIVATE_PROFILE_COMMAND})\""
PROFILE_PATH="$(resolve_profile_path "${SHELL_NAME}")"
PATH_PROFILE_LINE='export PATH="${HOME}/.local/bin:$PATH"'
ensure_profile_line "${PROFILE_PATH}" "${PATH_PROFILE_LINE}"
ensure_profile_line "${PROFILE_PATH}" "${ACTIVATE_PROFILE_LINE}"

NON_INTERACTIVE_PROFILE_PATH="$(resolve_non_interactive_profile_path "${SHELL_NAME}" "${PROFILE_PATH}")"
if ! is_blank "${NON_INTERACTIVE_PROFILE_PATH}"; then
  ensure_profile_line "${NON_INTERACTIVE_PROFILE_PATH}" "${PATH_PROFILE_LINE}"
  ensure_profile_line "${NON_INTERACTIVE_PROFILE_PATH}" "${ACTIVATE_PROFILE_SHIMS_LINE}"
fi

# Emit accumulated exports and activation script output for evaluation by caller
printf "%b" "$EXPORTS"
eval "$ACTIVATE_PROFILE_COMMAND"

