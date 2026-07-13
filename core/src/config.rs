use serde::{Deserialize, Serialize};
use std::fs;
use std::io;
use std::path::PathBuf;

/// Schema version this build understands. A loaded config is migrated to this
/// version; a config claiming a higher (foreign) version is clamped rather than
/// silently accepted verbatim.
pub const CURRENT_SCHEMA_VERSION: u32 = 1;

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
            schema_version: CURRENT_SCHEMA_VERSION,
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
    load_config_from(&config_path())
}

/// Load configuration from an explicit path. Behaves like `load_config` but
/// without depending on the process-global XDG path, so it can be tested with a
/// temporary directory.
fn load_config_from(path: &std::path::Path) -> Result<AppConfig, ConfigError> {
    if !path.exists() {
        tracing::info!(path = %path.display(), "No config file found, using defaults");
        return Ok(AppConfig::default());
    }

    let contents = fs::read_to_string(path).map_err(|e| ConfigError::Io {
        path: path.to_path_buf(),
        source: e,
    })?;

    let config: AppConfig = match toml::from_str(&contents) {
        Ok(cfg) => cfg,
        Err(e) => {
            // A corrupt file must not brick startup, but a full reset is data
            // loss: it re-triggers the first-run wizard and drops the saved
            // dashboard layout. Preserve the corrupt file under a *timestamped*
            // backup (so a good `.bak` is never clobbered), then salvage any
            // recoverable fields instead of returning bare defaults.
            tracing::error!(
                path = %path.display(),
                error = %e,
                "Config parse failed; backing up and salvaging recoverable state"
            );
            if let Err(be) = backup_corrupt_config(path) {
                tracing::warn!(error = %be, "Failed to back up unparseable config");
            }
            return Ok(salvage_partial_config(&contents));
        }
    };

    Ok(migrate_config(config))
}

/// Normalize a parsed config to the schema version this build supports.
///
/// A lower version is migrated up (currently a no-op field-compatible bump); a
/// higher (foreign) version is clamped so newer keys we do not understand are
/// not persisted back verbatim under a version we cannot honor.
fn migrate_config(mut config: AppConfig) -> AppConfig {
    if config.schema_version > CURRENT_SCHEMA_VERSION {
        tracing::warn!(
            found = config.schema_version,
            supported = CURRENT_SCHEMA_VERSION,
            "Config schema is newer than this build; clamping to supported version"
        );
        config.schema_version = CURRENT_SCHEMA_VERSION;
    } else if config.schema_version < CURRENT_SCHEMA_VERSION {
        // Future: apply stepwise migrations here (v1 -> v2 -> ...).
        config.schema_version = CURRENT_SCHEMA_VERSION;
    }
    config
}

/// Best-effort recovery of scalar fields from an unparseable config file.
///
/// TOML parsing already failed as a whole, so this does a lenient line scan for
/// the handful of fields whose loss is user-visible (the completed-setup flag
/// and the opaque UI-state document). Everything else falls back to defaults.
fn salvage_partial_config(contents: &str) -> AppConfig {
    let mut config = AppConfig::default();
    for line in contents.lines() {
        let line = line.trim();
        let (key, value) = match line.split_once('=') {
            Some((k, v)) => (k.trim(), v.trim()),
            None => continue,
        };
        match key {
            "first_run_complete" => {
                if value.starts_with("tru") {
                    config.first_run_complete = true;
                } else if value.starts_with("fal") {
                    config.first_run_complete = false;
                }
            }
            "ui_state" => {
                let v = value.trim_matches('"');
                if !v.is_empty() {
                    config.ui_state = Some(v.to_string());
                }
            }
            _ => {}
        }
    }
    config
}

