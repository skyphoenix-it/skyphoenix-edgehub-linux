#pragma once

#include <QDebug>
#include <QObject>
#include <QString>
#include <QUrl>

#include "autostart.h"
#include "xeneon_core.h"
#include "xeneon_string.h"

// --- Display hotplug (S10) disconnect/reconnect policy ---
//
// Pure decision helpers extracted from the hub's live QScreen hotplug handlers so
// the branching can be unit-tested headlessly (the actual window migration needs a
// live QScreen and is exercised by the smoke test instead). They translate the
// three write-only config keys — reconnect / notify_disconnect / fallback_behavior
// — into what the hub should do when the target Edge appears or disappears.

struct DisconnectDecision {
    bool hideWindow = false;  // blank/hide the hub window (fallback_behavior == "hide")
    bool notify = false;      // surface a "display disconnected" notice to QML
};

// Decide how the hub reacts when a screen is removed.
//   wasTarget        — the removed screen was the hub's current placement target.
//   fallbackBehavior — "hide" | "notify" | "ask" (from config.display.fallback_behavior).
//   notifyDisconnect — the notify-on-disconnect user preference.
// Only a loss of the TARGET screen triggers any behavior; unrelated screens are ignored.
inline DisconnectDecision decideOnScreenRemoved(bool wasTarget,
                                                const QString& fallbackBehavior,
                                                bool notifyDisconnect) {
    DisconnectDecision d;
    if (!wasTarget)
        return d;
    if (fallbackBehavior == QLatin1String("hide"))
        d.hideWindow = true;
    if (notifyDisconnect)
        d.notify = true;
    return d;
}

// Decide whether to migrate the hub window back onto a newly-added screen.
//   reconnectEnabled — the reconnect-on-hotplug preference (config.startup).
//   isTarget         — the added screen matches the hub's target (re-run of the match).
inline bool shouldReconnectToScreen(bool reconnectEnabled, bool isTarget) {
    return reconnectEnabled && isTarget;
}

// --- WizardBridge: QObject exposed to QML for first-run persistence ---

class WizardBridge : public QObject {
    Q_OBJECT
public:
    explicit WizardBridge(ConfigHandle* config, QObject* parent = nullptr)
        : QObject(parent), m_config(config) {}

    Q_INVOKABLE bool completeWizard(const QString& edidHash, const QString& connector,
                                     const QString& model, const QString& layout,
                                     const QString& themeMode, const QString& themeAccent,
                                     bool autostart, bool reconnect, bool notifyDisconnect) {
        if (!m_config) return false;

        // Persist display identity
        if (!edidHash.isEmpty())
            xeneon_config_set_target_edid_hash(m_config, edidHash.toUtf8().constData());
        if (!connector.isEmpty())
            xeneon_config_set_target_connector(m_config, connector.toUtf8().constData());
        if (!model.isEmpty())
            xeneon_config_set_target_model(m_config, model.toUtf8().constData());

        // Persist layout choice
        if (!layout.isEmpty())
            xeneon_config_set_starter_layout(m_config, layout.toUtf8().constData());

        // Persist theme
        if (!themeMode.isEmpty())
            xeneon_config_set_theme_mode(m_config, themeMode.toUtf8().constData());
        if (!themeAccent.isEmpty())
            xeneon_config_set_theme_accent(m_config, themeAccent.toUtf8().constData());

        // Persist startup preferences
        xeneon_config_set_autostart(m_config, autostart ? 1 : 0);
        xeneon_config_set_reconnect(m_config, reconnect ? 1 : 0);
        xeneon_config_set_notify_disconnect(m_config, notifyDisconnect ? 1 : 0);

        // Actually install/remove the XDG autostart entry to match the choice.
        applyAutostart(autostart);

        // Mark first-run complete
        xeneon_config_set_first_run_complete(m_config);

        // Save to disk
        int saved = xeneon_config_save(m_config);
        if (saved == 0) {
            qInfo() << "Wizard complete. Target:" << model << "Layout:" << layout
                     << "Theme:" << themeMode << "Autostart:" << autostart;
        } else {
            qWarning() << "Wizard complete but config save failed";
        }
        return saved == 0;
    }

