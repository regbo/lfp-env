#!/bin/sh
set -eu

# Validate Unix installer profile persistence without network access.

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lfp-env-test.XXXXXX")"

cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT HUP INT TERM

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    file_path="$1"
    expected_text="$2"
    grep -F -- "$expected_text" "$file_path" >/dev/null 2>&1 || fail "Expected '$expected_text' in $file_path"
}

assert_not_contains() {
    file_path="$1"
    unexpected_text="$2"
    if grep -F -- "$unexpected_text" "$file_path" >/dev/null 2>&1; then
        fail "Did not expect '$unexpected_text' in $file_path"
    fi
}

assert_count() {
    file_path="$1"
    expected_text="$2"
    expected_count="$3"
    actual_count="$(grep -F -c -- "$expected_text" "$file_path" || true)"
    [ "$actual_count" = "$expected_count" ] || fail "Expected '$expected_text' to appear $expected_count times in $file_path, got $actual_count"
}

create_version_tool() {
    tool_name="$1"
    version_output="$2"
    tool_path="$FAKE_BIN/$tool_name"
    cat >"$tool_path" <<EOF
#!/bin/sh
if [ "\${1:-}" = "--version" ]; then
    printf '%s\n' "$version_output"
    exit 0
fi
exit 0
EOF
    chmod +x "$tool_path"
}

create_pixi_tool() {
    tool_path="$FAKE_BIN/pixi"
    cat >"$tool_path" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
    printf '%s\n' 'pixi 0.40.0'
    exit 0
fi
if [ "${1:-}" = "global" ] && [ "${2:-}" = "install" ]; then
    if [ -n "${FAKE_PIXI_LOG:-}" ]; then
        shift 2
        printf '%s\n' "$*" >>"$FAKE_PIXI_LOG"
    fi
    exit 0
fi
exit 0
EOF
    chmod +x "$tool_path"
}

run_install() {
    home_dir="$1"
    stderr_path="$2"
    stdout_path="$3"
    shift 3
    PATH="$FAKE_BIN:$ORIGINAL_PATH" \
    HOME="$home_dir" \
    PIXI_HOME="$home_dir/.pixi" \
    FAKE_PIXI_LOG="$TEMP_DIR/pixi-install.log" \
    sh "$ROOT_DIR/install.sh" "$@" >"$stdout_path" 2>"$stderr_path"
}

run_install_without_home() {
    working_dir="$1"
    stderr_path="$2"
    stdout_path="$3"
    shift 3
    (
        cd "$working_dir"
        unset HOME
        PATH="$FAKE_BIN:$ORIGINAL_PATH" \
        FAKE_PIXI_LOG="$TEMP_DIR/pixi-install.log" \
        sh "$ROOT_DIR/install.sh" "$@" >"$stdout_path" 2>"$stderr_path"
    )
}

run_install_with_shell_only_home() {
    working_dir="$1"
    shell_home="$2"
    stderr_path="$3"
    stdout_path="$4"
    shift 4
    (
        cd "$working_dir"
        env -u HOME sh -c '
            HOME="$1"
            shift
            PATH="$1" \
            FAKE_PIXI_LOG="$2" \
            sh "$3" "$@" >"$4" 2>"$5"
        ' sh "$shell_home" "$FAKE_BIN:$ORIGINAL_PATH" "$TEMP_DIR/pixi-install.log" "$ROOT_DIR/install.sh" "$stdout_path" "$stderr_path" "$@"
    )
}

build_activation_command() {
    home_dir="$1"
    pixi_bin_dir="$home_dir/.pixi/bin"
    printf 'PIXI_BIN_DIR=%s;case ":$PATH:" in *":$PIXI_BIN_DIR:"*) ;; *) export PATH="$PIXI_BIN_DIR:$PATH";; esac;hash -r 2>/dev/null || true' "'$pixi_bin_dir'"
}

build_generated_home_activation_command() {
    home_dir="$1"
    printf 'HOME=%s;export HOME' "'$home_dir'"
}

extract_generated_home_dir() {
    file_path="$1"
    sed -n "s/^HOME='\([^']*\)';export HOME$/\1/p" "$file_path"
}

assert_profile_created_once() {
    home_dir="$1"
    activation_command="$(build_activation_command "$home_dir")"
    profile_path="$home_dir/.profile"
    zprofile_path="$home_dir/.zprofile"

    [ -f "$profile_path" ] || fail "Expected $profile_path to be created"
    [ -f "$zprofile_path" ] || fail "Expected $zprofile_path to exist"
    assert_contains "$profile_path" "$activation_command # lfp-env"
    assert_contains "$zprofile_path" "$activation_command # lfp-env"
    assert_count "$profile_path" "# lfp-env" 1
    assert_count "$zprofile_path" "# lfp-env" 1
}