/// Save configuration to the default XDG config path.
/// Creates parent directories if needed.
pub fn save_config(config: &AppConfig) -> Result<(), ConfigError> {
    let path = config_path();
    // config_path() always has a parent; fall back to CWD rather than panic.
    let dir = path.parent().unwrap_or_else(|| std::path::Path::new("."));

    fs::create_dir_all(dir).map_err(|e| ConfigError::Io {
        path: dir.to_path_buf(),
        source: e,
    })?;

    // Write to a temp file first, then rename (atomic on same filesystem).
    let tmp_path = path.with_extension("tmp");
    let contents = toml::to_string_pretty(config).map_err(|_e| ConfigError::Serialize)?;

    // Write + flush + fsync so the bytes are durable on disk before the rename;
    // otherwise a crash between rename and writeback can leave a truncated file.
    let write_result = (|| -> io::Result<()> {
        use std::io::Write;
        let mut f = fs::File::create(&tmp_path)?;
        f.write_all(contents.as_bytes())?;
        f.sync_all()?;
        Ok(())
    })();
    if let Err(e) = write_result {
        // Don't leave a stray temp file behind on failure.
        let _ = fs::remove_file(&tmp_path);
        return Err(ConfigError::Io {
            path: tmp_path,
            source: e,
        });
    }

    fs::rename(&tmp_path, &path).map_err(|e| {
        let _ = fs::remove_file(&tmp_path);
        ConfigError::Io {
            path: path.clone(),
            source: e,
        }
    })?;

    tracing::info!(path = %path.display(), "Configuration saved");
    Ok(())
}

/// Backup existing configuration before migration.
pub fn backup_config() -> Result<(), ConfigError> {
    backup_config_of(&config_path())
}

/// Back up `path` to a fixed `<name>.toml.bak` beside it. Extracted for testing.
///
/// This is the *canonical* good-config backup (single, overwritten each time a
/// known-good config is backed up). Corrupt configs must NOT use this — see
/// `backup_corrupt_config` — or they would clobber the last recoverable copy.
fn backup_config_of(path: &std::path::Path) -> Result<(), ConfigError> {
    if !path.exists() {
        return Ok(());
    }
    let backup = path.with_extension("toml.bak");
    fs::copy(path, &backup).map_err(|e| ConfigError::Io {
        path: backup,
        source: e,
    })?;
    Ok(())
}

