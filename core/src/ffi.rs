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

use crate::config::{self, AppConfig, FallbackBehavior, WidgetInstance};
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

/// Set the display fallback behavior. Accepts "hide", "notify", or "ask".
/// Returns 0 on success, -1 on null handle / null or unrecognized value.
#[no_mangle]
pub extern "C" fn xeneon_config_set_fallback_behavior(
    handle: *mut ConfigHandle,
    behavior: *const c_char,
) -> i32 {
    if handle.is_null() || behavior.is_null() {
        return -1;
    }
    let s = unsafe { CStr::from_ptr(behavior) }.to_string_lossy();
    let parsed = match s.as_ref() {
        "hide" => FallbackBehavior::Hide,
        "notify" => FallbackBehavior::Notify,
        "ask" => FallbackBehavior::Ask,
        _ => return -1,
    };
    unsafe { &mut *handle }.config.display.fallback_behavior = parsed;
    0
}

/// Get the display fallback behavior as "hide" / "notify" / "ask". Caller frees.
#[no_mangle]
pub extern "C" fn xeneon_config_get_fallback_behavior(handle: *const ConfigHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let s = match unsafe { &*handle }.config.display.fallback_behavior {
        FallbackBehavior::Hide => "hide",
        FallbackBehavior::Notify => "notify",
        FallbackBehavior::Ask => "ask",
    };
    to_c_string(s)
}

/// Get the reconnect-on-hotplug preference. Returns 1 if enabled, 0 if not, -1 on error.
#[no_mangle]
pub extern "C" fn xeneon_config_get_reconnect(handle: *const ConfigHandle) -> i32 {
    if handle.is_null() {
        return -1;
    }
    if unsafe { &*handle }.config.startup.reconnect_on_hotplug {
        1
    } else {
        0
    }
}

/// Get the notify-on-disconnect preference. Returns 1 if enabled, 0 if not, -1 on error.
#[no_mangle]
pub extern "C" fn xeneon_config_get_notify_disconnect(handle: *const ConfigHandle) -> i32 {
    if handle.is_null() {
        return -1;
    }
    if unsafe { &*handle }.config.startup.notify_on_disconnect {
        1
    } else {
        0
    }
}

/// Set the "reduce motion" accessibility preference.
#[no_mangle]
pub extern "C" fn xeneon_config_set_reduced_motion(handle: *mut ConfigHandle, enabled: i32) -> i32 {
    if handle.is_null() {
        return -1;
    }
    unsafe { &mut *handle }.config.theme.reduced_motion = enabled != 0;
    0
}

/// Get the "reduce motion" preference. Returns 1 if enabled, 0 if not, -1 on error.
#[no_mangle]
pub extern "C" fn xeneon_config_get_reduced_motion(handle: *const ConfigHandle) -> i32 {
    if handle.is_null() {
        return -1;
    }
    if unsafe { &*handle }.config.theme.reduced_motion {
        1
    } else {
        0
    }
}

/// Append a typed widget instance to `widgets.instances`.
///
/// `settings_json` is an opaque JSON object for the widget's settings; an empty
/// or invalid string is stored as a JSON null. Returns 0 on success, -1 on a
/// null handle or null `id`/`widget_type`.
#[no_mangle]
pub extern "C" fn xeneon_config_add_widget(
    handle: *mut ConfigHandle,
    id: *const c_char,
    widget_type: *const c_char,
    enabled: i32,
    settings_json: *const c_char,
) -> i32 {
    if handle.is_null() || id.is_null() || widget_type.is_null() {
        return -1;
    }
    let id = unsafe { CStr::from_ptr(id) }.to_string_lossy().to_string();
    let widget_type = unsafe { CStr::from_ptr(widget_type) }
        .to_string_lossy()
        .to_string();
    let settings = if settings_json.is_null() {
        serde_json::Value::Null
    } else {
        let raw = unsafe { CStr::from_ptr(settings_json) }.to_string_lossy();
        serde_json::from_str(&raw).unwrap_or(serde_json::Value::Null)
    };
    unsafe { &mut *handle }
        .config
        .widgets
        .instances
        .push(WidgetInstance {
            id,
            widget_type,
            enabled: enabled != 0,
            settings,
        });
    0
}

/// Number of typed widget instances. Returns -1 on a null handle.
#[no_mangle]
pub extern "C" fn xeneon_config_widget_count(handle: *const ConfigHandle) -> i32 {
    if handle.is_null() {
        return -1;
    }
    unsafe { &*handle }.config.widgets.instances.len() as i32
}

/// Remove all typed widget instances. Returns 0 on success, -1 on a null handle.
#[no_mangle]
pub extern "C" fn xeneon_config_clear_widgets(handle: *mut ConfigHandle) -> i32 {
    if handle.is_null() {
        return -1;
    }
    unsafe { &mut *handle }.config.widgets.instances.clear();
    0
}

