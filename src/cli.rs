use crate::install::config::MinimumVersionConfig;
use clap::{ArgAction, Parser, Subcommand};
use log::LevelFilter;
use std::ffi::OsString;

const DEFAULT_LOG_LEVEL: &str = "info";
const DEFAULT_PYTHON_MIN_VERSION: &str = "3.10";
const DEFAULT_UV_MIN_VERSION: &str = "0.9.9";

/// Command-line options for `lfp-env`.
#[derive(Debug, PartialEq, Eq)]
pub struct CliOptions {
    /// Print the raw crate version for machine comparisons.
    pub print_version: bool,

    /// Set log verbosity for runtime checks (error, warn, info, debug, trace, off).
    /// Reads LFP_ENV_LOG_LEVEL by default when not provided on CLI.
    pub log_level: LevelFilter,

    /// Minimum version checks applied before reusing or installing tools.
    pub minimum_versions: MinimumVersionConfig,

    /// Extra package selectors to install with `mise use -g` after setup completes.
    pub forwarded_args: Vec<String>,
}

/// Raw clap-parsed command-line arguments.
#[derive(Debug, Parser, PartialEq, Eq)]
#[command(name = "lfp-env", disable_version_flag = true)]
struct CliArguments {
    /// Print the raw crate version for machine comparisons.
    #[arg(long = "version", action = ArgAction::SetTrue)]
    print_version: bool,

    /// Set log verbosity for runtime checks.
    #[arg(
        long,
        env = "LFP_ENV_LOG_LEVEL",
        default_value = DEFAULT_LOG_LEVEL,
        value_parser = parse_level_filter
    )]
    log_level: LevelFilter,

    /// Minimum acceptable mise version before reinstalling or failing.
    #[arg(long, env = "LFP_ENV_MISE_MIN_VERSION")]
    mise_min_version: Option<String>,

    /// Minimum acceptable Python version.
    #[arg(
        long,
        env = "LFP_ENV_PYTHON_MIN_VERSION",
        default_value = DEFAULT_PYTHON_MIN_VERSION
    )]
    python_min_version: Option<String>,

    /// Minimum acceptable uv version.
    #[arg(
        long,
        env = "LFP_ENV_UV_MIN_VERSION",
        default_value = DEFAULT_UV_MIN_VERSION
    )]
    uv_min_version: Option<String>,

    /// Minimum acceptable git version.
    #[arg(long, env = "LFP_ENV_GIT_MIN_VERSION")]
    git_min_version: Option<String>,

    /// Extra package selectors to install with `mise use -g`.
    #[command(subcommand)]
    trailing_args: Option<TrailingArgs>,
}

/// Trailing arguments captured after the known installer flags.
#[derive(Debug, Subcommand, PartialEq, Eq)]
enum TrailingArgs {
    /// Treat any unrecognized trailing arguments as `mise use -g` selectors.
    #[command(external_subcommand)]
    Args(Vec<OsString>),
}

/// Parse CLI options from process arguments.
pub fn parse_cli_options() -> Result<CliOptions, String> {
    parse_cli_options_from(std::env::args_os())
}

/// Parse CLI options from an arbitrary iterator of process-style arguments.
fn parse_cli_options_from<I, T>(args: I) -> Result<CliOptions, String>
where
    I: IntoIterator<Item = T>,
    T: Into<OsString> + Clone,
{
    let arguments = CliArguments::try_parse_from(args).map_err(|err| err.to_string())?;
    Ok(CliOptions {
        print_version: arguments.print_version,
        log_level: arguments.log_level,
        minimum_versions: MinimumVersionConfig {
            mise: arguments.mise_min_version,
            python: arguments.python_min_version,
            uv: arguments.uv_min_version,
            git: arguments.git_min_version,
        },
        forwarded_args: extract_forwarded_args(arguments.trailing_args),
    })
}

/// Convert clap's external trailing args into plain strings for installer forwarding.
fn extract_forwarded_args(trailing_args: Option<TrailingArgs>) -> Vec<String> {
    match trailing_args {
        Some(TrailingArgs::Args(args)) => args
            .into_iter()
            .map(|value| value.to_string_lossy().to_string())
            .collect(),
        None => Vec::new(),
    }
}

/// Parse a runtime log level string into a `LevelFilter`.
pub fn parse_level_filter(value: &str) -> Result<LevelFilter, String> {
    let normalized = value.trim().to_ascii_lowercase();
    if normalized == "0" {
        return Ok(LevelFilter::Off);
    }
    if normalized.chars().all(|character| character.is_ascii_digit()) {
        return Ok(LevelFilter::Info);
    }
    normalized.parse::<LevelFilter>().map_err(|_| {
        format!("Invalid log level '{value}'. Expected one of: 0,error,warn,info,debug,trace,off")
    })
}