test_profile_updates_are_idempotent() {
    test_root="$TEMP_DIR/idempotent"
    home_dir="$test_root/home"
    mkdir -p "$home_dir"
    printf '%s\n' 'export EXISTING_PROFILE=1' >"$home_dir/.zprofile"

    run_install "$home_dir" "$test_root/first.err" "$test_root/first.out"
    assert_profile_created_once "$home_dir"
    assert_contains "$test_root/first.err" "Updated non-interactive profile $home_dir/.profile"
    assert_contains "$test_root/first.err" "Updated non-interactive profile $home_dir/.zprofile"

    first_profile_snapshot="$(cat "$home_dir/.profile")"
    first_zprofile_snapshot="$(cat "$home_dir/.zprofile")"

    run_install "$home_dir" "$test_root/second.err" "$test_root/second.out"
    assert_not_contains "$test_root/second.err" "Updated non-interactive profile"
    [ "$first_profile_snapshot" = "$(cat "$home_dir/.profile")" ] || fail ".profile changed on the second run"
    [ "$first_zprofile_snapshot" = "$(cat "$home_dir/.zprofile")" ] || fail ".zprofile changed on the second run"
}

test_existing_activation_line_is_not_rewritten() {
    test_root="$TEMP_DIR/existing-line"
    home_dir="$test_root/home"
    mkdir -p "$home_dir"
    activation_command="$(build_activation_command "$home_dir")"
    printf '%s\n' "$activation_command" >"$home_dir/.zprofile"

    run_install "$home_dir" "$test_root/run.err" "$test_root/run.out"

    assert_not_contains "$test_root/run.err" "Updated non-interactive profile $home_dir/.zprofile"
    assert_count "$home_dir/.zprofile" "PIXI_BIN_DIR=" 1
    assert_count "$home_dir/.zprofile" "# lfp-env" 0
    assert_contains "$home_dir/.profile" "$activation_command # lfp-env"
}

test_additional_args_are_globally_installed() {
    test_root="$TEMP_DIR/additional-args"
    home_dir="$test_root/home"
    mkdir -p "$home_dir"
    : >"$TEMP_DIR/pixi-install.log"

    run_install "$home_dir" "$test_root/run.err" "$test_root/run.out" jq yq

    assert_contains "$TEMP_DIR/pixi-install.log" "jq yq"
}

test_generated_home_is_exported() {
    test_root="$TEMP_DIR/generated-home"
    working_dir="$test_root/workspace"
    mkdir -p "$working_dir"
    : >"$TEMP_DIR/pixi-install.log"

    run_install_without_home "$working_dir" "$test_root/run.err" "$test_root/run.out"

    generated_home_dir="$(extract_generated_home_dir "$test_root/run.out")"
    [ -n "$generated_home_dir" ] || fail "Expected generated HOME to be exported in activation output"
    home_export_command="$(build_generated_home_activation_command "$generated_home_dir")"
    pixi_activation_command="$(build_activation_command "$generated_home_dir")"
    assert_contains "$test_root/run.out" "$home_export_command"
    assert_contains "$test_root/run.out" "$pixi_activation_command"
    [ ! -e "$generated_home_dir/.profile" ] || fail "Did not expect profile writes when HOME was generated"
}

test_shell_only_home_is_ignored() {
    test_root="$TEMP_DIR/shell-only-home"
    working_dir="$test_root/workspace"
    shell_home="$test_root/should-not-be-used"
    mkdir -p "$working_dir"
    : >"$TEMP_DIR/pixi-install.log"

    run_install_with_shell_only_home "$working_dir" "$shell_home" "$test_root/run.err" "$test_root/run.out"

    generated_home_dir="$(extract_generated_home_dir "$test_root/run.out")"
    [ -n "$generated_home_dir" ] || fail "Expected generated HOME when HOME only exists as a shell variable"
    [ "$generated_home_dir" != "$shell_home" ] || fail "Shell-only HOME should not be trusted"
}

ORIGINAL_PATH="${PATH:-}"
FAKE_BIN="$TEMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"
create_pixi_tool
create_version_tool python "Python 3.11.9"
create_version_tool uv "uv 0.10.9"
create_version_tool git "git version 2.50.1"

test_profile_updates_are_idempotent
test_existing_activation_line_is_not_rewritten
test_additional_args_are_globally_installed
test_generated_home_is_exported
test_shell_only_home_is_ignored
