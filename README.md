# lfp-env

Bootstrap installers for `lfp-env` plus a Rust CLI that validates the base toolchain needed to use the environment.

## What it does

The shell wrappers are now thin bootstraps. They:

- resolves a usable `HOME`
- downloads or reuses the `lfp-env` binary
- invokes the Rust installer entrypoint

The Rust installer mode then:

- resolves `HOME` and `TMPDIR` fallbacks where applicable
- installs or discovers `mise`
- emits shell activation commands on stdout
- optionally updates shell profiles
- ensures the default toolchain (`git`, `python`, `uv`) through `mise`
- forwards any remaining installer arguments to `mise`

The normal Rust runtime mode:

- checks `python` and requires `>= 3.10`
- checks that `uv` exists
- checks that `git` exists
- installs any missing requirement via `mise use -g <tool>@latest`

## Quick Start

### macOS/Linux

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-env/latest/install.sh | sh)"
```

Unix bootstrap logs go to stderr. Activation commands come from the Rust installer on stdout, and `eval "$(...)"` applies them to the current shell.

### Windows (PowerShell)

```powershell
& ([scriptblock]::Create((irm -useb https://raw.githubusercontent.com/regbo/lfp-env/latest/install.ps1))) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Invoke-Expression $_ }
```

Windows bootstrap logs also go to stderr. Activation commands come from the Rust installer on stdout and are evaluated into the current PowerShell session.

## Local Development

To test the current checkout on Unix, build the local binary first and point the bootstrap wrapper at it:

```sh
mise exec rust -- cargo build --bin lfp-env
LFP_ENV_INSTALL_PATH="$PWD/target/debug/lfp-env" eval "$(sh ./install.sh)"
```

On Windows, build the local binary first and point the bootstrap wrapper at it:

```powershell
$env:LFP_ENV_INSTALL_PATH = "$PWD\target\debug\lfp-env.exe"
mise exec rust -- cargo build --bin lfp-env
.\install.ps1 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Invoke-Expression $_ }
```

## Bootstrap Variables

These variables are read by the shell wrappers before Rust installer mode starts:

- `LFP_ENV_REPO`
  Default: `regbo/lfp-env`
  Selects which GitHub repository to download release assets from.
- `LFP_ENV_VERSION`
  Default: unset
  When set, downloads `v<version>` instead of `latest` and requires the bootstrap binary to match that exact version.
- `LFP_ENV_MIN_VERSION`
  Default: unset
  Requires the existing bootstrap binary version to be at least this version.
- `LFP_ENV_INSTALL_PATH`
  Default:
  Unix: `${HOME}/.local/bin/lfp-env`
  Windows: `%LOCALAPPDATA%\\bin\\lfp-env.exe`
  Overrides where the bootstrap wrapper stores and executes the `lfp-env` binary.

## Rust Installer Variables

These variables are consumed by the Rust installer mode:

- `LFP_ENV_ACTIVATE_PROFILE`
  Default: `1`
  Enables writing activation lines to shell profile files.
- `LFP_ENV_LOGGING_ENABLED`
  Default: `1`
  Controls installer logging on stderr. Set to `0` to suppress installer log lines.
- `LFP_ENV_LOG_LEVEL`
  Default: `info`
  Controls the normal `lfp-env` runtime log level when invoking the non-installer mode directly.

## Activation Behavior

The Rust installer emits activation commands on stdout.

On Unix, the emitted commands:

- ensure `MISE_INSTALL_DIR` is on `PATH`
- run `eval "$(mise activate --shims bash)"`
- export `HOME` if the installer had to fall back away from the incoming environment
- export `TMPDIR` as `${HOME}/.tmp` when no writable temp directory is already available

On Windows, the emitted commands:

- ensure the installed `mise` bin directory is on `PATH`
- run `mise activate --shims pwsh` in the current PowerShell session

## Profile Updates

When `LFP_ENV_ACTIVATE_PROFILE=1` and `HOME` did not need to be rewritten, the Unix Rust installer updates these files when applicable:

- `~/.profile`
- `~/.bash_profile`
- `~/.zshenv`
- `~/.zprofile`
- `~/.bashrc`
- `~/.zshrc`

Interactive shell profiles get `mise activate <shell>`. Non-interactive profiles get `mise activate --shims bash`.

On Windows, when `mise` is newly installed, the Rust installer updates:

- `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`

The inserted PowerShell activation uses `mise activate --shims pwsh`.

## Rust CLI

The user-facing Rust CLI supports:

```text
lfp-env --log-level <error|warn|info|debug|trace|off>
lfp-env --version
```

`lfp-env --version` prints only the raw semver, for example `0.1.0`, so shell installers can compare versions safely.

`LFP_ENV_LOG_LEVEL` is read when `--log-level` is not provided.

The shell wrappers use an internal Rust installer mode via `LFP_ENV_INSTALLER_MODE=1`. That mode is not intended as a public interface.

When hidden installer mode is used through `install.sh` or `install.ps1`, only installer-specific flags are parsed by `lfp-env`. Any remaining arguments after `--` are forwarded to `mise` after the default toolchain setup completes.

## Task Runner

Tasks are defined in `mise.toml`:

- `mise run commit`
- `mise run tag`

Those tasks call `scripts/deploy.py`:

- `mise run commit` -> `uv run --with-requirements requirements.txt -- scripts/deploy.py commit`
- `mise run tag` -> `uv run --with-requirements requirements.txt -- python scripts/deploy.py tag`

## Testing

The test suite is intentionally minimal and only smoke-tests the built Rust binary.

Run the full suite with:

```sh
mise exec rust -- cargo build --bin lfp-env
mise exec rust -- cargo test
```

## License

See `LICENSE`.
