// Unit tests for the shared display-matching helpers (screenIdentityHash,
// orientationName). Pure logic — no live QScreen — so QTEST_GUILESS_MAIN.
#include <QtTest>
#include <cstdint>

#include "display_match.h"
#include "xeneon_core.h"
#include "xeneon_string.h"

class TstDisplayMatch : public QObject {
    Q_OBJECT
private slots:
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
