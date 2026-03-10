$toolSpec = if ($env:LFP_ENV_TOOL_SPEC) { $env:LFP_ENV_TOOL_SPEC } else { "github:regbo/lfp-env" }
$cargoInstall = if ($env:LFP_ENV_CARGO_INSTALL) { $env:LFP_ENV_CARGO_INSTALL } else { "0" }
$disableRun = if ($env:LFP_ENV_DISABLE_RUN) { $env:LFP_ENV_DISABLE_RUN } else { "0" }

function Write-Stderr {
    param([Parameter(Mandatory = $true)][string]$Message)

    [Console]::Error.WriteLine($Message)
}

function Add-ActivateLine {
    param([Parameter(Mandatory = $true)][string]$Line)

    Write-Stderr "Activation output: $Line"
    Write-Output $Line
}


$repo = "jdx/mise"
$api  = "https://api.github.com/repos/$repo/releases/latest"

$release = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "powershell" }
$tag = $release.tag_name

$arch = if ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -eq "Arm64") {
    "arm64"
} else {
    "x64"
}

$filename = "mise-$tag-windows-$arch.zip"
$url = "https://github.com/$repo/releases/download/$tag/$filename"

$temp = Join-Path $env:TEMP $filename
$binDir = Join-Path $env:LOCALAPPDATA "bin"
$localCargoBin = Join-Path $HOME ".local\bin"
$binDirActivateLine = 'if (-not ($env:PATH.Split(";") -contains "$env:LOCALAPPDATA\bin")) { $env:PATH="$env:LOCALAPPDATA\bin;$env:PATH" }'
$shimsActivateLine = '$miseShimActivation = (& mise activate --shims pwsh | Out-String).Trim(); if (-not [string]::IsNullOrWhiteSpace($miseShimActivation)) { Invoke-Expression $miseShimActivation }'

Write-Stderr "Downloading $url"
Invoke-WebRequest -Uri $url -OutFile $temp

Write-Stderr "Preparing $binDir"
New-Item -ItemType Directory -Force $binDir | Out-Null

$extract = Join-Path $env:TEMP "mise-extract"
Write-Stderr "Using download file $temp"
Write-Stderr "Using extract directory $extract"
Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $temp -DestinationPath $extract -Force

$miseExe = Get-ChildItem -Path $extract -Recurse -Filter "mise.exe" | Select-Object -First 1
$shimExe = Get-ChildItem -Path $extract -Recurse -Filter "mise-shim.exe" | Select-Object -First 1

if (-not $miseExe) {
    throw "mise.exe not found in archive"
}

Copy-Item $miseExe.FullName (Join-Path $binDir "mise.exe") -Force
Write-Stderr "Copied $($miseExe.FullName) to $(Join-Path $binDir "mise.exe")"

if ($shimExe) {
    Copy-Item $shimExe.FullName (Join-Path $binDir "mise-shim.exe") -Force
    Write-Stderr "Copied $($shimExe.FullName) to $(Join-Path $binDir "mise-shim.exe")"
}

$userPath = [Environment]::GetEnvironmentVariable("PATH","User")
Write-Stderr "Discovered user PATH: $userPath"

if ($userPath -notlike "*$binDir*") {
    Write-Stderr "Adding $binDir to PATH"

    [Environment]::SetEnvironmentVariable("PATH", "$binDir;$userPath", "User")

    if ($env:PATH -notlike "*$binDir*") {
        $env:PATH = "$binDir;$env:PATH"
    }
}

Add-ActivateLine -Line $binDirActivateLine
Add-ActivateLine -Line $shimsActivateLine

Write-Stderr "Installed to $binDir"
& (Join-Path $binDir "mise.exe") -v 2>&1 | ForEach-Object { Write-Stderr "$_" }

$misePath = Join-Path $binDir "mise.exe"
Write-Stderr "Discovered mise path: $misePath"


$profilePath = "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
$line = '$miseShimActivation = (& mise activate --shims pwsh | Out-String).Trim(); if (-not [string]::IsNullOrWhiteSpace($miseShimActivation)) { Invoke-Expression $miseShimActivation }'
Write-Stderr "Discovered profile path: $profilePath"

if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Force $profilePath | Out-Null
    Write-Stderr "Created profile $profilePath"
}

if (-not (Select-String -Path $profilePath -SimpleMatch $line -Quiet)) {
    Add-Content -Path $profilePath -Value $line
    Write-Stderr "Updated profile $profilePath"
} else {
    Write-Stderr "No changes to $profilePath"
}


if ($disableRun -eq "0") {
    if ($cargoInstall -eq "1") {
        Write-Stderr "Building and installing $toolSpec"
        & $misePath exec rust -- cargo install --path "." --bin lfp-env --root "$HOME/.local" --force 2>&1 | ForEach-Object { Write-Stderr "$_" }
        Write-Stderr "Discovered local cargo bin directory: $localCargoBin"
        $lfpOutput = & "$localCargoBin/lfp-env.exe" @args
    } else {
        Write-Stderr "Installing $toolSpec"
        & $misePath use -g $toolSpec 2>&1 | ForEach-Object { Write-Stderr "$_" }
        $lfpOutput = & $misePath x $toolSpec -- lfp-env @args
    }
}
