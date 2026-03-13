# Exit on errors and undefined variables
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PYTHON_MIN_VERSION = $env:LFP_ENV_PYTHON_MIN_VERSION
if (-not $PYTHON_MIN_VERSION) { $PYTHON_MIN_VERSION = "3.10" }
$UV_MIN_VERSION = $env:LFP_ENV_UV_MIN_VERSION
if (-not $UV_MIN_VERSION) { $UV_MIN_VERSION = "0.9.9" }
$GIT_MIN_VERSION = $env:LFP_ENV_GIT_MIN_VERSION
$PIXI_INSTALL_URL = "https://pixi.sh/install.ps1"
$PROFILE_MARKER = "# lfp-env"

# Write routine installer activity to stderr.
function log {
    param([string]$msg)
    [Console]::Error.WriteLine("[lfp-env-install] $msg")
}

# Fail fast with a consistent error prefix.
function fail {
    param([string]$msg)
    throw "ERROR: $msg"
}

# Check whether a local path points at a file we can execute.
function is_exec {
    param([string]$path)
    if (-not $path) { return $false }
    return (Test-Path $path -PathType Leaf)
}

# Normalize versions so comparisons accept v-prefixed values.
function normalize_version {
    param([string]$value)
    if (-not $value) { return $value }
    return $value.TrimStart("v")
}

# Compare two dotted versions and return success when the first is >= the second.
function version_ge {
    param($a,$b)
    if ($a -eq $b) { return $true }
    $normalizedA = normalize_version $a.ToString()
    $normalizedB = normalize_version $b.ToString()
    $sorted = @($normalizedA,$normalizedB) | Sort-Object {[version]$_}
    if ($normalizedA -eq $normalizedB) { return $true }
    return $sorted[0] -eq $normalizedB
}

# Resolve the Pixi home directory, honoring PIXI_HOME.
function resolve_pixi_home_dir {
    if ($env:PIXI_HOME) {
        if ($env:PIXI_HOME -eq "~") {
            return $HOME
        }
        if ($env:PIXI_HOME.StartsWith("~/")) {
            return Join-Path $HOME $env:PIXI_HOME.Substring(2)
        }
        return $env:PIXI_HOME
    }
    return Join-Path $HOME ".pixi"
}

# Resolve the Pixi bin directory, honoring PIXI_BIN_DIR.
function resolve_pixi_bin_dir {
    param([string]$pixiHomeDir)
    if ($env:PIXI_BIN_DIR) { return $env:PIXI_BIN_DIR }
    return Join-Path $pixiHomeDir "bin"
}

# Capture the first dotted version token from common CLI version output.
function extract_version_token {
    param([string]$text)
    if (-not $text) { return $null }
    $match = [regex]::Match($text, "[0-9]+(?:\.[0-9]+)+")
    if ($match.Success) { return $match.Value }
    return $null
}

# Prepend a PATH entry once so newly installed tools are visible immediately.
function prepend_path {
    param([string]$pathEntry)
    if (-not $Env:PATH) {
        $Env:PATH = $pathEntry
        return
    }
    $entries = $Env:PATH -split ';'
    if ($entries -contains $pathEntry) { return }
    $Env:PATH = "$pathEntry;$Env:PATH"
}

# Stream a command's output to stderr so stdout stays reserved for activation output.
function invoke_with_stderr_pipe {
    param([scriptblock]$Command)

    & $Command 2>&1 | ForEach-Object { [Console]::Error.WriteLine($_) }
    return $?
}

# Inspect a tool once and return the raw output plus parsed version.
function inspect_tool {
    param([string]$toolName)

    $toolCommand = Get-Command $toolName -ErrorAction SilentlyContinue
    if (-not $toolCommand) { return $null }
    $reportedOutput = (& $toolCommand.Source --version 2>&1 | Out-String).Trim()
    return [pscustomobject]@{
        Command = $toolCommand
        Output = $reportedOutput
        Version = extract_version_token $reportedOutput
    }
}

