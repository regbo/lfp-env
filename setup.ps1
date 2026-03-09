$ErrorActionPreference = "Stop"

function Resolve-MiseCommand {
    $miseCommand = Get-Command mise -ErrorAction SilentlyContinue
    if ($miseCommand) {
        return $miseCommand.Source
    }
    # Refresh PATH from user and machine scopes for current session after installer runs.
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $combinedPath = @($userPath, $machinePath, $env:Path) -join ";"
    $env:Path = $combinedPath
    $miseCommand = Get-Command mise -ErrorAction SilentlyContinue
    if ($miseCommand) {
        return $miseCommand.Source
    }
    throw "mise is not available on PATH after installation."
}

# Install mise using the first available Windows package manager when needed.
if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id jdx.mise --exact --source winget --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
    } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop install mise
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install mise -y --no-progress
    } else {
        throw "No supported package manager found. Install winget, scoop, or chocolatey."
    }
}

$miseExecutable = Resolve-MiseCommand
$envSetupToolSpec = "github:regbo/lfp-env"
if (-not [string]::IsNullOrWhiteSpace($env:ENV_SETUP_LOCAL)) {
    & $miseExecutable exec rust -- cargo install --path . --bin lfp-env --root "$HOME/.local" --force
    $binaryPath = Join-Path $HOME ".local\bin\lfp-env.exe"
    & $binaryPath
} else {
    & $miseExecutable use -g $envSetupToolSpec
    & $miseExecutable x $envSetupToolSpec -- lfp-env
}