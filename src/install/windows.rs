#[cfg(windows)]
use super::config::InstallConfig;
#[cfg(windows)]
use super::mise::MiseInfo;
#[cfg(windows)]
use super::platform::{InstallContext, PlatformInstaller};
#[cfg(windows)]
use super::profile;
#[cfg(windows)]
use super::{log_install, ActivationOutput};
#[cfg(windows)]
use std::env;
#[cfg(windows)]
use std::fs;
#[cfg(windows)]
use std::path::{Path, PathBuf};

#[cfg(windows)]
pub struct WindowsPlatform;

#[cfg(windows)]
impl PlatformInstaller for WindowsPlatform {
    fn prepare_environment(
        &self,
        config: &mut InstallConfig,
    ) -> Result<InstallContext, String> {
        let home_dir = resolve_home_dir()?;
        env::set_var("HOME", &home_dir);
        log_install(
            config.logging_enabled,
            &format!("Discovered HOME directory: {}", home_dir.display()),
        );

        Ok(InstallContext {
            home_dir,
            home_changed: false,
            tmpdir_export_line: None,
            home_export_line: None,
        })
    }

    fn append_mise_activation(
        &self,
        _context: &InstallContext,
        mise_info: &MiseInfo,
        activation: &mut ActivationOutput,
    ) -> Result<(), String> {
        let bin_dir = mise_info.install_dir.to_string_lossy().to_string();
        activation.push(format!(
            "if (-not ($env:PATH.Split(';') -contains {})) {{ $env:PATH={} }}",
            pwsh_double_quote(&bin_dir),
            pwsh_double_quote_with_suffix(&bin_dir, ";$env:PATH")
        ));
        activation.push("$miseShimActivation = (& mise activate --shims pwsh | Out-String).Trim(); if (-not [string]::IsNullOrWhiteSpace($miseShimActivation)) { Invoke-Expression $miseShimActivation }".to_string());
        Ok(())
    }

    fn update_profiles(
        &self,
        config: &InstallConfig,
        context: &InstallContext,
        mise_info: &MiseInfo,
    ) -> Result<(), String> {
        if !config.activate_profile || !mise_info.installed_now {
            return Ok(());
        }

        let profile_dir = context.home_dir.join("Documents").join("PowerShell");
        fs::create_dir_all(&profile_dir)
            .map_err(|err| format!("Could not create PowerShell profile directory {}: {err}", profile_dir.display()))?;
        let profile_path = profile_dir.join("Microsoft.PowerShell_profile.ps1");
        log_install(
            config.logging_enabled,
            &format!("Discovered profile path: {}", profile_path.display()),
        );

        let profile_line =
            "(&mise activate --shims pwsh) | Out-String | Invoke-Expression".to_string();
        profile::update_tagged_profile_line(
            &profile_path,
            &profile_line,
            "#lfp-env-activate",
            true,
            config.logging_enabled,
        )
    }

    fn render_home_relative(&self, _home_dir: &Path, path: &Path) -> String {
        path.to_string_lossy().to_string()
    }
}

#[cfg(windows)]
fn resolve_home_dir() -> Result<PathBuf, String> {
    if let Ok(home) = env::var("HOME") {
        if !home.trim().is_empty() {
            return Ok(PathBuf::from(home));
        }
    }
    if let Ok(user_profile) = env::var("USERPROFILE") {
        if !user_profile.trim().is_empty() {
            return Ok(PathBuf::from(user_profile));
        }
    }

    let home_drive = env::var("HOMEDRIVE").unwrap_or_default();
    let home_path = env::var("HOMEPATH").unwrap_or_default();
    if !home_drive.trim().is_empty() && !home_path.trim().is_empty() {
        return Ok(PathBuf::from(format!("{home_drive}{home_path}")));
    }

    Err("Could not resolve HOME on Windows".to_string())
}

#[cfg(windows)]
fn pwsh_double_quote(value: &str) -> String {
    let escaped = value.replace('`', "``").replace('"', "`\"");
    format!("\"{escaped}\"")
}

#[cfg(windows)]
fn pwsh_double_quote_with_suffix(prefix: &str, suffix: &str) -> String {
    let combined = format!("{prefix}{suffix}");
    pwsh_double_quote(&combined)
}
