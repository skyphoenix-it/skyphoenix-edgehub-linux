/// Initialize structured logging for the application.
///
/// The maximum level is set from the explicit `level` argument (one of
/// "error" | "warn" | "info" | "debug" | "trace"); anything else falls back to
/// INFO. Safe to call multiple times — later calls are no-ops.
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
