$ErrorActionPreference = "Stop"

# Install mise using the first available Windows package manager when needed.
if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install jdx.mise
    } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop install mise
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install mise
    } else {
        throw "No supported package manager found. Install winget, scoop, or chocolatey."
    }
}

$envSetupToolSpec = "github:regbo/lfp-env"
if (-not [string]::IsNullOrWhiteSpace($env:ENV_SETUP_LOCAL)) {
    & mise exec rust -- cargo install --path . --bin lfp-env --root "$HOME/.local" --force
    $binaryPath = Join-Path $HOME ".local\bin\lfp-env.exe"
    & $binaryPath
} else {
    & mise use -g $envSetupToolSpec
    & mise x $envSetupToolSpec -- lfp-env
}