//! C-compatible FFI interface for the Rust core library.
//!
//! These functions are called from the C++ Qt application layer.
//! All string returns are owned by the caller and must be freed with `xeneon_string_free`.
//! All struct pointers must be freed with their corresponding `_free` function.
//!
//! Raw pointer dereferencing is inherent to FFI — functions accept and manipulate
//! raw pointers passed from C/C++ callers.

#![allow(clippy::not_unsafe_ptr_arg_deref)]

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::config::{self, AppConfig};
use crate::display;
use crate::logging;
use crate::metrics::{self, SystemMetrics};

/// Convert a Rust string into an owned C string pointer without panicking.
///
/// If the input contains an interior NUL byte, it is sanitized (NULs stripped)
/// rather than panicking and crashing the host C++ application. Returns a null
/// pointer only if allocation of the fallback also fails (effectively never).
fn to_c_string<S: Into<Vec<u8>>>(s: S) -> *mut c_char {
    let bytes = s.into();
    match CString::new(bytes.clone()) {
        Ok(c) => c.into_raw(),
        Err(_) => {
            // Strip interior NUL bytes and retry.
            let sanitized: Vec<u8> = bytes.into_iter().filter(|&b| b != 0).collect();
            CString::new(sanitized)
                .map(|c| c.into_raw())
                .unwrap_or(std::ptr::null_mut())
        }
    }
}

// --- Logging ---

#[no_mangle]
pub extern "C" fn xeneon_logging_init(level: *const c_char) {
    let level_str = if level.is_null() {
        "info"
    } else {
        unsafe { CStr::from_ptr(level) }.to_str().unwrap_or("info")
    };
    logging::init_logging(level_str);
}

/// Log a message from C/C++ at the given level.
/// level: 0=ERROR, 1=WARN, 2=INFO, 3=DEBUG, 4=TRACE
#[no_mangle]
pub extern "C" fn xeneon_logging_log(
    level: i32,
    file: *const c_char,
    line: i32,
    message: *const c_char,
) {
    let msg = if message.is_null() {
        ""
    } else {
        unsafe { CStr::from_ptr(message) }.to_str().unwrap_or("")
    };
    let file_str = if file.is_null() {
        "unknown"
    } else {
        unsafe { CStr::from_ptr(file) }
            .to_str()
            .unwrap_or("unknown")
    };

    match level {
        0 => tracing::error!(file = file_str, line = line, "{}", msg),
        1 => tracing::warn!(file = file_str, line = line, "{}", msg),
        2 => tracing::info!(file = file_str, line = line, "{}", msg),
        3 => tracing::debug!(file = file_str, line = line, "{}", msg),
        _ => tracing::trace!(file = file_str, line = line, "{}", msg),
    }
}

// --- Config ---

/// Opaque handle to application configuration.
pub struct ConfigHandle {
    config: AppConfig,
}

/// Load configuration from default XDG path.
/// Returns null on error (logs error internally).
#[no_mangle]
pub extern "C" fn xeneon_config_load() -> *mut ConfigHandle {
    match config::load_config() {
        Ok(c) => Box::into_raw(Box::new(ConfigHandle { config: c })),
        Err(e) => {
            tracing::error!("Failed to load config: {}", e);
            std::ptr::null_mut()
        }
    }
}

/// Save configuration to default XDG path.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub extern "C" fn xeneon_config_save(handle: *const ConfigHandle) -> i32 {
    if handle.is_null() {
        return -1;
    }
    let h = unsafe { &*handle };
    match config::save_config(&h.config) {
        Ok(()) => 0,
        Err(e) => {
            tracing::error!("Failed to save config: {}", e);
            -1
        }
    }
}

/// Free a ConfigHandle.
#[no_mangle]
pub extern "C" fn xeneon_config_free(handle: *mut ConfigHandle) {
    if !handle.is_null() {
        unsafe { drop(Box::from_raw(handle)) };
    }
}

/// Get whether this is the first run (wizard not completed).
/// Returns 1 if first run, 0 if not, -1 on error.
#[no_mangle]
pub extern "C" fn xeneon_config_is_first_run(handle: *const ConfigHandle) -> i32 {
    if handle.is_null() {
        return -1;
    }
    let h = unsafe { &*handle };
    if h.config.first_run_complete {
        0
    } else {
        1
    }
}

