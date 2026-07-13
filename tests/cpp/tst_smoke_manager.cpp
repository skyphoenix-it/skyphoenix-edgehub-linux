// Smoke test: launch the REAL manager binary offscreen with XENEON_GRAB → it must
// render, save a non-empty PNG, and exit 0. Exercises main(), the ManagerBackend
// construction/teardown, and the QML load path.
#include <QtTest>
#include <QProcess>
#include <QProcessEnvironment>
#include <QDir>
#include <QFile>
#include <QImage>

class TstSmokeManager : public QObject {
    Q_OBJECT
private slots:
    void grabsAndExitsClean() {
        const QString grab = QDir::tempPath() + "/xeneon-smoke-manager.png";
        QFile::remove(grab);

        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("QT_QPA_PLATFORM", "offscreen");
        env.insert("XENEON_GRAB", grab);

        QProcess p;
        p.setProcessEnvironment(env);
        p.setProgram(QStringLiteral(MGR_BIN));
        p.start();
        QVERIFY2(p.waitForStarted(5000), "manager failed to start");
        QVERIFY2(p.waitForFinished(30000), "manager did not exit in time");

        QCOMPARE(p.exitStatus(), QProcess::NormalExit);
        QCOMPARE(p.exitCode(), 0);

        QVERIFY2(QFile::exists(grab), "grab PNG was not written");
        QVERIFY2(QFileInfo(grab).size() > 0, "grab PNG is empty");
        QImage img(grab);
        QVERIFY2(!img.isNull(), "grab PNG is not a valid image");
        QFile::remove(grab);
    }
};

QTEST_GUILESS_MAIN(TstSmokeManager)
#include "tst_smoke_manager.moc"
