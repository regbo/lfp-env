# lfp-env

Lightweight setup scripts for bootstrapping `mise` and running the Rust-based environment tool.

## Quick start

### macOS/Linux

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-env/v0.1.2/setup.sh | sh)"
```

### Windows (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -c "irm -useb https://raw.githubusercontent.com/regbo/lfp-env/v0.1.2/setup.ps1 | iex"
```

## Local development mode

Set `ENV_SETUP_LOCAL` to install and run the local crate from the current repo checkout instead of GitHub.

```sh
ENV_SETUP_LOCAL=1 sh ./setup.sh
```

```powershell
$env:ENV_SETUP_LOCAL = "1"
.\setup.ps1
```

## Task runner

Tasks are defined in `mise.toml`:

- `mise run commit`
- `mise run tag`

These tasks call `workflow/deploy.py`:

- `mise run commit` -> `python workflow/deploy.py commit`
- `mise run tag` -> `python workflow/deploy.py tag`

## Testing

Unix:

```bash
for f in tests/unix/test_*.sh; do bash "$f"; done
```

Windows:

```powershell
Get-ChildItem tests/windows/test_*.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName }
```

## License

See `LICENSE`.