/// Set first run as complete.
#[no_mangle]
pub extern "C" fn xeneon_config_set_first_run_complete(handle: *mut ConfigHandle) -> i32 {
    if handle.is_null() {
        return -1;
    }
    let h = unsafe { &mut *handle };
    h.config.first_run_complete = true;
    0
}

/// Get the target EDID hash (returns null if not set).
/// Caller must free with xeneon_string_free.
#[no_mangle]
pub extern "C" fn xeneon_config_get_target_edid_hash(handle: *const ConfigHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };
    match &h.config.display.target_edid_hash {
        Some(hash) => to_c_string(hash.as_str()),
        None => std::ptr::null_mut(),
    }
}

/// Get the target connector name (returns null if not set).
/// Caller must free with xeneon_string_free.
#[no_mangle]
pub extern "C" fn xeneon_config_get_target_connector(handle: *const ConfigHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };
    match &h.config.display.target_connector {
        Some(conn) => to_c_string(conn.as_str()),
        None => std::ptr::null_mut(),
    }
}

/// Get the target display model name (returns null if not set).
/// Caller must free with xeneon_string_free.
#[no_mangle]
pub extern "C" fn xeneon_config_get_target_model(handle: *const ConfigHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };
    match &h.config.display.target_model {
        Some(model) => to_c_string(model.as_str()),
        None => std::ptr::null_mut(),
    }
}

/// Set the target EDID hash.
#[no_mangle]
pub extern "C" fn xeneon_config_set_target_edid_hash(
    handle: *mut ConfigHandle,
    hash: *const c_char,
) -> i32 {
    if handle.is_null() {
        return -1;
    }
    let h = unsafe { &mut *handle };
    if hash.is_null() {
        h.config.display.target_edid_hash = None;
    } else {
        let s = unsafe { CStr::from_ptr(hash) }
            .to_string_lossy()
            .to_string();
        h.config.display.target_edid_hash = Some(s);
    }
    0
}

/// Set the target connector.
#[no_mangle]
pub extern "C" fn xeneon_config_set_target_connector(
    handle: *mut ConfigHandle,
    connector: *const c_char,
) -> i32 {
    if handle.is_null() {
        return -1;
    }
    let h = unsafe { &mut *handle };
    if connector.is_null() {
        h.config.display.target_connector = None;
    } else {
        let s = unsafe { CStr::from_ptr(connector) }
            .to_string_lossy()
            .to_string();
        h.config.display.target_connector = Some(s);
    }
    0
}

/// Set the target display model name.
#[no_mangle]
pub extern "C" fn xeneon_config_set_target_model(
    handle: *mut ConfigHandle,
    model: *const c_char,
) -> i32 {
    if handle.is_null() {
        return -1;
    }
    let h = unsafe { &mut *handle };
    if model.is_null() {
        h.config.display.target_model = None;
    } else {
        let s = unsafe { CStr::from_ptr(model) }
            .to_string_lossy()
            .to_string();
        h.config.display.target_model = Some(s);
    }
    0
}

/// Get the config directory path.
/// Caller must free with xeneon_string_free.
#[no_mangle]
pub extern "C" fn xeneon_config_dir() -> *mut c_char {
    let dir = config::config_dir();
    to_c_string(dir.to_string_lossy().to_string())
}

/// Reset configuration to defaults.
/// Returns a new ConfigHandle with default values.
#[no_mangle]
pub extern "C" fn xeneon_config_reset() -> *mut ConfigHandle {
    match config::reset_config() {
        Ok(c) => Box::into_raw(Box::new(ConfigHandle { config: c })),
        Err(e) => {
            tracing::error!("Failed to reset config: {}", e);
            // Return defaults even if file removal failed
            Box::into_raw(Box::new(ConfigHandle {
                config: AppConfig::default(),
            }))
        }
    }
}

/// Get the theme mode string. Caller must free.
#[no_mangle]
pub extern "C" fn xeneon_config_get_theme_mode(handle: *const ConfigHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };
    to_c_string(h.config.theme.mode.as_str())
}

