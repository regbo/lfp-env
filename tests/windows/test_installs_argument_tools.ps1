Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "installs argument tools" -Body {
    Write-Host "[runner] running pixi-setup.ps1 with fzf"
    & .\pixi-setup.ps1 -NoPersistUserEnv fzf
    Write-Host "[runner] validating fzf exists"
    Assert-Command -Name "fzf"
}
