// Tests for ConfigBridge + WizardBridge against the REAL Rust config (hermetic
// temp XDG_CONFIG_HOME / HOME via the ctest ENVIRONMENT). GUILESS.
#include <QtTest>
#include <QFile>
#include <QDir>

#include "config_bridge.h"
#include "xeneon_core.h"

class TstConfigBridge : public QObject {
    Q_OBJECT
    ConfigHandle* cfg_ = nullptr;
private slots:
    void init() { cfg_ = xeneon_config_load(); QVERIFY(cfg_); }
    void cleanup() { if (cfg_) { xeneon_config_free(cfg_); cfg_ = nullptr; } }

    void uiStateRoundTrip() {
        ConfigBridge b(cfg_);
        const QString json = QStringLiteral("{\"widgets\":[{\"id\":\"clock\"}]}");
        QVERIFY(b.saveUiState(json));
        QCOMPARE(b.uiState(), json);
    }

    void applyExternalUiStatePersists() {
        ConfigBridge b(cfg_);
        QVERIFY(!b.applyExternalUiState(QString()));         // empty rejected
        const QString json = QStringLiteral("{\"a\":1}");
        QVERIFY(b.applyExternalUiState(json));
        QCOMPARE(b.uiState(), json);
    }

    void imageUrl_data() {
        QTest::addColumn<QString>("in");
        QTest::addColumn<QString>("out");
        QTest::newRow("empty")     << "" << "";
        QTest::newRow("qrc")       << "qrc:/img/x.png" << "qrc:/img/x.png";
        QTest::newRow("http")      << "http://h/x.png" << "http://h/x.png";
        QTest::newRow("file")      << "file:///x.png"  << "file:///x.png";
        // QUrl::toString() is PrettyDecoded: a space stays literal, but reserved
        // chars like '#' (which would otherwise start a fragment) are encoded.
        QTest::newRow("abs-space") << "/tmp/a b.png"   << "file:///tmp/a b.png";
        QTest::newRow("abs-hash")  << "/tmp/a#b.png"   << "file:///tmp/a%23b.png";
        QTest::newRow("relative")  << "rel.png"        << "rel.png";
    }
    void imageUrl() {
        QFETCH(QString, in);
        QFETCH(QString, out);
        ConfigBridge b(cfg_);
        QCOMPARE(b.imageUrl(in), out);
    }

    void configJsonNonEmpty() {
        ConfigBridge b(cfg_);
        QVERIFY(!b.configJson().isEmpty());
    }

    // S10: the formerly write-only display keys are now readable through the bridge
    // and round-trip whatever the FFI setters wrote (independent of defaults).
    void disconnectKeysExposedThroughBridge() {
        xeneon_config_set_reconnect(cfg_, 1);
        xeneon_config_set_notify_disconnect(cfg_, 0);
        QCOMPARE(xeneon_config_set_fallback_behavior(cfg_, "notify"), 0);
        ConfigBridge b(cfg_);
        QCOMPARE(b.reconnectOnHotplug(), true);
        QCOMPARE(b.notifyOnDisconnect(), false);
        QCOMPARE(b.fallbackBehavior(), QStringLiteral("notify"));

        xeneon_config_set_reconnect(cfg_, 0);
        xeneon_config_set_notify_disconnect(cfg_, 1);
        QCOMPARE(xeneon_config_set_fallback_behavior(cfg_, "hide"), 0);
        QCOMPARE(b.reconnectOnHotplug(), false);
        QCOMPARE(b.notifyOnDisconnect(), true);
        QCOMPARE(b.fallbackBehavior(), QStringLiteral("hide"));

        // Detached → guarded defaults, never a use-after-free.
        b.detach();
        QCOMPARE(b.reconnectOnHotplug(), false);
        QCOMPARE(b.notifyOnDisconnect(), false);
        QVERIFY(b.fallbackBehavior().isEmpty());
    }

    // S10: the pure hotplug policy the hub's QScreen handlers delegate to.
    void disconnectPolicyDecisionTable() {
        // Non-target loss is always a no-op, regardless of the keys.
        DisconnectDecision d = decideOnScreenRemoved(false, "hide", true);
        QVERIFY(!d.hideWindow);
        QVERIFY(!d.notify);

        // Target loss + fallback "hide" → blank the window.
        d = decideOnScreenRemoved(true, "hide", false);
        QVERIFY(d.hideWindow);
        QVERIFY(!d.notify);

        // Target loss + notify_disconnect → surface a notice; "notify" fallback does
        // not hide the window.
        d = decideOnScreenRemoved(true, "notify", true);
        QVERIFY(!d.hideWindow);
        QVERIFY(d.notify);

        // Both at once.
        d = decideOnScreenRemoved(true, "hide", true);
        QVERIFY(d.hideWindow);
        QVERIFY(d.notify);

        // Reconnect only migrates when enabled AND the added screen is the target.
        QVERIFY(shouldReconnectToScreen(true, true));
        QVERIFY(!shouldReconnectToScreen(false, true));
        QVERIFY(!shouldReconnectToScreen(true, false));
        QVERIFY(!shouldReconnectToScreen(false, false));
    }

    // After detach the bridge must become a guarded no-op (no use-after-free of the
    // freed config handle at shutdown).
    void detachGuards() {
        ConfigBridge b(cfg_);
        b.detach();
        QVERIFY(b.uiState().isEmpty());
        QVERIFY(!b.saveUiState(QStringLiteral("{\"x\":1}")));
        QVERIFY(b.starterLayout().isEmpty());
        QVERIFY(b.configJson().isEmpty());
    }

    void wizardNullConfigFails() {
        WizardBridge w(nullptr);
        QVERIFY(!w.completeWizard("h", "DP-3", "XENEON", "gaming", "dark", "#f00",
                                  false, true, true));
    }

    void wizardPersistsAndMarksFirstRunComplete() {
        WizardBridge w(cfg_);
        QVERIFY(w.completeWizard("hash1", "DP-3", "XENEON EDGE", "productivity",
                                 "dark", "#00ff00", /*autostart*/ false,
                                 /*reconnect*/ true, /*notifyDisconnect*/ true));
        // Reload from disk and confirm it stuck.
        ConfigHandle* fresh = xeneon_config_load();
        QVERIFY(fresh);
        QCOMPARE(xeneon_config_is_first_run(fresh), 0);
        char* layout = xeneon_config_get_starter_layout(fresh);
        QCOMPARE(QString::fromUtf8(layout), QStringLiteral("productivity"));
        xeneon_string_free(layout);
        xeneon_config_free(fresh);
    }
};

QTEST_GUILESS_MAIN(TstConfigBridge)
#include "tst_config_bridge.moc"
