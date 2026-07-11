use serde::{Deserialize, Serialize};
use std::fs;
use std::io;
use std::path::PathBuf;

/// Top-level application configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    /// Schema version for migration support.
    pub schema_version: u32,
    /// Whether first-run wizard has been completed.
    pub first_run_complete: bool,
    /// Display configuration.
    pub display: DisplayConfig,
    /// Theme settings.
    pub theme: ThemeConfig,
    /// Startup behavior.
    pub startup: StartupConfig,
    /// Widget configurations.
    pub widgets: WidgetsConfig,
    /// Opaque UI-state document (JSON) owned by the QML layer: the full dashboard
    /// layout (pages → slots → widget instances), per-widget settings/state, and
    /// runtime appearance overrides. Kept opaque so the UI schema can evolve
    /// without churning the Rust config structs. `None` until the UI saves once.
    #[serde(default)]
    pub ui_state: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DisplayConfig {
    /// SHA-256 of the EDID block (hex-encoded) for resilient display identity.
    pub target_edid_hash: Option<String>,
    /// Connector name fallback (e.g., "DP-2").
    pub target_connector: Option<String>,
    /// Display model name from EDID (for user display).
    pub target_model: Option<String>,
    /// Behavior when target display is missing.
    #[serde(default)]
    pub fallback_behavior: FallbackBehavior,
    /// Starter layout selected during first-run wizard.
    #[serde(default)]
    pub starter_layout: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub enum FallbackBehavior {
    #[serde(rename = "hide")]
    #[default]
    Hide,
    #[serde(rename = "notify")]
    Notify,
    #[serde(rename = "ask")]
    Ask,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThemeConfig {
    #[serde(default = "default_theme_mode")]
    pub mode: String,
    #[serde(default = "default_accent_color")]
    pub accent_color: String,
    #[serde(default)]
    pub reduced_motion: bool,
}

impl Default for ThemeConfig {
    fn default() -> Self {
        Self {
            mode: default_theme_mode(),
            accent_color: default_accent_color(),
            reduced_motion: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StartupConfig {
    #[serde(default)]
    pub autostart: bool,
    #[serde(default = "default_true")]
    pub reconnect_on_hotplug: bool,
    #[serde(default)]
    pub notify_on_disconnect: bool,
}

impl Default for StartupConfig {
    fn default() -> Self {
        Self {
            autostart: false,
            reconnect_on_hotplug: true,
            notify_on_disconnect: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WidgetsConfig {
    /// Version of widget configuration schema.
    pub version: u32,
    /// Configured widget instances.
    #[serde(default)]
    pub instances: Vec<WidgetInstance>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WidgetInstance {
    pub id: String,
    #[serde(rename = "type")]
    pub widget_type: String,
    pub enabled: bool,
    pub settings: serde_json::Value,
}

// --- Defaults ---

fn default_theme_mode() -> String {
    "dark".to_string()
}

fn default_accent_color() -> String {
    "#58A6FF".to_string()
}

fn default_true() -> bool {
    true
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            schema_version: 1,
            first_run_complete: false,
            display: DisplayConfig {
                target_edid_hash: None,
                target_connector: None,
                target_model: None,
                fallback_behavior: FallbackBehavior::default(),
                starter_layout: None,
            },
            theme: ThemeConfig::default(),
            startup: StartupConfig::default(),
            widgets: WidgetsConfig {
                version: 1,
                instances: Vec::new(),
            },
            ui_state: None,
        }
    }
}

// --- Config path ---

pub fn config_dir() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("xeneon-edge-hub")
}

pub fn config_path() -> PathBuf {
    config_dir().join("config.toml")
}

// --- Load / Save ---

/// Load configuration from the default XDG config path.
/// Returns default configuration if the file does not exist.
pub fn load_config() -> Result<AppConfig, ConfigError> {
    let path = config_path();
    if !path.exists() {
        tracing::info!(path = %path.display(), "No config file found, using defaults");
        return Ok(AppConfig::default());
    }

    let contents = fs::read_to_string(&path).map_err(|e| ConfigError::Io {
        path: path.clone(),
        source: e,
    })?;

    let config: AppConfig =
        toml::from_str(&contents).map_err(|_e| ConfigError::Parse { path: path.clone() })?;

    // Future: run schema migrations here based on config.schema_version

    Ok(config)
}

/// Save configuration to the default XDG config path.
/// Creates parent directories if needed.
pub fn save_config(config: &AppConfig) -> Result<(), ConfigError> {
    let path = config_path();
    let dir = path.parent().unwrap();

    fs::create_dir_all(dir).map_err(|e| ConfigError::Io {
        path: dir.to_path_buf(),
        source: e,
    })?;

    // Write to a temp file first, then rename (atomic on same filesystem).
    let tmp_path = path.with_extension("tmp");
    let contents = toml::to_string_pretty(config).map_err(|_e| ConfigError::Serialize)?;

    fs::write(&tmp_path, &contents).map_err(|e| ConfigError::Io {
        path: tmp_path.clone(),
        source: e,
    })?;

    fs::rename(&tmp_path, &path).map_err(|e| ConfigError::Io {
        path: path.clone(),
        source: e,
    })?;

    tracing::info!(path = %path.display(), "Configuration saved");
    Ok(())
}

/// Backup existing configuration before migration.
pub fn backup_config() -> Result<(), ConfigError> {
    let path = config_path();
    if !path.exists() {
        return Ok(());
    }
    let backup = path.with_extension("toml.bak");
    fs::copy(&path, &backup).map_err(|e| ConfigError::Io {
        path: backup,
        source: e,
    })?;
    Ok(())
}

/// Reset configuration to defaults.
pub fn reset_config() -> Result<AppConfig, ConfigError> {
    let path = config_path();
    if path.exists() {
        fs::remove_file(&path).map_err(|e| ConfigError::Io {
            path: path.clone(),
            source: e,
        })?;
    }
    Ok(AppConfig::default())
}

// --- Error ---

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("I/O error at {path}: {source}")]
    Io { path: PathBuf, source: io::Error },
    #[error("Parse error in {path}")]
    Parse { path: PathBuf },
    #[error("Serialization error")]
    Serialize,
}

// --- Tests ---

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = AppConfig::default();
        assert_eq!(config.schema_version, 1);
        assert!(!config.first_run_complete);
        assert_eq!(config.theme.mode, "dark");
    }

    #[test]
    fn test_roundtrip_config() {
        let mut config = AppConfig::default();
        config.display.target_edid_hash = Some("abc123".to_string());
        config.display.target_connector = Some("DP-2".to_string());

        let serialized = toml::to_string_pretty(&config).unwrap();
        let deserialized: AppConfig = toml::from_str(&serialized).unwrap();
        assert_eq!(
            deserialized.display.target_edid_hash,
            Some("abc123".to_string())
        );
    }

    #[test]
    fn test_ui_state_roundtrip_and_default_none() {
        // Fresh config has no UI state.
        let mut config = AppConfig::default();
        assert!(config.ui_state.is_none());

        // Round-trips through TOML as an opaque JSON string.
        config.ui_state = Some(r#"{"pages":[{"name":"System","slots":[]}]}"#.to_string());
        let serialized = toml::to_string_pretty(&config).unwrap();
        let deserialized: AppConfig = toml::from_str(&serialized).unwrap();
        assert_eq!(deserialized.ui_state, config.ui_state);
    }

    #[test]
    fn test_old_config_without_ui_state_still_parses() {
        // A config file written before ui_state existed must still load (serde default).
        let legacy = r##"
schema_version = 1
first_run_complete = true
[display]
fallback_behavior = "hide"
[theme]
mode = "dark"
accent_color = "#58A6FF"
reduced_motion = false
[startup]
autostart = false
reconnect_on_hotplug = true
notify_on_disconnect = false
[widgets]
version = 1
instances = []
"##;
        let cfg: AppConfig = toml::from_str(legacy).unwrap();
        assert!(cfg.ui_state.is_none());
        assert!(cfg.first_run_complete);
    }

    #[test]
    fn test_config_serialization_has_expected_keys() {
        let config = AppConfig::default();
        let toml_str = toml::to_string_pretty(&config).unwrap();
        assert!(toml_str.contains("schema_version"));
        assert!(toml_str.contains("first_run_complete"));
        assert!(toml_str.contains("[display]"));
        assert!(toml_str.contains("[theme]"));
    }
}
