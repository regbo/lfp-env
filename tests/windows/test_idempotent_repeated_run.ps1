Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "idempotent repeated run" -Body {
    Write-Host "[runner] running setup.ps1 twice"
    & .\setup.ps1
    & .\setup.ps1
    Write-Host "[runner] validating mise still exists"
    Assert-Command -Name "mise"
}
