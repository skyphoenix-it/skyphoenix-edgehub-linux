// Tests for ConfigBridge + WizardBridge against the REAL Rust config (hermetic
// temp XDG_CONFIG_HOME / HOME via the ctest ENVIRONMENT). GUILESS.
#include <QtTest>
#include <QFile>
#include <QDir>
#include <QTemporaryDir>
#include <QVariantMap>

#include "config_bridge.h"
#include "xeneon_core.h"

// Refuse to run outside a sandbox: this test would otherwise clobber the
// developer's real config / running hub. See hermetic.h.
#include "hermetic.h"
XENEON_REQUIRE_HERMETIC_ENV();

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

    // --- E7 Phase A: credential-reference resolution -------------------------
    // The bridge is what QML calls, so it owns the FFI's two-allocation contract
    // (value AND error must be freed). These run under the same ctest as the rest,
    // so a leak here shows up under the sanitizers/coverage build.

    void resolveSecret_envRef() {
        qputenv("XENEON_BRIDGE_TEST_TOKEN", "bridge-token");
        ConfigBridge b(cfg_);
        const QVariantMap r = b.resolveSecret("${env:XENEON_BRIDGE_TEST_TOKEN}");
        QCOMPARE(r["ok"].toBool(), true);
        QCOMPARE(r["value"].toString(), QStringLiteral("bridge-token"));
        QVERIFY(r["error"].toString().isEmpty());
        QCOMPARE(r["plaintext"].toBool(), false);
        qunsetenv("XENEON_BRIDGE_TEST_TOKEN");
    }

    void resolveSecret_fileRef() {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString p = dir.filePath("tok");
        QFile f(p);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write("file-token\n");   // trailing newline is the realistic case
        f.close();

        ConfigBridge b(cfg_);
        const QVariantMap r = b.resolveSecret("file:" + p);
        QCOMPARE(r["ok"].toBool(), true);
        QCOMPARE(r["value"].toString(), QStringLiteral("file-token"));
    }

    // A missing ref must fail with a reason — not silently resolve to empty, which
    // would send an unauthenticated request that looks like a server-side 401.
    void resolveSecret_missingRefReportsWhy() {
        qunsetenv("XENEON_BRIDGE_ABSENT");
        ConfigBridge b(cfg_);
        const QVariantMap r = b.resolveSecret("${env:XENEON_BRIDGE_ABSENT}");
        QCOMPARE(r["ok"].toBool(), false);
        QVERIFY(r["value"].toString().isEmpty());
        QVERIFY2(r["error"].toString().contains("XENEON_BRIDGE_ABSENT"),
                 qPrintable("error should name the var: " + r["error"].toString()));
    }

    // Legacy plaintext keeps working (E1 shipped the field) but is flagged so the
    // UI can tell the user it is sitting in config.toml.
    void resolveSecret_plaintextWorksButIsFlagged() {
        ConfigBridge b(cfg_);
        const QVariantMap r = b.resolveSecret("ghp_legacy_literal");
        QCOMPARE(r["ok"].toBool(), true);
        QCOMPARE(r["value"].toString(), QStringLiteral("ghp_legacy_literal"));
        QCOMPARE(r["plaintext"].toBool(), true);
    }

    // An unconfigured token is a success with no value — not an error, and not a
    // plaintext warning about a secret that does not exist.
    void resolveSecret_emptyIsANoOpSuccess() {
        ConfigBridge b(cfg_);
        const QVariantMap r = b.resolveSecret(QString());
        QCOMPARE(r["ok"].toBool(), true);
        QVERIFY(r["value"].toString().isEmpty());
        QCOMPARE(r["plaintext"].toBool(), false);
    }

    void resolveSecret_keyringIsNotYetSupported() {
        ConfigBridge b(cfg_);
        const QVariantMap r = b.resolveSecret("secret://edge/ci");
        QCOMPARE(r["ok"].toBool(), false);
        QVERIFY(!r["error"].toString().isEmpty());
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
