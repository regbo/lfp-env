use clap::{ArgAction, Parser, ValueEnum};
use log::{debug, info, warn, Level, LevelFilter};
use std::collections::BTreeSet;
use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

/// A program requirement definition for setup checks.
struct ProgramSpec {
    name: &'static str,
    version_args: &'static [&'static str],
    min_version: Option<&'static str>,
}

/// Command-line options for lfp-env.
#[derive(Parser, Debug)]
#[command(
    name = "lfp-env",
    about = "Bootstrap required environment tooling",
    disable_version_flag = false
)]
struct CliOptions {
    /// Explicit path to the mise executable.
    #[arg(long = "mise-bin", alias = "mise_bin")]
    mise_bin: Option<String>,
    /// Environment override passed as KEY:VALUE.
    #[arg(long = "env", value_name = "KEY:VALUE", value_parser = parse_env_pair, action = ArgAction::Append)]
    env_overrides: Vec<(String, String)>,
    /// Whether to write profile updates. Defaults to true.
    #[arg(long = "profile", default_value_t = true)]
    profile: bool,
    /// Force exporting the mise parent directory into PATH output.
    #[arg(long = "export-path", action = ArgAction::SetTrue)]
    export_path: bool,
    /// Override export output format. Useful for cross-platform testing.
    #[arg(long = "export-path-format", value_enum, default_value = "auto")]
    export_path_format: ExportFormat,
    /// Set log verbosity for this run (error, warn, info, debug, trace, off).
    /// Reads LOG_LEVEL by default when not provided on CLI.
    #[arg(long = "log-level", env = "LOG_LEVEL", default_value = "info", value_parser = parse_level_filter)]
    log_level: LevelFilter,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, ValueEnum)]
enum ExportFormat {
    Auto,
    Unix,
    Windows,
}

/// Program checks:
/// - Python must satisfy minimum version
/// - uv/git must exist (any version accepted)
const PROGRAM_SPECS: &[ProgramSpec] = &[
    ProgramSpec {
        name: "python",
        version_args: &["--version"],
        min_version: Some("3.10"),
    },
    ProgramSpec {
        name: "uv",
        version_args: &["--version"],
        min_version: None,
    },
    ProgramSpec {
        name: "git",
        version_args: &["--version"],
        min_version: None,
    },
];
const PKG_NAME: &str = env!("CARGO_PKG_NAME");

/// Entry point:
/// - Validates required programs
/// - Installs missing or too-old programs via mise
fn main() -> Result<(), String> {
    let options = parse_cli_options()?;
    init_logger(options.log_level);
    debug!(
        "CLI options resolved: profile={}, export_path={}, export_path_format={:?}, log_level={:?}",
        options.profile, options.export_path, options.export_path_format, options.log_level
    );
    let mise_bin = match options.mise_bin.clone() {
        Some(path) => path,
        None => resolve_mise_bin()?,
    };
    let mise_doctor_output = run_command_capture(&mise_bin, &["doctor"], false)
        .map_err(|err| format!("Failed to run 'mise doctor': {err}"))?;
    if debug_enabled() {
        debug_lazy(|| format!("mise doctor output at startup:\n{}", mise_doctor_output));
    }
    let mise_shims_path = resolve_mise_shims_dir_from_doctor(&mise_doctor_output)?;
    debug!(
        "Resolved mise shims path once at startup: '{}'",
        mise_shims_path.display()
    );
    apply_env_overrides(&options.env_overrides);
    info!("Using mise binary at '{}'", mise_bin);
    info!("Starting environment program checks");
    for program in PROGRAM_SPECS {
        info!("Checking program '{}'", program.name);
        ensure_program(program, &mise_bin)?;
    }
    if should_write_profile(&options) {
        configure_shell_profile(&mise_shims_path)?;
    } else {
        info!("Skipping profile configuration (--profile=false)");
    }
    let export_format = resolve_export_format(options.export_path_format);
    info!("Environment program checks complete");
    print_env_exports(
        &options.env_overrides,
        &mise_bin,
        options.export_path,
        export_format,
        &mise_shims_path,
    )?;
    Ok(())
}

fn init_logger(log_level: LevelFilter) {
    env_logger::Builder::new()
        .filter_level(log_level)
        .format(|buf, record| {
            if record.level() == log::Level::Info {
                writeln!(buf, "[{}] {}", PKG_NAME, record.args())
            } else {
                writeln!(buf, "[{}] [{}] {}", PKG_NAME, record.level(), record.args())
            }
        })
        .init();
}

