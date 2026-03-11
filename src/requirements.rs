use crate::install::config::MinimumVersionConfig;
use crate::install::process;
use crate::version;
use log::{debug, info, warn};

/// A program requirement definition for setup checks.
struct ProgramSpec {
    name: &'static str,
    version_args: &'static [&'static str],
    min_version: Option<String>,
    mise_package_name: Option<&'static str>,
    mise_version: Option<&'static str>,
}

impl ProgramSpec {
    /// Resolve the package name used when installing a missing requirement via mise.
    fn mise_package_name(&self) -> &'static str {
        self.mise_package_name.unwrap_or(self.name)
    }

    /// Resolve the version used when installing a missing requirement via mise.
    fn mise_version(&self) -> &'static str {
        self.mise_version.unwrap_or("latest")
    }

    /// Resolve the optional minimum version constraint for the program.
    fn min_version(&self) -> Option<&str> {
        self.min_version.as_deref()
    }
}

/// Run all required runtime tool checks.
pub fn run_checks(mise_bin: &str, minimum_versions: &MinimumVersionConfig) -> Result<(), String> {
    debug!("Using mise binary at '{}'", mise_bin);
    debug!("Starting environment program checks");
    let program_specs = build_program_specs(minimum_versions);
    for program in &program_specs {
        debug!("Checking program '{}'", program.name);
        ensure_program(program, mise_bin)?;
    }
    debug!("Environment program checks complete");
    Ok(())
}

/// Build program requirement checks from the selected minimum version config.
fn build_program_specs(minimum_versions: &MinimumVersionConfig) -> Vec<ProgramSpec> {
    vec![
        ProgramSpec {
            name: "python",
            version_args: &["--version"],
            min_version: minimum_versions.python.clone(),
            mise_package_name: None,
            mise_version: None,
        },
        ProgramSpec {
            name: "uv",
            version_args: &["--version"],
            min_version: minimum_versions.uv.clone(),
            mise_package_name: None,
            mise_version: None,
        },
        ProgramSpec {
            name: "git",
            version_args: &["--version"],
            min_version: minimum_versions.git.clone(),
            mise_package_name: Some("conda:git"),
            mise_version: None,
        },
    ]
}

/// Ensure a program is available and, when required, meets minimum version.
fn ensure_program(program: &ProgramSpec, mise_bin: &str) -> Result<(), String> {
    debug!(
        "Ensuring program '{}' with version args {:?}, min_version {:?}, mise_package '{}', and mise_version '{}'",
        program.name,
        program.version_args,
        program.min_version(),
        program.mise_package_name(),
        program.mise_version()
    );
    let inspection = inspect_program(program);
    let needs_install = match inspection {
        Ok(output_text) => {
            log_program_status(program, &output_text);
            false
        }
        Err(err) => {
            warn!(
                "Program '{}' check failed, will install via mise: {}",
                program.name, err
            );
            true
        }
    };

    if needs_install {
        install_with_mise(program, mise_bin)?;
        let output_text = inspect_program(program).map_err(|err| {
            format!(
                "Program '{}' still failed validation after mise install: {err}",
                program.name
            )
        })?;
        log_program_status(program, &output_text);
        info!("Program '{}' installed via mise", program.name);
    }

    Ok(())
}

/// Run the program version command and validate any configured minimum version.
fn inspect_program(program: &ProgramSpec) -> Result<String, String> {
    let output_text = run_command_capture_check(program.name, program.version_args)?;
    if let Some(min_version) = program.min_version() {
        if !version::is_version_at_least(&output_text, min_version) {
            return Err(format!(
                "reported version is below minimum {} (reported: {})",
                min_version, output_text
            ));
        }
    }
    Ok(output_text)
}

/// Emit the appropriate success log after a program passes inspection.
fn log_program_status(program: &ProgramSpec, output_text: &str) {
    if let Some(min_version) = program.min_version() {
        info!(
            "Program '{}' meets minimum version {} (reported: {})",
            program.name, min_version, output_text
        );
    } else {
        info!("Program '{}' is available (reported: {})", program.name, output_text);
    }
}

/// Install a program using the configured mise package selector and version.
fn install_with_mise(program: &ProgramSpec, mise_bin: &str) -> Result<(), String> {
    let tool_selector = format!("{}@{}", program.mise_package_name(), program.mise_version());
    info!(
        "Installing '{}' with selector '{}'",
        program.name, tool_selector
    );
    run_command_status(mise_bin, &["use", "-g", &tool_selector])
        .map_err(|err| format!("Failed to install {} via mise: {err}", program.name))
}

/// Run a command and capture stdout/stderr text when successful.
fn run_command_capture_check(command: &str, args: &[&str]) -> Result<String, String> {
    debug!("Running command capture: '{}' with args {:?}", command, args);
    process::run_capture(command, args).map(|output| output.trim().to_string())
}

/// Run a command and require a successful exit status.
fn run_command_status(command: &str, args: &[&str]) -> Result<(), String> {
    debug!("Running command status: '{}' with args {:?}", command, args);
    process::run_status(command, args)
}

#[cfg(test)]
mod tests {
    use super::{build_program_specs, MinimumVersionConfig, ProgramSpec};

    #[test]
    fn defaults_mise_package_name_to_requirement_name() {
        let program = ProgramSpec {
            name: "python",
            version_args: &["--version"],
            min_version: Some("3.10".to_string()),
            mise_package_name: None,
            mise_version: None,
        };
        assert_eq!(program.mise_package_name(), "python");
    }

    #[test]
    fn defaults_mise_version_to_latest() {
        let program = ProgramSpec {
            name: "uv",
            version_args: &["--version"],
            min_version: None,
            mise_package_name: None,
            mise_version: None,
        };
        assert_eq!(program.mise_version(), "latest");
    }

    #[test]
    fn allows_overriding_mise_package_name() {
        let program = ProgramSpec {
            name: "git",
            version_args: &["--version"],
            min_version: None,
            mise_package_name: Some("github-cli"),
            mise_version: None,
        };
        assert_eq!(program.mise_package_name(), "github-cli");
    }

    #[test]
    fn builds_program_specs_from_selected_minimum_versions() {
        let specs = build_program_specs(&MinimumVersionConfig {
            mise: Some("2024.11.0".to_string()),
            python: Some("3.10".to_string()),
            uv: Some("0.9.9".to_string()),
            git: None,
        });
        assert_eq!(specs[0].min_version(), Some("3.10"));
        assert_eq!(specs[1].min_version(), Some("0.9.9"));
        assert_eq!(specs[2].min_version(), None);
    }
}