/// Get the typed widget instances as a JSON array. Caller must free.
#[no_mangle]
pub extern "C" fn xeneon_config_get_widgets_json(handle: *const ConfigHandle) -> *mut c_char {
    if handle.is_null() {
        return std::ptr::null_mut();
    }
    let h = unsafe { &*handle };
    match serde_json::to_string(&h.config.widgets.instances) {
        Ok(json) => to_c_string(json),
        Err(_) => std::ptr::null_mut(),
    }
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

/// Get CPU temperature in Celsius. Returns NaN if unavailable.
///
/// "Unavailable" (no sensor / unreadable) is signalled with NaN — the C++ side
/// must check `isnan()`, never `== -1.0`. Every genuine reading is passed
/// through intact, INCLUDING a real `-1.0` °C (which is a valid sub-zero
/// temperature, not a sentinel): only `None` maps to NaN. A null handle still
/// returns `-1.0` for backward compatibility with the FFI error convention.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_cpu_temp(handle: *const MetricsHandle) -> f64 {
    if handle.is_null() {
        return -1.0;
    }
    // Only `None` maps to NaN; every real reading (incl. -1.0) passes through.
    unsafe { &*handle }
        .metrics
        .cpu_temp_celsius
        .unwrap_or(f64::NAN)
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

/// Get GPU temperature in Celsius. Returns NaN if unavailable.
///
/// Uses NaN (check `isnan()`) for "unavailable"; every real reading — including
/// a genuine `-1.0` °C — is passed through, only `None` maps to NaN. See
/// `xeneon_metrics_get_cpu_temp`. A null handle still returns `-1.0` for
/// backward compatibility.
#[no_mangle]
pub extern "C" fn xeneon_metrics_get_gpu_temp(handle: *const MetricsHandle) -> f64 {
    if handle.is_null() {
        return -1.0;
    }
    // Only `None` maps to NaN; every real reading (incl. -1.0) passes through.
    unsafe { &*handle }
        .metrics
        .gpu_temp_celsius
        .unwrap_or(f64::NAN)
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

// --- Secrets (E7 Phase A) ---

/// Resolve a stored credential reference (`${env:VAR}`, `file:/path`, or a
/// legacy plaintext literal) to the value to send.
///
/// Returns the resolved value (caller frees with `xeneon_string_free`), or NULL
/// on failure. On failure, if `err_out` is non-null it receives an owned message
/// which the caller must ALSO free with `xeneon_string_free`. The message names
/// the reference (a variable name or path) and never the secret's value.
///
/// Resolving here rather than in QML is deliberate: QML cannot read the process
/// environment at all, and keeping resolution behind the FFI means the resolved
/// value only ever exists transiently in the caller's frame — never in
/// `ui_state`, and so never in `config.toml`.
#[no_mangle]
pub extern "C" fn xeneon_secret_resolve(
    raw: *const c_char,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    if !err_out.is_null() {
        unsafe { *err_out = std::ptr::null_mut() };
    }
    if raw.is_null() {
        if !err_out.is_null() {
            unsafe { *err_out = to_c_string("no reference given") };
        }
        return std::ptr::null_mut();
    }
    let raw_str = match unsafe { CStr::from_ptr(raw) }.to_str() {
        Ok(s) => s,
        Err(_) => {
            if !err_out.is_null() {
                unsafe { *err_out = to_c_string("reference is not valid UTF-8") };
            }
            return std::ptr::null_mut();
        }
    };
    match crate::secrets::resolve(raw_str) {
        Ok(v) => to_c_string(v),
        Err(e) => {
            // e's Display carries the var name / path only — never the value.
            if !err_out.is_null() {
                unsafe { *err_out = to_c_string(e.to_string()) };
            }
            std::ptr::null_mut()
        }
    }
}

/// 1 when the stored value is a bare plaintext secret (so the UI can warn), 0
/// when it is a reference or empty.
#[no_mangle]
pub extern "C" fn xeneon_secret_is_plaintext(raw: *const c_char) -> i32 {
    if raw.is_null() {
        return 0;
    }
    match unsafe { CStr::from_ptr(raw) }.to_str() {
        Ok(s) => crate::secrets::is_plaintext(s) as i32,
        Err(_) => 0,
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

    // --- Secrets FFI ---

    #[test]
    fn secret_resolve_env_ref_over_ffi() {
        let _g = crate::TEST_ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        std::env::set_var("XENEON_FFI_SECRET", "ffi-token");
        unsafe {
            let raw = CString::new("${env:XENEON_FFI_SECRET}").unwrap();
            let mut err: *mut c_char = std::ptr::null_mut();
            let got = xeneon_secret_resolve(raw.as_ptr(), &mut err);
            assert!(err.is_null(), "success must not set an error");
            assert_eq!(take(got), "ffi-token");
        }
        std::env::remove_var("XENEON_FFI_SECRET");
    }

    #[test]
    fn secret_resolve_failure_returns_null_and_an_error() {
        let _g = crate::TEST_ENV_LOCK
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        std::env::remove_var("XENEON_FFI_ABSENT");
        unsafe {
            let raw = CString::new("${env:XENEON_FFI_ABSENT}").unwrap();
            let mut err: *mut c_char = std::ptr::null_mut();
            let got = xeneon_secret_resolve(raw.as_ptr(), &mut err);
            assert!(got.is_null());
            let msg = take(err);
            assert!(
                msg.contains("XENEON_FFI_ABSENT"),
                "error should name the var: {msg}"
            );
        }
    }

    // The whole point of the module is that a secret never escapes into a place
    // it can be persisted or logged — an error string is one of those places.
    #[test]
    fn secret_resolve_error_never_contains_the_secret_value() {
        unsafe {
            let dir = tempfile::tempdir().unwrap();
            let p = dir.path().join("tok");
            std::fs::write(&p, "").unwrap(); // empty → FileEmpty error
            let raw = CString::new(format!("file:{}", p.display())).unwrap();
            let mut err: *mut c_char = std::ptr::null_mut();
            let got = xeneon_secret_resolve(raw.as_ptr(), &mut err);
            assert!(got.is_null());
            let msg = take(err);
            assert!(msg.contains("empty"), "got: {msg}");
        }
    }

    #[test]
    fn secret_resolve_handles_null_and_reports_it() {
        unsafe {
            let mut err: *mut c_char = std::ptr::null_mut();
            let got = xeneon_secret_resolve(std::ptr::null(), &mut err);
            assert!(got.is_null());
            assert!(!err.is_null(), "a null ref must still explain itself");
            let _ = take(err);
            // A null err_out must not crash either.
            assert!(xeneon_secret_resolve(std::ptr::null(), std::ptr::null_mut()).is_null());
        }
    }

    // No `unsafe` block: xeneon_secret_is_plaintext is a safe extern "C" fn (it
    // guards the null itself), so wrapping the calls would be unused-unsafe.
    #[test]
    fn secret_is_plaintext_over_ffi() {
        let lit = CString::new("ghp_abc").unwrap();
        let r = CString::new("${env:TOK}").unwrap();
        let empty = CString::new("").unwrap();
        assert_eq!(xeneon_secret_is_plaintext(lit.as_ptr()), 1);
        assert_eq!(xeneon_secret_is_plaintext(r.as_ptr()), 0);
        assert_eq!(xeneon_secret_is_plaintext(empty.as_ptr()), 0);
        assert_eq!(xeneon_secret_is_plaintext(std::ptr::null()), 0);
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

    // --- Comprehensive null-handle sentinel coverage ---

    #[test]
    fn every_getter_setter_null_handle_returns_documented_sentinel() {
        use std::ptr;
        let n: *const ConfigHandle = ptr::null();
        let nm: *mut ConfigHandle = ptr::null_mut();

        // Config: i32 setters return -1.
        assert_eq!(xeneon_config_set_theme_mode(nm, ptr::null()), -1);
        assert_eq!(xeneon_config_set_theme_accent(nm, ptr::null()), -1);
        assert_eq!(xeneon_config_set_reconnect(nm, 1), -1);
        assert_eq!(xeneon_config_set_notify_disconnect(nm, 1), -1);
        assert_eq!(xeneon_config_set_starter_layout(nm, ptr::null()), -1);
        assert_eq!(xeneon_config_set_ui_state(nm, ptr::null()), -1);
        assert_eq!(xeneon_config_set_target_edid_hash(nm, ptr::null()), -1);
        assert_eq!(xeneon_config_set_target_connector(nm, ptr::null()), -1);
        assert_eq!(xeneon_config_set_target_model(nm, ptr::null()), -1);
        // Config: string getters return null.
        assert!(xeneon_config_get_target_edid_hash(n).is_null());
        assert!(xeneon_config_get_target_model(n).is_null());
        assert!(xeneon_config_get_theme_mode(n).is_null());
        assert!(xeneon_config_get_starter_layout(n).is_null());

        // Metrics: numeric getters return their documented sentinels.
        let mh: *const MetricsHandle = ptr::null();
        assert_eq!(xeneon_metrics_get_cpu_usage(mh), 0.0);
        assert_eq!(xeneon_metrics_get_cpu_temp(mh), -1.0);
        assert_eq!(xeneon_metrics_get_ram_usage(mh), 0.0);
        assert_eq!(xeneon_metrics_get_ram_total(mh), 0);
        assert_eq!(xeneon_metrics_get_ram_used(mh), 0);
        assert_eq!(xeneon_metrics_get_cpu_cores(mh), 0);
        assert_eq!(xeneon_metrics_get_gpu_usage(mh), -1.0);
        assert_eq!(xeneon_metrics_get_gpu_temp(mh), -1.0);
        assert_eq!(xeneon_metrics_get_net_rx(mh), 0.0);
        assert_eq!(xeneon_metrics_get_net_tx(mh), 0.0);
        assert_eq!(xeneon_metrics_get_disk_total(mh), 0);
        assert_eq!(xeneon_metrics_get_disk_used(mh), 0);
        assert!(xeneon_metrics_to_json(mh).is_null());
    }

    // --- Config FFI setter/getter round-trips (in-memory, no disk) ---

    fn cstr(s: &str) -> CString {
        CString::new(s).unwrap()
    }

    #[test]
    fn existing_config_setters_roundtrip_through_to_json() {
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;

        assert_eq!(xeneon_config_set_first_run_complete(p), 0);
        assert_eq!(xeneon_config_set_autostart(p, 1), 0);
        assert_eq!(xeneon_config_set_reconnect(p, 0), 0);
        assert_eq!(xeneon_config_set_notify_disconnect(p, 1), 0);
        let mode = cstr("light");
        assert_eq!(xeneon_config_set_theme_mode(p, mode.as_ptr()), 0);
        let accent = cstr("#FF0000");
        assert_eq!(xeneon_config_set_theme_accent(p, accent.as_ptr()), 0);
        let layout = cstr("gaming");
        assert_eq!(xeneon_config_set_starter_layout(p, layout.as_ptr()), 0);
        let ui = cstr(r#"{"pages":[1]}"#);
        assert_eq!(xeneon_config_set_ui_state(p, ui.as_ptr()), 0);

        // starter_layout has a dedicated getter — round-trip it.
        let got_layout = unsafe { take(xeneon_config_get_starter_layout(p)) };
        assert_eq!(got_layout, "gaming");

        // Everything else observable via to_json.
        let json = unsafe { take(xeneon_config_to_json(p)) };
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["first_run_complete"], true);
        assert_eq!(v["startup"]["autostart"], true);
        assert_eq!(v["startup"]["reconnect_on_hotplug"], false);
        assert_eq!(v["startup"]["notify_on_disconnect"], true);
        assert_eq!(v["theme"]["mode"], "light");
        assert_eq!(v["theme"]["accent_color"], "#FF0000");
        assert_eq!(v["ui_state"], r#"{"pages":[1]}"#);
    }

    // --- BUG: no FFI setter for fallback_behavior ---

    #[test]
    fn bug_no_ffi_setter_for_fallback_behavior() {
        // Simulate the wizard choosing "Notify on missing display". There is no
        // xeneon_config_set_fallback_behavior, so the choice cannot be persisted
        // through the core API and the typed field stays at its default "hide".
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;
        let notify = cstr("notify");
        assert_eq!(xeneon_config_set_fallback_behavior(p, notify.as_ptr()), 0);
        let json = unsafe { take(xeneon_config_to_json(p)) };
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(
            v["display"]["fallback_behavior"], "notify",
            "BUG: no FFI setter for fallback_behavior; wizard 'notify' choice cannot be persisted"
        );
    }

    // --- BUG: no FFI setter for reduced_motion ---

    #[test]
    fn bug_no_ffi_setter_for_reduced_motion() {
        // Simulate the accessibility toggle "Reduce motion". Only theme_mode and
        // accent have setters, so reduced_motion can never be toggled via FFI.
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;
        assert_eq!(xeneon_config_set_reduced_motion(p, 1), 0);
        let json = unsafe { take(xeneon_config_to_json(p)) };
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(
            v["theme"]["reduced_motion"], true,
            "BUG: no FFI setter for reduced_motion; accessibility toggle is dead"
        );
    }

    // --- BUG: no FFI accessor for the typed widgets list ---

    #[test]
    fn bug_no_ffi_accessor_for_typed_widgets() {
        // The typed widgets.instances surface has no FFI setter/getter, so it can
        // never be populated through the core API (widget layout lives only in
        // the opaque ui_state). Anything trusting the typed list sees zero widgets.
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;
        let id = cstr("clock-1");
        let ty = cstr("clock");
        let settings = cstr(r#"{"format":"24h"}"#);
        assert_eq!(
            xeneon_config_add_widget(p, id.as_ptr(), ty.as_ptr(), 1, settings.as_ptr()),
            0
        );
        assert_eq!(xeneon_config_widget_count(p), 1);
        let json = unsafe { take(xeneon_config_to_json(p)) };
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        let instances = v["widgets"]["instances"].as_array().unwrap();
        assert!(
            !instances.is_empty(),
            "BUG: no FFI accessor for typed widgets; widgets.instances is permanently empty"
        );
    }

    // --- BUG: -1.0 'unavailable' sentinel collides with a real -1.0 reading ---

    #[test]
    fn bug_cpu_temp_sentinel_collides_with_subzero_reading() {
        // Unavailable (None) is the ONLY thing that maps to the NaN "no sensor"
        // signal.
        let none = MetricsHandle {
            metrics: SystemMetrics {
                cpu_temp_celsius: None,
                ..Default::default()
            },
        };
        assert!(
            xeneon_metrics_get_cpu_temp(&none as *const MetricsHandle).is_nan(),
            "an unavailable CPU temp (None) must be signalled with NaN"
        );
        // A genuine -1.0 °C reading (cold ambient / chilled rig) is a real value
        // and must be passed through EXACTLY, not swallowed as "unavailable".
        let real = MetricsHandle {
            metrics: SystemMetrics {
                cpu_temp_celsius: Some(-1.0),
                ..Default::default()
            },
        };
        assert_eq!(
            xeneon_metrics_get_cpu_temp(&real as *const MetricsHandle),
            -1.0,
            "a real -1.0 °C CPU reading must pass through, not collide with the 'unavailable' signal"
        );
    }

    #[test]
    fn bug_gpu_temp_sentinel_collides_with_subzero_reading() {
        let none = MetricsHandle {
            metrics: SystemMetrics {
                gpu_temp_celsius: None,
                ..Default::default()
            },
        };
        assert!(
            xeneon_metrics_get_gpu_temp(&none as *const MetricsHandle).is_nan(),
            "an unavailable GPU temp (None) must be signalled with NaN"
        );
        let real = MetricsHandle {
            metrics: SystemMetrics {
                gpu_temp_celsius: Some(-1.0),
                ..Default::default()
            },
        };
        assert_eq!(
            xeneon_metrics_get_gpu_temp(&real as *const MetricsHandle),
            -1.0,
            "a real -1.0 °C GPU reading must pass through, not collide with the 'unavailable' signal"
        );
    }

    // --- metrics_to_json: correct null-vs-number typing for optionals ---

    #[test]
    fn metrics_to_json_emits_all_keys_with_correct_types() {
        // Optional temps absent → JSON null; present → JSON number.
        let h = MetricsHandle {
            metrics: SystemMetrics {
                cpu_usage_percent: 12.5,
                cpu_temp_celsius: None,
                ram_usage_percent: 40.0,
                ram_total_bytes: 16,
                ram_used_bytes: 8,
                cpu_core_count: 8,
                gpu_usage_percent: Some(55.0),
                gpu_temp_celsius: None,
                net_rx_bytes_per_sec: 1.0,
                net_tx_bytes_per_sec: 2.0,
                disk_total_bytes: 100,
                disk_used_bytes: 50,
                disk_usage_percent: 50.0,
            },
        };
        let json = unsafe { take(xeneon_metrics_to_json(&h as *const MetricsHandle)) };
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();

        for key in [
            "cpu_usage_percent",
            "cpu_temp_celsius",
            "ram_usage_percent",
            "ram_total_bytes",
            "ram_used_bytes",
            "cpu_core_count",
            "gpu_usage_percent",
            "gpu_temp_celsius",
            "net_rx_bytes_per_sec",
            "net_tx_bytes_per_sec",
            "disk_total_bytes",
            "disk_used_bytes",
            "disk_usage_percent",
        ] {
            assert!(v.get(key).is_some(), "missing key {key}");
        }
        assert!(v["cpu_temp_celsius"].is_null());
        assert!(v["gpu_temp_celsius"].is_null());
        assert!(v["gpu_usage_percent"].is_number());
        assert_eq!(v["gpu_usage_percent"], 55.0);
        assert_eq!(v["cpu_core_count"], 8);
    }

    #[test]
    fn metrics_to_json_present_temps_are_numbers() {
        let h = MetricsHandle {
            metrics: SystemMetrics {
                cpu_temp_celsius: Some(42.0),
                gpu_temp_celsius: Some(50.0),
                ..Default::default()
            },
        };
        let json = unsafe { take(xeneon_metrics_to_json(&h as *const MetricsHandle)) };
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["cpu_temp_celsius"], 42.0);
        assert_eq!(v["gpu_temp_celsius"], 50.0);
    }

    // --- Logging FFI: init + log at every level, null-tolerant ---

    #[test]
    fn logging_ffi_init_and_log_all_levels() {
        // Null level → defaults to "info"; a valid level string is honored.
        xeneon_logging_init(std::ptr::null());
        let dbg = cstr("debug");
        xeneon_logging_init(dbg.as_ptr());

        let file = cstr("ffi.rs");
        let msg = cstr("hello from C");
        for level in 0..=4 {
            xeneon_logging_log(level, file.as_ptr(), 42, msg.as_ptr());
        }
        // Out-of-range level falls into the trace arm; null file/message tolerated.
        xeneon_logging_log(99, std::ptr::null(), 0, std::ptr::null());
    }

    // --- Config: target edid/connector/model setter↔getter round-trips ---

    #[test]
    fn config_target_fields_roundtrip_and_clear() {
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;

        let edid = cstr("deadbeef");
        let conn = cstr("DP-3");
        let model = cstr("XENEON EDGE");
        assert_eq!(xeneon_config_set_target_edid_hash(p, edid.as_ptr()), 0);
        assert_eq!(xeneon_config_set_target_connector(p, conn.as_ptr()), 0);
        assert_eq!(xeneon_config_set_target_model(p, model.as_ptr()), 0);

        unsafe {
            assert_eq!(take(xeneon_config_get_target_edid_hash(p)), "deadbeef");
            assert_eq!(take(xeneon_config_get_target_connector(p)), "DP-3");
            assert_eq!(take(xeneon_config_get_target_model(p)), "XENEON EDGE");
        }

        // Passing null clears each field → getters return null.
        assert_eq!(xeneon_config_set_target_edid_hash(p, std::ptr::null()), 0);
        assert_eq!(xeneon_config_set_target_connector(p, std::ptr::null()), 0);
        assert_eq!(xeneon_config_set_target_model(p, std::ptr::null()), 0);
        assert!(xeneon_config_get_target_edid_hash(p).is_null());
        assert!(xeneon_config_get_target_connector(p).is_null());
        assert!(xeneon_config_get_target_model(p).is_null());
    }

    // --- Config: fallback_behavior all variants + invalid + getter ---

    #[test]
    fn config_fallback_behavior_roundtrip_all_variants() {
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;

        for value in ["hide", "notify", "ask"] {
            let c = cstr(value);
            assert_eq!(xeneon_config_set_fallback_behavior(p, c.as_ptr()), 0);
            let got = unsafe { take(xeneon_config_get_fallback_behavior(p)) };
            assert_eq!(got, value);
        }
        // An unrecognized value is rejected with -1 and leaves the prior value.
        let bad = cstr("explode");
        assert_eq!(xeneon_config_set_fallback_behavior(p, bad.as_ptr()), -1);
        let still = unsafe { take(xeneon_config_get_fallback_behavior(p)) };
        assert_eq!(still, "ask");
        // Null handle / null value guards.
        assert_eq!(
            xeneon_config_set_fallback_behavior(std::ptr::null_mut(), bad.as_ptr()),
            -1
        );
        assert_eq!(xeneon_config_set_fallback_behavior(p, std::ptr::null()), -1);
        assert!(xeneon_config_get_fallback_behavior(std::ptr::null()).is_null());
    }

    // --- Config: reconnect + notify_disconnect getters (S10 disconnect wiring) ---

    #[test]
    fn config_reconnect_and_notify_disconnect_getters_roundtrip() {
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;

        // Getters read whatever the setters wrote (independent of the defaults).
        assert_eq!(xeneon_config_set_reconnect(p, 1), 0);
        assert_eq!(xeneon_config_get_reconnect(p), 1);
        assert_eq!(xeneon_config_set_reconnect(p, 0), 0);
        assert_eq!(xeneon_config_get_reconnect(p), 0);

        assert_eq!(xeneon_config_set_notify_disconnect(p, 1), 0);
        assert_eq!(xeneon_config_get_notify_disconnect(p), 1);
        assert_eq!(xeneon_config_set_notify_disconnect(p, 0), 0);
        assert_eq!(xeneon_config_get_notify_disconnect(p), 0);

        // Null handle → -1 sentinel.
        assert_eq!(xeneon_config_get_reconnect(std::ptr::null()), -1);
        assert_eq!(xeneon_config_get_notify_disconnect(std::ptr::null()), -1);
    }

    // --- Config: reduced_motion setter↔getter ---

    #[test]
    fn config_reduced_motion_roundtrip() {
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;
        assert_eq!(xeneon_config_get_reduced_motion(p), 0);
        assert_eq!(xeneon_config_set_reduced_motion(p, 1), 0);
        assert_eq!(xeneon_config_get_reduced_motion(p), 1);
        assert_eq!(xeneon_config_set_reduced_motion(p, 0), 0);
        assert_eq!(xeneon_config_get_reduced_motion(p), 0);
        assert_eq!(xeneon_config_get_reduced_motion(std::ptr::null()), -1);
        assert_eq!(
            xeneon_config_set_reduced_motion(std::ptr::null_mut(), 1),
            -1
        );
    }

    // --- Config: is_first_run + theme_mode getter + config_dir ---

    #[test]
    fn config_first_run_theme_and_dir() {
        // `xeneon_config_dir()` reads the process-global `XDG_CONFIG_HOME`; hold
        // the shared env lock so we don't race a concurrent locked writer
        // (`std::env::set_var` is unsound when another thread reads/writes env
        // concurrently).
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;
        assert_eq!(xeneon_config_is_first_run(p), 1);
        assert_eq!(xeneon_config_set_first_run_complete(p), 0);
        assert_eq!(xeneon_config_is_first_run(p), 0);

        let mode = unsafe { take(xeneon_config_get_theme_mode(p)) };
        assert_eq!(mode, "dark");

        // config_dir does not require a handle and always returns a non-empty path.
        let dir = unsafe { take(xeneon_config_dir()) };
        assert!(dir.contains("xeneon-edge-hub"));
    }

    // --- Config: typed widget accessors ---

    #[test]
    fn config_widget_accessors_full_cycle() {
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;
        assert_eq!(xeneon_config_widget_count(p), 0);

        let id = cstr("w1");
        let ty = cstr("clock");
        let settings = cstr(r#"{"format":"24h"}"#);
        assert_eq!(
            xeneon_config_add_widget(p, id.as_ptr(), ty.as_ptr(), 1, settings.as_ptr()),
            0
        );
        // Null settings_json → stored as JSON null, still counts.
        let id2 = cstr("w2");
        let ty2 = cstr("weather");
        assert_eq!(
            xeneon_config_add_widget(p, id2.as_ptr(), ty2.as_ptr(), 0, std::ptr::null()),
            0
        );
        assert_eq!(xeneon_config_widget_count(p), 2);

        let json = unsafe { take(xeneon_config_get_widgets_json(p)) };
        let arr: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(arr.as_array().unwrap().len(), 2);

        assert_eq!(xeneon_config_clear_widgets(p), 0);
        assert_eq!(xeneon_config_widget_count(p), 0);

        // Null-handle / null-id guards.
        assert_eq!(
            xeneon_config_add_widget(
                std::ptr::null_mut(),
                id.as_ptr(),
                ty.as_ptr(),
                1,
                std::ptr::null()
            ),
            -1
        );
        assert_eq!(
            xeneon_config_add_widget(p, std::ptr::null(), ty.as_ptr(), 1, std::ptr::null()),
            -1
        );
        assert_eq!(xeneon_config_clear_widgets(std::ptr::null_mut()), -1);
        assert_eq!(xeneon_config_widget_count(std::ptr::null()), -1);
        assert!(xeneon_config_get_widgets_json(std::ptr::null()).is_null());
    }

    // --- Config: starter_layout + ui_state null-clear branches ---

    #[test]
    fn config_starter_layout_and_ui_state_clear() {
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;
        // Absent → getter null.
        assert!(xeneon_config_get_starter_layout(p).is_null());
        assert!(xeneon_config_get_ui_state(p).is_null());

        let layout = cstr("minimal");
        assert_eq!(xeneon_config_set_starter_layout(p, layout.as_ptr()), 0);
        assert_eq!(
            unsafe { take(xeneon_config_get_starter_layout(p)) },
            "minimal"
        );
        // Null clears it back to None.
        assert_eq!(xeneon_config_set_starter_layout(p, std::ptr::null()), 0);
        assert!(xeneon_config_get_starter_layout(p).is_null());

        let ui = cstr("STATE");
        assert_eq!(xeneon_config_set_ui_state(p, ui.as_ptr()), 0);
        assert_eq!(unsafe { take(xeneon_config_get_ui_state(p)) }, "STATE");
        assert_eq!(xeneon_config_set_ui_state(p, std::ptr::null()), 0);
        assert!(xeneon_config_get_ui_state(p).is_null());
    }

    // --- Invalid UTF-8 must not panic across the ABI ---

    #[test]
    fn setters_tolerate_invalid_utf8_without_panic() {
        // 0xFF/0xFE are valid C-string bytes (no interior NUL) but invalid UTF-8.
        let bad = CString::new(vec![0x66, 0xff, 0xfe, 0x6f]).unwrap();
        let mut h = ConfigHandle {
            config: AppConfig::default(),
        };
        let p = &mut h as *mut ConfigHandle;
        // to_string_lossy replaces the invalid bytes rather than panicking.
        assert_eq!(xeneon_config_set_theme_mode(p, bad.as_ptr()), 0);
        assert_eq!(xeneon_config_set_theme_accent(p, bad.as_ptr()), 0);
        assert_eq!(xeneon_config_set_target_connector(p, bad.as_ptr()), 0);
        assert_eq!(xeneon_config_set_ui_state(p, bad.as_ptr()), 0);
        // Round-trips back through JSON without crashing.
        let json = unsafe { take(xeneon_config_to_json(p)) };
        assert!(json.contains("theme"));
    }

    // --- Display FFI over real EDID bytes ---

    fn sample_edid() -> Vec<u8> {
        let mut edid = vec![0u8; 128];
        edid[0..8].copy_from_slice(&[0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]);
        // Manufacturer COR.
        let mfg: u16 = ((3u16) << 10) | ((15u16) << 5) | 18u16;
        edid[8] = (mfg >> 8) as u8;
        edid[9] = (mfg & 0xFF) as u8;
        edid[21] = 39;
        edid[22] = 11;
        // Monitor-name descriptor in the second slot.
        edid[72 + 3] = 0xFC;
        for (i, b) in b"EDGE".iter().enumerate() {
            edid[72 + 5 + i] = *b;
        }
        for i in b"EDGE".len()..13 {
            edid[72 + 5 + i] = 0x0A;
        }
        edid
    }

    #[test]
    fn display_ffi_over_real_edid() {
        let edid = sample_edid();
        let ptr = edid.as_ptr();
        let len = edid.len();

        let hash = unsafe { take(xeneon_display_compute_edid_hash(ptr, len)) };
        assert_eq!(hash.len(), 64);
        let mfg = unsafe { take(xeneon_display_parse_manufacturer(ptr, len)) };
        assert_eq!(mfg, "COR");
        let name = unsafe { take(xeneon_display_parse_model_name(ptr, len)) };
        assert_eq!(name, "EDGE");
        assert_eq!(xeneon_display_is_xeneon_edge(ptr, len), 1);

        // Null/empty guards.
        assert!(xeneon_display_compute_edid_hash(std::ptr::null(), 0).is_null());
        assert!(xeneon_display_compute_edid_hash(ptr, 0).is_null());
        assert!(xeneon_display_parse_model_name(std::ptr::null(), 0).is_null());
        assert_eq!(xeneon_display_is_xeneon_edge(std::ptr::null(), 0), 0);
        // A non-Edge (all-zero) 128-byte EDID → not an Edge.
        let zero = [0u8; 128];
        assert_eq!(xeneon_display_is_xeneon_edge(zero.as_ptr(), zero.len()), 0);

        // Parsers that yield None must return null (not a bogus string). An
        // all-zero EDID has an invalid (0) manufacturer group and no 0xFC block.
        assert!(xeneon_display_parse_manufacturer(zero.as_ptr(), zero.len()).is_null());
        assert!(xeneon_display_parse_model_name(zero.as_ptr(), zero.len()).is_null());
    }

    // --- Metrics FFI: collect real handle and hit every accessor ---

    #[test]
    fn metrics_ffi_collect_and_all_getters() {
        let handle = xeneon_metrics_collect();
        assert!(!handle.is_null());
        let hc = handle as *const MetricsHandle;

        assert!(xeneon_metrics_get_cpu_usage(hc) >= 0.0);
        // Temp is either a real number or NaN, never a panic.
        let _ = xeneon_metrics_get_cpu_temp(hc);
        assert!(xeneon_metrics_get_ram_usage(hc) >= 0.0);
        assert!(xeneon_metrics_get_ram_total(hc) > 0);
        let _ = xeneon_metrics_get_ram_used(hc);
        assert!(xeneon_metrics_get_cpu_cores(hc) > 0);
        let _ = xeneon_metrics_get_gpu_usage(hc);
        let _ = xeneon_metrics_get_gpu_temp(hc);
        assert!(xeneon_metrics_get_net_rx(hc) >= 0.0);
        assert!(xeneon_metrics_get_net_tx(hc) >= 0.0);
        assert!(xeneon_metrics_get_disk_total(hc) > 0);
        let _ = xeneon_metrics_get_disk_used(hc);

        let json = unsafe { take(xeneon_metrics_to_json(hc)) };
        assert!(json.contains("cpu_usage_percent"));

        xeneon_metrics_free(handle);
    }

    #[test]
    fn cpu_temp_passes_through_ordinary_subzero_and_present() {
        // A present non-(-1.0) temperature is passed through unchanged, including
        // an ordinary sub-zero reading.
        let h = MetricsHandle {
            metrics: SystemMetrics {
                cpu_temp_celsius: Some(-5.0),
                gpu_temp_celsius: Some(-5.0),
                ..Default::default()
            },
        };
        assert_eq!(
            xeneon_metrics_get_cpu_temp(&h as *const MetricsHandle),
            -5.0
        );
        assert_eq!(
            xeneon_metrics_get_gpu_temp(&h as *const MetricsHandle),
            -5.0
        );
    }

    #[test]
    fn gpu_usage_present_value_passthrough() {
        let h = MetricsHandle {
            metrics: SystemMetrics {
                gpu_usage_percent: Some(73.0),
                ..Default::default()
            },
        };
        assert_eq!(
            xeneon_metrics_get_gpu_usage(&h as *const MetricsHandle),
            73.0
        );
    }

    // --- Config handle lifecycle via XDG_CONFIG_HOME override ---

    /// Serialize env-var-mutating tests; `XDG_CONFIG_HOME` is process-global.
    /// Shared crate-wide so config.rs and ffi.rs tests can't race each other.
    use crate::TEST_ENV_LOCK as ENV_LOCK;

    #[test]
    fn config_handle_load_mutate_save_free_lifecycle() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let dir = tempfile::tempdir().unwrap();
        std::env::set_var("XDG_CONFIG_HOME", dir.path());

        // Load (no file yet → defaults), mutate, save, free.
        let h = xeneon_config_load();
        assert!(!h.is_null());
        assert_eq!(xeneon_config_set_first_run_complete(h), 0);
        let mode = cstr("light");
        assert_eq!(xeneon_config_set_theme_mode(h, mode.as_ptr()), 0);
        let ui = cstr("PERSISTED");
        assert_eq!(xeneon_config_set_ui_state(h, ui.as_ptr()), 0);
        assert_eq!(xeneon_config_save(h as *const ConfigHandle), 0);
        xeneon_config_free(h);

        // Reload from disk: the mutations survived.
        let h2 = xeneon_config_load();
        assert!(!h2.is_null());
        assert_eq!(xeneon_config_is_first_run(h2), 0);
        assert_eq!(unsafe { take(xeneon_config_get_ui_state(h2)) }, "PERSISTED");
        xeneon_config_free(h2);

        // Reset returns a fresh default handle.
        let h3 = xeneon_config_reset();
        assert!(!h3.is_null());
        assert_eq!(xeneon_config_is_first_run(h3), 1);
        xeneon_config_free(h3);

        std::env::remove_var("XDG_CONFIG_HOME");
    }
}

#[cfg(test)]
mod proptests {
    use super::*;
    use proptest::prelude::*;

    /// Round-trip a live C-string back to Rust and free it.
    unsafe fn take(p: *mut c_char) -> String {
        assert!(!p.is_null());
        let s = CStr::from_ptr(p).to_string_lossy().into_owned();
        xeneon_string_free(p);
        s
    }

    proptest! {
        /// `xeneon_metrics_to_json` emits every key and losslessly round-trips all
        /// numeric fields for arbitrary finite metric values.
        #[test]
        fn metrics_to_json_roundtrips_all_fields(
            cpu in 0.0f64..100.0, ram in 0.0f64..100.0, disk in 0.0f64..100.0,
            ram_total in 0u64..u64::MAX, ram_used in 0u64..u64::MAX,
            cores in 0u32..1024,
            gpu in prop::option::of(0.0f64..100.0),
            cpu_temp in prop::option::of(-50.0f64..150.0),
            rx in 0.0f64..1e12, tx in 0.0f64..1e12,
        ) {
            let h = MetricsHandle {
                metrics: SystemMetrics {
                    cpu_usage_percent: cpu,
                    cpu_temp_celsius: cpu_temp,
                    ram_usage_percent: ram,
                    ram_total_bytes: ram_total,
                    ram_used_bytes: ram_used,
                    cpu_core_count: cores,
                    gpu_usage_percent: gpu,
                    gpu_temp_celsius: None,
                    net_rx_bytes_per_sec: rx,
                    net_tx_bytes_per_sec: tx,
                    disk_total_bytes: 100,
                    disk_used_bytes: 50,
                    disk_usage_percent: disk,
                },
            };
            let json = unsafe { take(xeneon_metrics_to_json(&h as *const MetricsHandle)) };
            let v: serde_json::Value = serde_json::from_str(&json).unwrap();
            for key in [
                "cpu_usage_percent", "cpu_temp_celsius", "ram_usage_percent",
                "ram_total_bytes", "ram_used_bytes", "cpu_core_count",
                "gpu_usage_percent", "gpu_temp_celsius", "net_rx_bytes_per_sec",
                "net_tx_bytes_per_sec", "disk_total_bytes", "disk_used_bytes",
                "disk_usage_percent",
            ] {
                prop_assert!(v.get(key).is_some(), "missing key {}", key);
            }
            prop_assert_eq!(v["ram_total_bytes"].as_u64().unwrap(), ram_total);
            prop_assert_eq!(v["ram_used_bytes"].as_u64().unwrap(), ram_used);
            prop_assert_eq!(v["cpu_core_count"].as_u64().unwrap(), cores as u64);
            // Value-check every float field, not just key-presence: a
            // wrong-value-under-right-key regression must fail. The JSON
            // round-trip can differ by a single ULP, so compare within a tight
            // relative tolerance (still orders of magnitude below any real
            // wrong-value bug).
            let close = |a: f64, b: f64| (a - b).abs() <= 1e-9 * a.abs().max(1.0);
            prop_assert!(close(v["cpu_usage_percent"].as_f64().unwrap(), cpu));
            prop_assert!(close(v["ram_usage_percent"].as_f64().unwrap(), ram));
            prop_assert!(close(v["disk_usage_percent"].as_f64().unwrap(), disk));
            prop_assert!(close(v["net_rx_bytes_per_sec"].as_f64().unwrap(), rx));
            prop_assert!(close(v["net_tx_bytes_per_sec"].as_f64().unwrap(), tx));
            match cpu_temp {
                Some(t) => prop_assert!(close(v["cpu_temp_celsius"].as_f64().unwrap(), t)),
                None => prop_assert!(v["cpu_temp_celsius"].is_null()),
            }
            match gpu {
                Some(g) => prop_assert!(close(v["gpu_usage_percent"].as_f64().unwrap(), g)),
                None => prop_assert!(v["gpu_usage_percent"].is_null()),
            }
        }

        /// Config setters never panic on arbitrary (NUL-free) C-string input,
        /// including non-UTF-8 byte sequences, and the handle stays serializable.
        #[test]
        fn config_setters_survive_arbitrary_cstring_input(
            bytes in prop::collection::vec(1u8..=255, 0..32)
        ) {
            let c = CString::new(bytes).unwrap();
            let mut h = ConfigHandle { config: AppConfig::default() };
            let p = &mut h as *mut ConfigHandle;
            prop_assert_eq!(xeneon_config_set_theme_mode(p, c.as_ptr()), 0);
            prop_assert_eq!(xeneon_config_set_target_model(p, c.as_ptr()), 0);
            prop_assert_eq!(xeneon_config_set_ui_state(p, c.as_ptr()), 0);
            let json = unsafe { take(xeneon_config_to_json(p)) };
            prop_assert!(serde_json::from_str::<serde_json::Value>(&json).is_ok());
        }
    }
}
