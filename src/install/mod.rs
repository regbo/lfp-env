pub mod config;
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
use self::mise::MiseInfo;
use self::platform::{create_platform, InstallContext};
use crate::cli::CliOptions;
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
    mise_info: MiseInfo,
    activation: ActivationOutput,
}

impl InstallState {
    /// Build the full installer state from env and platform detection.
    fn new(options: CliOptions) -> Result<Self, String> {
        let mut config =
            InstallConfig::from_env(options.forwarded_args, options.minimum_versions)?;
        let platform = create_platform();
        let context = platform.prepare_environment(&mut config)?;
        let mise_info = mise::ensure_available(
            platform.as_ref(),
            &context,
            config.logging_enabled,
            config.minimum_versions.mise.as_deref(),
        )?;
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

    /// Ensure default tools exist via mise, then install any requested extra tools.
    fn run_post_install_actions(&self) -> Result<(), String> {
        let mise_bin = self.mise_info.bin_path.to_string_lossy().to_string();
        self.configure_new_mise(&mise_bin)?;
        requirements::run_checks(&mise_bin, &self.config.minimum_versions)?;

        if self.config.forwarded_mise_args.is_empty() {
            return Ok(());
        }

        log_install(
            self.config.logging_enabled,
            &format!(
                "Installing extra tools with mise use -g: {}",
                self.config.forwarded_mise_args.join(" ")
            ),
        );
        let mut mise_args = vec!["use".to_string(), "-g".to_string()];
        mise_args.extend(self.config.forwarded_mise_args.clone());
        process::run_command(&mise_bin, &mise_args, &[], true).map(|_| ())
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
        process::run_command(mise_bin, &settings_args, &[], true).map(|_| ())?;
        mise::apply_bash_shims_path(&self.mise_info.bin_path)
    }
}

/// Run the installer orchestration path.
pub fn run(options: CliOptions) -> Result<(), String> {
    let mut state = InstallState::new(options)?;
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
