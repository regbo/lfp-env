use log::{info, warn};
use std::process::Command;

/// A program requirement definition for setup checks.
struct ProgramSpec {
    name: &'static str,
    version_args: &'static [&'static str],
    min_version: Option<&'static str>,
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

/// Entry point:
/// - Validates required programs
/// - Installs missing or too-old programs via mise
fn main() -> Result<(), String> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    info!("Starting environment program checks");
    for program in PROGRAM_SPECS {
        info!("Checking program '{}'", program.name);
        ensure_program(program)?;
    }
    info!("Environment program checks complete");
    Ok(())
}

/// Ensure a program is available and, when required, meets minimum version.
fn ensure_program(program: &ProgramSpec) -> Result<(), String> {
    let version_output = run_command_capture(program.name, program.version_args);
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
        install_with_mise(program.name, program.min_version)?;
        info!("Program '{}' installed via mise", program.name);
    }

    Ok(())
}

/// Install a program using mise:
/// - with explicit minimum version when configured
/// - otherwise latest version
fn install_with_mise(program_name: &str, min_version: Option<&str>) -> Result<(), String> {
    let version_selector = match min_version {
        Some(version) => version,
        None => "latest",
    };
    let tool_selector = format!("{program_name}@{version_selector}");
    info!("Installing '{}' with selector '{}'", program_name, tool_selector);
    run_command_status("mise", &["use", "-g", &tool_selector])
        .map_err(|err| format!("Failed to install {program_name} via mise: {err}"))
}

/// Run a command and capture stdout/stderr text when successful.
fn run_command_capture(command: &str, args: &[&str]) -> Result<String, String> {
    let output = Command::new(command)
        .args(args)
        .output()
        .map_err(|err| format!("Could not start '{command}': {err}"))?;

    if !output.status.success() {
        return Err(format!(
            "Command '{command} {}' failed with status {}",
            args.join(" "),
            output.status
        ));
    }

    let stdout_text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if !stdout_text.is_empty() {
        return Ok(stdout_text);
    }

    Ok(String::from_utf8_lossy(&output.stderr).trim().to_string())
}

/// Run a command and require a successful exit status.
fn run_command_status(command: &str, args: &[&str]) -> Result<(), String> {
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
