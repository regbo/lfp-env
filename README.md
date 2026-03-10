# lfp-env

Lightweight bootstrap installers for `mise` plus a Rust CLI that validates the base toolchain needed to use `lfp-env`.

## What it does

The install scripts:

- ensure `HOME` and `TMPDIR` are usable
- install `mise` if it is not already available
- emit activation commands on stdout for the current shell session
- optionally update shell profiles
- either install `github:regbo/lfp-env` with `mise` or build the local crate with Cargo

The Rust binary:

- checks `python` and requires `>= 3.10`
- checks that `uv` exists
- checks that `git` exists
- installs any missing requirement via `mise use -g <tool>@latest`

## Quick Start

### macOS/Linux

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-env/latest/install.sh | sh)"
```

The shell installer writes log messages to stderr and activation commands to stdout. `eval "$(...)"` applies those activation commands to the current shell.

### Windows (PowerShell)

```powershell
& ([scriptblock]::Create((irm -useb https://raw.githubusercontent.com/regbo/lfp-env/latest/install.ps1))) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Invoke-Expression $_ }
```

The PowerShell installer also writes logs to stderr and activation commands to stdout. Evaluating the output applies the activation lines to the current session.

## Local Development

Set `LFP_ENV_CARGO_INSTALL=1` to build and run the local crate from the current checkout instead of installing `github:regbo/lfp-env` with `mise`.

### macOS/Linux

```sh
eval "$(LFP_ENV_CARGO_INSTALL=1 sh ./install.sh)"
```

### Windows (PowerShell)

```powershell
$env:LFP_ENV_CARGO_INSTALL = "1"
.\install.ps1 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Invoke-Expression $_ }
```

## Installer Environment Variables

Both install scripts support these environment variables:

- `LFP_ENV_TOOL_SPEC`
  Default: `github:regbo/lfp-env`
  Controls the `mise` tool selector used in the non-Cargo install path.
- `LFP_ACTIVATE_PROFILE`
  Default: `1`
  Enables writing activation lines to shell profile files.
- `LFP_ENV_DISABLE_RUN`
  Default: `0`
  When set to `1`, the installer performs setup and emits activation output but does not run `lfp-env`.
- `LFP_ENV_CARGO_INSTALL`
  Default: `0`
  When set to `1`, builds and installs the local crate with Cargo into `~/.local` instead of using `mise` to install the GitHub tool spec.
- `LFP_ENV_LOGGING_ENABLED`
  Default: `1`
  Controls installer logging on stderr. Set to `0` to suppress script-side logs.

## Activation Behavior

The install scripts always emit activation commands on stdout.

On Unix, the emitted commands:

- ensure `MISE_INSTALL_DIR` is on `PATH`
- run `eval "$(mise activate --shims bash)"`

On PowerShell, the emitted commands:

- ensure the `mise` bin directory is on `PATH`
- run the output of `mise activate --shims pwsh`
- in Cargo mode, also ensure the local Cargo bin directory is on `PATH`

## Profile Updates

### macOS/Linux

When `LFP_ACTIVATE_PROFILE=1`, `install.sh` updates these files when applicable:

- `~/.profile`
- `~/.bash_profile`
- `~/.zshenv`
- `~/.zprofile`
- `~/.bashrc`
- `~/.zshrc`

Interactive shell profiles get `mise activate <shell>`. Non-interactive shell profiles get `mise activate --shims bash`.

### Windows (PowerShell)

When `LFP_ACTIVATE_PROFILE=1` and the script performs `mise` setup itself, `install.ps1` updates:

- `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`

It adds a `mise activate --shims pwsh` activation line if it is not already present.

## Rust CLI

The `lfp-env` binary currently supports one CLI option:

```text
lfp-env --log-level <error|warn|info|debug|trace|off>
```

It also reads `LOG_LEVEL` when `--log-level` is not provided.

The binary does not manage shell profiles and does not emit activation exports. That behavior lives in the install scripts.

## Task Runner

Tasks are defined in `mise.toml`:

- `mise run commit`
- `mise run tag`

Those tasks call `scripts/deploy.py`:

- `mise run commit` -> `uv run --with-requirements requirements.txt -- scripts/deploy.py commit`
- `mise run tag` -> `uv run --with-requirements requirements.txt -- python scripts/deploy.py tag`

## Testing

### Unix

```bash
for f in tests/unix/test_*.sh; do bash "$f"; done
```

### Windows

```powershell
Get-ChildItem tests/windows/test_*.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName }
```

## License

See `LICENSE`.
