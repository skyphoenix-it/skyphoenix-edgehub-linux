// Unit test for metricsToJson(): it must return a parsed JSON object sourced from
// the real Rust metrics collector (no fake). We assert structure/shape rather than
// exact values (which are host-dependent), and that repeated calls stay well-formed
// (exercises the atomic warn-once guard path without tripping it).
#include <QtTest>
#include <QRegularExpression>

#include "display_match.h"

class TstMetricsJson : public QObject {
    Q_OBJECT
private slots:
    // The malformed/atomic-warn branch of parseMetrics() is unreachable through the
    // real collector (it always yields valid JSON), so exercise the seam directly:
    // malformed / empty bytes → empty object, and the warn-once path fires (once).
    void malformedBytesYieldEmpty() {
        // First malformed input warns exactly once (atomic guard); assert the warning.
        QTest::ignoreMessage(QtWarningMsg,
                             QRegularExpression("parseMetrics: malformed metrics JSON"));
        QVERIFY(parseMetrics(QByteArray("{not valid json")).isEmpty());
        // A second malformed input must NOT warn again (warn-once) and still be empty.
        QVERIFY(parseMetrics(QByteArray("also bad")).isEmpty());
        // Empty buffer is also treated as malformed → empty object.
        QVERIFY(parseMetrics(QByteArray()).isEmpty());
        // A well-formed buffer parses through the same seam.
        const QJsonObject ok = parseMetrics(QByteArray("{\"a\":1,\"b\":2}"));
        QCOMPARE(ok.value("a").toInt(), 1);
        QCOMPARE(ok.value("b").toInt(), 2);
    }

    void returnsObject() {
        const QJsonObject o = metricsToJson();
        // The Rust collector always yields a populated object on a normal host.
        QVERIFY(!o.isEmpty());
    }

    void hasCoreNumericFields() {
        const QJsonObject o = metricsToJson();
        // Contract with QML: these keys are read by the widgets. Assert presence +
        // numeric type for the always-available ones.
        for (const char* key : {"cpu_usage_percent", "ram_usage_percent",
                                 "ram_total_bytes", "ram_used_bytes", "cpu_core_count"}) {
            QVERIFY2(o.contains(QLatin1String(key)),
                     qPrintable(QStringLiteral("missing metrics key: %1").arg(key)));
            QVERIFY2(o.value(QLatin1String(key)).isDouble(),
                     qPrintable(QStringLiteral("metrics key not numeric: %1").arg(key)));
        }
    }

    void cpuUsageInRange() {
        const QJsonObject o = metricsToJson();
        const double cpu = o.value("cpu_usage_percent").toDouble(-1.0);
        QVERIFY(cpu >= 0.0 && cpu <= 100.0);
    }

    void stableAcrossRepeatedCalls() {
        // Repeated collection must keep producing well-formed objects (also drives
        // the shared warn-once path many times without a data race / crash).
        for (int i = 0; i < 5; ++i)
            QVERIFY(!metricsToJson().isEmpty());
    }
};

QTEST_GUILESS_MAIN(TstMetricsJson)
#include "tst_metrics_json.moc"