# Install Pixi if it is not already available on PATH or in PIXI_BIN_DIR.
function ensure_pixi {
    $pixiHomeDir = resolve_pixi_home_dir
    $pixiBinDir = resolve_pixi_bin_dir $pixiHomeDir
    $pixiBin = Join-Path $pixiBinDir "pixi.exe"
    New-Item -ItemType Directory -Force -Path $pixiBinDir | Out-Null

    $pixiCommand = Get-Command pixi -ErrorAction SilentlyContinue
    if ($pixiCommand) {
        prepend_path (Split-Path $pixiCommand.Source)
        return
    }

    if (Test-Path $pixiBin -PathType Leaf) {
        prepend_path $pixiBinDir
        return
    }

    log "Installing pixi"
    $pixiInstallScript = Join-Path $TEMP_DIR "pixi-install.ps1"
    log "Downloading $PIXI_INSTALL_URL"
    Invoke-WebRequest -Uri $PIXI_INSTALL_URL -OutFile $pixiInstallScript

    $previousPixiHome = $env:PIXI_HOME
    $previousPixiBinDir = $env:PIXI_BIN_DIR
    $env:PIXI_HOME = $pixiHomeDir
    $env:PIXI_BIN_DIR = $pixiBinDir
    try {
        if (-not (invoke_with_stderr_pipe { & $pixiInstallScript })) {
            fail "pixi installation failed."
        }
    }
    catch {
        fail "pixi installation failed."
    }
    finally {
        if ($null -ne $previousPixiHome) { $env:PIXI_HOME = $previousPixiHome } else { Remove-Item Env:PIXI_HOME -ErrorAction SilentlyContinue }
        if ($null -ne $previousPixiBinDir) { $env:PIXI_BIN_DIR = $previousPixiBinDir } else { Remove-Item Env:PIXI_BIN_DIR -ErrorAction SilentlyContinue }
    }

    if (-not (Test-Path $pixiBin -PathType Leaf)) {
        fail "pixi installation did not create $pixiBin."
    }
    prepend_path $pixiBinDir
}

# Run pixi global install while keeping stdout reserved for activation output.
function run_pixi_global_install {
    param([string[]]$selectors)
    try {
        if (-not (invoke_with_stderr_pipe { & pixi global install @selectors })) {
            fail "pixi global install failed for: $($selectors -join ' ')"
        }
    }
    catch {
        fail "pixi global install failed for: $($selectors -join ' ')"
    }
}

# Ensure a required global tool exists and optionally meets a minimum version.
function ensure_global_tool {
    param(
        [string]$toolName,
        [string]$minVersion,
        [string]$pixiSelector
    )

    $toolInfo = inspect_tool $toolName
    if ($toolInfo) {
        if (-not $minVersion) {
            log "Program '$toolName' is available (reported: $($toolInfo.Output))"
            return
        }
        if ($toolInfo.Version -and (version_ge $toolInfo.Version $minVersion)) {
            log "Program '$toolName' meets minimum version $minVersion (reported: $($toolInfo.Output))"
            return
        }
    }

    log "Installing '$toolName' with pixi global install: $pixiSelector"
    run_pixi_global_install @($pixiSelector)

    $toolInfo = inspect_tool $toolName
    if (-not $toolInfo) {
        fail "Program '$toolName' is still unavailable after pixi install."
    }
    if ($minVersion -and ((-not $toolInfo.Version) -or (-not (version_ge $toolInfo.Version $minVersion)))) {
        fail "Program '$toolName' is below minimum version $minVersion after pixi install (reported: $($toolInfo.Output))."
    }
    if ($minVersion) {
        log "Program '$toolName' meets minimum version $minVersion (reported: $($toolInfo.Output))"
        return
    }
    log "Program '$toolName' is available (reported: $($toolInfo.Output))"
}