fn parse_level_filter(value: &str) -> Result<LevelFilter, String> {
    value
        .trim()
        .parse::<LevelFilter>()
        .map_err(|_| format!("Invalid log level '{value}'. Expected one of: error,warn,info,debug,trace,off"))
}

fn debug_enabled() -> bool {
    log::log_enabled!(Level::Debug)
}

fn debug_lazy<F>(build_message: F)
where
    F: FnOnce() -> String,
{
    if debug_enabled() {
        debug!("{}", build_message());
    }
}

fn resolve_export_format(export_format: ExportFormat) -> ExportFormat {
    match export_format {
        ExportFormat::Auto => {
            if cfg!(windows) {
                ExportFormat::Windows
            } else {
                ExportFormat::Unix
            }
        }
        ExportFormat::Unix => ExportFormat::Unix,
        ExportFormat::Windows => ExportFormat::Windows,
    }
}

fn should_write_profile(options: &CliOptions) -> bool {
    options.profile
}

fn apply_env_overrides(env_overrides: &[(String, String)]) {
    for (key, value) in env_overrides {
        let previous = env::var(key).ok();
        debug_lazy(|| {
            format!(
                "Applying env override key='{}' previous={:?} next={:?}",
                key, previous, value
            )
        });
        env::set_var(key, value);
        info!("Applied env override '{}'", key);
        debug_lazy(|| format!("Current env '{}' now {:?}", key, env::var(key).ok()));
    }
}

fn parse_env_pair(value: &str) -> Result<(String, String), String> {
    let (key, env_value) = value
        .split_once(':')
        .ok_or_else(|| format!("Invalid --env value '{value}', expected KEY:VALUE"))?;
    if key.is_empty() {
        return Err(format!(
            "Invalid --env value '{value}', key cannot be empty"
        ));
    }
    Ok((key.to_string(), env_value.to_string()))
}

/// Print shell export lines for overridden env vars.
/// This is emitted on stdout so callers can `eval "$(install.sh)"`.
fn print_env_exports(
    env_overrides: &[(String, String)],
    mise_bin: &str,
    force_export_path: bool,
    export_format: ExportFormat,
    mise_shims_path: &Path,
) -> Result<(), String> {
    debug!(
        "Preparing export output: env_override_count={}, force_export_path={}, export_format={:?}",
        env_overrides.len(),
        force_export_path,
        export_format
    );
    if env_overrides.is_empty() {
        info!("No env to update");
    }
    let mut emitted: BTreeSet<&str> = BTreeSet::new();
    for (key, _) in env_overrides {
        if !emitted.insert(key.as_str()) {
            debug!("Skipping duplicate env override key '{}'", key);
            continue;
        }
        if let Ok(value) = env::var(key) {
            debug_lazy(|| format!("Emitting env export for key='{}' value={:?}", key, value));
            println!("{}", format_env_assignment_line(key, &value, export_format));
        }
    }
    for path_export_line in build_path_export_lines(
        mise_bin,
        force_export_path,
        export_format,
        mise_shims_path,
    )? {
        println!("{path_export_line}");
    }
    Ok(())
}

/// Build PATH export lines for required directories.
/// Required directories:
/// - Parent directory of `mise_bin`
/// - `${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims` (resolved value)
fn build_path_export_lines(
    mise_bin: &str,
    force_export_path: bool,
    export_format: ExportFormat,
    mise_shims_path: &Path,
) -> Result<Vec<String>, String> {
    let path_value = env::var("PATH").unwrap_or_default();
    let mut lines: Vec<String> = Vec::new();
    debug_lazy(|| format!("Current PATH before export checks: {}", path_value));

    if let Some(mise_parent) = Path::new(mise_bin).parent() {
        debug!("Resolved mise parent directory '{}'", mise_parent.display());
        if force_export_path || !path_contains_directory(&path_value, mise_parent) {
            let export_dir = render_home_relative_path(mise_parent, export_format);
            lines.push(format_path_prepend_line(&export_dir, export_format));
        } else {
            info!("PATH already contains mise parent directory");
        }
    }

    debug!(
        "Using pre-resolved mise shims directory '{}'",
        mise_shims_path.display()
    );
    if force_export_path || !path_contains_directory(&path_value, mise_shims_path) {
        let export_dir = render_home_relative_path(mise_shims_path, export_format);
        lines.push(format_path_prepend_line(&export_dir, export_format));
    } else {
        info!("PATH already contains mise shims directory");
    }

    debug_lazy(|| format!("Generated PATH export lines: {:?}", lines));
    Ok(lines)
}

