$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Validate Windows installer profile persistence without network access.

function Fail {
    param([string]$Message)
    throw "ERROR: $Message"
}

function Assert-Contains {
    param(
        [string]$Path,
        [string]$ExpectedText
    )

    $content = Get-Content -Raw $Path
    if ($null -eq $content) { $content = "" }
    if (-not $content.Contains($ExpectedText)) {
        Fail "Expected '$ExpectedText' in $Path"
    }
}

function Assert-NotContains {
    param(
        [string]$Path,
        [string]$UnexpectedText
    )

    $content = Get-Content -Raw $Path
    if ($null -eq $content) { $content = "" }
    if ($content.Contains($UnexpectedText)) {
        Fail "Did not expect '$UnexpectedText' in $Path"
    }
}

function Assert-Count {
    param(
        [string]$Path,
        [string]$ExpectedText,
        [int]$ExpectedCount
    )

    $count = ([regex]::Matches((Get-Content -Raw $Path), [regex]::Escape($ExpectedText))).Count
    if ($count -ne $ExpectedCount) {
        Fail "Expected '$ExpectedText' to appear $ExpectedCount times in $Path, got $count"
    }
}

function New-FakeVersionTool {
    param(
        [string]$Name,
        [string]$VersionOutput
    )

    $cmdToolPath = Join-Path $script:FakeBin "$Name.cmd"
    @"
@echo off
if "%1"=="--version" (
  echo $VersionOutput
  exit /b 0
)
exit /b 0
"@ | Set-Content -Path $cmdToolPath -Encoding ascii

    $shellToolPath = Join-Path $script:FakeBin $Name
    @"
#!/bin/sh
if [ "\${1:-}" = "--version" ]; then
  printf '%s\n' '$VersionOutput'
  exit 0
fi
exit 0
"@ | Set-Content -Path $shellToolPath -Encoding ascii
    if (-not $IsWindows) {
        chmod +x $shellToolPath
    }
}

function New-FakePixiTool {
    $cmdToolPath = Join-Path $script:FakeBin "pixi.cmd"
    @"
@echo off
if "%1"=="--version" (
  echo pixi 0.40.0
  exit /b 0
)
if /I "%1"=="global" if /I "%2"=="install" (
  if not "%FAKE_PIXI_LOG%"=="" (
    shift
    shift
    echo %*>> "%FAKE_PIXI_LOG%"
  )
  exit /b 0
)
exit /b 0
"@ | Set-Content -Path $cmdToolPath -Encoding ascii

    $shellToolPath = Join-Path $script:FakeBin "pixi"
    @'
#!/bin/sh
if [ "\${1:-}" = "--version" ]; then
  printf '%s\n' 'pixi 0.40.0'
  exit 0
fi
if [ "\${1:-}" = "global" ] && [ "\${2:-}" = "install" ]; then
  if [ -n "${FAKE_PIXI_LOG:-}" ]; then
    shift 2
    printf '%s\n' "$*" >>"$FAKE_PIXI_LOG"
  fi
  exit 0
fi
exit 0
'@ | Set-Content -Path $shellToolPath -Encoding ascii
    if (-not $IsWindows) {
        chmod +x $shellToolPath
    }
}

