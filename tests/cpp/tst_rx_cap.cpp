// Robustness tests for ManagerBackend's IPC read path (onSocketReadyRead):
//   1. An unterminated flood (no '\n') is CAPPED — the pending RX buffer never
//      grows past ~1 MB, so a stuck/hostile peer can't OOM the Manager.
//   2. A malformed JSON line is LOGGED and IGNORED without desyncing the stream:
//      a valid uiState sent right after it is still adopted.
// Both drive a REAL QLocalSocket (the same seam the sync tests use) so the read
// slot runs exactly as in production. Needs a QGuiApplication (offscreen).
#include <QtTest>
#include <QLocalServer>
#include <QLocalSocket>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>

#include "manager_backend.h"

// Refuse to run outside a sandbox: this test would otherwise clobber the
// developer's real config / running hub. See hermetic.h.
#include "hermetic.h"
XENEON_REQUIRE_HERMETIC_ENV();

static const char* kSock = "xeneon-edge-hub-ctl";

// Minimal server that hands us the connected socket so the test can write raw
// bytes (well-formed or not) straight at the Manager's read slot.
class RawHub : public QObject {
    Q_OBJECT
public:
    QLocalServer server;
    QLocalSocket* client = nullptr;
    bool start() {
        QLocalServer::removeServer(kSock);
        connect(&server, &QLocalServer::newConnection, this, [this] {
            client = server.nextPendingConnection();
        });
        return server.listen(kSock);
    }
    void sendUiState(const QString& state) {
        client->write(QJsonDocument(QJsonObject{{"type", "uiState"}, {"state", state}})
                          .toJson(QJsonDocument::Compact));
        client->write("\n");
        client->flush();
    }
    void sendRaw(const QByteArray& bytes) { client->write(bytes); client->flush(); }
};

class TstRxCap : public QObject {
    Q_OBJECT
    qint64 clockMs_ = 100000;
private slots:

    // ── An unterminated flood is bounded ──
    void unterminatedFloodIsCapped() {
        RawHub hub; QVERIFY(hub.start());
        ManagerBackend b;
        b.setClockForTest([this] { return clockMs_; });
        QTRY_VERIFY_WITH_TIMEOUT(hub.client != nullptr, 5000);
        QTRY_VERIFY_WITH_TIMEOUT(b.hubConnected(), 5000);

        // Push ~4 MB with NO newline in chunks; pump the event loop so the read
        // slot runs between chunks (matching real streamed delivery).
        const QByteArray chunk(256 * 1024, 'x');   // 256 KiB of non-newline bytes
        for (int i = 0; i < 16; ++i) {             // 4 MiB total
            hub.sendRaw(chunk);
            QTest::qWait(10);
            // The pending buffer must stay bounded well under the flood size. Allow
            // headroom (cap + one in-flight chunk) but assert it never approaches 4 MB.
            QVERIFY2(b.rxBufferSizeForTest() <= (1 << 20) + chunk.size(),
                     qPrintable(QStringLiteral("rx buffer grew to %1 bytes")
                                    .arg(b.rxBufferSizeForTest())));
        }

        // Close the (garbage) unterminated frame with a newline — the residual is
        // consumed as one malformed line and dropped. A following newline-terminated
        // message then parses normally: the reader resynced rather than wedging.
        QSignalSpy spy(&b, &ManagerBackend::configChanged);
        hub.sendRaw(QByteArray("\n"));              // terminate the corrupt frame
        QTest::qWait(20);
        hub.sendUiState(QStringLiteral("{\"afterflood\":1}"));
        QTRY_VERIFY_WITH_TIMEOUT(spy.count() >= 1, 5000);
        QCOMPARE(b.uiState(), QStringLiteral("{\"afterflood\":1}"));
    }

    // ── A malformed line is ignored without desyncing the stream ──
    void malformedLineIgnoredNoDesync() {
        RawHub hub; QVERIFY(hub.start());
        ManagerBackend b;
        b.setClockForTest([this] { return clockMs_; });
        QTRY_VERIFY_WITH_TIMEOUT(hub.client != nullptr, 5000);
        QTRY_VERIFY_WITH_TIMEOUT(b.hubConnected(), 5000);

        QSignalSpy spy(&b, &ManagerBackend::configChanged);

        // One garbage line + one blank line + one VALID uiState, all framed by '\n'
        // in a single write so they process in order. The garbage/blank must be
        // skipped and the valid line still adopted (proves framing kept us in sync).
        QByteArray msgs;
        msgs += QByteArray("{ this is : not json ]\n");
        msgs += QByteArray("   \n");
        msgs += QJsonDocument(QJsonObject{{"type", "uiState"}, {"state", "{\"ok\":9}"}})
                    .toJson(QJsonDocument::Compact) + "\n";
        hub.sendRaw(msgs);

        QTRY_VERIFY_WITH_TIMEOUT(b.uiState() == QStringLiteral("{\"ok\":9}"), 5000);
        QCOMPARE(spy.count(), 1);   // exactly the one valid line was adopted
        QCOMPARE(b.rxBufferSizeForTest(), 0);   // all complete lines consumed
    }
};

QTEST_MAIN(TstRxCap)
#include "tst_rx_cap.moc"
