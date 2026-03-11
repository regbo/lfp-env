use std::ffi::OsStr;
use std::io::{self, Write};
use std::process::Command;

/// Run a command, optionally mirror output to stderr, and return combined text.
pub fn run_command<S>(
    command: &str,
    args: &[S],
    extra_env: &[(&str, String)],
    mirror_to_stderr: bool,
) -> Result<String, String>
where
    S: AsRef<OsStr>,
{
    let output = Command::new(command)
        .args(args.iter().map(AsRef::as_ref))
        .envs(extra_env.iter().map(|(key, value)| (*key, value)))
        .output()
        .map_err(|err| format!("Could not start '{command}': {err}"))?;
    let stdout_text = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr_text = String::from_utf8_lossy(&output.stderr).to_string();

    if mirror_to_stderr {
        write_to_stderr(&output.stdout)
            .map_err(|err| format!("Failed to write command stdout: {err}"))?;
        write_to_stderr(&output.stderr)
            .map_err(|err| format!("Failed to write command stderr: {err}"))?;
    }

    if !output.status.success() {
        return Err(format!(
            "Command '{command}' failed with status {}. stdout={:?} stderr={:?}",
            output.status,
            stdout_text.trim(),
            stderr_text.trim()
        ));
    }

    if !stdout_text.trim().is_empty() {
        return Ok(stdout_text);
    }
    Ok(stderr_text)
}

/// Run a command and return captured output without mirroring streams.
pub fn run_capture<S>(command: &str, args: &[S]) -> Result<String, String>
where
    S: AsRef<OsStr>,
{
    run_command(command, args, &[], false)
}

/// Run a command and require success without keeping its output.
pub fn run_status<S>(command: &str, args: &[S]) -> Result<(), String>
where
    S: AsRef<OsStr>,
{
    run_command(command, args, &[], false).map(|_| ())
}

fn write_to_stderr(bytes: &[u8]) -> io::Result<()> {
    if bytes.is_empty() {
        return Ok(());
    }
    let mut stderr = io::stderr().lock();
    stderr.write_all(bytes)?;
    stderr.flush()
}