# Build the stdout activation command for the current PowerShell session.
function build_activation_command {
    $pixiHomeDir = resolve_pixi_home_dir
    $pixiBinDir = resolve_pixi_bin_dir $pixiHomeDir
    return "`$PixiBinDir = '$($pixiBinDir.Replace("'", "''"))'; if (-not ((`$Env:PATH -split ';') -contains `$PixiBinDir)) { `$Env:PATH = `"`$PixiBinDir;`$Env:PATH`" }"
}

# Tag the managed profile line so reruns can avoid duplicates.
function build_profile_line {
    $activationCommand = build_activation_command
    return "$activationCommand $PROFILE_MARKER"
}

# Append the managed activation line to a profile when it is not already present.
function write_profile_block {
    param([string]$profilePath)

    $profileDir = Split-Path -Parent $profilePath
    if ($profileDir) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }

    $existingContent = ""
    if (Test-Path $profilePath -PathType Leaf) {
        $existingContent = Get-Content -Raw $profilePath
    }

    $existingLines = $existingContent -split "\r?\n"
    $activationCommand = build_activation_command
    $profileLine = build_profile_line
    if ($existingLines -contains $activationCommand -or $existingLines -contains $profileLine) {
        return
    }

    # Remove previously tagged single-line entries before appending the managed activation line.
    $cleanedContent = $existingContent
    $managedLinePattern = "(?m)^.*$([regex]::Escape($PROFILE_MARKER))\s*$\r?\n?"
    $cleanedContent = [regex]::Replace($cleanedContent, $managedLinePattern, "")
    $cleanedContent = $cleanedContent.TrimEnd([char[]]"`r`n")

    if ([string]::IsNullOrWhiteSpace($cleanedContent)) {
        $renderedContent = "$profileLine`r`n"
    }
    else {
        $renderedContent = "$cleanedContent`r`n`r`n$profileLine`r`n"
    }

    if ($existingContent -ceq $renderedContent) {
        return
    }

    Set-Content -Path $profilePath -Value $renderedContent -Encoding utf8
    log "Updated non-interactive profile $profilePath"
}

# Update the common PowerShell profiles used by non-interactive shells.
function update_shell_profiles {
    $profilePaths = [System.Collections.Generic.List[string]]::new()
    $profilePaths.Add($PROFILE.CurrentUserAllHosts)
    if ((Test-Path $PROFILE.CurrentUserCurrentHost -PathType Leaf) -and ($PROFILE.CurrentUserCurrentHost -ne $PROFILE.CurrentUserAllHosts)) {
        $profilePaths.Add($PROFILE.CurrentUserCurrentHost)
    }

    $seenPaths = @{}
    foreach ($profilePath in $profilePaths) {
        if (-not $profilePath) { continue }
        if ($seenPaths.ContainsKey($profilePath)) { continue }
        $seenPaths[$profilePath] = $true
        write_profile_block $profilePath
    }
}

# Print the activation command that callers should invoke in the current shell.
function print_activation {
    Write-Output (build_activation_command)
}

$TEMP_DIR = $null

# Remove temporary installer files on exit.
function cleanup {
    if ($TEMP_DIR -and (Test-Path $TEMP_DIR)) {
        Remove-Item -Recurse -Force $TEMP_DIR
    }
}

try {
    if (-not $TEMP_DIR) {
        $TEMP_DIR = Join-Path ([System.IO.Path]::GetTempPath()) ("lfp-env-install-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $TEMP_DIR | Out-Null
    }
    ensure_pixi
    ensure_global_tool "python" $PYTHON_MIN_VERSION "python"
    ensure_global_tool "uv" $UV_MIN_VERSION "uv"
    ensure_global_tool "git" $GIT_MIN_VERSION "git"
    update_shell_profiles

    if ($args.Count -gt 0) {
        log "Installing additional packages with pixi global install: $($args -join ' ')"
        run_pixi_global_install $args
    }
    print_activation
    exit 0
}
finally {
    cleanup
}