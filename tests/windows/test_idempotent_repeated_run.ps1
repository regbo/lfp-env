Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "idempotent repeated run" -Body {
    Write-Host "[runner] running install.ps1 twice"
    Run-InstallAndEval
    Run-InstallAndEval
    Write-Host "[runner] validating mise still exists"
    mise -v | Out-Null
}
