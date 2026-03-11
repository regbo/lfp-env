mod cli;
mod install;
mod requirements;
mod version;

use log::{Level, LevelFilter, Metadata, Record};
use std::sync::atomic::{AtomicU8, Ordering};
use std::io::Write;

const PKG_NAME: &str = env!("CARGO_PKG_NAME");
const PKG_VERSION: &str = env!("CARGO_PKG_VERSION");
static LOGGER: SimpleLogger = SimpleLogger::new();

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
    install::run(options)
}

/// Minimal logger implementation used for installer and runtime output.
struct SimpleLogger {
    max_level: AtomicU8,
}

impl SimpleLogger {
    const fn new() -> Self {
        Self {
            max_level: AtomicU8::new(level_filter_to_u8(LevelFilter::Off)),
        }
    }

    fn set_level(&self, log_level: LevelFilter) {
        self.max_level
            .store(level_filter_to_u8(log_level), Ordering::Relaxed);
    }

    fn current_level(&self) -> LevelFilter {
        level_filter_from_u8(self.max_level.load(Ordering::Relaxed))
    }
}

impl log::Log for SimpleLogger {
    fn enabled(&self, metadata: &Metadata<'_>) -> bool {
        metadata.level() <= self.current_level()
    }

    fn log(&self, record: &Record<'_>) {
        if !self.enabled(record.metadata()) {
            return;
        }

        // Keep the existing stderr format stable without bringing in a full logger dependency.
        let mut stderr = std::io::stderr().lock();
        let _ = if record.level() == Level::Info {
            writeln!(stderr, "[{}] {}", PKG_NAME, record.args())
        } else {
            writeln!(stderr, "[{}] [{}] {}", PKG_NAME, record.level(), record.args())
        };
    }

    fn flush(&self) {}
}

fn init_logger(log_level: LevelFilter) {
    LOGGER.set_level(log_level);
    log::set_max_level(log_level);
    let _ = log::set_logger(&LOGGER);
}

const fn level_filter_to_u8(level_filter: LevelFilter) -> u8 {
    match level_filter {
        LevelFilter::Off => 0,
        LevelFilter::Error => 1,
        LevelFilter::Warn => 2,
        LevelFilter::Info => 3,
        LevelFilter::Debug => 4,
        LevelFilter::Trace => 5,
    }
}

const fn level_filter_from_u8(value: u8) -> LevelFilter {
    match value {
        1 => LevelFilter::Error,
        2 => LevelFilter::Warn,
        3 => LevelFilter::Info,
        4 => LevelFilter::Debug,
        5 => LevelFilter::Trace,
        _ => LevelFilter::Off,
    }
}
