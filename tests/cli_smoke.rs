use std::path::PathBuf;
use std::process::Command;

/// Smoke test the built binary and keep assertions minimal.
#[test]
fn version_flag_prints_raw_semver() {
    let output = Command::new(installer_binary_path())
        .arg("--version")
        .output()
        .expect("expected lfp-env binary to start");

    assert!(
        output.status.success(),
        "lfp-env --version failed with status {}.\nstdout:\n{}\nstderr:\n{}",
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let version_text = String::from_utf8_lossy(&output.stdout);
    assert_raw_semver(version_text.trim());
}

/// Resolve the compiled test binary path provided by Cargo.
fn installer_binary_path() -> PathBuf {
    if let Some(path_text) = option_env!("CARGO_BIN_EXE_lfp-env") {
        let path = PathBuf::from(path_text);
        if path.is_file() {
            return path;
        }
    }
    if let Some(path_text) = option_env!("CARGO_BIN_EXE_lfp_env") {
        let path = PathBuf::from(path_text);
        if path.is_file() {
            return path;
        }
    }

    panic!("expected Cargo to provide the compiled lfp-env binary path for integration tests");
}

/// Assert that a version string is plain machine-readable semver.
fn assert_raw_semver(version_text: &str) {
    let parts: Vec<&str> = version_text.split('.').collect();
    assert_eq!(
        parts.len(),
        3,
        "expected raw semver with three numeric parts, got: {version_text}"
    );
    assert!(
        parts
            .iter()
            .all(|part| !part.is_empty() && part.chars().all(|character| character.is_ascii_digit())),
        "expected raw semver with numeric parts only, got: {version_text}"
    );
}
