// Traversal matrix for sanitizeImageName(): a crafted image name must never
// resolve outside the images directory. Pure string/path logic — GUILESS.
#include <QtTest>
#include <QDir>

#include "path_sanitize.h"

class TstPathSanitize : public QObject {
    Q_OBJECT
    QString imagesDir_;
private slots:
    void initTestCase() {
        imagesDir_ = QDir::cleanPath(QDir::tempPath() + "/xeneon-sanitize-test/images");
        QDir().mkpath(imagesDir_);
    }

    // Accepted names collapse to <imagesDir>/<basename>.
    void accepts_data() {
        QTest::addColumn<QString>("name");
        QTest::addColumn<QString>("expectBase");
        QTest::newRow("plain")        << "photo.png"       << "photo.png";
        QTest::newRow("with-space")   << "my photo.png"    << "my photo.png";
        QTest::newRow("with-hash")    << "a#b.png"         << "a#b.png";
        QTest::newRow("subpath-strip")<< "a/b.png"         << "b.png";       // dir stripped
        QTest::newRow("deep-strip")   << "x/y/z.png"       << "z.png";
        QTest::newRow("dotfile")      << ".hidden.png"     << ".hidden.png";
    }
    void accepts() {
        QFETCH(QString, name);
        QFETCH(QString, expectBase);
        const auto r = sanitizeImageName(name, imagesDir_);
        QVERIFY2(r.has_value(), "expected accepted");
        QCOMPARE(*r, QDir::cleanPath(imagesDir_ + "/" + expectBase));
        // The resolved path is genuinely inside the images dir.
        QVERIFY(r->startsWith(imagesDir_ + "/"));
    }

    // Rejected names (empty / dot / would traverse out).
    void rejects_data() {
        QTest::addColumn<QString>("name");
        QTest::newRow("empty")        << "";
        QTest::newRow("dot")          << ".";
        QTest::newRow("dotdot")       << "..";
        QTest::newRow("trailing-slash")<< "foo/";   // fileName() == "" → rejected
    }
    void rejects() {
        QFETCH(QString, name);
        QVERIFY(!sanitizeImageName(name, imagesDir_).has_value());
    }

    // Traversal attempts collapse to a bare filename and stay INSIDE the dir (never
    // escape), regardless of how many ../ segments or an absolute prefix is used.
    void traversalContained_data() {
        QTest::addColumn<QString>("name");
        QTest::newRow("parent")        << "../secret.png";
        QTest::newRow("deep-parent")   << "../../../.config/foo.png";
        QTest::newRow("absolute")      << "/etc/passwd";
        QTest::newRow("absolute-home") << "/home/simon/.ssh/id_rsa";
    }
    void traversalContained() {
        QFETCH(QString, name);
        const auto r = sanitizeImageName(name, imagesDir_);
        // Either rejected, or contained strictly within the images dir — never an
        // escape to a parent/sibling path.
        if (r.has_value()) {
            QVERIFY2(r->startsWith(imagesDir_ + "/"),
                     qPrintable(QStringLiteral("escaped to: %1").arg(*r)));
            QVERIFY(!r->contains(".."));
        }
    }
};

QTEST_GUILESS_MAIN(TstPathSanitize)
#include "tst_path_sanitize.moc"
