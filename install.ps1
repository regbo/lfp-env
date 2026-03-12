# Exit on errors and undefined variables
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$REPO = $env:LFP_ENV_REPO
if (-not $REPO) { $REPO = "regbo/lfp-env" }

$VERSION = $env:LFP_ENV_VERSION
$MIN_VERSION = $env:LFP_ENV_MIN_VERSION
$INSTALL_PATH = $env:LFP_ENV_INSTALL_PATH

function logging_enabled {
    $level = $env:LFP_ENV_LOG_LEVEL
    if (-not $level) { return $true }

    switch ($level.Trim().ToLowerInvariant()) {
        "info" { return $true }
        "debug" { return $true }
        default { return $false }
    }
}

function log {
    param([string]$msg)
    if (-not (logging_enabled)) { return }
    Write-Error "[lfp-env-install] $msg"
}

function is_exec {
    param([string]$path)
    if (-not $path) { return $false }
    return (Test-Path $path -PathType Leaf)
}

function version_ge {
    param($a,$b)
    if ($a -eq $b) { return $true }
    $sorted = @($a,$b) | Sort-Object {[version]$_}
    return $sorted[0] -eq $b
}

function detect_asset_name {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture

    switch ($arch) {
        "Arm64" { $arch_target = "aarch64" }
        "X64"   { $arch_target = "x86_64" }
        default { throw "ERROR: unsupported architecture: $arch" }
    }

    return "lfp-env-$arch_target-pc-windows-msvc.zip"
}

$DEFAULT_INSTALL_PATH = Join-Path $env:LOCALAPPDATA "bin\lfp-env.exe"
if ($INSTALL_PATH) { $LFP_ENV_BIN = $INSTALL_PATH } else { $LFP_ENV_BIN = $DEFAULT_INSTALL_PATH }

$BIN_DIR = Split-Path $LFP_ENV_BIN
New-Item -ItemType Directory -Force -Path $BIN_DIR | Out-Null

log "Repo: $REPO"
log "Version: $(if($VERSION){$VERSION}else{'latest'})"
log "Install path: $LFP_ENV_BIN"

$TEMP_DIR = $null
$INSTALL_REQUIRED = $false

function cleanup {
    if ($TEMP_DIR -and (Test-Path $TEMP_DIR)) {
        Remove-Item -Recurse -Force $TEMP_DIR
    }
}

try {

    if (-not (is_exec $LFP_ENV_BIN)) {
        $INSTALL_REQUIRED = $true
    }
    else {
        $CURRENT_VERSION = (& $LFP_ENV_BIN --version 2>$null)

        if ($VERSION -and $MIN_VERSION) {
            if (-not (version_ge $VERSION $MIN_VERSION)) {
                throw "ERROR: VERSION ($VERSION) does not satisfy MIN_VERSION ($MIN_VERSION)"
            }
        }

        if ($VERSION) {
            if ($CURRENT_VERSION -ne $VERSION) { $INSTALL_REQUIRED = $true }
        }
        elseif ($MIN_VERSION) {
            if (-not (version_ge $CURRENT_VERSION $MIN_VERSION)) { $INSTALL_REQUIRED = $true }
        }
    }

    if ($INSTALL_REQUIRED) {

        $ASSET_NAME = detect_asset_name

        if ($VERSION) {
            $RELEASE_URL = "https://github.com/$REPO/releases/download/v$VERSION/$ASSET_NAME"
        } else {
            $RELEASE_URL = "https://github.com/$REPO/releases/latest/download/$ASSET_NAME"
        }

        $TEMP_DIR = Join-Path ([System.IO.Path]::GetTempPath()) ("lfp-env-install-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $TEMP_DIR | Out-Null

        $ARCHIVE_PATH = Join-Path $TEMP_DIR $ASSET_NAME

        log "Downloading $RELEASE_URL"
        Invoke-WebRequest -Uri $RELEASE_URL -OutFile $ARCHIVE_PATH

        $EXTRACT_DIR = Join-Path $TEMP_DIR "extract"
        Expand-Archive -Path $ARCHIVE_PATH -DestinationPath $EXTRACT_DIR -Force
        $EXTRACTED_BIN = Join-Path $EXTRACT_DIR "lfp-env.exe"
        if (-not (Test-Path $EXTRACTED_BIN)) {
            throw "ERROR: extracted archive did not contain lfp-env.exe"
        }
        Copy-Item $EXTRACTED_BIN $LFP_ENV_BIN -Force
        log "Installed lfp-env to $LFP_ENV_BIN"
    }

    $env:LFP_ENV_INSTALLER_MODE = "1"
    if ($args.Count -gt 0) {
        & $LFP_ENV_BIN @args
    }
    else {
        & $LFP_ENV_BIN
    }
    exit $LASTEXITCODE
}
finally {
    cleanup
}