#ifndef XENEON_CORE_H
#define XENEON_CORE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// === Opaque Handles ===
typedef struct ConfigHandle ConfigHandle;
typedef struct MetricsHandle MetricsHandle;

// === Logging ===

typedef enum {
    XENEON_LOG_ERROR = 0,
    XENEON_LOG_WARN  = 1,
    XENEON_LOG_INFO  = 2,
    XENEON_LOG_DEBUG = 3,
    XENEON_LOG_TRACE = 4,
} XeneonLogLevel;

void xeneon_logging_init(const char* level);
void xeneon_logging_log(int level, const char* file, int line, const char* message);

// === Configuration ===
ConfigHandle* xeneon_config_load(void);
int xeneon_config_save(const ConfigHandle* handle);
void xeneon_config_free(ConfigHandle* handle);
int xeneon_config_is_first_run(const ConfigHandle* handle);
int xeneon_config_set_first_run_complete(ConfigHandle* handle);

char* xeneon_config_get_target_edid_hash(const ConfigHandle* handle);
char* xeneon_config_get_target_connector(const ConfigHandle* handle);
char* xeneon_config_get_target_model(const ConfigHandle* handle);

int xeneon_config_set_target_edid_hash(ConfigHandle* handle, const char* hash);
int xeneon_config_set_target_connector(ConfigHandle* handle, const char* connector);
int xeneon_config_set_target_model(ConfigHandle* handle, const char* model);

char* xeneon_config_get_theme_mode(const ConfigHandle* handle);
char* xeneon_config_dir(void);
char* xeneon_config_to_json(const ConfigHandle* handle);
ConfigHandle* xeneon_config_reset(void);

int xeneon_config_set_theme_mode(ConfigHandle* handle, const char* mode);
int xeneon_config_set_theme_accent(ConfigHandle* handle, const char* color);
int xeneon_config_set_autostart(ConfigHandle* handle, int enabled);
int xeneon_config_set_reconnect(ConfigHandle* handle, int enabled);
int xeneon_config_set_notify_disconnect(ConfigHandle* handle, int enabled);
int xeneon_config_set_starter_layout(ConfigHandle* handle, const char* layout_id);
char* xeneon_config_get_starter_layout(const ConfigHandle* handle);

// Display fallback behavior: "hide" | "notify" | "ask".
// set returns 0 on success, -1 on null handle / null / unrecognized value.
int xeneon_config_set_fallback_behavior(ConfigHandle* handle, const char* behavior);
char* xeneon_config_get_fallback_behavior(const ConfigHandle* handle); // caller frees

// "Reduce motion" accessibility preference.
int xeneon_config_set_reduced_motion(ConfigHandle* handle, int enabled);
int xeneon_config_get_reduced_motion(const ConfigHandle* handle); // 1/0, -1 on error

// Typed widget instances (widgets.instances). settings_json is opaque JSON.
int xeneon_config_add_widget(ConfigHandle* handle, const char* id,
                             const char* widget_type, int enabled,
                             const char* settings_json);
int xeneon_config_widget_count(const ConfigHandle* handle); // -1 on null handle
int xeneon_config_clear_widgets(ConfigHandle* handle);
char* xeneon_config_get_widgets_json(const ConfigHandle* handle); // JSON array; caller frees

// Opaque UI-state JSON (dashboard layout + per-widget settings + appearance).
char* xeneon_config_get_ui_state(const ConfigHandle* handle);
int xeneon_config_set_ui_state(ConfigHandle* handle, const char* json);

// === Display Utilities ===
char* xeneon_display_compute_edid_hash(const uint8_t* edid_data, size_t len);
char* xeneon_display_parse_manufacturer(const uint8_t* edid_data, size_t len);
char* xeneon_display_parse_model_name(const uint8_t* edid_data, size_t len);
int xeneon_display_is_xeneon_edge(const uint8_t* edid_data, size_t len);

// === System Metrics ===
MetricsHandle* xeneon_metrics_collect(void);
void xeneon_metrics_free(MetricsHandle* handle);

double xeneon_metrics_get_cpu_usage(const MetricsHandle* handle);
double xeneon_metrics_get_cpu_temp(const MetricsHandle* handle);  // NaN if unavailable (isnan)
double xeneon_metrics_get_ram_usage(const MetricsHandle* handle);
uint64_t xeneon_metrics_get_ram_total(const MetricsHandle* handle);
uint64_t xeneon_metrics_get_ram_used(const MetricsHandle* handle);
uint32_t xeneon_metrics_get_cpu_cores(const MetricsHandle* handle);
double xeneon_metrics_get_gpu_usage(const MetricsHandle* handle); // -1.0 if unavailable
double xeneon_metrics_get_gpu_temp(const MetricsHandle* handle);  // NaN if unavailable (isnan)
double xeneon_metrics_get_net_rx(const MetricsHandle* handle);    // bytes/sec
double xeneon_metrics_get_net_tx(const MetricsHandle* handle);    // bytes/sec
uint64_t xeneon_metrics_get_disk_total(const MetricsHandle* handle);
uint64_t xeneon_metrics_get_disk_used(const MetricsHandle* handle);
char* xeneon_metrics_to_json(const MetricsHandle* handle);

// === String Utilities ===
void xeneon_string_free(char* s);

#ifdef __cplusplus
}
#endif

#endif // XENEON_CORE_H

