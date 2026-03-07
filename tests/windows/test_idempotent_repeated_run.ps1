Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "idempotent repeated run" -Body {
    Write-Host "[runner] running pixi-init.ps1 twice"
    & .\pixi-init.ps1 -NoPersistUserEnv
    & .\pixi-init.ps1 -NoPersistUserEnv
    Write-Host "[runner] validating pixi still exists"
    Assert-Command -Name "pixi"
}
