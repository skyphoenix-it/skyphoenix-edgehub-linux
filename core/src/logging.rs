use std::str::FromStr;

/// Initialize structured logging for the application.
///
/// Log level is controlled by RUST_LOG environment variable.
/// Default: INFO for our crate, WARN for dependencies.
pub fn init_logging(level: &str) {
    let filter = match level {
        "error" => tracing_subscriber::filter::LevelFilter::ERROR,
        "warn" => tracing_subscriber::filter::LevelFilter::WARN,
        "info" => tracing_subscriber::filter::LevelFilter::INFO,
        "debug" => tracing_subscriber::filter::LevelFilter::DEBUG,
        "trace" => tracing_subscriber::filter::LevelFilter::TRACE,
        _ => tracing_subscriber::filter::LevelFilter::INFO,
    };

    // try_init is safe to call multiple times (subsequent calls are no-ops)
    let _ = tracing_subscriber::fmt()
        .with_max_level(filter)
        .with_target(false)
        .with_ansi(true)
        .try_init();
}

/// Log levels mirroring the application's log level configuration.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum LogLevel {
    Error = 0,
    Warn = 1,
    Info = 2,
    Debug = 3,
    Trace = 4,
}

impl FromStr for LogLevel {
    type Err = ();

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "error" => Ok(LogLevel::Error),
            "warn" | "warning" => Ok(LogLevel::Warn),
            "info" => Ok(LogLevel::Info),
            "debug" => Ok(LogLevel::Debug),
            "trace" => Ok(LogLevel::Trace),
            _ => Ok(LogLevel::Info),
        }
    }
}
