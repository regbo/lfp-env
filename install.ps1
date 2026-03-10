$toolSpec = if ($env:LFP_ENV_TOOL_SPEC) { $env:LFP_ENV_TOOL_SPEC } else { "github:regbo/lfp-env" }
$cargoInstall = if ($env:LFP_ENV_CARGO_INSTALL) { $env:LFP_ENV_CARGO_INSTALL } else { "0" }
$disableRun = if ($env:LFP_ENV_DISABLE_RUN) { $env:LFP_ENV_DISABLE_RUN } else { "0" }

function Update-SessionExports {
    param([object[]]$Lines)

    foreach ($lineObject in $Lines) {
        if ($null -eq $lineObject) {
            continue
        }

        $line = [string]$lineObject
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line.TrimStart().StartsWith('$env:')) {
            Invoke-Expression $line
        }

        Write-Output $line
    }
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

Write-Host "Downloading $url"
Invoke-WebRequest -Uri $url -OutFile $temp

Write-Host "Preparing $binDir"
New-Item -ItemType Directory -Force $binDir | Out-Null

$extract = Join-Path $env:TEMP "mise-extract"
Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $temp -DestinationPath $extract -Force

$miseExe = Get-ChildItem -Path $extract -Recurse -Filter "mise.exe" | Select-Object -First 1
$shimExe = Get-ChildItem -Path $extract -Recurse -Filter "mise-shim.exe" | Select-Object -First 1

if (-not $miseExe) {
    throw "mise.exe not found in archive"
}

Copy-Item $miseExe.FullName (Join-Path $binDir "mise.exe") -Force

if ($shimExe) {
    Copy-Item $shimExe.FullName (Join-Path $binDir "mise-shim.exe") -Force
}

$userPath = [Environment]::GetEnvironmentVariable("PATH","User")
if ($userPath -notlike "*$binDir*") {
    Write-Host "Adding $binDir to PATH"
    [Environment]::SetEnvironmentVariable("PATH", "$binDir;$userPath", "User")
}
$env:PATH = "$binDir;$env:PATH"

Write-Host "Installed to $binDir"
& (Join-Path $binDir "mise.exe") -v

$misePath = Join-Path $binDir "mise.exe"

if ($disableRun -eq "0") {
    if ($cargoInstall -eq "1") {
        Write-Host "Building and installing $toolSpec"
        & $misePath exec rust -- cargo install --path "." --bin lfp-env --root "$HOME/.local" --force
        $lfpOutput = & "$HOME/.local/bin/lfp-env.exe" @args
        Update-SessionExports -Lines $lfpOutput
    } else {
        Write-Host "Installing $toolSpec"
        & $misePath use -g $toolSpec
        $lfpOutput = & $misePath x $toolSpec -- lfp-env @args
        Update-SessionExports -Lines $lfpOutput
    }
}