/// Get config in JSON format (for diagnostics/QML). Caller must free.
#[no_mangle]
pub extern "C" fn xeneon_config_to_json(handle: *const ConfigHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };
    match serde_json::to_string_pretty(&h.config) {
        Ok(json) => to_c_string(json),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Set theme mode (e.g. "dark", "light", "oled", "high_contrast").
#[no_mangle]
pub extern "C" fn xeneon_config_set_theme_mode(
    handle: *mut ConfigHandle,
    mode: *const c_char,
) -> i32 {
    if handle.is_null() || mode.is_null() {
        return -1;
    }
    let h = unsafe { &mut *handle };
    h.config.theme.mode = unsafe { CStr::from_ptr(mode) }
        .to_string_lossy()
        .to_string();
    0
}

/// Set theme accent color (hex, e.g. "#58A6FF").
#[no_mangle]
pub extern "C" fn xeneon_config_set_theme_accent(
    handle: *mut ConfigHandle,
    color: *const c_char,
) -> i32 {
    if handle.is_null() || color.is_null() {
        return -1;
    }
    let h = unsafe { &mut *handle };
    h.config.theme.accent_color = unsafe { CStr::from_ptr(color) }
        .to_string_lossy()
        .to_string();
    0
}

/// Set autostart preference.
#[no_mangle]
pub extern "C" fn xeneon_config_set_autostart(handle: *mut ConfigHandle, enabled: i32) -> i32 {
    if handle.is_null() {
        return -1;
    }
    unsafe { &mut *handle }.config.startup.autostart = enabled != 0;
    0
}

/// Set reconnect-on-hotplug preference.
#[no_mangle]
pub extern "C" fn xeneon_config_set_reconnect(handle: *mut ConfigHandle, enabled: i32) -> i32 {
    if handle.is_null() {
        return -1;
    }
    unsafe { &mut *handle }.config.startup.reconnect_on_hotplug = enabled != 0;
    0
}

/// Set notify-on-disconnect preference.
#[no_mangle]
pub extern "C" fn xeneon_config_set_notify_disconnect(
    handle: *mut ConfigHandle,
    enabled: i32,
) -> i32 {
    if handle.is_null() {
        return -1;
    }
    unsafe { &mut *handle }.config.startup.notify_on_disconnect = enabled != 0;
    0
}

/// Set the starter layout ID (e.g. "productivity", "gaming", "minimal", "blank").
#[no_mangle]
pub extern "C" fn xeneon_config_set_starter_layout(
    handle: *mut ConfigHandle,
    layout_id: *const c_char,
) -> i32 {
    if handle.is_null() {
        return -1;
    }
    let h = unsafe { &mut *handle };
    if layout_id.is_null() {
        h.config.display.starter_layout = None;
    } else {
        h.config.display.starter_layout = Some(
            unsafe { CStr::from_ptr(layout_id) }
                .to_string_lossy()
                .to_string(),
        );
    }
    0
}

/// Get the starter layout ID chosen during the wizard (null if unset).
/// Caller must free with xeneon_string_free.
#[no_mangle]
pub extern "C" fn xeneon_config_get_starter_layout(handle: *const ConfigHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };
    match &h.config.display.starter_layout {
        Some(layout) => to_c_string(layout.as_str()),
        None => std::ptr::null_mut(),
    }
}

/// Get the opaque UI-state JSON document (null if never saved).
/// Caller must free with xeneon_string_free.
#[no_mangle]
pub extern "C" fn xeneon_config_get_ui_state(handle: *const ConfigHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };
    match &h.config.ui_state {
        Some(json) => to_c_string(json.as_str()),
        None => std::ptr::null_mut(),
    }
}

/// Set the opaque UI-state JSON document (pass null to clear).
/// Does not save to disk on its own — call `xeneon_config_save`.
#[no_mangle]
pub extern "C" fn xeneon_config_set_ui_state(
    handle: *mut ConfigHandle,
    json: *const c_char,
) -> i32 {
    if handle.is_null() {
        return -1;
    }
    let h = unsafe { &mut *handle };
    if json.is_null() {
        h.config.ui_state = None;
    } else {
        h.config.ui_state = Some(
            unsafe { CStr::from_ptr(json) }
                .to_string_lossy()
                .to_string(),
        );
    }
    0
}

// --- Display utilities ---

/// Compute the EDID hash from raw EDID bytes.
/// Caller provides pointer to EDID data and its length.
/// Returns hex-encoded SHA-256 hash. Caller must free with xeneon_string_free.
#[no_mangle]
pub extern "C" fn xeneon_display_compute_edid_hash(
    edid_data: *const u8,
    len: usize,
) -> *mut c_char {
    if edid_data.is_null() || len == 0 {
        return std::ptr::null_mut();
    }
    let edid = unsafe { std::slice::from_raw_parts(edid_data, len) };
    let hash = display::compute_edid_hash(edid);
    to_c_string(hash)
}

