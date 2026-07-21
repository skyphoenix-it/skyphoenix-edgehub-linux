// The licence FFI as the Qt app actually consumes it: C string in, owned JSON
// out, free with xeneon_string_free. GUILESS.
//
// Scope note: this asserts the FFI *contract* and the fail-soft guarantee. It
// cannot assert "a valid key unlocks Pro", because this path is pinned to the
// public key compiled into the core and nothing may redirect it at runtime -
// that immovability IS the security property, and a C++ test that could bypass
// it would be a licence bypass. The verifier's own behaviour (valid / tampered
// / wrong-issuer / expired / truncated) is proven against a test issuer in the
// Rust unit tests in core/src/license.rs.
#include <QtTest>
#include <QJsonDocument>
#include <QJsonObject>

#include "xeneon_core.h"

namespace {
// Call the FFI and parse. Owns and frees the returned string, as every caller
// of an xeneon_* string function must.
QJsonObject verify(const char* key) {
    char* raw = xeneon_license_verify_json(key);
    [&] { QVERIFY2(raw != nullptr, "FFI must never return null, even for a bad key"); }();
    const QByteArray json(raw);
    xeneon_string_free(raw);
    QJsonParseError err{};
    const auto doc = QJsonDocument::fromJson(json, &err);
    [&] {
        QVERIFY2(err.error == QJsonParseError::NoError,
                 qPrintable("FFI returned unparseable JSON: " + err.errorString()));
        QVERIFY(doc.isObject());
    }();
    return doc.object();
}
}  // namespace

class TstLicense : public QObject {
    Q_OBJECT
private slots:
    // The documented shape is a contract the QML/C++ side reads by key name.
    void reports_the_documented_shape() {
        const auto o = verify("");
        for (const char* f : {"state", "tier", "reason", "issuedTo", "id", "expires"})
            QVERIFY2(o.contains(f), qPrintable(QString("missing field: %1").arg(f)));
        // Nothing verified → no holder data is invented.
        QVERIFY(o.value("issuedTo").isNull());
        QVERIFY(o.value("id").isNull());
        QVERIFY(o.value("expires").isNull());
    }

    // Fail CLOSED (never a paid tier) but SOFT (never a crash, never a null).
    void every_unusable_key_is_the_free_tier_data() {
        QTest::addColumn<QByteArray>("key");
        QTest::newRow("empty")        << QByteArray("");
        QTest::newRow("whitespace")   << QByteArray("   \n\t ");
        QTest::newRow("garbage")      << QByteArray("hello world");
        QTest::newRow("two-segments") << QByteArray("XE1.onlytwo");
        QTest::newRow("four-segments")<< QByteArray("XE1.a.b.c");
        QTest::newRow("wrong-prefix") << QByteArray("XE9.AAAA.BBBB");
        QTest::newRow("non-base64")   << QByteArray("XE1.****.****");
        QTest::newRow("padded-b64")   << QByteArray("XE1.AAAA=.BBBB=");
        QTest::newRow("jwt-lookalike")<< QByteArray("eyJhbGciOiJub25lIn0.eyJ0aWVyIjoicHJvIn0.");
        // Well-formed shape, unverifiable content - the shipped default until a
        // real issuer key exists.
        QTest::newRow("well-formed")  << QByteArray("XE1.eyJ0aWVyIjoicHJvIn0.AAAA");
        // A long paste and a lone separator: neither may index out of bounds.
        QTest::newRow("very-long")    << QByteArray("XE1.") + QByteArray(8192, 'A') + ".AAAA";
        QTest::newRow("dots-only")    << QByteArray("....");
    }
    void every_unusable_key_is_the_free_tier() {
        QFETCH(QByteArray, key);
        const auto o = verify(key.constData());
        QCOMPARE(o.value("tier").toString(), QStringLiteral("free"));
        QCOMPARE(o.value("state").toString(), QStringLiteral("unlicensed"));
        // Unlicensed must always explain itself - support needs the failure mode.
        QVERIFY2(o.value("reason").isString() && !o.value("reason").toString().isEmpty(),
                 "an unlicensed result must carry a reason");
    }

    // A null key is "no licence", not a crash and not a null return.
    void null_key_is_free_not_a_crash() {
        const auto o = verify(nullptr);
        QCOMPARE(o.value("tier").toString(), QStringLiteral("free"));
        QCOMPARE(o.value("state").toString(), QStringLiteral("unlicensed"));
    }

    // The result is user- and log-facing. It must name the failure mode and
    // never hand the key back - the same rule secrets.rs holds for tokens.
    void the_result_never_echoes_the_key() {
        const auto o = verify("XE1.SUPERSECRETLICENCEPAYLOAD.SUPERSECRETSIGNATURE");
        const QByteArray whole = QJsonDocument(o).toJson(QJsonDocument::Compact);
        QVERIFY2(!whole.contains("SUPERSECRET"), "the licence key leaked into the result: " + whole);
    }

    // `tier` is the gate; it may never be anything but a tier this build knows.
    void tier_is_always_a_known_value() {
        for (const char* k : {"", "garbage", "XE1.a.b", "XE1.eyJ0aWVyIjoicHJvIn0.AAAA"}) {
            const auto t = verify(k).value("tier").toString();
            QVERIFY2(t == "free" || t == "pro", qPrintable("unknown tier: " + t));
        }
    }

    // Verification is offline by construction (the public key is compiled in),
    // so it must be fast and repeatable - a network call would show up as
    // latency or as a differing answer. This is a smoke check of that claim,
    // not a substitute for the CI egress gate.
    void verification_is_offline_fast_and_deterministic() {
        const auto first = verify("XE1.eyJ0aWVyIjoicHJvIn0.AAAA");
        QElapsedTimer t;
        t.start();
        for (int i = 0; i < 200; ++i) {
            const auto o = verify("XE1.eyJ0aWVyIjoicHJvIn0.AAAA");
            QCOMPARE(o.value("state").toString(), first.value("state").toString());
            QCOMPARE(o.value("tier").toString(), first.value("tier").toString());
        }
        // 200 verifications in a second is unreachable for anything that resolves
        // DNS or opens a socket, even to a local refusal.
        QVERIFY2(t.elapsed() < 1000, qPrintable(QString("200 verifications took %1ms - "
                                                        "is something doing I/O?").arg(t.elapsed())));
    }
};

QTEST_MAIN(TstLicense)
#include "tst_license.moc"
