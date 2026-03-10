pub mod config;
#[cfg(not(windows))]
pub mod download;
pub mod mise;
pub mod platform;
pub mod process;
pub mod profile;
#[cfg(unix)]
pub mod unix;
#[cfg(windows)]
pub mod windows;

use self::config::InstallConfig;
use self::platform::create_platform;
use self::platform::InstallContext;
use crate::requirements;
use log::info;

/// Installer activation lines that are emitted on stdout for shell eval.
#[derive(Default)]
pub struct ActivationOutput {
    lines: Vec<String>,
}

impl ActivationOutput {
    /// Add a shell-safe activation line.
    pub fn push(&mut self, line: String) {
        self.lines.push(line);
    }

    /// Print the final activation snippet as a single eval-safe line.
    pub fn print(&self) {
        if self.lines.is_empty() {
            println!();
            return;
        }
        println!("{}", self.lines.join(";"));
    }
}

/// Shared installer state passed through the Unix install flow.
struct InstallState {
    config: InstallConfig,
    platform: Box<dyn platform::PlatformInstaller>,
    context: InstallContext,
    mise_info: mise::MiseInfo,
    activation: ActivationOutput,
}

impl InstallState {
    /// Build the full installer state from env and platform detection.
    fn new(forwarded_mise_args: Vec<String>) -> Result<Self, String> {
        let mut config = InstallConfig::from_env(forwarded_mise_args)?;
        let platform = create_platform();
        let context = platform.prepare_environment(&mut config)?;
        let mise_info = mise::ensure_available(platform.as_ref(), &context, config.logging_enabled)?;
        Ok(Self {
            config,
            platform,
            context,
            mise_info,
            activation: ActivationOutput::default(),
        })
    }

    /// Populate activation output with environment and mise setup.
    fn build_activation(&mut self) -> Result<(), String> {
        if let Some(home_export_line) = self.context.home_export_line.clone() {
            self.activation.push(home_export_line);
        }
        if let Some(tmpdir_export_line) = self.context.tmpdir_export_line.clone() {
            self.activation.push(tmpdir_export_line);
        }
        self.platform
            .append_mise_activation(&self.context, &self.mise_info, &mut self.activation)?;
        if cfg!(unix) {
            self.activation.push("hash -r 2>/dev/null || true".to_string());
        }
        Ok(())
    }

    /// Update shell profiles after activation has been prepared.
    fn update_profiles(&self) -> Result<(), String> {
        self.platform
            .update_profiles(&self.config, &self.context, &self.mise_info)
    }

    /// Ensure default tools exist via mise, then forward remaining args to mise directly.
    fn run_post_install_actions(&self) -> Result<(), String> {
        if self.config.disable_run {
            return Ok(());
        }

        let mise_bin = self.mise_info.bin_path.to_string_lossy().to_string();
        self.configure_new_mise(&mise_bin)?;
        requirements::run_checks(&mise_bin)?;

        if self.config.forwarded_mise_args.is_empty() {
            return Ok(());
        }

        log_install(
            self.config.logging_enabled,
            &format!(
                "Forwarding arguments to mise: {}",
                self.config.forwarded_mise_args.join(" ")
            ),
        );
        process::run_command(&mise_bin, &self.config.forwarded_mise_args, &[], true).map(|_| ())
    }

    /// Apply one-time settings immediately after a fresh `mise` install.
    fn configure_new_mise(&self, mise_bin: &str) -> Result<(), String> {
        if !self.mise_info.installed_now {
            return Ok(());
        }

        log_install(
            self.config.logging_enabled,
            "Enabling mise experimental settings for this new install.",
        );
        let settings_args = ["settings", "experimental=true"];
        process::run_command(mise_bin, &settings_args, &[], true).map(|_| ())
    }
}

/// Run the installer orchestration path.
pub fn run(forwarded_mise_args: Vec<String>) -> Result<(), String> {
    let mut state = InstallState::new(forwarded_mise_args)?;
    state.build_activation()?;
    state.update_profiles()?;
    state.activation.print();
    state.run_post_install_actions()?;
    Ok(())
}

pub fn log_install(enabled: bool, message: &str) {
    if enabled {
        info!("{message}");
    }
}
