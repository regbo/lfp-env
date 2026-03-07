param(
    [switch]$NoPersistUserEnv,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Tools
)

$ErrorActionPreference = "Stop"

# Accumulates environment assignment lines for callers that want to inspect output.
$script:Exports = [ordered]@{}
$script:PathModified = $false

function Append-Export {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $script:Exports[$Name] = $Value
}

function Log {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Command)
    if (-not $Command -or $Command.Count -eq 0) {
        return
    }
    $commandArgs = @()
    if ($Command.Count -gt 1) {
        $commandArgs = $Command[1..($Command.Count - 1)]
    }
    & $Command[0] @commandArgs 2>&1 | ForEach-Object {
        [Console]::Error.WriteLine($_)
    }
}

function Convert-ToText {
    param([Parameter(ValueFromPipeline = $true)]$Value)
    if ($null -eq $Value) {
        return ""
    }
    if ($Value -is [byte[]]) {
        return [System.Text.Encoding]::UTF8.GetString($Value)
    }
    if ($Value -is [string]) {
        return $Value
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        return (($Value | ForEach-Object { "$_" }) -join [Environment]::NewLine)
    }
    return [string]$Value
}

function Is-Blank {
    param([string]$Value)
    return [string]::IsNullOrWhiteSpace($Value)
}

function Is-Exec {
    param([string]$Name)
    if (Is-Blank $Name) {
        return $false
    }
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Http-Get {
    param([string]$Url)
    if (Is-Blank $Url) {
        throw "http_get requires a URL."
    }

    if (Is-Exec "Invoke-WebRequest") {
        return (Convert-ToText ((Invoke-WebRequest -UseBasicParsing -Uri $Url).Content))
    }

    if (Is-Exec "curl.exe") {
        return (Convert-ToText (& curl.exe -fsSL $Url))
    }

    if (Is-Exec "wget.exe") {
        return (Convert-ToText (& wget.exe -qO- $Url))
    }

    throw "Neither Invoke-WebRequest, curl.exe, nor wget.exe is available."
}

function Is-WritableDir {
    param([string]$Location)
    if (Is-Blank $Location) {
        return $false
    }

    try {
        New-Item -ItemType Directory -Path $Location -Force | Out-Null
        if (-not (Test-Path -Path $Location -PathType Container)) {
            return $false
        }

        $probe = Join-Path $Location (".write-probe-{0}.tmp" -f ([guid]::NewGuid().ToString("N")))
        New-Item -ItemType File -Path $probe -Force | Out-Null
        Remove-Item -Path $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function Set-EnvVar {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )
    Set-Item -Path ("Env:{0}" -f $Name) -Value $Value
}

function Ensure-EnvDir {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)][string[]]$Candidates = @()
    )

    $softFail = $false
    if ($Candidates.Count -gt 0 -and $Candidates[0] -eq "-") {
        $softFail = $true
        if ($Candidates.Count -eq 1) {
            $Candidates = @()
        } else {
            $Candidates = $Candidates[1..($Candidates.Count - 1)]
        }
    }

    $current = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (Is-WritableDir $current) {
        Set-EnvVar -Name $Name -Value $current
        return
    }

    foreach ($location in $Candidates) {
        if (Is-WritableDir $location) {
            Set-EnvVar -Name $Name -Value $location
            Append-Export -Name $Name -Value $location
            return
        }
    }

    if ($softFail) {
        return
    }

    throw "Could not resolve a writable $Name directory."
}

function Ensure-PathDir {
    param([string]$Dir)
    if (Is-Blank $Dir) {
        return
    }

    $pathParts = ($env:PATH -split ';') | Where-Object { $_ -ne '' }
    if ($pathParts -contains $Dir) {
        return
    }
    $env:PATH = "$Dir;$env:PATH"
    $script:PathModified = $true
}

function Ensure-Installed {
    param([string]$Tool)
    if (Is-Blank $Tool) {
        return
    }

    if (-not (Is-Exec $Tool)) {
        Log pixi global install $Tool
        if (-not (Is-Exec $Tool)) {
            throw "$Tool not found after installation."
        }
    }
}

function Persist-UserEnvVar {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
}

# Resolve TEMP and align TMP/TMPDIR.
Ensure-EnvDir -Name "TEMP" -Candidates @($env:TEMP, $env:TMPDIR, $env:TMP, "/tmp", ".\.tmp")
$env:TMPDIR = $env:TEMP
$env:TMP = $env:TEMP

# Resolve HOME
Ensure-EnvDir -Name "HOME" -Candidates @("/home", ".\home", "$($env:TEMP)\home")

# Resolve LOCAL_BIN and ensure it is on PATH.
Ensure-EnvDir -Name "LOCAL_BIN" -Candidates @("$($env:HOME)\.local\bin")
Ensure-PathDir -Dir $env:LOCAL_BIN

# Resolve PIXI_HOME and ensure it is on PATH.
Ensure-EnvDir -Name "PIXI_HOME" -Candidates @("$($env:HOME)\.pixi")
Ensure-PathDir -Dir "$($env:PIXI_HOME)\bin"
if (-not (Is-Exec "pixi")) {
    New-Item -ItemType Directory -Path "$($env:PIXI_HOME)\bin" -Force | Out-Null
    $pixiInstaller = Convert-ToText (Http-Get "https://pixi.sh/install.ps1")
    Invoke-Expression -Command $pixiInstaller
    if (-not (Is-Exec "pixi")) {
        throw "pixi installation failed."
    }
}

Ensure-Installed -Tool "python"
Ensure-Installed -Tool "uv"
Ensure-Installed -Tool "git"

if (@($Tools).Count -gt 0) {
    foreach ($tool in @($Tools)) {
        Ensure-Installed -Tool $tool
    }
}

if ($script:Exports.Count -gt 0 -or $script:PathModified) {
    if ($script:PathModified) {
        Append-Export -Name "PATH" -Value $env:PATH
    }
    if (-not $NoPersistUserEnv) {
        foreach ($entry in $script:Exports.GetEnumerator()) {
            $name = $entry.Key
            $value = [Environment]::GetEnvironmentVariable($name, "Process")
            if ($null -ne $value) {
                Persist-UserEnvVar -Name $name -Value $value
            }
        }
    } else {
        # Keep changes in current PowerShell session only.
        foreach ($entry in $script:Exports.GetEnumerator()) {
            Set-EnvVar -Name $entry.Key -Value "$($entry.Value)"
        }
    }
}
