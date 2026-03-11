use super::log_install;
use super::platform::{InstallContext, PlatformInstaller};
use super::process;
use crate::version;
use log::debug;
use std::env;
use std::path::{Path, PathBuf};

/// Resolved `mise` details after discovery or installation.
pub struct MiseInfo {
    pub bin_path: PathBuf,
    pub install_dir: PathBuf,
    pub shim_path: Option<PathBuf>,
    pub installed_now: bool,
}

/// Ensure `mise` is available for the rest of the installer flow.
pub fn ensure_available(
    platform: &dyn PlatformInstaller,
    context: &InstallContext,
    logging_enabled: bool,
    min_version: Option<&str>,
) -> Result<MiseInfo, String> {
    if let Some(bin_path) = find_mise_path() {
        if verify_mise_binary(&bin_path, logging_enabled, min_version).is_ok() {
            let mise_info = resolve_mise_info(bin_path, false)?;
            log_mise_info(platform, context, logging_enabled, &mise_info);
            return Ok(mise_info);
        }
    }

    if let Some(bin_path) = platform.find_mise_install_candidate(context) {
        if verify_mise_binary(&bin_path, logging_enabled, min_version).is_ok() {
            log_install(
                logging_enabled,
                &format!(
                    "mise not found on PATH. Reusing existing install at {}",
                    bin_path.display()
                ),
            );
            let mise_info = resolve_mise_info(bin_path, false)?;
            log_mise_info(platform, context, logging_enabled, &mise_info);
            return Ok(mise_info);
        }
    }

    log_install(
        logging_enabled,
        "mise not found on PATH or in the install location. Installing.",
    );
    let mise_info = platform.install_mise(context, logging_enabled)?;
    verify_mise_binary(&mise_info.bin_path, logging_enabled, min_version)?;
    log_mise_info(platform, context, logging_enabled, &mise_info);
    Ok(mise_info)
}

/// Apply the PATH exported by `mise activate --shims bash` to the current process.
pub fn apply_bash_shims_path(bin_path: &Path) -> Result<(), String> {
    #[cfg(not(unix))]
    {
        let _ = bin_path;
        return Ok(());
    }

    #[cfg(unix)]
    {
        let activation_output = process::run_capture(
            bin_path.to_string_lossy().as_ref(),
            &["activate", "--shims", "bash"],
        )?;
        let Some(exported_path) = extract_exported_path(&activation_output) else {
            debug!(
                "No PATH export found in 'mise activate --shims bash' output, leaving PATH unchanged"
            );
            return Ok(());
        };
        let resolved_path = resolve_exported_path(&exported_path);
        debug!(
            "Applying PATH from 'mise activate --shims bash': {}",
            resolved_path
        );
        env::set_var("PATH", resolved_path);
        Ok(())
    }
}

/// Build the shared `mise` metadata used by activation and profile updates.
pub(crate) fn resolve_mise_info(bin_path: PathBuf, installed_now: bool) -> Result<MiseInfo, String> {
    let install_dir = parent_dir(&bin_path)?;
    let shim_path = find_mise_shim_path(&install_dir);
    Ok(MiseInfo {
        bin_path,
        install_dir,
        shim_path,
        installed_now,
    })
}

/// Verify that the resolved `mise` binary can answer `-v` before reuse.
pub(crate) fn verify_mise_binary(
    bin_path: &Path,
    logging_enabled: bool,
    min_version: Option<&str>,
) -> Result<(), String> {
    let version_args = ["-v"];
    match process::run_command(bin_path.to_string_lossy().as_ref(), &version_args, &[], false) {
        Ok(version_output) => {
            if let Some(min_version) = min_version {
                if !version::is_version_at_least(&version_output, min_version) {
                    let mismatch = format!(
                        "reported version is below minimum {} (reported: {})",
                        min_version,
                        version_output.trim()
                    );
                    log_install(
                        logging_enabled,
                        &format!(
                            "Ignoring outdated mise binary {}: {mismatch}",
                            bin_path.display()
                        ),
                    );
                    return Err(format!(
                        "mise binary {} failed verification: {mismatch}",
                        bin_path.display()
                    ));
                }
            }
            log_install(
                logging_enabled,
                &format!(
                    "Verified mise binary {} with version output: {}",
                    bin_path.display(),
                    version_output.trim()
                ),
            );
            Ok(())
        }
        Err(err) => {
            log_install(
                logging_enabled,
                &format!(
                    "Ignoring unusable mise binary {}: {err}",
                    bin_path.display()
                ),
            );
            Err(format!(
                "mise binary {} failed verification: {err}",
                bin_path.display()
            ))
        }
    }
}

