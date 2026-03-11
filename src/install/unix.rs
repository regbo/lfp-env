use super::config::InstallConfig;
use super::download;
use super::mise::{self, MiseInfo};
use super::platform::{InstallContext, PlatformInstaller};
use super::process;
use super::profile;
use super::{log_install, ActivationOutput};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

/// Unix installer implementation for shell activation and profile updates.
pub struct UnixPlatform;

impl PlatformInstaller for UnixPlatform {
    fn prepare_environment(
        &self,
        config: &mut InstallConfig,
    ) -> Result<InstallContext, String> {
        let original_home = env::var("HOME").ok();
        let home_dir = resolve_home_dir()?;
        let home_changed = original_home.as_deref() != Some(home_dir.as_str());
        env::set_var("HOME", &home_dir);
        log_install(config.logging_enabled, &format!("Discovered HOME directory: {home_dir}"));

        let home_export_line = if home_changed {
            config.activate_profile = false;
            log_install(config.logging_enabled, &format!("Setting HOME to {home_dir}"));
            Some(format!("export HOME={}", shell_double_quote(&home_dir)))
        } else {
            None
        };

        let tmpdir_export_line = match resolve_tmpdir()? {
            Some(tmp_dir) => {
                log_install(config.logging_enabled, &format!("Discovered TMPDIR directory: {tmp_dir}"));
                None
            }
            None => {
                let home_tmp_dir = Path::new(&home_dir).join(".tmp");
                fs::create_dir_all(&home_tmp_dir).map_err(|err| {
                    format!(
                        "Could not create TMPDIR directory {}: {err}",
                        home_tmp_dir.display()
                    )
                })?;
                let home_tmp_dir_string = home_tmp_dir.to_string_lossy().to_string();
                env::set_var("TMPDIR", &home_tmp_dir_string);
                log_install(
                    config.logging_enabled,
                    &format!("Created TMPDIR directory: {home_tmp_dir_string}"),
                );
                log_install(
                    config.logging_enabled,
                    &format!("Setting TMPDIR to {home_tmp_dir_string}"),
                );
                Some(r"export TMPDIR=\${HOME}/.tmp".to_string())
            }
        };

        Ok(InstallContext {
            home_dir: PathBuf::from(home_dir),
            tmpdir_export_line,
            home_export_line,
        })
    }