/// Resolve the shims directory from `mise doctor` output.
fn resolve_mise_shims_dir_from_doctor(mise_doctor_output: &str) -> Result<PathBuf, String> {
    let mut in_dirs_section = false;
    for line in mise_doctor_output.lines() {
        let trimmed = line.trim();
        if trimmed == "dirs:" {
            in_dirs_section = true;
            continue;
        }
        if !in_dirs_section {
            continue;
        }
        if !line.starts_with("  ") {
            break;
        }
        if let Some(value) = trimmed.strip_prefix("shims:") {
            let raw_path = value.trim();
            if raw_path.is_empty() {
                return Err(
                    "Found 'shims:' in mise doctor output, but it did not contain a path."
                        .to_string(),
                );
            }
            let expanded = expand_home_dir_token(raw_path);
            debug!(
                "Resolved shims path from mise doctor: raw='{}' expanded='{}'",
                raw_path, expanded
            );
            return Ok(PathBuf::from(expanded));
        }
    }
    Err("Could not resolve mise shims directory from 'mise doctor' output.".to_string())
}

/// Expand a leading '~' using HOME or USERPROFILE.
fn expand_home_dir_token(path_value: &str) -> String {
    if !path_value.starts_with('~') {
        return path_value.to_string();
    }
    let home = env::var("HOME")
        .ok()
        .or_else(|| env::var("USERPROFILE").ok())
        .unwrap_or_else(|| "~".to_string());
    if path_value == "~" {
        return home;
    }
    let suffix = path_value.trim_start_matches('~');
    let normalized_suffix = suffix.trim_start_matches(['/', '\\']);
    format!("{}/{}", home, normalized_suffix)
}

/// Render a path as ${HOME}/... when possible, otherwise absolute.
fn render_home_relative_path(path: &Path, export_format: ExportFormat) -> String {
    let absolute = normalize_path_string(path.to_string_lossy().as_ref());
    if let Ok(home) = env::var("HOME") {
        let home_normalized = normalize_path_string(&home);
        if absolute == home_normalized {
            return match export_format {
                ExportFormat::Unix => "${HOME}".to_string(),
                ExportFormat::Windows => "$HOME".to_string(),
                ExportFormat::Auto => "${HOME}".to_string(),
            };
        }
        if let Some(suffix) = absolute.strip_prefix(&(home_normalized.clone() + "/")) {
            return match export_format {
                ExportFormat::Unix => format!("${{HOME}}/{suffix}"),
                ExportFormat::Windows => format!("$HOME/{suffix}"),
                ExportFormat::Auto => format!("${{HOME}}/{suffix}"),
            };
        }
    }
    absolute
}

/// Check if PATH already contains a directory.
/// Supports entries in expanded form, ${HOME}/..., $HOME/..., and ~/...
fn path_contains_directory(path_value: &str, target_directory: &Path) -> bool {
    let target = normalize_path_string(target_directory.to_string_lossy().as_ref());
    let home = env::var("HOME").ok().map(|value| normalize_path_string(&value));
    #[cfg(windows)]
    let path_separator = ';';
    #[cfg(not(windows))]
    let path_separator = ':';
    for entry in path_value.split(path_separator) {
        let trimmed = entry.trim();
        if trimmed.is_empty() {
            continue;
        }
        let normalized_entry = normalize_path_string(trimmed);
        if normalized_entry == target {
            return true;
        }
        let expanded = expand_home_path_entry(trimmed, home.as_deref());
        if normalize_path_string(&expanded) == target {
            return true;
        }
    }
    debug!(
        "PATH does not contain target directory '{}'",
        target_directory.display()
    );
    false
}

/// Expand a PATH segment if it starts with a home token.
fn expand_home_path_entry(entry: &str, home: Option<&str>) -> String {
    let Some(home_dir) = home else {
        return entry.to_string();
    };
    if entry == "~" {
        return home_dir.to_string();
    }
    if let Some(suffix) = entry.strip_prefix("~/") {
        return format!("{home_dir}/{suffix}");
    }
    if entry == "$HOME" || entry == "${HOME}" {
        return home_dir.to_string();
    }
    if let Some(suffix) = entry.strip_prefix("$HOME/") {
        return format!("{home_dir}/{suffix}");
    }
    if let Some(suffix) = entry.strip_prefix("${HOME}/") {
        return format!("{home_dir}/{suffix}");
    }
    entry.to_string()
}

