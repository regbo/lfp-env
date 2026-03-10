mod cli;
mod install;
mod requirements;

use log::LevelFilter;
use std::io::Write;

const PKG_NAME: &str = env!("CARGO_PKG_NAME");
const PKG_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Main entry point:
/// - Prints a raw semver when requested
/// - Always runs installer orchestration
/// - Ensures required environment tooling through mise
fn main() {
    if let Err(err) = run() {
        eprintln!("Error: {err}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let options = cli::parse_cli_options()?;
    if options.print_version {
        println!("{PKG_VERSION}");
        return Ok(());
    }

    init_logger(options.log_level);
    install::run(options.forwarded_args)
}

fn init_logger(log_level: LevelFilter) {
    env_logger::Builder::new()
        .filter_level(log_level)
        .format(|buf, record| {
            if record.level() == log::Level::Info {
                writeln!(buf, "[{}] {}", PKG_NAME, record.args())
            } else {
                writeln!(buf, "[{}] [{}] {}", PKG_NAME, record.level(), record.args())
            }
        })
        .init();
}
