Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "installs argument tools" -Body {
    Write-Host "[runner] running pixi-setup.ps1 with hello"
    & .\pixi-setup.ps1 -NoPersistUserEnv hello
    Write-Host "[runner] validating hello exists"
    Assert-Command -Name "hello"
}
