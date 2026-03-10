use super::config::InstallConfig;
use super::mise::MiseInfo;
use super::ActivationOutput;
use std::path::{Path, PathBuf};

/// Shared installer context prepared by a platform implementation.
pub struct InstallContext {
    pub home_dir: PathBuf,
    pub tmpdir_export_line: Option<String>,
    pub home_export_line: Option<String>,
}

/// Platform-specific installer behavior.
pub trait PlatformInstaller {
    fn prepare_environment(
        &self,
        config: &mut InstallConfig,
    ) -> Result<InstallContext, String>;

    fn append_mise_activation(
        &self,
        context: &InstallContext,
        mise_info: &MiseInfo,
        activation: &mut ActivationOutput,
    ) -> Result<(), String>;

    fn update_profiles(
        &self,
        config: &InstallConfig,
        context: &InstallContext,
        mise_info: &MiseInfo,
    ) -> Result<(), String>;

    fn render_home_relative(&self, home_dir: &Path, path: &Path) -> String;
}

#[cfg(unix)]
pub fn create_platform() -> Box<dyn PlatformInstaller> {
    Box::new(super::unix::UnixPlatform)
}

#[cfg(not(unix))]
pub fn create_platform() -> Box<dyn PlatformInstaller> {
    Box::new(super::windows::WindowsPlatform)
}
