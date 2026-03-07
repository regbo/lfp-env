# lfp-pixi

Lightweight bootstrap scripts to get `pixi` installed quickly and ensure a few core tools are available.

## TLDR

*NIX install:

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main/pixi-init.sh | sh)"
```

Windows install:

```powershell
powershell -ExecutionPolicy Bypass -c "irm -useb https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main/pixi-init.ps1 | iex"
```

## What the scripts do

Both init scripts:

- Resolve writable environment directories (`TEMP`, `HOME`, `LOCAL_BIN`, `PIXI_HOME`)
- Add required tool directories to `PATH`
- Install `pixi` if missing
- Ensure `python` and `git` are available via `pixi global install`
- Optionally install any additional tools you pass as arguments
- Are safe to run repeatedly

## Use cases

- Adding Pixi to a machine that may or may not already have it
- Installing a package manager quickly in ephemeral environments (for example Databricks Apps setup steps)
- Bootstrapping developer tooling (`python`, `git`, plus optional tools like `jq`) on fresh machines
- Creating repeatable, low-friction setup commands for onboarding docs and CI bootstrap steps
- Standardizing environment directory and `PATH` setup across Linux/macOS shells and PowerShell

This repo includes:

- `pixi-init.sh` for POSIX shells (macOS/Linux, and shell environments in containers)
- `pixi-init.ps1` for PowerShell
- `pixi-init-test.sh` for containerized validation of the shell script

## Quick start

### POSIX shell (`pixi-init.sh`)

Run from GitHub and apply exported environment changes in your current shell:

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main/pixi-init.sh | sh)"
```

Install extra tools at the same time:

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main/pixi-init.sh | sh -s -- jq yq)"
```

Notes:

- The script emits `export ...` statements only when it had to resolve missing env vars or update `PATH`.
- `curl` or `wget` must be available to fetch the Pixi installer.

### PowerShell (`pixi-init.ps1`)

Run from GitHub using `irm` and `iex`:

```powershell
powershell -ExecutionPolicy Bypass -c "irm -useb https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main/pixi-init.ps1 | iex"
```

Install extra tools:

```powershell
powershell -ExecutionPolicy Bypass -c "& ([scriptblock]::Create((irm -useb https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main/pixi-init.ps1))) jq yq"
```

By default, when environment values are newly resolved, the script persists them to the current user environment.  
To keep changes only in the current PowerShell session:

```powershell
powershell -ExecutionPolicy Bypass -c "& ([scriptblock]::Create((irm -useb https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main/pixi-init.ps1))) -NoPersistUserEnv"
```

## Testing

`pixi-init-test.sh` runs integration checks in a Debian container and verifies:

- Bootstrap installs `pixi`, `git`, and `python`
- Extra tool installation via arguments works
- Re-running initialization is idempotent

Run tests with Docker or Podman:

```bash
./pixi-init-test.sh
```

Optional environment variables:

- `CONTAINER_RUNTIME` to force `docker` or `podman`
- `PIXI_INIT_TEST_IMAGE` to override the base image (default: `debian:stable-slim`)

## License

See `LICENSE`.
