Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "installs argument tools" -Body {
    Write-Host "[runner] running pixi-setup.ps1 with ripgrep"
    & .\pixi-setup.ps1 -NoPersistUserEnv ripgrep
    Write-Host "[runner] validating rg exists"
    Assert-Command -Name "rg"
}