/// Normalize path text for reliable string comparison.
fn normalize_path_string(path: &str) -> String {
    if path.is_empty() {
        return String::new();
    }
    let mut normalized = path.replace('\\', "/");
    while normalized.ends_with('/') && normalized.len() > 1 {
        normalized.pop();
    }
    normalized
}

fn format_env_assignment_line(key: &str, value: &str, export_format: ExportFormat) -> String {
    match export_format {
        ExportFormat::Unix | ExportFormat::Auto => {
            let escaped = value.replace('\'', "'\\''");
            format!("export {key}='{escaped}'")
        }
        ExportFormat::Windows => {
            let escaped = value.replace('\'', "''");
            format!("$env:{key}='{escaped}'")
        }
    }
}

fn format_path_prepend_line(path_to_prepend: &str, export_format: ExportFormat) -> String {
    match export_format {
        ExportFormat::Unix | ExportFormat::Auto => format!("export PATH=\"{path_to_prepend}:$PATH\""),
        ExportFormat::Windows => format!("$env:PATH=\"{path_to_prepend};$env:PATH\""),
    }
}

/// Ensure a program is available and, when required, meets minimum version.
fn ensure_program(program: &ProgramSpec, mise_bin: &str) -> Result<(), String> {
    debug!(
        "Ensuring program '{}' with version args {:?} and min_version {:?}",
        program.name, program.version_args, program.min_version
    );
    let version_output = run_command_capture_check(program.name, program.version_args);
    let needs_install = match version_output {
        Ok(output_text) => match program.min_version {
            Some(min_version) => {
                if is_version_at_least(&output_text, min_version) {
                    info!(
                        "Program '{}' meets minimum version {} (reported: {})",
                        program.name, min_version, output_text
                    );
                    false
                } else {
                    warn!(
                        "Program '{}' is below minimum version {} (reported: {})",
                        program.name, min_version, output_text
                    );
                    true
                }
            }
            None => {
                info!("Program '{}' is available (reported: {})", program.name, output_text);
                false
            }
        },
        Err(err) => {
            warn!(
                "Program '{}' check failed, will install via mise: {}",
                program.name, err
            );
            true
        }
    };

    if needs_install {
        install_with_mise(program.name, mise_bin)?;
        info!("Program '{}' installed via mise", program.name);
    }

    Ok(())
}

/// Install a program using mise at latest version.
fn install_with_mise(program_name: &str, mise_bin: &str) -> Result<(), String> {
    let tool_selector = format!("{program_name}@latest");
    info!("Installing '{}' with selector '{}'", program_name, tool_selector);
    run_command_status(mise_bin, &["use", "-g", &tool_selector])
        .map_err(|err| format!("Failed to install {program_name} via mise: {err}"))
}

/// Run a command and capture stdout/stderr text when successful.
fn run_command_capture_check(command: &str, args: &[&str]) -> Result<String, String> {
    run_command_capture(command, args, true)
}

fn run_command_capture(
    command: &str,
    args: &[&str],
    check_exit_status: bool,
) -> Result<String, String> {
    debug!("Running command capture: '{}' with args {:?}", command, args);
    let output = Command::new(command)
        .args(args)
        .output()
        .map_err(|err| format!("Could not start '{command}': {err}"))?;
    let stdout_text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr_text = String::from_utf8_lossy(&output.stderr).trim().to_string();


    if check_exit_status && !output.status.success() {
        return Err(format!(
            "Command '{command} {}' failed with status {}. stdout={:?} stderr={:?}",
            args.join(" "),
            output.status,
            stdout_text,
            stderr_text
        ));
    }
    if !stdout_text.is_empty() {
        if !stderr_text.is_empty() {
            debug_lazy(|| format!("Command '{}' stderr: {:?}", command, stderr_text));
        }
        return Ok(stdout_text);
    }
    Ok(stderr_text)
}