/// Parse manufacturer from EDID. Caller must free.
#[no_mangle]
pub extern "C" fn xeneon_display_parse_manufacturer(
    edid_data: *const u8,
    len: usize,
) -> *mut c_char {
    if edid_data.is_null() || len == 0 {
        return std::ptr::null_mut();
    }
    let edid = unsafe { std::slice::from_raw_parts(edid_data, len) };
    match display::parse_manufacturer(edid) {
        Some(mfg) => to_c_string(mfg),
        None => std::ptr::null_mut(),
    }
}

/// Parse model name from EDID. Caller must free.
#[no_mangle]
pub extern "C" fn xeneon_display_parse_model_name(edid_data: *const u8, len: usize) -> *mut c_char {
    if edid_data.is_null() || len == 0 {
        return std::ptr::null_mut();
    }
    let edid = unsafe { std::slice::from_raw_parts(edid_data, len) };
    match display::parse_model_name(edid) {
        Some(name) => to_c_string(name),
        None => std::ptr::null_mut(),
    }
}

/// Check if EDID likely belongs to a Xeneon Edge. Returns 1 if yes, 0 if no.
#[no_mangle]
pub extern "C" fn xeneon_display_is_xeneon_edge(edid_data: *const u8, len: usize) -> i32 {
    if edid_data.is_null() || len == 0 {
        return 0;
    }
    let edid = unsafe { std::slice::from_raw_parts(edid_data, len) };
    if display::is_xeneon_edge(edid) {
        1
    } else {
        0
    }
}

// --- Metrics ---

/// Opaque handle to system metrics.
pub struct MetricsHandle {
    metrics: SystemMetrics,
}

/// Collect current system metrics.
/// Returns a MetricsHandle; caller must free with xeneon_metrics_free.
#[no_mangle]
pub extern "C" fn xeneon_metrics_collect() -> *mut MetricsHandle {
    let m = metrics::collect_metrics();
    Box::into_raw(Box::new(MetricsHandle { metrics: m }))
}

/// Free a MetricsHandle.
#[no_mangle]
pub extern "C" fn xeneon_metrics_free(handle: *mut MetricsHandle) {
    if !handle.is_null() {
        unsafe { drop(Box::from_raw(handle)) };
    }
}

/// Get CPU usage percentage (0.0 - 100.0).
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_cpu_usage(handle: *const MetricsHandle) -> f64 {
    if handle.is_null() {
        return 0.0;
    }
    unsafe { &*handle }.metrics.cpu_usage_percent
}

/// Get CPU temperature in Celsius. Returns -1.0 if unavailable.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_cpu_temp(handle: *const MetricsHandle) -> f64 {
    if handle.is_null() {
        return -1.0;
    }
    unsafe { &*handle }.metrics.cpu_temp_celsius.unwrap_or(-1.0)
}

/// Get RAM usage percentage (0.0 - 100.0).
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_ram_usage(handle: *const MetricsHandle) -> f64 {
    if handle.is_null() {
        return 0.0;
    }
    unsafe { &*handle }.metrics.ram_usage_percent
}

/// Get total RAM in bytes.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_ram_total(handle: *const MetricsHandle) -> u64 {
    if handle.is_null() {
        return 0;
    }
    unsafe { &*handle }.metrics.ram_total_bytes
}

/// Get used RAM in bytes.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_ram_used(handle: *const MetricsHandle) -> u64 {
    if handle.is_null() {
        return 0;
    }
    unsafe { &*handle }.metrics.ram_used_bytes
}

/// Get CPU core count.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_cpu_cores(handle: *const MetricsHandle) -> u32 {
    if handle.is_null() {
        return 0;
    }
    unsafe { &*handle }.metrics.cpu_core_count
}

/// Get GPU usage percentage (0.0 - 100.0). Returns -1.0 if unavailable.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_gpu_usage(handle: *const MetricsHandle) -> f64 {
    if handle.is_null() {
        return -1.0;
    }
    unsafe { &*handle }
        .metrics
        .gpu_usage_percent
        .unwrap_or(-1.0)
}

/// Get GPU temperature in Celsius. Returns -1.0 if unavailable.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_gpu_temp(handle: *const MetricsHandle) -> f64 {
    if handle.is_null() {
        return -1.0;
    }
    unsafe { &*handle }.metrics.gpu_temp_celsius.unwrap_or(-1.0)
}

/// Get network receive rate in bytes/second.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_net_rx(handle: *const MetricsHandle) -> f64 {
    if handle.is_null() {
        return 0.0;
    }
    unsafe { &*handle }.metrics.net_rx_bytes_per_sec
}