function Build-ActivationCommand {
    param([string]$HomeDir)

    $pixiBinDir = Join-Path $HomeDir ".pixi\bin"
    return "`$PixiBinDir = '$($pixiBinDir.Replace("'", "''"))'; if (-not ((`$Env:PATH -split ';') -contains `$PixiBinDir)) { `$Env:PATH = `"`$PixiBinDir;`$Env:PATH`" }"
}

function Invoke-Installer {
    param(
        [string]$HomeDir,
        [pscustomobject]$ProfileObject,
        [string]$StdErrPath,
        [string]$StdOutPath,
        [string[]]$AdditionalArgs = @()
    )

    $env:PIXI_HOME = Join-Path $HomeDir ".pixi"
    $env:PATH = "$script:FakeBin$([System.IO.Path]::PathSeparator)$script:OriginalPath"
    $env:FAKE_PIXI_LOG = Join-Path $script:TempDir "pixi-install.log"
    $script:PROFILE = $ProfileObject
    & $script:InstallPath @AdditionalArgs 2> $StdErrPath > $StdOutPath
}

function Assert-ProfileCreatedOnce {
    param(
        [string]$HomeDir,
        [string]$AllHostsPath,
        [string]$CurrentHostPath
    )

    if (-not (Test-Path $AllHostsPath -PathType Leaf)) {
        Fail "Expected $AllHostsPath to be created"
    }
    if (-not (Test-Path $CurrentHostPath -PathType Leaf)) {
        Fail "Expected $CurrentHostPath to exist"
    }
    Assert-Contains $AllHostsPath '$PixiBinDir ='
    Assert-Contains $CurrentHostPath '$PixiBinDir ='
    Assert-Contains $AllHostsPath "# lfp-env"
    Assert-Contains $CurrentHostPath "# lfp-env"
    Assert-Count $AllHostsPath "# lfp-env" 1
    Assert-Count $CurrentHostPath "# lfp-env" 1
}

function Test-ProfileUpdatesAreIdempotent {
    $testRoot = Join-Path $script:TempDir "idempotent"
    $homeDir = Join-Path $testRoot "home"
    New-Item -ItemType Directory -Force -Path $homeDir | Out-Null
    $allHostsPath = Join-Path $testRoot "Microsoft.PowerShell_profile.ps1"
    $currentHostPath = Join-Path $testRoot "CurrentHost_profile.ps1"
    "Set-Variable ExistingProfile 1" | Set-Content -Path $currentHostPath -Encoding utf8
    $profileObject = [pscustomobject]@{
        CurrentUserAllHosts = $allHostsPath
        CurrentUserCurrentHost = $currentHostPath
    }

    Invoke-Installer $homeDir $profileObject (Join-Path $testRoot "first.err") (Join-Path $testRoot "first.out")
    Assert-ProfileCreatedOnce $homeDir $allHostsPath $currentHostPath

    $firstAllHostsSnapshot = Get-Content -Raw $allHostsPath
    $firstCurrentHostSnapshot = Get-Content -Raw $currentHostPath

    Invoke-Installer $homeDir $profileObject (Join-Path $testRoot "second.err") (Join-Path $testRoot "second.out")
    if ($firstAllHostsSnapshot -cne (Get-Content -Raw $allHostsPath)) {
        Fail "CurrentUserAllHosts profile changed on the second run"
    }
    if ($firstCurrentHostSnapshot -cne (Get-Content -Raw $currentHostPath)) {
        Fail "CurrentUserCurrentHost profile changed on the second run"
    }
}

function Test-ExistingActivationLineIsNotRewritten {
    $testRoot = Join-Path $script:TempDir "existing-line"
    $homeDir = Join-Path $testRoot "home"
    New-Item -ItemType Directory -Force -Path $homeDir | Out-Null
    $allHostsPath = Join-Path $testRoot "Microsoft.PowerShell_profile.ps1"
    $currentHostPath = Join-Path $testRoot "CurrentHost_profile.ps1"
    $activationCommand = Build-ActivationCommand $homeDir
    $activationCommand | Set-Content -Path $currentHostPath -Encoding utf8
    $profileObject = [pscustomobject]@{
        CurrentUserAllHosts = $allHostsPath
        CurrentUserCurrentHost = $currentHostPath
    }

    Invoke-Installer $homeDir $profileObject (Join-Path $testRoot "run.err") (Join-Path $testRoot "run.out")

    if ((Get-Content -Raw $currentHostPath).TrimEnd("`r", "`n") -cne $activationCommand) {
        Fail "Expected the existing activation line in $currentHostPath to remain unchanged"
    }
    Assert-Count $currentHostPath "# lfp-env" 0
    Assert-Contains $allHostsPath '$PixiBinDir ='
    Assert-Contains $allHostsPath "# lfp-env"
}

function Test-AdditionalArgsAreGloballyInstalled {
    if (-not $IsWindows) {
        return
    }

    $testRoot = Join-Path $script:TempDir "additional-args"
    $homeDir = Join-Path $testRoot "home"
    New-Item -ItemType Directory -Force -Path $homeDir | Out-Null
    $allHostsPath = Join-Path $testRoot "Microsoft.PowerShell_profile.ps1"
    $currentHostPath = Join-Path $testRoot "CurrentHost_profile.ps1"
    $profileObject = [pscustomobject]@{
        CurrentUserAllHosts = $allHostsPath
        CurrentUserCurrentHost = $currentHostPath
    }

    Set-Content -Path (Join-Path $script:TempDir "pixi-install.log") -Value "" -Encoding utf8
    Invoke-Installer $homeDir $profileObject (Join-Path $testRoot "run.err") (Join-Path $testRoot "run.out") @("jq", "yq")

    $pixiLogPath = Join-Path $script:TempDir "pixi-install.log"
    Assert-Contains $pixiLogPath "jq"
    Assert-Contains $pixiLogPath "yq"
}

$script:RootDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:InstallPath = Join-Path $script:RootDir "install.ps1"
$script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("lfp-env-test-" + [guid]::NewGuid())
$script:FakeBin = Join-Path $script:TempDir "fake-bin"
$script:OriginalPath = $env:PATH

try {
    New-Item -ItemType Directory -Force -Path $script:FakeBin | Out-Null
    New-FakePixiTool
    New-FakeVersionTool python "Python 3.11.9"
    New-FakeVersionTool uv "uv 0.10.9"
    New-FakeVersionTool git "git version 2.50.1"

    Test-ProfileUpdatesAreIdempotent
    Test-ExistingActivationLineIsNotRewritten
    Test-AdditionalArgsAreGloballyInstalled
}
finally {
    if (Test-Path $script:TempDir) {
        Remove-Item -Recurse -Force $script:TempDir
    }
}
