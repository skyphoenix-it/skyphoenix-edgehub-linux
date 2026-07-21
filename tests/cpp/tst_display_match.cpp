// Unit tests for the shared display-matching helpers (screenIdentityHash,
// orientationName). Pure logic — no live QScreen — so QTEST_GUILESS_MAIN.
#include <QtTest>
#include <cstdint>

#include "display_match.h"
#include "xeneon_core.h"
#include "xeneon_string.h"

// Refuse to run outside a sandbox: this test would otherwise clobber the
// developer's real config / running hub. See hermetic.h.
#include "hermetic.h"
XENEON_REQUIRE_HERMETIC_ENV();

class TstDisplayMatch : public QObject {
    Q_OBJECT
private slots:
    void configuredIdentityDetection() {
        QVERIFY(!hasConfiguredTargetIdentity(QString(), QString(), QString()));
        QVERIFY(!hasConfiguredTargetIdentity("", "", ""));
        QVERIFY(hasConfiguredTargetIdentity("edid-hash", "", ""));
        QVERIFY(hasConfiguredTargetIdentity("", "XENEON EDGE", ""));
        QVERIFY(hasConfiguredTargetIdentity("", "", "DP-3"));

        // A malformed/manual non-empty value is still an explicit selection. It
        // must fail closed rather than accidentally restoring primary fallback.
        QVERIFY(hasConfiguredTargetIdentity("", " ", ""));
    }

    void startupPlacementDecisionTable() {
        // Normal auto-detection remains authoritative on unconfigured installs.
        QCOMPARE(decideStartupDisplayPlacement(false, true, false),
                 StartupDisplayPlacement::MatchedTarget);

        // First-run/no-selection behavior remains the primary fallback when
        // nothing can be auto-detected.
        QCOMPARE(decideStartupDisplayPlacement(false, false, false),
                 StartupDisplayPlacement::PrimaryFallback);

        // A configured target that is present uses the target as normal.
        QCOMPARE(decideStartupDisplayPlacement(true, true, false),
                 StartupDisplayPlacement::MatchedTarget);

        // Release blocker: an absent configured target must never turn into a
        // fullscreen primary-screen placement.
        QCOMPARE(decideStartupDisplayPlacement(true, false, false),
                 StartupDisplayPlacement::KeepHidden);

        // --reset-wizard is an explicit recovery request. It may use primary,
        // but only through the dedicated windowed recovery branch.
        QCOMPARE(decideStartupDisplayPlacement(true, false, true),
                 StartupDisplayPlacement::PrimaryRecovery);
    }

    void targetRemovalSafetyDecisionTable() {
        // Unrelated monitor removal never changes Hub visibility or signals.
        TargetRemovalSafetyDecision d = decideTargetRemovalSafety(false, "hide", true);
        QVERIFY(!d.hideWindow);
        QVERIFY(!d.notify);
        QVERIFY(!d.requestSelection);

        // Target loss is always hidden, even when the user-facing policy asks
        // for a notice rather than explicitly choosing "hide".
        d = decideTargetRemovalSafety(true, "hide", false);
        QVERIFY(d.hideWindow);
        QVERIFY(!d.notify);
        QVERIFY(!d.requestSelection);

        d = decideTargetRemovalSafety(true, "notify", false);
        QVERIFY(d.hideWindow);
        QVERIFY(d.notify);
        QVERIFY(!d.requestSelection);

        d = decideTargetRemovalSafety(true, "ask", false);
        QVERIFY(d.hideWindow);
        QVERIFY(d.notify);
        QVERIFY(d.requestSelection);

        // The independent notify preference remains effective with "hide".
        d = decideTargetRemovalSafety(true, "hide", true);
        QVERIFY(d.hideWindow);
        QVERIFY(d.notify);
        QVERIFY(!d.requestSelection);

        // Unknown/manual policy values also fail closed.
        d = decideTargetRemovalSafety(true, "unexpected", false);
        QVERIFY(d.hideWindow);
        QVERIFY(!d.notify);
        QVERIFY(!d.requestSelection);
    }

