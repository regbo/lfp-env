Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "installs argument tools" -Body {
    Write-Host "[runner] running pixi-init.ps1 with jq"
    & .\pixi-init.ps1 -NoPersistUserEnv jq
    Write-Host "[runner] validating jq exists"
    Assert-Command -Name "jq"
}
