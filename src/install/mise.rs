use super::log_install;
#[cfg(not(windows))]
use super::download;
use super::platform::{InstallContext, PlatformInstaller};
use super::process;
#[cfg(windows)]
use serde::Deserialize;
use std::fs;
#[cfg(windows)]
use std::io::{self, Cursor};
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
) -> Result<MiseInfo, String> {
    if let Some(bin_path) = find_mise_path() {
        if verify_mise_binary(&bin_path, logging_enabled).is_ok() {
            let mise_info = resolve_mise_info(bin_path, false)?;
            log_mise_info(platform, context, logging_enabled, &mise_info);
            return Ok(mise_info);
        }
    }

    if let Some(bin_path) = find_mise_in_install_location(context) {
        if verify_mise_binary(&bin_path, logging_enabled).is_ok() {
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
    let mise_info = install_mise(platform, context, logging_enabled)?;
    log_mise_info(platform, context, logging_enabled, &mise_info);
    Ok(mise_info)
}

#[cfg(not(windows))]
fn install_mise(
    _platform: &dyn PlatformInstaller,
    context: &InstallContext,
    logging_enabled: bool,
) -> Result<MiseInfo, String> {
    let local_bin = context.home_dir.join(".local").join("bin");
    fs::create_dir_all(&local_bin)
        .map_err(|err| format!("Could not create mise install directory {}: {err}", local_bin.display()))?;
    let install_script = download::download_text("https://mise.run")?;
    let temp_dir = tempfile::tempdir().map_err(|err| format!("Could not create temp dir for mise install: {err}"))?;
    let script_path = temp_dir.path().join("install-mise.sh");
    fs::write(&script_path, install_script)
        .map_err(|err| format!("Could not write mise install script {}: {err}", script_path.display()))?;
    let install_dir_value = local_bin.to_string_lossy().to_string();
    let install_path_value = local_bin.join("mise").to_string_lossy().to_string();
    let extra_env = vec![
        ("MISE_INSTALL_DIR", install_dir_value),
        ("MISE_INSTALL_PATH", install_path_value),
    ];
    let args = vec![script_path.to_string_lossy().to_string()];
    process::run_command("sh", &args, &extra_env, true).map(|_| ())?;

    let bin_path = local_bin.join("mise");
    if !bin_path.is_file() {
        return Err("mise installation failed".to_string());
    }
    verify_mise_binary(&bin_path, logging_enabled)?;

    Ok(MiseInfo {
        bin_path,
        install_dir: local_bin,
        shim_path: None,
        installed_now: true,
    })
}

#[cfg(windows)]
fn install_mise(
    _platform: &dyn PlatformInstaller,
    _context: &InstallContext,
    logging_enabled: bool,
) -> Result<MiseInfo, String> {
    let release = latest_mise_release()?;
    let asset_name = format!("mise-{}-windows-{}.zip", release.tag_name, detect_windows_arch()?);
    let download_url = format!(
        "https://github.com/jdx/mise/releases/download/{}/{}",
        release.tag_name, asset_name
    );

    log_install(logging_enabled, &format!("Downloading {download_url}"));
    let archive_bytes = download_bytes(&download_url)?;
    let temp_dir = tempfile::tempdir().map_err(|err| format!("Could not create temp dir for mise install: {err}"))?;
    let archive_path = temp_dir.path().join(&asset_name);
    fs::write(&archive_path, &archive_bytes)
        .map_err(|err| format!("Could not write mise archive {}: {err}", archive_path.display()))?;

    let install_dir = localappdata_bin_dir()?;
    fs::create_dir_all(&install_dir)
        .map_err(|err| format!("Could not create mise install directory {}: {err}", install_dir.display()))?;
    log_install(logging_enabled, &format!("Preparing {}", install_dir.display()));
    log_install(logging_enabled, &format!("Using download file {}", archive_path.display()));
    log_install(logging_enabled, &format!("Using extract directory {}", temp_dir.path().display()));

    let (mise_exe_bytes, shim_exe_bytes) = extract_mise_zip(&archive_bytes)?;
    let bin_path = install_dir.join("mise.exe");
    fs::write(&bin_path, mise_exe_bytes)
        .map_err(|err| format!("Could not write mise executable {}: {err}", bin_path.display()))?;
    log_install(logging_enabled, &format!("Copied extracted mise.exe to {}", bin_path.display()));

    let shim_path = match shim_exe_bytes {
        Some(shim_bytes) => {
            let shim_path = install_dir.join("mise-shim.exe");
            fs::write(&shim_path, shim_bytes)
                .map_err(|err| format!("Could not write mise shim {}: {err}", shim_path.display()))?;
            log_install(logging_enabled, &format!("Copied extracted mise-shim.exe to {}", shim_path.display()));
            Some(shim_path)
        }
        None => None,
    };

    let user_path = read_user_path().unwrap_or_default();
    log_install(logging_enabled, &format!("Discovered user PATH: {user_path}"));
    ensure_windows_path_contains(&install_dir, &user_path, logging_enabled)?;

    log_install(logging_enabled, &format!("Installed to {}", install_dir.display()));
    verify_mise_binary(&bin_path, logging_enabled)?;

    Ok(MiseInfo {
        bin_path,
        install_dir,
        shim_path,
        installed_now: true,
    })
}

/// Build the shared `mise` metadata used by activation and profile updates.
fn resolve_mise_info(bin_path: PathBuf, installed_now: bool) -> Result<MiseInfo, String> {
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
fn verify_mise_binary(bin_path: &Path, logging_enabled: bool) -> Result<(), String> {
    let version_args = ["-v"];
    match process::run_command(bin_path.to_string_lossy().as_ref(), &version_args, &[], false) {
        Ok(version_output) => {
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

/// Probe the default install location before downloading a fresh `mise` copy.
fn find_mise_in_install_location(context: &InstallContext) -> Option<PathBuf> {
    let bin_path = expected_mise_bin_path(context)?;
    if bin_path.is_file() {
        return Some(bin_path);
    }
    None
}

#[cfg(not(windows))]
fn expected_mise_bin_path(context: &InstallContext) -> Option<PathBuf> {
    Some(context.home_dir.join(".local").join("bin").join("mise"))
}

#[cfg(windows)]
fn expected_mise_bin_path(_context: &InstallContext) -> Option<PathBuf> {
    localappdata_bin_dir().ok().map(|dir| dir.join("mise.exe"))
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

#[cfg(windows)]
fn download_bytes(url: &str) -> Result<Vec<u8>, String> {
    let client = reqwest::blocking::Client::builder()
        .build()
        .map_err(|err| format!("Could not build HTTP client: {err}"))?;
    let response = client
        .get(url)
        .header(reqwest::header::USER_AGENT, "lfp-env-installer")
        .send()
        .map_err(|err| format!("Could not download {url}: {err}"))?;
    let response = response
        .error_for_status()
        .map_err(|err| format!("Download failed for {url}: {err}"))?;
    response
        .bytes()
        .map(|bytes| bytes.to_vec())
        .map_err(|err| format!("Could not read downloaded bytes from {url}: {err}"))
}

#[cfg(windows)]
#[derive(Deserialize)]
struct GithubRelease {
    tag_name: String,
}

#[cfg(windows)]
fn latest_mise_release() -> Result<GithubRelease, String> {
    let client = reqwest::blocking::Client::builder()
        .build()
        .map_err(|err| format!("Could not build HTTP client: {err}"))?;
    let response = client
        .get("https://api.github.com/repos/jdx/mise/releases/latest")
        .header(reqwest::header::USER_AGENT, "lfp-env-installer")
        .send()
        .map_err(|err| format!("Could not query mise latest release: {err}"))?;
    let response = response
        .error_for_status()
        .map_err(|err| format!("GitHub latest release request failed: {err}"))?;
    response
        .json::<GithubRelease>()
        .map_err(|err| format!("Could not parse mise latest release response: {err}"))
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
fn ensure_windows_path_contains(install_dir: &Path, user_path: &str, logging_enabled: bool) -> Result<(), String> {
    let install_dir_text = install_dir.to_string_lossy().to_string();
    if user_path_contains(user_path, &install_dir_text) {
        ensure_process_path_contains(&install_dir_text);
        return Ok(());
    }

    log_install(logging_enabled, &format!("Adding {} to PATH", install_dir.display()));
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
