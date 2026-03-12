#[cfg(windows)]
use super::config::InstallConfig;
#[cfg(windows)]
use super::mise::{self, MiseInfo};
#[cfg(windows)]
use super::platform::{InstallContext, PlatformInstaller};
#[cfg(windows)]
use super::profile;
#[cfg(windows)]
use serde::de::DeserializeOwned;
#[cfg(windows)]
use super::{log_install, ActivationOutput};
#[cfg(windows)]
use serde::Deserialize;
#[cfg(windows)]
use std::env;
#[cfg(windows)]
use std::fs;
#[cfg(windows)]
use std::io::{self, Cursor};
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

    fn find_mise_install_candidate(&self, _context: &InstallContext) -> Option<PathBuf> {
        localappdata_bin_dir().ok().map(|dir| dir.join("mise.exe"))
    }

    fn install_mise(
        &self,
        _context: &InstallContext,
        logging_enabled: bool,
    ) -> Result<MiseInfo, String> {
        let release = latest_mise_release()?;
        let asset_name = format!(
            "mise-{}-windows-{}.zip",
            release.tag_name,
            detect_windows_arch()?
        );
        let download_url = format!(
            "https://github.com/jdx/mise/releases/download/{}/{}",
            release.tag_name, asset_name
        );

        log_install(logging_enabled, &format!("Downloading {download_url}"));
        let archive_bytes = download_bytes(&download_url)?;
        let temp_dir = tempfile::tempdir()
            .map_err(|err| format!("Could not create temp dir for mise install: {err}"))?;
        let archive_path = temp_dir.path().join(&asset_name);
        fs::write(&archive_path, &archive_bytes).map_err(|err| {
            format!(
                "Could not write mise archive {}: {err}",
                archive_path.display()
            )
        })?;

        let install_dir = localappdata_bin_dir()?;
        fs::create_dir_all(&install_dir).map_err(|err| {
            format!(
                "Could not create mise install directory {}: {err}",
                install_dir.display()
            )
        })?;
        log_install(logging_enabled, &format!("Preparing {}", install_dir.display()));
        log_install(
            logging_enabled,
            &format!("Using download file {}", archive_path.display()),
        );
        log_install(
            logging_enabled,
            &format!("Using extract directory {}", temp_dir.path().display()),
        );

        let (mise_exe_bytes, shim_exe_bytes) = extract_mise_zip(&archive_bytes)?;
        let bin_path = install_dir.join("mise.exe");
        fs::write(&bin_path, mise_exe_bytes).map_err(|err| {
            format!(
                "Could not write mise executable {}: {err}",
                bin_path.display()
            )
        })?;
        log_install(
            logging_enabled,
            &format!("Copied extracted mise.exe to {}", bin_path.display()),
        );

        if let Some(shim_bytes) = shim_exe_bytes {
            let shim_path = install_dir.join("mise-shim.exe");
            fs::write(&shim_path, shim_bytes).map_err(|err| {
                format!("Could not write mise shim {}: {err}", shim_path.display())
            })?;
            log_install(
                logging_enabled,
                &format!("Copied extracted mise-shim.exe to {}", shim_path.display()),
            );
        }

        let user_path = read_user_path().unwrap_or_default();
        log_install(logging_enabled, &format!("Discovered user PATH: {user_path}"));
        ensure_windows_path_contains(&install_dir, &user_path, logging_enabled)?;

        log_install(logging_enabled, &format!("Installed to {}", install_dir.display()));
        mise::resolve_mise_info(bin_path, true)
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

#[cfg(windows)]
#[derive(Deserialize)]
struct GithubRelease {
    tag_name: String,
}

#[cfg(windows)]
fn latest_mise_release() -> Result<GithubRelease, String> {
    download_json("https://api.github.com/repos/jdx/mise/releases/latest")
        .map_err(|err| format!("Could not query mise latest release: {err}"))
}

#[cfg(windows)]
fn build_http_client() -> Result<reqwest::blocking::Client, String> {
    reqwest::blocking::Client::builder()
        .build()
        .map_err(|err| format!("Could not build HTTP client: {err}"))
}

#[cfg(windows)]
fn get_http_response(url: &str) -> Result<reqwest::blocking::Response, String> {
    let response = build_http_client()?
        .get(url)
        .header(reqwest::header::USER_AGENT, "lfp-env-installer")
        .send()
        .map_err(|err| format!("Could not download {url}: {err}"))?;
    response
        .error_for_status()
        .map_err(|err| format!("Download failed for {url}: {err}"))
}

#[cfg(windows)]
fn download_bytes(url: &str) -> Result<Vec<u8>, String> {
    get_http_response(url)?
        .bytes()
        .map(|bytes| bytes.to_vec())
        .map_err(|err| format!("Could not read downloaded bytes from {url}: {err}"))
}

#[cfg(windows)]
fn download_json<T>(url: &str) -> Result<T, String>
where
    T: DeserializeOwned,
{
    get_http_response(url)?
        .json::<T>()
        .map_err(|err| format!("Could not parse JSON response from {url}: {err}"))
}

#[cfg(windows)]
fn detect_windows_arch() -> Result<&'static str, String> {
    match std::env::consts::ARCH {
        "x86_64" => Ok("x64"),
        "aarch64" => Ok("arm64"),
        other => Err(format!("unsupported windows architecture: {other}")),
    }
}

