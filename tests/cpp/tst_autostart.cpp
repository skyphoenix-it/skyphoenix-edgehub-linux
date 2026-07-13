// Tests for applyAutostart(): install/remove the XDG autostart .desktop entry,
// with the honest disable return (real QFile::remove result). HOME is redirected
// to a per-test temp dir via the ctest ENVIRONMENT. GUILESS (needs QCoreApplication
// for applicationFilePath()).
#include <QtTest>
#include <QDir>
#include <QFile>
#include <QFileInfo>

#include <unistd.h>

#include "autostart.h"

class TstAutostart : public QObject {
    Q_OBJECT
    QString path_;
private slots:
    void initTestCase() {
        path_ = QDir::homePath() + "/.config/autostart/xeneon-edge-hub.desktop";
        // Start clean.
        QFile::remove(path_);
    }
    void cleanup() {
        // Restore write on the entry dir first so a test that dropped permissions
        // (and may have asserted mid-way) doesn't leave a read-only dir behind.
        const QString dir = QFileInfo(path_).absolutePath();
        QFileInfo fi(dir);
        if (fi.exists() && fi.isDir())
            QFile(dir).setPermissions(QFile::ReadUser | QFile::WriteUser | QFile::ExeUser);
        QFile::remove(path_);
    }

    void enableCreatesEntry() {
        QVERIFY(applyAutostart(true));
        QVERIFY(QFile::exists(path_));
        QFile f(path_);
        QVERIFY(f.open(QIODevice::ReadOnly | QIODevice::Text));
        const QString content = QString::fromUtf8(f.readAll());
        QVERIFY(content.contains("[Desktop Entry]"));
        QVERIFY(content.contains("Exec="));
        QVERIFY(content.contains("X-GNOME-Autostart-enabled=true"));
    }

    void disableRemovesEntry() {
        QVERIFY(applyAutostart(true));
        QVERIFY(QFile::exists(path_));
        QVERIFY(applyAutostart(false));      // real remove → true
        QVERIFY(!QFile::exists(path_));
    }

    // Disabling a non-existent entry is already "off" → honest success, not a lie
    // about a removal that didn't happen.
    void disableWhenAbsentIsSuccess() {
        QFile::remove(path_);
        QVERIFY(!QFile::exists(path_));
        QVERIFY(applyAutostart(false));
    }

    // Honest return regression: when the removal genuinely fails (parent dir made
    // read-only so unlink is denied), applyAutostart(false) must report false —
    // the hub previously returned true unconditionally on the disable path.
    void disableReturnsRealRemoveResult() {
        if (::geteuid() == 0)
            QSKIP("running as root ignores directory permissions");
        QVERIFY(applyAutostart(true));
        const QString dir = QFileInfo(path_).absolutePath();
        QFile dirFile(dir);
        QVERIFY(dirFile.setPermissions(QFile::ReadUser | QFile::ExeUser));  // drop write
        const bool r = applyAutostart(false);
        // Restore write so cleanup() can delete the file.
        dirFile.setPermissions(QFile::ReadUser | QFile::WriteUser | QFile::ExeUser);
        QVERIFY2(!r, "disable must return the real (failed) remove result");
        QVERIFY(QFile::exists(path_));  // removal really was denied
    }

    // Enable-path failure: when the entry can't be written (dir made read-only so
    // QFile::open fails), applyAutostart(true) must report false, not lie success.
    void enableReturnsFalseWhenDirUnwritable() {
        if (::geteuid() == 0)
            QSKIP("running as root ignores directory permissions");
        const QString dir = QFileInfo(path_).absolutePath();
        QVERIFY(QDir().mkpath(dir));
        QFile::remove(path_);
        QFile dirFile(dir);
        QVERIFY(dirFile.setPermissions(QFile::ReadUser | QFile::ExeUser));  // drop write
        const bool r = applyAutostart(true);
        // Restore write so cleanup() can operate.
        dirFile.setPermissions(QFile::ReadUser | QFile::WriteUser | QFile::ExeUser);
        QVERIFY2(!r, "enable must fail when the entry file can't be opened for write");
        QVERIFY(!QFile::exists(path_));  // nothing was written
    }

    // Exec quoting: a program path containing a space must be double-quoted in the
    // .desktop Exec line (else it parses as multiple arguments); a plain path is left
    // untouched. This is the seam applyAutostart() uses for its Exec= value.
    void execQuotingHandlesSpaces() {
        QCOMPARE(quoteExecForDesktop(QStringLiteral("/usr/bin/xeneon-edge-hub")),
                 QStringLiteral("/usr/bin/xeneon-edge-hub"));
        QCOMPARE(quoteExecForDesktop(QStringLiteral("/opt/My Apps/xeneon-edge-hub")),
                 QStringLiteral("\"/opt/My Apps/xeneon-edge-hub\""));
        // A path with multiple spaces is wrapped exactly once, as a whole.
        QCOMPARE(quoteExecForDesktop(QStringLiteral("/a b/c d/hub")),
                 QStringLiteral("\"/a b/c d/hub\""));
    }
};

QTEST_GUILESS_MAIN(TstAutostart)
#include "tst_autostart.moc"
