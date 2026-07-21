// SystemSettingsProbe - the OS reduce-motion read (XDG settings portal).
//
// These tests drive the PARSING SEAM (unwrapDBusVariant / interpretSetting /
// applySetting) with crafted variants, so they are independent of the host's
// actual desktop settings - the exact values the portal would deliver are
// reproduced here as literals (shapes verified against a live KDE Plasma
// portal, Settings v2: ReadOne returns v(x), legacy Read returns v(v(x)),
// SettingChanged carries v(x)). CTest runs this executable under its own
// dbus-run-session, so the integration case exercises the real async transport
// without reading from or subscribing to the user's desktop bus.
#include <QtTest>
#include <QDBusConnection>
#include <QDBusVariant>
#include <QSignalSpy>

#include "system_settings_probe.h"

// Refuse to run outside a sandbox - see hermetic.h (a raw run once destroyed a
// developer's real config).
#include "hermetic.h"
XENEON_REQUIRE_HERMETIC_ENV();

static QVariant dbusWrapped(const QVariant& inner) {
    return QVariant::fromValue(QDBusVariant(inner));
}

class TstSystemSettingsProbe : public QObject {
    Q_OBJECT

private slots:
    // No bus, no portal, no key → false. The default must be "no OS signal".
    void defaultIsNoSignal() {
        SystemSettingsProbe probe;
        QCOMPARE(probe.reduceMotion(), false);
    }

    // ReadOne hands back v(x); the deprecated Read hands back v(v(x)). Both
    // shapes must peel to the same plain value.
    void unwrapPeelsNestedDBusVariants() {
        QCOMPARE(SystemSettingsProbe::unwrapDBusVariant(QVariant(true)).toBool(), true);
        QCOMPARE(SystemSettingsProbe::unwrapDBusVariant(dbusWrapped(QVariant(true))).toBool(), true);
        QCOMPARE(SystemSettingsProbe::unwrapDBusVariant(
                     dbusWrapped(dbusWrapped(QVariant(quint32(1))))).toUInt(), 1u);
    }

    void interpretSetting_data() {
        QTest::addColumn<QString>("ns");
        QTest::addColumn<QString>("key");
        QTest::addColumn<QVariant>("value");
        QTest::addColumn<bool>("relevant");
        QTest::addColumn<bool>("reduce");

        // The standardized cross-desktop key: 0 = no preference, 1 = reduce.
        QTest::newRow("appearance reduced-motion 1")
            << "org.freedesktop.appearance" << "reduced-motion"
            << dbusWrapped(QVariant(quint32(1))) << true << true;
        QTest::newRow("appearance reduced-motion 0")
            << "org.freedesktop.appearance" << "reduced-motion"
            << dbusWrapped(QVariant(quint32(0))) << true << false;
        // A future enum value must read as "no preference", not as "reduce".
        QTest::newRow("appearance reduced-motion future value")
            << "org.freedesktop.appearance" << "reduced-motion"
            << dbusWrapped(QVariant(quint32(2))) << true << false;

        // GNOME's key (compat backends, incl. KDE's, answer it too). Inverted:
        // animations DISABLED means reduce.
        QTest::newRow("gnome enable-animations false")
            << "org.gnome.desktop.interface" << "enable-animations"
            << dbusWrapped(QVariant(false)) << true << true;
        QTest::newRow("gnome enable-animations true")
            << "org.gnome.desktop.interface" << "enable-animations"
            << dbusWrapped(QVariant(true)) << true << false;

        // Deliberately NOT interpreted: kdeglobals is not probed (ReadOne
        // cannot fetch it on a real Plasma box), and unrelated keys from the
        // same namespaces must not be misread as a motion opinion.
        QTest::newRow("kdeglobals AnimationDurationFactor ignored")
            << "org.kde.kdeglobals.KDE" << "AnimationDurationFactor"
            << dbusWrapped(QVariant(QStringLiteral("0"))) << false << false;
        QTest::newRow("appearance color-scheme ignored")
            << "org.freedesktop.appearance" << "color-scheme"
            << dbusWrapped(QVariant(quint32(1))) << false << false;
        QTest::newRow("gnome other key ignored")
            << "org.gnome.desktop.interface" << "color-scheme"
            << dbusWrapped(QVariant(QStringLiteral("prefer-dark"))) << false << false;
    }
    void interpretSetting() {
        QFETCH(QString, ns);
        QFETCH(QString, key);
        QFETCH(QVariant, value);
        QFETCH(bool, relevant);
        QFETCH(bool, reduce);

        const std::optional<bool> got = SystemSettingsProbe::interpretSetting(ns, key, value);
        QCOMPARE(got.has_value(), relevant);
        if (relevant)
            QCOMPARE(got.value(), reduce);
    }