/// Run a command and require a successful exit status.
fn run_command_status(command: &str, args: &[&str]) -> Result<(), String> {
    debug!("Running command status: '{}' with args {:?}", command, args);
    let status = Command::new(command)
        .args(args)
        .status()
        .map_err(|err| format!("Could not start '{command}': {err}"))?;

    if status.success() {
        return Ok(());
    }

    Err(format!(
        "Command '{command} {}' failed with status {status}",
        args.join(" ")
    ))
}

/// Compare program output version against a minimum version requirement.
/// Uses lenient_semver to parse versions from command output tokens.
fn is_version_at_least(output: &str, min_version: &str) -> bool {
    let current = extract_version_token(output)
        .and_then(|token| lenient_semver::parse(&token).ok());
    let minimum = lenient_semver::parse(min_version).ok();
    match (current, minimum) {
        (Some(current_version), Some(minimum_version)) => current_version >= minimum_version,
        _ => false,
    }
}

/// Extract the first parseable version token from command output.
/// Examples:
/// - "Python 3.10.12" -> 3.10.12
/// - "uv 0.5.22 (abcd)" -> 0.5.22
fn extract_version_token(output: &str) -> Option<String> {
    for raw_token in output.split_whitespace() {
        let cleaned = raw_token.trim_matches(|ch: char| !ch.is_ascii_alphanumeric() && ch != '.');
        if cleaned.is_empty() {
            continue;
        }
        if lenient_semver::parse(cleaned).is_ok() {
            return Some(cleaned.to_string());
        }
    }
    None
}

/// Parse CLI options.
/// Supports:
/// - --mise-bin <path>
/// - --mise_bin <path> (compatibility)
fn parse_cli_options() -> Result<CliOptions, String> {
    CliOptions::try_parse().map_err(|err| err.to_string())
}

#[cfg(windows)]
fn resolve_mise_bin() -> Result<String, String> {
    debug!("Resolving mise binary via which crate on Windows");
    let resolved = which::which("mise")
        .map_err(|err| format!("Failed to resolve mise binary path via which crate: {err}"))?;
    debug!("Resolved mise binary to '{}'", resolved.display());
    Ok(resolved.to_string_lossy().to_string())
}

#[cfg(not(windows))]
fn resolve_mise_bin() -> Result<String, String> {
    debug!("Resolving mise binary via 'type -a mise'");
    let output = run_command_capture_check("sh", &["-lc", "type -a mise"])?;
    for line in output.lines() {
        let trimmed = line.trim();
        if let Some((_, path_part)) = trimmed.split_once(" is /") {
            let candidate = format!("/{}", path_part.trim());
            if Path::new(&candidate).is_file() {
                debug!("Resolved mise binary from type -a to '{}'", candidate);
                return Ok(candidate);
            }
        }
    }
    debug!("Falling back to which crate for mise resolution");
    let resolved = which::which("mise").map_err(|err| {
        format!("Failed to resolve mise binary path via type -a or which crate: {err}")
    })?;
    debug!("Resolved mise binary from which crate to '{}'", resolved.display());
    Ok(resolved.to_string_lossy().to_string())
}

