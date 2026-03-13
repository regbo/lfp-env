# lfp-env

`lfp-env` bootstraps a Pixi-based local environment with shell scripts. It installs or reuses Pixi with the official Pixi installer, ensures the default CLI tools are ready, and emits non-interactive PATH activation for the current shell.

By default it ensures:

- `pixi`
- `python` with minimum version `3.10`
- `uv` with minimum version `0.9.9`
- `git`

## Quick Start

### macOS/Linux

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-env/v1.0.6/install.sh | sh)"
```

If `curl` is not available, `wget` works too:

```sh
eval "$(wget -qO- https://raw.githubusercontent.com/regbo/lfp-env/v1.0.6/install.sh | sh)"
```

### Windows (PowerShell)

```powershell
& ([scriptblock]::Create((irm -useb https://raw.githubusercontent.com/regbo/lfp-env/v1.0.6/install.ps1))) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Invoke-Expression $_ }
```

The bootstrap scripts write status messages to stderr and print non-interactive PATH activation to stdout. They also refresh tagged non-interactive activation lines in profile files so later shells can pick up the same Pixi bin directory setup.

## Verify Your Install

Run these after installation:

```sh
pixi --version
python --version
uv --version
git --version
```

If the install succeeded, all four commands should work in the current shell.

## Install A Specific Version

The `main` branch README always points at `latest`.

When you view this README from a release tag, the install URLs in that tagged README are rewritten to that exact tag so the commands stay pinned to the version you are viewing.

## Install Extra Tools

Pass package selectors after the installer command to install them globally with Pixi:

```text
pixi global install ...
```

For example, on macOS/Linux:

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-env/v1.0.6/install.sh | sh -s yq jq)"
```

This installs `yq` and `jq`.

On Windows (PowerShell):

```powershell
& ([scriptblock]::Create((irm -useb https://raw.githubusercontent.com/regbo/lfp-env/v1.0.6/install.ps1))) yq | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Invoke-Expression $_ }
```

This installs `yq`.

## What It Does

During installation, `lfp-env`:

- installs or reuses Pixi with the official Pixi install script
- makes the Pixi bin directory available to the current non-interactive shell
- refreshes tagged non-interactive activation lines in profile files
- installs missing or outdated default tools with `pixi global install`, including `python`
- installs any extra trailing package selectors with `pixi global install`

## Local Development

Use Pixi tasks for the repo workflow:

```sh
pixi run test
pixi run dev
pixi run commit
pixi run tag
```

To test the current checkout through the bootstrap wrapper on macOS/Linux:

```sh
eval "$(sh ./install.sh)"
```

To test the current checkout through the bootstrap wrapper on Windows:

```powershell
.\install.ps1 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Invoke-Expression $_ }
```

## Configuration

Bootstrap variables:

- `LFP_ENV_PYTHON_MIN_VERSION`
  Default: `3.10`
  Controls the minimum Python version enforced by the bootstrap scripts.
- `LFP_ENV_UV_MIN_VERSION`
  Default: `0.9.9`
  Requires the discovered `uv` version to be at least this version.
- `LFP_ENV_GIT_MIN_VERSION`
  Default: unset
  Requires the discovered `git` version to be at least this version.
- `PIXI_HOME`
  Default: `~/.pixi`
  Controls where the official Pixi installer places its files.
- `PIXI_BIN_DIR`
  Default: `${PIXI_HOME}/bin`
  Controls where the official Pixi installer exposes the `pixi` executable.

Any trailing arguments passed to the bootstrap scripts are installed with `pixi global install ...` after the default tool checks succeed.

## Shell Behavior

On Unix, the emitted activation commands:

- ensure the Pixi bin directory is on `PATH`
- refresh the shell command hash
- are also written to `~/.profile` and any existing `.bash_profile`, `.bash_login`, or `.zprofile`

On Windows, the emitted activation commands:

- ensure the Pixi bin directory is on `PATH` for the current PowerShell session
- are also written to the current-user all-hosts PowerShell profile and any existing current-host profile

The official Pixi installer still handles interactive shell profile updates. `lfp-env` manages non-interactive profile blocks for its own PATH activation and refreshes them on reruns.

## License

See `LICENSE`.
