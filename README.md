# lfp-env

Lightweight install scripts for bootstrapping `mise` and running the Rust-based environment tool.

## Quick start

### macOS/Linux

```sh
eval "$(curl -fsSL https://raw.githubusercontent.com/regbo/lfp-env/v0.1.11/install.sh | sh)"
```

### Windows (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -c "irm -useb https://raw.githubusercontent.com/regbo/lfp-env/v0.1.11/install.ps1 | iex"
```

## Local development mode

Set `ENV_LOCAL_INSTALL` to install and run the local crate from the current repo checkout instead of GitHub.

```sh
ENV_LOCAL_INSTALL=1 sh ./install.sh
```

```powershell
$env:ENV_LOCAL_INSTALL = "1"
.\install.ps1
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