/// Log the resolved `mise` location details once discovery or installation completes.
fn log_mise_info(
    platform: &dyn PlatformInstaller,
    context: &InstallContext,
    logging_enabled: bool,
    mise_info: &MiseInfo,
) {
    log_install(
        logging_enabled,
        &format!(
            "Discovered mise install directory: {}",
            mise_info.install_dir.display()
        ),
    );
    log_install(
        logging_enabled,
        &format!(
            "Rendered mise install directory: {}",
            platform.render_home_relative(&context.home_dir, &mise_info.install_dir)
        ),
    );
    log_install(
        logging_enabled,
        &format!("mise binary found: {}", mise_info.bin_path.display()),
    );
    if let Some(shim_path) = &mise_info.shim_path {
        log_install(
            logging_enabled,
            &format!("Discovered mise shim path: {}", shim_path.display()),
        );
    }
    if mise_info.installed_now {
        log_install(logging_enabled, "Installed mise during this run.");
    }
}

fn find_mise_path() -> Option<PathBuf> {
    which::which("mise").ok().or_else(|| which::which("mise.exe").ok())
}

fn find_mise_shim_path(install_dir: &Path) -> Option<PathBuf> {
    let shim_path = install_dir.join(if cfg!(windows) { "mise-shim.exe" } else { "mise-shim" });
    if shim_path.is_file() {
        return Some(shim_path);
    }
    None
}

fn parent_dir(path: &Path) -> Result<PathBuf, String> {
    path.parent()
        .map(Path::to_path_buf)
        .ok_or_else(|| format!("Could not determine parent directory for {}", path.display()))
}

/// Extract the PATH assignment emitted by `mise activate --shims bash`.
fn extract_exported_path(activation_output: &str) -> Option<String> {
    activation_output.lines().find_map(|line| {
        let trimmed = line.trim();
        let path_value = trimmed.strip_prefix("export PATH=")?;
        Some(unquote_shell_value(path_value))
    })
}

/// Resolve a shell PATH assignment by expanding the current process PATH placeholder.
fn resolve_exported_path(path_value: &str) -> String {
    let current_path = env::var("PATH").unwrap_or_default();
    path_value
        .replace("${PATH}", &current_path)
        .replace("$PATH", &current_path)
}

/// Remove a single layer of matching shell quotes around an exported value.
fn unquote_shell_value(value: &str) -> String {
    if value.len() >= 2 {
        let bytes = value.as_bytes();
        let first = bytes[0];
        let last = bytes[value.len() - 1];
        if (first == b'"' && last == b'"') || (first == b'\'' && last == b'\'') {
            return value[1..value.len() - 1].to_string();
        }
    }
    value.to_string()
}

#[cfg(test)]
mod tests {
    use super::{extract_exported_path, resolve_exported_path, unquote_shell_value};

    #[test]
    fn extracts_exported_path_from_activation_output() {
        let output = "export PATH=\"/tmp/mise/shims:/tmp/bin:$PATH\"\nexport MISE_SHELL=bash";
        assert_eq!(
            extract_exported_path(output).as_deref(),
            Some("/tmp/mise/shims:/tmp/bin:$PATH")
        );
    }

    #[test]
    fn ignores_activation_output_without_path_export() {
        let output = "export MISE_SHELL=bash";
        assert_eq!(extract_exported_path(output), None);
    }

    #[test]
    fn resolves_path_placeholders_against_current_process_path() {
        let original_path = std::env::var("PATH").ok();
        std::env::set_var("PATH", "/usr/bin:/bin");
        assert_eq!(
            resolve_exported_path("/tmp/mise/shims:$PATH"),
            "/tmp/mise/shims:/usr/bin:/bin"
        );
        match original_path {
            Some(path) => std::env::set_var("PATH", path),
            None => std::env::remove_var("PATH"),
        }
    }

    #[test]
    fn unquotes_shell_values() {
        assert_eq!(unquote_shell_value("\"/tmp/path\""), "/tmp/path");
        assert_eq!(unquote_shell_value("'/tmp/path'"), "/tmp/path");
        assert_eq!(unquote_shell_value("/tmp/path"), "/tmp/path");
    }
}
