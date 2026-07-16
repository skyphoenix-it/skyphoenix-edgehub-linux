// MetricsWorker on a dedicated QThread: it must emit well-formed compact JSON and
// tear down cleanly (timer deleted on the worker thread, thread joined). GUILESS +
// a real event loop for the queued cross-thread signal.
#include <QtTest>
#include <QThread>
#include <QSignalSpy>
#include <QJsonDocument>
#include <QJsonObject>

#include "metrics_worker.h"

// Refuse to run outside a sandbox: this test would otherwise clobber the
// developer's real config / running hub. See hermetic.h.
#include "hermetic.h"
XENEON_REQUIRE_HERMETIC_ENV();

class TstMetricsWorker : public QObject {
    Q_OBJECT
private slots:
    void emitsWellFormedJson() {
        QThread thread;
        MetricsWorker worker;
        worker.moveToThread(&thread);

        QSignalSpy spy(&worker, &MetricsWorker::metricsReady);
        QVERIFY(spy.isValid());

        // begin() runs ON the worker thread and emits an initial sample immediately.
        connect(&thread, &QThread::started, &worker, &MetricsWorker::begin);
        thread.start();

        // Initial sample should arrive well within a second.
        QVERIFY(spy.wait(3000));
        QVERIFY(spy.count() >= 1);

        const QByteArray json = spy.at(0).at(0).toByteArray();
        QVERIFY(!json.isEmpty());
        QJsonParseError err;
        const QJsonDocument doc = QJsonDocument::fromJson(json, &err);
        QCOMPARE(err.error, QJsonParseError::NoError);
        QVERIFY(doc.isObject());
        QVERIFY(doc.object().contains("cpu_usage_percent"));

        // Clean teardown: stop the timer on the worker thread, then join.
        QMetaObject::invokeMethod(&worker, "stop", Qt::BlockingQueuedConnection);
        thread.quit();
        QVERIFY(thread.wait(3000));
    }
};

QTEST_GUILESS_MAIN(TstMetricsWorker)
#include "tst_metrics_worker.moc"
