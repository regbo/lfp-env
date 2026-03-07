# lfp-pixi

Lightweight bootstrap scripts to get `pixi` installed quickly and ensure a few core tools are available.

## TLDR

MacOS/Linux install:

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-pixi/v0.0.10/pixi-setup.sh | sh)"
```

Windows install:

```powershell
powershell -ExecutionPolicy Bypass -c "irm -useb https://raw.githubusercontent.com/regbo/lfp-pixi/v0.0.10/pixi-setup.ps1 | iex"
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

- `pixi-setup.sh` for POSIX shells (macOS/Linux, and shell environments in containers)
- `pixi-setup.ps1` for PowerShell
- `tests/unix` and `tests/windows` for script validation

## Quick start

### POSIX shell (`pixi-setup.sh`)

Run from GitHub and apply exported environment changes in your current shell:

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-pixi/v0.0.10/pixi-setup.sh | sh)"
```

Install extra tools at the same time:

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-pixi/v0.0.10/pixi-setup.sh | sh -s -- jq yq)"
```

Notes:

- The script emits `export ...` statements only when it had to resolve missing env vars or update `PATH`.
- `curl` or `wget` must be available to fetch the Pixi installer.

### PowerShell (`pixi-setup.ps1`)

Run from GitHub using `irm` and `iex`:

```powershell
powershell -ExecutionPolicy Bypass -c "irm -useb https://raw.githubusercontent.com/regbo/lfp-pixi/v0.0.10/pixi-setup.ps1 | iex"
```

Install extra tools:

```powershell
powershell -ExecutionPolicy Bypass -c "& ([scriptblock]::Create((irm -useb 'https://raw.githubusercontent.com/regbo/lfp-pixi/v0.0.10/pixi-setup.ps1'))) jq yq"
```

By default, when environment values are newly resolved, the script persists them to the current user environment.  
To keep changes only in the current PowerShell session:

```powershell
powershell -ExecutionPolicy Bypass -c "& ([scriptblock]::Create((irm -useb 'https://raw.githubusercontent.com/regbo/lfp-pixi/v0.0.10/pixi-setup.ps1'))) -NoPersistUserEnv"
```

## Testing

Tag-triggered GitHub Actions test jobs run validation from `tests/unix` and `tests/windows`, and verify:

- Bootstrap installs `pixi`, `git`, and `python`
- Extra tool installation via arguments works
- Re-running initialization is idempotent

Run Unix tests locally:

```bash
for f in tests/unix/test_*.sh; do bash "$f"; done
```

Windows tests can be run with:

```powershell
Get-ChildItem tests/windows/test_*.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName }
```

## License

See `LICENSE`.