    fn append_mise_activation(
        &self,
        context: &InstallContext,
        mise_info: &super::mise::MiseInfo,
        activation: &mut ActivationOutput,
    ) -> Result<(), String> {
        let rendered_dir = self.render_home_relative(&context.home_dir, &mise_info.install_dir);
        activation.push(build_path_activation_line(&rendered_dir));
        activation.push(r#"eval "$(mise activate --shims bash)""#.to_string());
        prepend_path(&mise_info.install_dir);
        Ok(())
    }

    fn update_profiles(
        &self,
        config: &InstallConfig,
        context: &InstallContext,
        mise_info: &MiseInfo,
    ) -> Result<(), String> {
        if !config.activate_profile {
            return Ok(());
        }
        let activate_tag = "#lfp-env-activate".to_string();
        let rendered_dir = self.render_home_relative(&context.home_dir, &mise_info.install_dir);
        let path_line = build_path_activation_line(&rendered_dir);

        let noninteractive_line = format!(r#"{path_line}; eval "$(mise activate --shims bash)""#);
        let bash_interactive_line = format!(r#"{path_line}; eval "$(mise activate bash)""#);
        let zsh_interactive_line = format!(r#"{path_line}; eval "$(mise activate zsh)""#);

        let home_dir = &context.home_dir;
        let specs = vec![
            (home_dir.join(".profile"), noninteractive_line.clone(), true),
            (home_dir.join(".bash_profile"), noninteractive_line.clone(), false),
            (home_dir.join(".zshenv"), noninteractive_line.clone(), false),
            (home_dir.join(".zprofile"), noninteractive_line, false),
            (home_dir.join(".bashrc"), bash_interactive_line, false),
            (home_dir.join(".zshrc"), zsh_interactive_line, false),
        ];

        for (profile_path, profile_line, create_if_missing) in specs {
            profile::update_tagged_profile_line(
                &profile_path,
                &profile_line,
                &activate_tag,
                create_if_missing,
                config.logging_enabled,
            )?;
        }

        Ok(())
    }

    fn find_mise_install_candidate(&self, context: &InstallContext) -> Option<PathBuf> {
        let bin_path = context.home_dir.join(".local").join("bin").join("mise");
        if bin_path.is_file() {
            return Some(bin_path);
        }
        None
    }

    fn install_mise(
        &self,
        context: &InstallContext,
        logging_enabled: bool,
    ) -> Result<MiseInfo, String> {
        let local_bin = context.home_dir.join(".local").join("bin");
        fs::create_dir_all(&local_bin).map_err(|err| {
            format!(
                "Could not create mise install directory {}: {err}",
                local_bin.display()
            )
        })?;
        let install_script = download::download_text("https://mise.run")?;
        let temp_dir = tempfile::tempdir()
            .map_err(|err| format!("Could not create temp dir for mise install: {err}"))?;
        let script_path = temp_dir.path().join("install-mise.sh");
        fs::write(&script_path, install_script).map_err(|err| {
            format!(
                "Could not write mise install script {}: {err}",
                script_path.display()
            )
        })?;
        let install_path_value = local_bin.join("mise").to_string_lossy().to_string();
        let extra_env = vec![
            ("MISE_INSTALL_PATH", install_path_value),
        ];
        let args = vec![script_path.to_string_lossy().to_string()];
        process::run_command("sh", &args, &extra_env, true).map(|_| ())?;

        let bin_path = local_bin.join("mise");
        if !bin_path.is_file() {
            return Err("mise installation failed".to_string());
        }
        mise::verify_mise_binary(&bin_path, logging_enabled, None)?;
        mise::resolve_mise_info(bin_path, true)
    }

    fn render_home_relative(&self, home_dir: &Path, path: &Path) -> String {
        if path == home_dir {
            return "${HOME}".to_string();
        }
        if let Ok(relative_path) = path.strip_prefix(home_dir) {
            if relative_path.as_os_str().is_empty() {
                return "${HOME}".to_string();
            }
            return format!("${{HOME}}/{}", relative_path.to_string_lossy());
        }
        path.to_string_lossy().to_string()
    }

}

fn resolve_home_dir() -> Result<String, String> {
    if let Ok(home) = env::var("HOME") {
        if !home.trim().is_empty() {
            return Ok(home);
        }
    }

    for candidate in ["/home", "/home/app"] {
        let path = Path::new(candidate);
        if path.is_dir() && is_writable_dir(path) {
            return Ok(candidate.to_string());
        }
    }

    let fallback = env::current_dir()
        .map_err(|err| format!("Could not resolve current directory for HOME fallback: {err}"))?
        .join("home");
    fs::create_dir_all(&fallback)
        .map_err(|err| format!("Could not create HOME fallback directory {}: {err}", fallback.display()))?;
    Ok(fallback.to_string_lossy().to_string())
}

fn resolve_tmpdir() -> Result<Option<String>, String> {
    for name in ["TMPDIR", "TMP", "TEMP", "TEMPDIR"] {
        if let Ok(value) = env::var(name) {
            if !value.trim().is_empty() && is_writable_dir(Path::new(&value)) {
                return Ok(Some(value));
            }
        }
    }

    for candidate in ["/tmp", "/var/tmp", "/usr/tmp"] {
        let path = Path::new(candidate);
        if path.is_dir() && is_writable_dir(path) {
            return Ok(Some(candidate.to_string()));
        }
    }

    Ok(None)
}

fn is_writable_dir(path: &Path) -> bool {
    if !path.is_dir() {
        return false;
    }
    let probe_path = path.join(format!(".lfp-env-write-probe-{}", std::process::id()));
    match fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&probe_path)
    {
        Ok(_) => {
            let _ = fs::remove_file(&probe_path);
            true
        }
        Err(_) => false,
    }
}

fn prepend_path(path: &Path) {
    let current_path = env::var_os("PATH").unwrap_or_default();
    let path_value = path.to_string_lossy();
    let current_text = current_path.to_string_lossy();
    let needle = format!(":{path_value}:");
    let haystack = format!(":{current_text}:");
    if haystack.contains(&needle) {
        return;
    }

    if current_text.is_empty() {
        env::set_var("PATH", path_value.to_string());
        return;
    }
    env::set_var("PATH", format!("{path_value}:{current_text}"));
}

fn shell_double_quote(value: &str) -> String {
    let escaped = value.replace('\\', "\\\\").replace('"', "\\\"");
    format!("\"{escaped}\"")
}

/// Build the reusable Unix PATH activation snippet for the resolved mise install directory.
fn build_path_activation_line(rendered_dir: &str) -> String {
    format!(
        "MISE_INSTALL_DIR={}; case \":$PATH:\" in *\":$MISE_INSTALL_DIR:\"*) ;; *) export PATH=\"$MISE_INSTALL_DIR:$PATH\";; esac",
        shell_double_quote(rendered_dir)
    )
}