#[cfg(windows)]
fn localappdata_bin_dir() -> Result<PathBuf, String> {
    let localappdata = std::env::var("LOCALAPPDATA")
        .map_err(|_| "LOCALAPPDATA is not set".to_string())?;
    Ok(PathBuf::from(localappdata).join("bin"))
}

#[cfg(windows)]
fn extract_mise_zip(archive_bytes: &[u8]) -> Result<(Vec<u8>, Option<Vec<u8>>), String> {
    let cursor = Cursor::new(archive_bytes);
    let mut archive = zip::ZipArchive::new(cursor)
        .map_err(|err| format!("Could not open mise zip archive: {err}"))?;
    let mut mise_exe = None;
    let mut mise_shim = None;

    for index in 0..archive.len() {
        let mut file = archive
            .by_index(index)
            .map_err(|err| format!("Could not read mise zip entry {index}: {err}"))?;
        let name = file.name().replace('\\', "/");
        if name.ends_with("/mise.exe") {
            let mut bytes = Vec::new();
            io::copy(&mut file, &mut bytes)
                .map_err(|err| format!("Could not extract mise.exe: {err}"))?;
            mise_exe = Some(bytes);
        } else if name.ends_with("/mise-shim.exe") {
            let mut bytes = Vec::new();
            io::copy(&mut file, &mut bytes)
                .map_err(|err| format!("Could not extract mise-shim.exe: {err}"))?;
            mise_shim = Some(bytes);
        }
    }

    let mise_exe = mise_exe.ok_or_else(|| "mise.exe not found in archive".to_string())?;
    Ok((mise_exe, mise_shim))
}

#[cfg(windows)]
fn ensure_windows_path_contains(
    install_dir: &Path,
    user_path: &str,
    logging_enabled: bool,
) -> Result<(), String> {
    let install_dir_text = install_dir.to_string_lossy().to_string();
    if user_path_contains(user_path, &install_dir_text) {
        ensure_process_path_contains(&install_dir_text);
        return Ok(());
    }

    log_install(
        logging_enabled,
        &format!("Adding {} to PATH", install_dir.display()),
    );
    write_user_path(&prepend_path_entry(&install_dir_text, user_path))?;
    ensure_process_path_contains(&install_dir_text);
    Ok(())
}

#[cfg(windows)]
fn user_path_contains(user_path: &str, entry: &str) -> bool {
    user_path
        .split(';')
        .any(|segment| segment.eq_ignore_ascii_case(entry))
}

#[cfg(windows)]
fn prepend_path_entry(entry: &str, path_value: &str) -> String {
    if path_value.trim().is_empty() {
        return entry.to_string();
    }
    format!("{entry};{path_value}")
}

#[cfg(windows)]
fn ensure_process_path_contains(entry: &str) {
    let current_path = std::env::var("PATH").unwrap_or_default();
    if user_path_contains(&current_path, entry) {
        return;
    }
    let next_path = prepend_path_entry(entry, &current_path);
    std::env::set_var("PATH", next_path);
}

#[cfg(windows)]
fn read_user_path() -> Result<String, String> {
    use winreg::enums::HKEY_CURRENT_USER;
    use winreg::RegKey;

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let env_key = hkcu
        .open_subkey("Environment")
        .map_err(|err| format!("Could not open HKCU\\Environment: {err}"))?;
    match env_key.get_value::<String, _>("Path") {
        Ok(value) => Ok(value),
        Err(_) => Ok(String::new()),
    }
}

#[cfg(windows)]
fn write_user_path(value: &str) -> Result<(), String> {
    use winreg::enums::HKEY_CURRENT_USER;
    use winreg::RegKey;

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let (env_key, _) = hkcu
        .create_subkey("Environment")
        .map_err(|err| format!("Could not create HKCU\\Environment: {err}"))?;
    env_key
        .set_value("Path", &value)
        .map_err(|err| format!("Could not update user PATH: {err}"))
}
