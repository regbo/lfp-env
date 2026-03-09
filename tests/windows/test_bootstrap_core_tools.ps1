Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "bootstrap and core tools" -Body {
    Write-Host "[runner] running install.ps1"
    & .\install.ps1

    Write-Host "[runner] validating installed binaries"
    Assert-Command -Name "mise"
    Assert-Command -Name "git"
    Assert-Command -Name "uv"
    Assert-Command -Name "python"
}
