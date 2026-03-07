Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "idempotent repeated run" -Body {
    Write-Host "[runner] running pixi-setup.ps1 twice"
    & .\pixi-setup.ps1 -NoPersistUserEnv
    & .\pixi-setup.ps1 -NoPersistUserEnv
    Write-Host "[runner] validating pixi still exists"
    Assert-Command -Name "pixi"
}
