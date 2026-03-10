Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "runs install script" -Body {
    Write-Host "[runner] running install.ps1"
    Run-InstallAndEval
    Write-Host "[runner] validating mise exists"
    mise -v | Out-Null
}