/// Get network transmit rate in bytes/second.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_net_tx(handle: *const MetricsHandle) -> f64 {
    if handle.is_null() {
        return 0.0;
    }
    unsafe { &*handle }.metrics.net_tx_bytes_per_sec
}

/// Get total root-filesystem size in bytes.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_disk_total(handle: *const MetricsHandle) -> u64 {
    if handle.is_null() {
        return 0;
    }
    unsafe { &*handle }.metrics.disk_total_bytes
}

/// Get used root-filesystem space in bytes.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_disk_used(handle: *const MetricsHandle) -> u64 {
    if handle.is_null() {
        return 0;
    }
    unsafe { &*handle }.metrics.disk_used_bytes
}

/// Get metrics as a JSON string. Caller must free.
#[no_mangle]
pub extern "C" fn xeneon_metrics_to_json(handle: *const MetricsHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let m = &unsafe { &*handle }.metrics;
    let json = serde_json::json!({
        "cpu_usage_percent": m.cpu_usage_percent,
        "cpu_temp_celsius": m.cpu_temp_celsius,
        "ram_usage_percent": m.ram_usage_percent,
        "ram_total_bytes": m.ram_total_bytes,
        "ram_used_bytes": m.ram_used_bytes,
        "cpu_core_count": m.cpu_core_count,
        "gpu_usage_percent": m.gpu_usage_percent,
        "gpu_temp_celsius": m.gpu_temp_celsius,
        "net_rx_bytes_per_sec": m.net_rx_bytes_per_sec,
        "net_tx_bytes_per_sec": m.net_tx_bytes_per_sec,
        "disk_total_bytes": m.disk_total_bytes,
        "disk_used_bytes": m.disk_used_bytes,
        "disk_usage_percent": m.disk_usage_percent,
    });
    match serde_json::to_string(&json) {
        Ok(s) => to_c_string(s),
        Err(_) => std::ptr::null_mut(),
    }
}

// --- String utilities ---

/// Free a string returned by any xeneon_* function.
/// Must be called for every non-null string returned.
#[no_mangle]
pub extern "C" fn xeneon_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Round-trip a to_c_string result back to a Rust &str for assertions,
    /// then free it. Safe: `p` is a live pointer from `to_c_string`.
    unsafe fn take(p: *mut c_char) -> String {
        assert!(!p.is_null());
        let s = CStr::from_ptr(p).to_string_lossy().into_owned();
        xeneon_string_free(p);
        s
    }

    #[test]
    fn to_c_string_roundtrips_plain_utf8() {
        unsafe {
            assert_eq!(take(to_c_string("hello")), "hello");
            assert_eq!(take(to_c_string(String::new())), "");
        }
    }

    #[test]
    fn to_c_string_sanitizes_interior_nul() {
        // An interior NUL would make CString::new fail; it must be stripped, not panic.
        unsafe {
            assert_eq!(take(to_c_string(vec![b'a', 0, b'b'])), "ab");
        }
    }

    #[test]
    fn null_handle_guards_return_sentinels() {
        use std::ptr;
        // Integer-returning guards.
        assert_eq!(xeneon_config_save(ptr::null()), -1);
        assert_eq!(xeneon_config_is_first_run(ptr::null()), -1);
        assert_eq!(xeneon_config_set_first_run_complete(ptr::null_mut()), -1);
        assert_eq!(xeneon_config_set_autostart(ptr::null_mut(), 1), -1);
        // String-returning guards.
        assert!(xeneon_config_get_target_connector(ptr::null()).is_null());
        assert!(xeneon_config_get_ui_state(ptr::null()).is_null());
        assert!(xeneon_config_to_json(ptr::null()).is_null());
    }

    #[test]
    fn free_null_pointers_is_a_noop() {
        // Freeing null must never crash.
        xeneon_string_free(std::ptr::null_mut());
        xeneon_config_free(std::ptr::null_mut());
        xeneon_metrics_free(std::ptr::null_mut());
    }

    #[test]
    fn parse_helpers_tolerate_null_and_empty() {
        use std::ptr;
        // Null / zero-length EDID buffers must not deref or panic.
        assert!(xeneon_display_parse_manufacturer(ptr::null(), 0).is_null());
        assert!(xeneon_display_parse_model_name(ptr::null(), 0).is_null());
        assert_eq!(xeneon_display_is_xeneon_edge(ptr::null(), 0), 0);
    }
}
