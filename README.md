# lfp-env

`lfp-env` bootstraps a working local environment by installing or reusing `mise`, activating it in your current shell, and ensuring the default tools needed by this project are available.

By default it makes sure these tools are ready to use:

- `mise`
- `python` with minimum version `3.10`
- `uv` with minimum version `0.9.9`
- `git`

## Quick Start

### macOS/Linux

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-env/latest/install.sh | sh)"
```

If `curl` is not available, `wget` works too:

```sh
eval "$(wget -qO- https://raw.githubusercontent.com/regbo/lfp-env/latest/install.sh | sh)"
```

### Windows (PowerShell)

```powershell
& ([scriptblock]::Create((irm -useb https://raw.githubusercontent.com/regbo/lfp-env/latest/install.ps1))) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Invoke-Expression $_ }
```

The installers write logs to stderr and emit activation commands on stdout. The examples above evaluate that stdout in your current shell so the environment is ready immediately.

## Verify Your Install

Run these after installation:

```sh
mise --version
python --version
uv --version
git --version
```

If the install succeeded, all four commands should work in the current shell.

## Install A Specific Version

On macOS/Linux:

```sh
LFP_ENV_VERSION=0.2.6 eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-env/latest/install.sh | sh)"
```

With `wget`:

```sh
LFP_ENV_VERSION=0.2.6 eval "$(wget -qO- https://raw.githubusercontent.com/regbo/lfp-env/latest/install.sh | sh)"
```

On Windows (PowerShell):

```powershell
$env:LFP_ENV_VERSION = "0.2.6"
& ([scriptblock]::Create((irm -useb https://raw.githubusercontent.com/regbo/lfp-env/latest/install.ps1))) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Invoke-Expression $_ }
```

## Install Extra Tools

Pass package selectors after the installer command to install them globally with `mise`.

```text
mise use -g ...
```

For example, on macOS/Linux:

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-env/latest/install.sh | sh -s yq@latest jq)"
```

This installs `yq@latest` and `jq`.

```sh
mise use -g yq@latest jq
```

On Windows (PowerShell):

```powershell
& ([scriptblock]::Create((irm -useb https://raw.githubusercontent.com/regbo/lfp-env/latest/install.ps1))) nano@latest jq | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Invoke-Expression $_ }
```

## What It Does

During installation, `lfp-env`:

- downloads or reuses the `lfp-env` binary
- resolves a usable `HOME`
- installs or discovers `mise`
- activates `mise` for the current shell
- optionally updates shell profile files
- installs missing default tools through `mise`

## Local Development

To test the current checkout on macOS/Linux:

```sh
mise exec rust -- cargo build --bin lfp-env
LFP_ENV_INSTALL_PATH="$PWD/target/debug/lfp-env" eval "$(sh ./install.sh)"
```

To test the current checkout on Windows:

```powershell
$env:LFP_ENV_INSTALL_PATH = "$PWD\target\debug\lfp-env.exe"
mise exec rust -- cargo build --bin lfp-env
.\install.ps1 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Invoke-Expression $_ }
```

## CLI

| CLI flag | Environment variable | Default |
| --- | --- | --- |
| `--version` | n/a | prints the current `lfp-env` version |
| `--log-level <level>` | `LFP_ENV_LOG_LEVEL` | `info` |
| `--mise-min-version <version>` | `LFP_ENV_MISE_MIN_VERSION` | unset |
| `--python-min-version <version>` | `LFP_ENV_PYTHON_MIN_VERSION` | `3.10` |
| `--uv-min-version <version>` | `LFP_ENV_UV_MIN_VERSION` | `0.9.9` |
| `--git-min-version <version>` | `LFP_ENV_GIT_MIN_VERSION` | unset |

`lfp-env --version` prints only the raw semver, for example `0.2.6`.

Set `LFP_ENV_LOG_LEVEL=0` to disable routine stderr logging.

Trailing package selectors are installed with `mise use -g ...` after the default toolchain setup completes.

## Configuration

Bootstrap wrapper variables:

- `LFP_ENV_REPO`
  Default: `regbo/lfp-env`
  Selects which GitHub repository to download release assets from.
- `LFP_ENV_VERSION`
  Default: unset
  Downloads `v<version>` instead of `latest` and requires the bootstrap binary to match that exact version.
- `LFP_ENV_MIN_VERSION`
  Default: unset
  Requires the existing bootstrap binary version to be at least this version.
- `LFP_ENV_INSTALL_PATH`
  Default on Unix: `${HOME}/.local/bin/lfp-env`
  Default on Windows: `%LOCALAPPDATA%\bin\lfp-env.exe`
  Overrides where the bootstrap wrapper stores and executes the `lfp-env` binary.

Installer variables:

- `LFP_ENV_ACTIVATE_PROFILE`
  Default: `1`
  Writes activation lines to shell profile files when possible.

## Shell Behavior

On Unix, the emitted activation commands:

- ensure the `mise` install directory is on `PATH`
- run `eval "$(mise activate --shims bash)"`
- export `HOME` if the installer had to fall back away from the incoming environment
- export `TMPDIR` as `${HOME}/.tmp` when no writable temp directory is already available

On Windows, the emitted activation commands:

- ensure the installed `mise` bin directory is on `PATH`
- run `mise activate --shims pwsh` in the current PowerShell session

## Profile Updates

When `LFP_ENV_ACTIVATE_PROFILE=1` and `HOME` did not need to be rewritten, Unix updates these files when applicable:

- `~/.profile`
- `~/.bash_profile`
- `~/.zshenv`
- `~/.zprofile`
- `~/.bashrc`
- `~/.zshrc`

On Windows, when `mise` is newly installed, the installer updates:

- `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`

## Maintenance

Useful project tasks:

- `mise commit`
- `mise tag`
- `mise build`
- `mise dev`

Run the test suite with:

```sh
mise exec rust -- cargo build --bin lfp-env
mise exec rust -- cargo test
```

## License

See `LICENSE`.
