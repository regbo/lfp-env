Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "runs setup script" -Body {
    Write-Host "[runner] running setup.ps1"
    & .\setup.ps1
    Write-Host "[runner] validating mise exists"
    Assert-Command -Name "mise"
}
