use clap::{ArgAction, Parser};
use log::LevelFilter;

/// Command-line options for `lfp-env`.
#[derive(Parser, Debug)]
#[command(
    name = "lfp-env",
    about = "Bootstrap required environment tooling",
    disable_version_flag = true
)]
pub struct CliOptions {
    /// Print the raw crate version for machine comparisons.
    #[arg(long = "version", action = ArgAction::SetTrue)]
    pub print_version: bool,

    /// Set log verbosity for runtime checks (error, warn, info, debug, trace, off).
    /// Reads LFP_ENV_LOG_LEVEL by default when not provided on CLI.
    #[arg(long = "log-level", env = "LFP_ENV_LOG_LEVEL", default_value = "info", value_parser = parse_level_filter)]
    pub log_level: LevelFilter,

    /// Forward all remaining args to `mise` after installer setup completes.
    #[arg(trailing_var_arg = true, allow_hyphen_values = true, hide = true)]
    pub forwarded_args: Vec<String>,
}

/// Parse CLI options from process arguments.
pub fn parse_cli_options() -> Result<CliOptions, String> {
    CliOptions::try_parse().map_err(|err| err.to_string())
}

/// Parse a runtime log level string into a `LevelFilter`.
pub fn parse_level_filter(value: &str) -> Result<LevelFilter, String> {
    value.trim().parse::<LevelFilter>().map_err(|_| {
        format!("Invalid log level '{value}'. Expected one of: error,warn,info,debug,trace,off")
    })
}
