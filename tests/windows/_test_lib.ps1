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

function Invoke-Test {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    Write-Log "START: $Name"
    Push-Location (Join-Path $PSScriptRoot "..\..")
    try {
        & $Body
        Write-Log "PASS: $Name"
    } finally {
        Pop-Location
    }
}
