$ErrorActionPreference = "Stop"
$envToolSpec = if ([string]::IsNullOrWhiteSpace($env:ENV_TOOL_SPEC)) { "github:regbo/lfp-env" } else { $env:ENV_TOOL_SPEC }
$localSetupValue = if ([string]::IsNullOrWhiteSpace($env:ENV_LOCAL_INSTALL)) { "false" } else { $env:ENV_LOCAL_INSTALL }

function Is-TrueFlag {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }
    $normalized = $Value.Trim().ToLowerInvariant()
    return $normalized -eq "1" -or $normalized -eq "true"
}

function Resolve-MiseCommand {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $combinedPath = @($userPath, $machinePath, $env:Path) -join ";"
    $env:Path = $combinedPath
    $miseCommand = Get-Command mise -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq "Application" } | Select-Object -First 1
    if ($miseCommand -and -not [string]::IsNullOrWhiteSpace($miseCommand.Source)) {
        return $miseCommand.Source
    }
    throw "mise is not available on PATH after installation."
}

function Update-SessionExports {
    param([object[]]$Lines)
    foreach ($lineObject in $Lines) {
        if ($null -eq $lineObject) {
            continue
        }
        $line = [string]$lineObject
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line.TrimStart().StartsWith('$env:')) {
            Invoke-Expression $line
        }
        Write-Output $line
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
$isLocalSetup = Is-TrueFlag -Value $localSetupValue

if ($isLocalSetup) {
    & $miseExecutable exec rust -- cargo install --path . --bin lfp-env --root "$HOME/.local" --force
    $binaryPath = Join-Path $HOME ".local\bin\lfp-env.exe"
    $lfpOutput = & $binaryPath --mise_bin $miseExecutable @args
    Update-SessionExports -Lines $lfpOutput
} else {
    & $miseExecutable use -g $envToolSpec
    $lfpOutput = & $miseExecutable x $envToolSpec -- lfp-env --mise_bin $miseExecutable @args
    Update-SessionExports -Lines $lfpOutput
}
