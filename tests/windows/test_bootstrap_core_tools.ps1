Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_test_lib.ps1"

Invoke-Test -Name "bootstrap and core tools" -Body {
    Write-Host "[runner] running pixi-setup.ps1"
    & .\pixi-setup.ps1 -NoPersistUserEnv

    Write-Host "[runner] validating resolved environment and binaries"
    Assert-NotBlank -Value $env:TEMP -Name "TEMP"
    Assert-NotBlank -Value $env:HOME -Name "HOME"
    Assert-NotBlank -Value $env:LOCAL_BIN -Name "LOCAL_BIN"
    Assert-NotBlank -Value $env:PIXI_HOME -Name "PIXI_HOME"
    Assert-Command -Name "pixi"
    Assert-Command -Name "git"
    Assert-Command -Name "python"
}
