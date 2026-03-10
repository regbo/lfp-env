Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Shared helpers for Windows setup tests.

function Write-Log {
    param([Parameter(Mandatory = $true)][string]$Message)
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "[$timestamp] $Message"
}

function Assert-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Expected command '$Name' to be available on PATH."
    }
}

function Assert-NotBlank {
    param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Expected environment variable '$Name' to be non-empty."
    }
}

function Reset-SessionPath {
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$machinePath;$userPath"
}

function Invoke-Test {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )
    # $env:RUST_BACKTRACE = "1"
    # $env:MISE_VERBOSE = "1"
    $env:LFP_ENV_CARGO_INSTALL = "1"
    Reset-SessionPath
    Write-Log "START: $Name"
    Push-Location (Join-Path $PSScriptRoot "..\..")
    try {
        & $Body
        Write-Log "PASS: $Name"
    } finally {
        Pop-Location
    }
}