/// Back up an unparseable `path` to a unique, timestamped file beside it so a
/// previously-saved good `.bak` is never overwritten by corrupt content.
/// Returns the backup path on success.
fn backup_corrupt_config(path: &std::path::Path) -> Result<PathBuf, ConfigError> {
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let file_name = path
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_else(|| "config.toml".to_string());

    // Guarantee uniqueness even for repeated corruption within the same second.
    let mut backup = path.with_file_name(format!("{file_name}.corrupt-{ts}.bak"));
    let mut counter: u32 = 1;
    while backup.exists() {
        backup = path.with_file_name(format!("{file_name}.corrupt-{ts}-{counter}.bak"));
        counter += 1;
    }

    fs::copy(path, &backup).map_err(|e| ConfigError::Io {
        path: backup.clone(),
        source: e,
    })?;
    Ok(backup)
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

    // --- FallbackBehavior / reduced_motion serde round-trips (typed layer) ---

    #[test]
    fn test_fallback_behavior_serde_variants() {
        // The typed enum round-trips through TOML with the documented renames.
        for (variant, rendered) in [
            (FallbackBehavior::Hide, "hide"),
            (FallbackBehavior::Notify, "notify"),
            (FallbackBehavior::Ask, "ask"),
        ] {
            let mut cfg = AppConfig::default();
            cfg.display.fallback_behavior = variant.clone();
            let s = toml::to_string_pretty(&cfg).unwrap();
            assert!(
                s.contains(&format!("fallback_behavior = \"{rendered}\"")),
                "expected {rendered} in:\n{s}"
            );
            let back: AppConfig = toml::from_str(&s).unwrap();
            assert_eq!(back.display.fallback_behavior, variant);
        }
    }

    // --- Persistence round-trip via explicit path (no global XDG dependency) ---

    #[test]
    fn test_save_then_load_roundtrip_preserves_all_fields() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.toml");

        let mut cfg = AppConfig::default();
        cfg.first_run_complete = true;
        cfg.display.fallback_behavior = FallbackBehavior::Notify;
        cfg.display.starter_layout = Some("gaming".to_string());
        cfg.theme.reduced_motion = true;
        cfg.startup.autostart = true;
        cfg.startup.reconnect_on_hotplug = false;
        cfg.startup.notify_on_disconnect = true;
        cfg.ui_state = Some(r#"{"pages":[]}"#.to_string());

        // Serialize + write ourselves (save_config uses the global path).
        let contents = toml::to_string_pretty(&cfg).unwrap();
        fs::write(&path, contents).unwrap();

        let loaded = load_config_from(&path).unwrap();
        assert!(loaded.first_run_complete);
        assert_eq!(loaded.display.fallback_behavior, FallbackBehavior::Notify);
        assert_eq!(loaded.display.starter_layout.as_deref(), Some("gaming"));
        assert!(loaded.theme.reduced_motion);
        assert!(loaded.startup.autostart);
        assert!(!loaded.startup.reconnect_on_hotplug);
        assert!(loaded.startup.notify_on_disconnect);
        assert_eq!(loaded.ui_state.as_deref(), Some(r#"{"pages":[]}"#));
    }

    #[test]
    fn test_load_missing_file_returns_default() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("does-not-exist.toml");
        let cfg = load_config_from(&path).unwrap();
        assert!(!cfg.first_run_complete);
    }

    // --- BUG: corrupt config triggers a silent full reset (data loss) ---

    #[test]
    fn bug_corrupt_config_silently_resets_and_loses_state() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.toml");
        // A torn / partially-written config (power-loss mid-write).
        fs::write(&path, "first_run_complete = tru\nthis is not = = toml").unwrap();

        let cfg = load_config_from(&path).unwrap();
        // Correct behavior: the loader should NOT silently discard the user's
        // completed-setup flag and dashboard layout. Today it returns
        // AppConfig::default(), re-triggering the first-run wizard and dropping
        // ui_state — a data-loss regression.
        assert!(
            cfg.first_run_complete,
            "BUG: corrupt config silently resets first_run_complete → wizard reappears"
        );
    }

    // --- BUG: repeated corruption clobbers the only recoverable backup ---

    #[test]
    fn bug_repeated_corruption_clobbers_prior_backup() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.toml");

        // 1) A good config with a real saved layout exists and is backed up.
        let mut good = AppConfig::default();
        good.first_run_complete = true;
        good.ui_state = Some("LAYOUT_V1_IRREPLACEABLE".to_string());
        fs::write(&path, toml::to_string_pretty(&good).unwrap()).unwrap();
        backup_config_of(&path).unwrap(); // config.toml.bak now holds LAYOUT_V1

        // 2) The config is later corrupted; loading backs it up again to the
        //    SAME fixed .bak filename, overwriting the good backup.
        fs::write(&path, "garbage = = = not toml").unwrap();
        let _ = load_config_from(&path);

        let bak = fs::read_to_string(path.with_extension("toml.bak")).unwrap();
        assert!(
            bak.contains("LAYOUT_V1_IRREPLACEABLE"),
            "BUG: fixed .bak filename let a corrupt config overwrite the recoverable backup"
        );
    }

    // --- BUG: schema_version migrations are unimplemented (no-op) ---

    #[test]
    fn bug_higher_schema_version_is_not_migrated() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.toml");
        let mut cfg = AppConfig::default();
        cfg.schema_version = 99; // a version newer than this build understands
        fs::write(&path, toml::to_string_pretty(&cfg).unwrap()).unwrap();

        let loaded = load_config_from(&path).unwrap();
        // Correct behavior: a migration step should normalize the config to the
        // schema version this build actually supports (1). Today the "Future:
        // run schema migrations here" comment is a no-op, so the foreign version
        // is loaded verbatim with no migration.
        assert_eq!(
            loaded.schema_version, 1,
            "BUG: schema migrations are unimplemented; foreign schema_version loaded verbatim"
        );
    }
}