    // Detach from the Rust config handle before it is freed at shutdown, so any
    // late QML call becomes a guarded no-op instead of a use-after-free.
    void detach() { m_config = nullptr; }

private:
    ConfigHandle* m_config;
};

// --- ConfigBridge: runtime config access for QML (layout persistence, etc.) ---

class ConfigBridge : public QObject {
    Q_OBJECT
public:
    explicit ConfigBridge(ConfigHandle* config, QObject* parent = nullptr)
        : QObject(parent), m_config(config) {}

    // Opaque UI-state JSON (dashboard layout + per-widget settings + appearance).
    // Build version, injected at compile time via -DXENEON_VERSION (git describe;
    // or the pkgver for packaged builds). Falls back to "dev" for syntax-only builds.
    Q_INVOKABLE QString appVersion() const {
#ifdef XENEON_VERSION
        return QStringLiteral(XENEON_VERSION);
#else
        return QStringLiteral("dev");
#endif
    }

    Q_INVOKABLE QString uiState() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_get_ui_state(m_config));
        return s.qstring();
    }

    // Persist the UI-state JSON and flush to disk atomically. Returns success.
    Q_INVOKABLE bool saveUiState(const QString& json) {
        if (!m_config) return false;
        xeneon_config_set_ui_state(m_config, json.toUtf8().constData());
        bool ok = xeneon_config_save(m_config) == 0;
        if (!ok) qWarning() << "Failed to persist UI state";
        return ok;
    }

    // Apply a UI-state document pushed from the companion Manager app over IPC:
    // persist it to the in-memory config + disk. The live reload is handled by
    // main() re-pushing the JSON to QML. Kept separate from saveUiState so intent
    // is explicit at the call site.
    bool applyExternalUiState(const QString& json) {
        if (!m_config || json.isEmpty()) return false;
        xeneon_config_set_ui_state(m_config, json.toUtf8().constData());
        return xeneon_config_save(m_config) == 0;
    }

    // Starter layout id chosen during the wizard ("productivity"/"gaming"/…).
    Q_INVOKABLE QString starterLayout() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_get_starter_layout(m_config));
        return s.qstring();
    }

    // Resolve a wallpaper/image path to a loadable URL. Scheme URLs (qrc:, http:,
    // file:) pass through untouched; a local path is percent-encoded via QUrl so
    // spaces / '#' / other reserved characters don't produce a malformed URL that
    // silently fails to load. Mirrors the Manager's backend.imageUrl() so the same
    // stored appearance.wallpaper resolves identically in the hub and the Manager.
    Q_INVOKABLE QString imageUrl(const QString& path) const {
        if (path.isEmpty()) return QString();
        if (path.contains("://")) return path;
        if (path.startsWith('/')) return QUrl::fromLocalFile(path).toString();
        return path;
    }

    // Display hotplug preferences (S10) — read by the hub's QScreen handlers and
    // available to QML for the Display/Diagnostics surfaces. These mirror the three
    // formerly write-only keys so QML can render + honor them.
    Q_INVOKABLE bool reconnectOnHotplug() const {
        if (!m_config) return false;
        return xeneon_config_get_reconnect(m_config) == 1;
    }
    Q_INVOKABLE bool notifyOnDisconnect() const {
        if (!m_config) return false;
        return xeneon_config_get_notify_disconnect(m_config) == 1;
    }
    // "hide" | "notify" | "ask" (empty only if detached).
    Q_INVOKABLE QString fallbackBehavior() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_get_fallback_behavior(m_config));
        return s.qstring();
    }

    // Full pretty-printed config JSON (for the Diagnostics → Config tab).
    Q_INVOKABLE QString configJson() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_to_json(m_config));
        return s.qstring();
    }

    // Detach from the Rust config handle before it is freed at shutdown, so any
    // late QML call becomes a guarded no-op instead of a use-after-free.
    void detach() { m_config = nullptr; }

private:
    ConfigHandle* m_config;
};