    void disconnectNoticeContent() {
        DisplayDisconnectNotice notice = displayDisconnectNotice("DP-3", false);
        QCOMPARE(notice.summary, QStringLiteral("Dashboard display disconnected"));
        QVERIFY(notice.body.contains(QStringLiteral("DP-3")));
        QVERIFY(notice.body.contains(QStringLiteral("hidden")));
        QVERIFY(notice.body.contains(QStringLiteral("waiting for reconnection")));
        QVERIFY(!notice.body.contains(QStringLiteral("Manager")));

        notice = displayDisconnectNotice(" DP-4 ", true);
        QVERIFY(notice.body.contains(QStringLiteral("DP-4")));
        QVERIFY(notice.body.contains(QStringLiteral("Xeneon Edge Manager")));
        QVERIFY(notice.body.contains(QStringLiteral("select a display")));

        notice = displayDisconnectNotice(QString(), false);
        QVERIFY(notice.body.startsWith(QStringLiteral("The dashboard display")));
    }

    // The identity hash must be deterministic for identical identity fields.
    void identityHashDeterministic() {
        const QString a = screenIdentityHash("DP-3", "XENEON EDGE", "Corsair", "SN123");
        const QString b = screenIdentityHash("DP-3", "XENEON EDGE", "Corsair", "SN123");
        QVERIFY(!a.isEmpty());
        QCOMPARE(a, b);
    }

    // Distinct identities must produce distinct hashes (each field participates).
    void identityHashDistinct() {
        const QString base = screenIdentityHash("DP-3", "XENEON", "Corsair", "SN1");
        QVERIFY(base != screenIdentityHash("DP-4", "XENEON", "Corsair", "SN1"));
        QVERIFY(base != screenIdentityHash("DP-3", "OTHER",  "Corsair", "SN1"));
        QVERIFY(base != screenIdentityHash("DP-3", "XENEON", "Acme",    "SN1"));
        QVERIFY(base != screenIdentityHash("DP-3", "XENEON", "Corsair", "SN2"));
    }

    // Pin the concatenation contract: name+model+manufacturer+serial, hashed by the
    // Rust core. The two duplicated call sites in main.cpp (screenToJson +
    // findTargetScreen) MUST agree with this, else target matching silently fails.
    void identityHashMatchesRawConcat() {
        const QString name = "DP-3", model = "XENEON EDGE",
                      manuf = "Corsair", serial = "SN123";
        QByteArray id;
        id.append(name.toUtf8());
        id.append(model.toUtf8());
        id.append(manuf.toUtf8());
        id.append(serial.toUtf8());
        XeneonString raw(xeneon_display_compute_edid_hash(
            reinterpret_cast<const uint8_t*>(id.constData()), id.size()));
        QCOMPARE(screenIdentityHash(name, model, manuf, serial), raw.qstring());
    }

    // Empty identity is still a valid (stable) hash, not a crash / empty string.
    void identityHashEmptyInputs() {
        const QString h = screenIdentityHash("", "", "", "");
        QCOMPARE(h, screenIdentityHash("", "", "", ""));
    }

    void orientationSpelling_data() {
        QTest::addColumn<int>("orient");
        QTest::addColumn<QString>("name");
        QTest::newRow("landscape")         << int(Qt::LandscapeOrientation)         << "landscape";
        QTest::newRow("portrait")          << int(Qt::PortraitOrientation)          << "portrait";
        QTest::newRow("inverted-landscape")<< int(Qt::InvertedLandscapeOrientation) << "inverted-landscape";
        QTest::newRow("inverted-portrait") << int(Qt::InvertedPortraitOrientation)  << "inverted-portrait";
        QTest::newRow("primary-empty")     << int(Qt::PrimaryOrientation)           << "";
    }
    void orientationSpelling() {
        QFETCH(int, orient);
        QFETCH(QString, name);
        QCOMPARE(orientationName(static_cast<Qt::ScreenOrientation>(orient)), name);
    }
};

QTEST_GUILESS_MAIN(TstDisplayMatch)
#include "tst_display_match.moc"