/// Configure shell profile to include local bin path and mise activation.
fn configure_shell_profile(mise_shims_path: &Path) -> Result<(), String> {
    #[cfg(windows)]
    {
        let shims_export_dir = render_home_relative_path(mise_shims_path, ExportFormat::Windows);
        ensure_windows_user_path_contains(mise_shims_path)?;
        info!(
            "Configured Windows user PATH to include '{}' (resolved path: '{}')",
            shims_export_dir,
            mise_shims_path.display()
        );
        return Ok(());
    }

    #[cfg(not(windows))]
    {
        let home = env::var("HOME").map_err(|_| "HOME is not set".to_string())?;
        debug!("Configuring non-Windows profiles under HOME='{}'", home);
        let shims_export_dir = render_home_relative_path(mise_shims_path, ExportFormat::Unix);
        let shims_path_line = format!("export PATH=\"{shims_export_dir}:$PATH\"");

        for profile_path in resolve_non_interactive_profiles(&home) {
            debug!("Checking non-interactive profile '{}'", profile_path.display());
            ensure_profile_line(&profile_path, &shims_path_line)?;
        }

        for (shell_name, profile_path) in resolve_interactive_profiles(&home) {
            debug!(
                "Checking interactive profile '{}' for shell '{}'",
                profile_path.display(),
                shell_name
            );
            let activation_line = format!(r#"eval "$(mise activate {shell_name})""#);
            ensure_profile_line(&profile_path, &activation_line)?;
        }

        Ok(())
    }
}

#[cfg(windows)]
fn ensure_windows_user_path_contains(path_to_add: &Path) -> Result<(), String> {
    let target = path_to_add.to_string_lossy().replace('\'', "''");
    let script = format!(
        "$target='{target}'; \
         $current=[Environment]::GetEnvironmentVariable('Path','User'); \
         $parts=@(); \
         if(-not [string]::IsNullOrWhiteSpace($current)){{ \
           $parts=$current -split ';' | Where-Object {{ -not [string]::IsNullOrWhiteSpace($_) }} \
         }}; \
         $normalizedTarget=$target.Trim().TrimEnd('\\').ToLowerInvariant(); \
         $exists=$false; \
         foreach($part in $parts){{ \
           if($part.Trim().TrimEnd('\\').ToLowerInvariant() -eq $normalizedTarget){{ \
             $exists=$true; break \
           }} \
         }}; \
         if(-not $exists){{ \
           if($parts.Count -gt 0){{ $newPath=\"$current;$target\" }} else {{ $newPath=$target }}; \
           [Environment]::SetEnvironmentVariable('Path',$newPath,'User') \
         }}"
    );
    run_command_status(
        "powershell",
        &["-NoProfile", "-NonInteractive", "-Command", &script],
    )
    .map_err(|err| format!("Failed to persist Windows user PATH: {err}"))
}

#[cfg(not(windows))]
fn resolve_non_interactive_profiles(home: &str) -> Vec<PathBuf> {
    vec![
        Path::new(home).join(".profile"),
        Path::new(home).join(".bash_profile"),
        Path::new(home).join(".bash_login"),
        Path::new(home).join(".zprofile"),
    ]
}

#[cfg(not(windows))]
fn resolve_interactive_profiles(home: &str) -> Vec<(&'static str, PathBuf)> {
    vec![
        ("bash", Path::new(home).join(".bashrc")),
        ("zsh", Path::new(home).join(".zshrc")),
        ("fish", Path::new(home).join(".config/fish/config.fish")),
        ("elvish", Path::new(home).join(".elvish/rc.elv")),
        ("nu", Path::new(home).join(".config/nushell/config.nu")),
        ("xonsh", Path::new(home).join(".xonshrc")),
    ]
}

#[cfg(not(windows))]
fn ensure_profile_line(profile_path: &Path, line: &str) -> Result<(), String> {
    if !profile_path.exists() {
        return Ok(());
    }
    if !profile_path.is_file() {
        return Ok(());
    }

    let existing = fs::read_to_string(profile_path).unwrap_or_default();
    debug_lazy(|| {
        format!(
            "Profile before update '{}':\n{}",
            profile_path.display(),
            existing
        )
    });
    if existing.lines().any(|existing_line| existing_line == line) {
        info!(
            "Profile line already exists in '{}'",
            profile_path.display()
        );
        return Ok(());
    }

    let mut file = OpenOptions::new()
        .append(true)
        .open(profile_path)
        .map_err(|err| {
            format!(
                "Failed to open profile file '{}': {}",
                profile_path.display(),
                err
            )
        })?;
    writeln!(file, "{}", line).map_err(|err| {
        format!(
            "Failed to write profile file '{}': {}",
            profile_path.display(),
            err
        )
    })?;
    debug_lazy(|| {
        let mut after = existing.clone();
        if !after.ends_with('\n') && !after.is_empty() {
            after.push('\n');
        }
        after.push_str(line);
        after.push('\n');
        format!("Profile after update '{}':\n{}", profile_path.display(), after)
    });
    info!("Updated profile '{}'", profile_path.display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{extract_version_token, is_version_at_least};

    #[test]
    fn parses_full_python_version() {
        let parsed = extract_version_token("Python 3.11.7");
        assert_eq!(parsed, Some("3.11.7".to_string()));
    }

    #[test]
    fn parses_prefixed_uv_version() {
        let parsed = extract_version_token("uv 0.5.22 (Homebrew 2025-03-01)");
        assert_eq!(parsed, Some("0.5.22".to_string()));
    }

    #[test]
    fn detects_minimum_version_success() {
        assert!(is_version_at_least("Python 3.10.1", "3.10"));
    }

    #[test]
    fn detects_minimum_version_failure() {
        assert!(!is_version_at_least("Python 3.9.21", "3.10"));
    }
}
