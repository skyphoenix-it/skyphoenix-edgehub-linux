pub mod config;
pub mod display;
pub mod ffi;
pub mod logging;
pub mod metrics;

// Single crate-wide lock serializing every test that mutates the process-global
// `XDG_CONFIG_HOME` env var. Tests live in multiple modules (config.rs, ffi.rs);
// without ONE shared lock they race on the env var and intermittently observe
// each other's temp dirs (e.g. a save landing in a dir a concurrent test just
// reset). Any test that sets/removes XDG_CONFIG_HOME must hold this guard.
#[cfg(test)]
pub(crate) static TEST_ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