    // The stateful fold: property + notify, dedup, and the OR of both sources.
    void applySettingUpdatesPropertyAndSignals() {
        SystemSettingsProbe probe;
        QSignalSpy spy(&probe, &SystemSettingsProbe::reduceMotionChanged);

        // OS asks to reduce → true, one signal.
        probe.applySetting("org.freedesktop.appearance", "reduced-motion",
                           dbusWrapped(QVariant(quint32(1))));
        QCOMPARE(probe.reduceMotion(), true);
        QCOMPARE(spy.count(), 1);

        // Same value again → no spurious signal.
        probe.applySetting("org.freedesktop.appearance", "reduced-motion",
                           dbusWrapped(QVariant(quint32(1))));
        QCOMPARE(spy.count(), 1);

        // Second source also says reduce → still true, still no new signal.
        probe.applySetting("org.gnome.desktop.interface", "enable-animations",
                           dbusWrapped(QVariant(false)));
        QCOMPARE(probe.reduceMotion(), true);
        QCOMPARE(spy.count(), 1);

        // First source withdraws, second still says reduce → OR keeps it true.
        probe.applySetting("org.freedesktop.appearance", "reduced-motion",
                           dbusWrapped(QVariant(quint32(0))));
        QCOMPARE(probe.reduceMotion(), true);
        QCOMPARE(spy.count(), 1);

        // Second source withdraws too → false, second signal.
        probe.applySetting("org.gnome.desktop.interface", "enable-animations",
                           dbusWrapped(QVariant(true)));
        QCOMPARE(probe.reduceMotion(), false);
        QCOMPARE(spy.count(), 2);
    }

    void irrelevantKeysNeverSignal() {
        SystemSettingsProbe probe;
        QSignalSpy spy(&probe, &SystemSettingsProbe::reduceMotionChanged);
        probe.applySetting("org.freedesktop.appearance", "color-scheme",
                           dbusWrapped(QVariant(quint32(1))));
        probe.applySetting("org.kde.kdeglobals.KDE", "AnimationDurationFactor",
                           dbusWrapped(QVariant(QStringLiteral("0"))));
        probe.applySetting("com.example.junk", "reduced-motion",
                           dbusWrapped(QVariant(quint32(1))));
        QCOMPARE(probe.reduceMotion(), false);
        QCOMPARE(spy.count(), 0);
    }

    // The live-update path: the portal's SettingChanged slot must fold exactly
    // like the initial read (invoked via the meta-object, as QtDBus would).
    void settingChangedSlotPropagates() {
        SystemSettingsProbe probe;
        QSignalSpy spy(&probe, &SystemSettingsProbe::reduceMotionChanged);
        QVERIFY(QMetaObject::invokeMethod(
            &probe, "onSettingChanged", Qt::DirectConnection,
            Q_ARG(QString, "org.gnome.desktop.interface"),
            Q_ARG(QString, "enable-animations"),
            Q_ARG(QDBusVariant, QDBusVariant(QVariant(false)))));
        QCOMPARE(probe.reduceMotion(), true);
        QCOMPARE(spy.count(), 1);
    }

    // Integration: CTest supplies a private bus. Claim the portal service name
    // without exporting an object so calls fail locally as UnknownObject instead
    // of activating the host's xdg-desktop-portal service (which can inherit the
    // test's output pipe and keep CTest waiting after the executable exits). A raw
    // developer invocation skips: only the marked private bus is safe to claim.
    // The contract is "both async reads are safe and a missing portal object leaves
    // the conservative default unchanged".
    void startAgainstRealBusIsSafe() {
        if (qEnvironmentVariable("XENEON_TEST_PRIVATE_DBUS") != QLatin1String("1"))
            QSKIP("run through CTest to exercise the private D-Bus session");
        QDBusConnection bus = QDBusConnection::sessionBus();
        QVERIFY(bus.isConnected());
        QVERIFY(bus.registerService(QStringLiteral("org.freedesktop.portal.Desktop")));
        SystemSettingsProbe probe;
        probe.start();
        QTest::qWait(1500);  // let the async ReadOne round-trips complete
        QCOMPARE(probe.reduceMotion(), false);
        QVERIFY(bus.unregisterService(QStringLiteral("org.freedesktop.portal.Desktop")));
    }
};

QTEST_GUILESS_MAIN(TstSystemSettingsProbe)
#include "tst_system_settings_probe.moc"