#[cfg(test)]
mod tests {
    use super::{parse_cli_options_from, LevelFilter};
    use std::env;
    use std::sync::{Mutex, MutexGuard};

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn lock_env() -> MutexGuard<'static, ()> {
        ENV_LOCK.lock().expect("env test mutex poisoned")
    }

    #[test]
    fn parses_version_flag() {
        let _lock = lock_env();
        let options = parse_cli_options_from(vec!["lfp-env", "--version"]).unwrap();
        assert!(options.print_version);
        assert_eq!(options.log_level, LevelFilter::Info);
        assert_eq!(options.minimum_versions.python.as_deref(), Some("3.10"));
        assert_eq!(options.minimum_versions.uv.as_deref(), Some("0.9.9"));
        assert!(options.forwarded_args.is_empty());
    }

    #[test]
    fn parses_log_level_assignment() {
        let _lock = lock_env();
        let options = parse_cli_options_from(vec!["lfp-env", "--log-level=debug"]).unwrap();
        assert_eq!(options.log_level, LevelFilter::Debug);
    }

    #[test]
    fn parses_log_level_separate_value() {
        let _lock = lock_env();
        let options =
            parse_cli_options_from(vec!["lfp-env", "--log-level", "trace"]).unwrap();
        assert_eq!(options.log_level, LevelFilter::Trace);
    }

    #[test]
    fn parses_log_level_zero_as_off() {
        let _lock = lock_env();
        let options = parse_cli_options_from(vec!["lfp-env", "--log-level", "0"]).unwrap();
        assert_eq!(options.log_level, LevelFilter::Off);
    }

    #[test]
    fn parses_non_zero_numeric_log_level_as_info() {
        let _lock = lock_env();
        let options = parse_cli_options_from(vec!["lfp-env", "--log-level", "1"]).unwrap();
        assert_eq!(options.log_level, LevelFilter::Info);
    }

    #[test]
    fn forwards_unknown_arguments_to_mise() {
        let _lock = lock_env();
        let options = parse_cli_options_from(vec![
            "lfp-env",
            "nano@latest",
            "jq",
        ])
        .unwrap();
        assert_eq!(
            options.forwarded_args,
            vec!["nano@latest".to_string(), "jq".to_string()]
        );
    }

    #[test]
    fn forwards_arguments_after_double_dash() {
        let _lock = lock_env();
        let options = parse_cli_options_from(vec![
            "lfp-env",
            "--log-level=warn",
            "--",
            "--version",
        ])
        .unwrap();
        assert_eq!(options.log_level, LevelFilter::Warn);
        assert_eq!(options.forwarded_args, vec!["--version".to_string()]);
    }

    #[test]
    fn parses_known_flags_before_package_selectors() {
        let _lock = lock_env();
        let options = parse_cli_options_from(vec![
            "lfp-env",
            "--log-level=debug",
            "nano@latest",
            "jq",
        ])
        .unwrap();
        assert_eq!(options.log_level, LevelFilter::Debug);
        assert_eq!(
            options.forwarded_args,
            vec!["nano@latest".to_string(), "jq".to_string()]
        );
    }

    #[test]
    fn reads_min_versions_from_environment() {
        let _lock = lock_env();
        let _guard = EnvGuard::set(&[
            ("LFP_ENV_MISE_MIN_VERSION", Some("2024.10.1")),
            ("LFP_ENV_GIT_MIN_VERSION", Some("2.39.0")),
            ("LFP_ENV_LOG_LEVEL", Some("0")),
        ]);
        let options = parse_cli_options_from(vec!["lfp-env"]).unwrap();
        assert_eq!(options.log_level, LevelFilter::Off);
        assert_eq!(options.minimum_versions.mise.as_deref(), Some("2024.10.1"));
        assert_eq!(options.minimum_versions.git.as_deref(), Some("2.39.0"));
        assert_eq!(options.minimum_versions.python.as_deref(), Some("3.10"));
        assert_eq!(options.minimum_versions.uv.as_deref(), Some("0.9.9"));
    }

    #[test]
    fn parses_min_versions_from_cli_flags() {
        let _lock = lock_env();
        let options = parse_cli_options_from(vec![
            "lfp-env",
            "--mise-min-version",
            "2024.9.8",
            "--python-min-version",
            "3.11",
            "--uv-min-version",
            "0.10.0",
            "--git-min-version",
            "2.42.0",
        ])
        .unwrap();
        assert_eq!(options.minimum_versions.mise.as_deref(), Some("2024.9.8"));
        assert_eq!(options.minimum_versions.python.as_deref(), Some("3.11"));
        assert_eq!(options.minimum_versions.uv.as_deref(), Some("0.10.0"));
        assert_eq!(options.minimum_versions.git.as_deref(), Some("2.42.0"));
    }

    struct EnvGuard {
        previous_values: Vec<(&'static str, Option<String>)>,
    }

    impl EnvGuard {
        fn set(entries: &[(&'static str, Option<&str>)]) -> Self {
            let previous_values = entries
                .iter()
                .map(|(name, value)| {
                    let previous = env::var(name).ok();
                    match value {
                        Some(value) => env::set_var(name, value),
                        None => env::remove_var(name),
                    }
                    (*name, previous)
                })
                .collect();
            Self { previous_values }
        }
    }

    impl Drop for EnvGuard {
        fn drop(&mut self) {
            for (name, previous) in self.previous_values.drain(..) {
                match previous {
                    Some(value) => env::set_var(name, value),
                    None => env::remove_var(name),
                }
            }
        }
    }
}
