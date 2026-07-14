// Smoke test: launch the REAL hub binary offscreen with XENEON_GRAB → it must
// render, save a non-empty PNG, and exit 0. Exercises main(), screen matching,
// the metrics thread lifecycle, and doubles as the XENEON_GRAB use-after-free
// regression (the deferred grab lambda now captures grabPath by value).
#include <QtTest>
#include <QProcess>
#include <QProcessEnvironment>
#include <QDir>
#include <QFile>
#include <QImage>

class TstSmokeHub : public QObject {
    Q_OBJECT
private slots:
    void grabsAndExitsClean() {
        // The grab hook is compiled out unless -DXENEON_QA_HOOKS=ON (product
        // builds must ignore XENEON_GRAB). Without it the hub renders normally
        // and never exits, so this test can only time out — skip with the real
        // reason instead. scripts/run_cpp_tests.sh and CI both configure it ON.
        if (!QA_HOOKS_BUILD)
            QSKIP("hub built without XENEON_QA_HOOKS: XENEON_GRAB is compiled out, "
                  "so it cannot render-and-exit. Configure -DXENEON_QA_HOOKS=ON.");

        const QString grab = QDir::tempPath() + "/xeneon-smoke-hub.png";
        QFile::remove(grab);

        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("QT_QPA_PLATFORM", "offscreen");
        env.insert("XENEON_GRAB", grab);
        env.insert("XENEON_GRAB_W", "800");
        env.insert("XENEON_GRAB_H", "480");

        QProcess p;
        p.setProcessEnvironment(env);
        p.setProgram(QStringLiteral(HUB_BIN));
        p.start();
        QVERIFY2(p.waitForStarted(5000), "hub failed to start");
        QVERIFY2(p.waitForFinished(30000), "hub did not exit in time");

        QCOMPARE(p.exitStatus(), QProcess::NormalExit);
        QCOMPARE(p.exitCode(), 0);

        QVERIFY2(QFile::exists(grab), "grab PNG was not written");
        QVERIFY2(QFileInfo(grab).size() > 0, "grab PNG is empty");
        QImage img(grab);
        QVERIFY2(!img.isNull(), "grab PNG is not a valid image");
        QFile::remove(grab);
    }
};

QTEST_GUILESS_MAIN(TstSmokeHub)
#include "tst_smoke_hub.moc"
