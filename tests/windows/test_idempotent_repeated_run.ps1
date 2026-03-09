Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "idempotent repeated run" -Body {
    Write-Host "[runner] running install.ps1 twice"
    & .\install.ps1
    & .\install.ps1
    Write-Host "[runner] validating mise still exists"
    mise -v | Out-Null
}
