$ErrorActionPreference = "Stop"
$envSetupToolSpec = if ([string]::IsNullOrWhiteSpace($env:ENV_SETUP_TOOL_SPEC)) { "github:regbo/lfp-env" } else { $env:ENV_SETUP_TOOL_SPEC }
$localSetupValue = if ([string]::IsNullOrWhiteSpace($env:ENV_SETUP_LOCAL)) { "false" } else { $env:ENV_SETUP_LOCAL }

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

function Is-TrueFlag {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }
    $normalized = $Value.Trim().ToLowerInvariant()
    return $normalized -eq "1" -or $normalized -eq "true"
}

function Activate-MiseSession {
    param(
        [Parameter(Mandatory = $true)][string]$MiseExecutable,
        [Parameter(Mandatory = $true)][string]$ShellName
    )
    $activationScript = & $MiseExecutable activate $ShellName | Out-String
    if (-not [string]::IsNullOrWhiteSpace($activationScript)) {
        $strictModeVersion = $null
        if (Get-Variable -Name PSStrictModeVersion -ErrorAction SilentlyContinue) {
            $strictModeVersion = $PSStrictModeVersion
        }
        Set-StrictMode -Off
        try {
            Invoke-Expression -Command $activationScript
        } finally {
            if ($null -ne $strictModeVersion) {
                Set-StrictMode -Version $strictModeVersion
            }
        }
    }
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
Activate-MiseSession -MiseExecutable $miseExecutable -ShellName "pwsh"
$isLocalSetup = Is-TrueFlag -Value $localSetupValue

if ($isLocalSetup) {
    & $miseExecutable exec rust -- cargo install --path . --bin lfp-env --root "$HOME/.local" --force
    $binaryPath = Join-Path $HOME ".local\bin\lfp-env.exe"
    & $binaryPath
} else {
    & $miseExecutable use -g $envSetupToolSpec
    & $miseExecutable x $envSetupToolSpec -- lfp-env
}

# lfp-env may install additional tools (for example uv/python) during execution.
# Refresh shims and re-activate so the current session can resolve new commands.
& $miseExecutable reshim
Activate-MiseSession -MiseExecutable $miseExecutable -ShellName "pwsh"