#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QObject>
#include <QString>
#include <QVariant>

#include <optional>

// ─────────────────────────────────────────────────────────────────────────────
// SystemSettingsProbe - the OS "reduce motion" signal for QML.
//
// QML cannot read this on its own: there is NO reduce-motion style hint in any
// Qt 6 (verified on 6.11 - `Qt.styleHints.useReducedMotion === undefined`; the
// only a11y hint is `accessibility.contrastPreference`, itself 6.10+). So the
// platform read happens here, over the XDG desktop portal's Settings interface
// (org.freedesktop.portal.Desktop, org.freedesktop.portal.Settings), and QML
// binds `theme.systemReduceMotion` to the `reduceMotion` property.
//
// Two keys are read, and BOTH are real (verified against a live portal on KDE
// Plasma, Settings version 2):
//   • "org.freedesktop.appearance" / "reduced-motion"  (u: 1 = reduce) - the
//     standardized cross-desktop key (newer xdg-desktop-portal releases).
//   • "org.gnome.desktop.interface" / "enable-animations"  (b: false = reduce)
//     - GNOME's key, which compat backends (including KDE's) also answer.
// KDE's own kdeglobals AnimationDurationFactor is deliberately NOT probed:
// on a real Plasma box ReadOne("org.kde.kdeglobals.KDE",
// "AnimationDurationFactor") fails with "Requested setting not found" (the key
// only appears via ReadAll, typed as a string), and the two keys above already
// cover Plasma - its portal backend flips them when animations are disabled.
//
// The two sources are OR-ed: any OS-level "reduce" wins. That is the a11y-safe
// combination, and the user can still force motion back on per-device via
// theme.reduceMotionPreference === "off" (explicit beats OS - see Theme.qml).
//
// Failure policy (a hard requirement): no session bus, no portal, no key →
// `reduceMotion` simply stays false and NOTHING is logged. A dashboard
// appliance must not spam the journal because a headless box has no portal.
//
// Live updates: the portal's SettingChanged(ns, key, value) signal is
// subscribed BEFORE the initial reads, so a toggle that races startup is not
// lost; a settings change propagates without a restart.
//
// Testing: applySetting()/interpretSetting()/unwrapDBusVariant() are the pure
// parsing seam - tests drive them directly with crafted variants instead of
// depending on the host's real desktop settings (see
// tests/cpp/tst_system_settings_probe.cpp).
// ─────────────────────────────────────────────────────────────────────────────
class SystemSettingsProbe : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool reduceMotion READ reduceMotion NOTIFY reduceMotionChanged)
public:
    explicit SystemSettingsProbe(QObject* parent = nullptr) : QObject(parent) {}

    bool reduceMotion() const { return m_effective; }

    // Connect + subscribe + kick off the initial async reads. Separate from the
    // ctor so tests can exercise the parsing seam without ever touching D-Bus.
    void start() {
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (!bus.isConnected())
            return;  // no bus → no signal, silently (see failure policy above)

        // Subscribe first so a change emitted between the initial read and the
        // subscription cannot be lost.
        bus.connect(QStringLiteral("org.freedesktop.portal.Desktop"),
                    QStringLiteral("/org/freedesktop/portal/desktop"),
                    QStringLiteral("org.freedesktop.portal.Settings"),
                    QStringLiteral("SettingChanged"),
                    this, SLOT(onSettingChanged(QString,QString,QDBusVariant)));

        readKey(QStringLiteral("org.freedesktop.appearance"),
                QStringLiteral("reduced-motion"), /*legacyRead=*/false);
        readKey(QStringLiteral("org.gnome.desktop.interface"),
                QStringLiteral("enable-animations"), /*legacyRead=*/false);
    }

    // ── Pure parsing seam (unit-testable, no D-Bus needed) ───────────────────

    // Portal values arrive wrapped: ReadOne returns v(x), the deprecated Read
    // returns v(v(x)), SettingChanged carries v(x). Peel every QDBusVariant
    // layer so the interpreters below see the plain value.
    static QVariant unwrapDBusVariant(QVariant v) {
        while (v.userType() == qMetaTypeId<QDBusVariant>())
            v = qvariant_cast<QDBusVariant>(v).variant();
        return v;
    }

    // Does this (namespace, key, value) express a reduce-motion opinion?
    //   engaged true  → OS asks to reduce motion
    //   engaged false → OS explicitly does not
    //   nullopt       → not a key we understand (ignored)
    static std::optional<bool> interpretSetting(const QString& ns, const QString& key,
                                                const QVariant& value) {
        const QVariant v = unwrapDBusVariant(value);
        if (ns == QLatin1String("org.freedesktop.appearance") &&
            key == QLatin1String("reduced-motion")) {
            // Spec convention (as for contrast/color-scheme): 0 = no preference,
            // 1 = reduce. Unknown future values are treated as "no preference".
            return v.toUInt() == 1;
        }
        if (ns == QLatin1String("org.gnome.desktop.interface") &&
            key == QLatin1String("enable-animations")) {
            return !v.toBool();
        }
        return std::nullopt;
    }

    // Fold one setting into the per-source state and recompute the OR. Public:
    // this is the seam the tests drive with crafted variants.
    void applySetting(const QString& ns, const QString& key, const QVariant& value) {
        const std::optional<bool> opinion = interpretSetting(ns, key, value);
        if (!opinion.has_value())
            return;
        if (ns == QLatin1String("org.freedesktop.appearance"))
            m_appearance = opinion;
        else
            m_gnome = opinion;
        const bool eff = m_appearance.value_or(false) || m_gnome.value_or(false);
        if (eff != m_effective) {
            m_effective = eff;
            emit reduceMotionChanged();
        }
    }

signals:
    void reduceMotionChanged();

private slots:
    void onSettingChanged(const QString& ns, const QString& key, const QDBusVariant& value) {
        applySetting(ns, key, value.variant());
    }

private:
    void readKey(const QString& ns, const QString& key, bool legacyRead) {
        QDBusMessage msg = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.portal.Desktop"),
            QStringLiteral("/org/freedesktop/portal/desktop"),
            QStringLiteral("org.freedesktop.portal.Settings"),
            legacyRead ? QStringLiteral("Read") : QStringLiteral("ReadOne"));
        msg << ns << key;
        auto* watcher = new QDBusPendingCallWatcher(
            QDBusConnection::sessionBus().asyncCall(msg, 3000), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, ns, key, legacyRead](QDBusPendingCallWatcher* w) {
            w->deleteLater();
            QDBusPendingReply<QDBusVariant> reply = *w;
            if (reply.isError()) {
                // ReadOne is Settings v2 (2023). An older portal only has the
                // deprecated Read (returns v(v(x)) - unwrap handles the extra
                // layer). Any other error ("setting not found", no portal at
                // all) means "no signal": stay false, log nothing.
                if (!legacyRead &&
                    reply.error().type() == QDBusError::UnknownMethod)
                    readKey(ns, key, /*legacyRead=*/true);
                return;
            }
            applySetting(ns, key, reply.value().variant());
        });
    }

    // Last known opinion per source; nullopt until (unless) that key answers.
    std::optional<bool> m_appearance;  // org.freedesktop.appearance/reduced-motion
    std::optional<bool> m_gnome;       // org.gnome.desktop.interface/enable-animations
    bool m_effective = false;
};
