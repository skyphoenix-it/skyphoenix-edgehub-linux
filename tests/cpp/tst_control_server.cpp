// Integration tests for ControlServer over a REAL QLocalSocket. Covers the full
// newline-delimited JSON protocol: ping, getUiState, setUiState (honest ok/fail
// ack), empty/malformed/unknown, shutdown ordering, the 8 MiB buffer cap, and
// re-entrancy (multiple lines + a handler that re-enters the event loop).
#include <QtTest>
#include <QLocalServer>
#include <QLocalSocket>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QElapsedTimer>
#include <QCoreApplication>

#include "control_server.h"

// Refuse to run outside a sandbox: this test would otherwise clobber the
// developer's real config / running hub. See hermetic.h.
#include "hermetic.h"
XENEON_REQUIRE_HERMETIC_ENV();

static const char* kSock = "xeneon-edge-hub-ctl";

class TstControlServer : public QObject {
    Q_OBJECT

    ControlServer* srv_ = nullptr;
    QString providerState_;
    bool ackResult_ = true;

    // Open a client, send one request line, collect `nLines` reply lines. The
    // server and client share this thread's event loop, so we PUMP events (rather
    // than block on the client fd) — otherwise the server never accepts/replies.
    QList<QJsonObject> exchange(const QByteArray& req, int nLines = 1) {
        QLocalSocket c;
        c.connectToServer(kSock);
        QElapsedTimer t; t.start();
        while (c.state() != QLocalSocket::ConnectedState && t.elapsed() < 3000)
            QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        if (c.state() != QLocalSocket::ConnectedState) return {};

        QByteArray line = req;
        if (!line.endsWith('\n')) line.append('\n');
        c.write(line);
        c.flush();

        QByteArray buf;
        QList<QJsonObject> out;
        t.restart();
        while (out.size() < nLines && t.elapsed() < 3000) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
            buf += c.readAll();
            int nl;
            while ((nl = buf.indexOf('\n')) >= 0) {
                out << QJsonDocument::fromJson(buf.left(nl)).object();
                buf.remove(0, nl + 1);
            }
        }
        return out;
    }

private slots:
    void init() {
        srv_ = new ControlServer(this);
        srv_->setStateProvider([this] { return providerState_; });
        connect(srv_, &ControlServer::uiStateReceived, this,
                [this](const QString&, bool* ok) { if (ok) *ok = ackResult_; });
        QVERIFY(srv_->start());
    }
    void cleanup() {
        delete srv_;
        srv_ = nullptr;
        QLocalServer::removeServer(kSock);
    }

    void ping() {
        const auto r = exchange("{\"type\":\"ping\"}");
        QCOMPARE(r.size(), 1);
        QCOMPARE(r[0].value("type").toString(), QStringLiteral("pong"));
    }

    void getUiState() {
        providerState_ = QStringLiteral("{\"layout\":\"grid\"}");
        const auto r = exchange("{\"type\":\"getUiState\"}");
        QCOMPARE(r.size(), 1);
        QCOMPARE(r[0].value("type").toString(), QStringLiteral("uiState"));
        QCOMPARE(r[0].value("state").toString(), providerState_);
    }

    void setUiStateOkAck() {
        ackResult_ = true;
        QSignalSpy spy(srv_, &ControlServer::uiStateReceived);
        const auto r = exchange("{\"type\":\"setUiState\",\"state\":\"{\\\"a\\\":1}\"}");
        QCOMPARE(r.size(), 1);
        QCOMPARE(r[0].value("type").toString(), QStringLiteral("ok"));
        QCOMPARE(spy.count(), 1);
    }

    // Honest fail ack: when the owner reports the apply failed, the ack must be an
    // error, not a lie of success (else the Manager silently diverges).
    void setUiStateFailAck() {
        ackResult_ = false;
        const auto r = exchange("{\"type\":\"setUiState\",\"state\":\"{\\\"a\\\":1}\"}");
        QCOMPARE(r.size(), 1);
        QCOMPARE(r[0].value("type").toString(), QStringLiteral("error"));
        QCOMPARE(r[0].value("message").toString(), QStringLiteral("failed to apply state"));
    }

    void setUiStateEmpty() {
        const auto r = exchange("{\"type\":\"setUiState\",\"state\":\"\"}");
        QCOMPARE(r.size(), 1);
        QCOMPARE(r[0].value("type").toString(), QStringLiteral("error"));
        QCOMPARE(r[0].value("message").toString(), QStringLiteral("empty state"));
    }

    void malformedJson() {
        const auto r = exchange("{not json");
        QCOMPARE(r.size(), 1);
        QCOMPARE(r[0].value("type").toString(), QStringLiteral("error"));
        QCOMPARE(r[0].value("message").toString(), QStringLiteral("invalid json"));
    }

    void unknownType() {
        const auto r = exchange("{\"type\":\"frobnicate\"}");
        QCOMPARE(r.size(), 1);
        QCOMPARE(r[0].value("type").toString(), QStringLiteral("error"));
        QCOMPARE(r[0].value("message").toString(), QStringLiteral("unknown type"));
    }

    // shutdown ORDERING: the ack MUST be written+flushed BEFORE shutdownRequested is
    // emitted. We wire the shutdown slot to immediately tear the server down (as
    // main() quits the loop on shutdown), so the ok is only observable if it was
    // written first — a reversed (emit-before-write) order would close the socket and
    // DROP the ack, making `r` empty.
    void shutdownAcksThenSignals() {
        QSignalSpy spy(srv_, &ControlServer::shutdownRequested);
        ControlServer* dying = srv_;
        QMetaObject::Connection conn = connect(srv_, &ControlServer::shutdownRequested, this,
            [dying] { dying->deleteLater(); });   // tear down on shutdown, like main()
        const auto r = exchange("{\"type\":\"shutdown\"}");
        disconnect(conn);
        srv_ = nullptr;   // handed to deleteLater; keep cleanup() from double-deleting
        QCOMPARE(r.size(), 1);
        QCOMPARE(r[0].value("type").toString(), QStringLiteral("ok"));   // ack survived
        QVERIFY(spy.count() >= 1);                                        // signal fired
    }

    // 8 MiB cap: a client that streams a huge line with no newline has its
    // connection dropped rather than growing the buffer unbounded.
    void oversizedMessageDropsConnection() {
        QLocalSocket c;
        c.connectToServer(kSock);
        QElapsedTimer t; t.start();
        while (c.state() != QLocalSocket::ConnectedState && t.elapsed() < 3000)
            QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        QVERIFY(c.state() == QLocalSocket::ConnectedState);

        QByteArray chunk(1024 * 1024, 'x');   // 1 MiB, no newline
        for (int i = 0; i < 10 && c.state() == QLocalSocket::ConnectedState; ++i) {
            c.write(chunk);
            c.flush();
            c.waitForBytesWritten(500);
            QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        }
        // Server aborts the connection once the buffer exceeds 8 MiB.
        t.restart();
        while (c.state() == QLocalSocket::ConnectedState && t.elapsed() < 3000)
            QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        QVERIFY(c.state() != QLocalSocket::ConnectedState);
    }

    // Two complete requests in a single write must both be processed, in order.
    void multipleLinesInOneWrite() {
        const auto r = exchange("{\"type\":\"ping\"}\n{\"type\":\"ping\"}", /*nLines*/ 2);
        QCOMPARE(r.size(), 2);
        QCOMPARE(r[0].value("type").toString(), QStringLiteral("pong"));
        QCOMPARE(r[1].value("type").toString(), QStringLiteral("pong"));
    }

    // A handler that re-enters the event loop (processEvents) mid-dispatch must not
    // corrupt the per-connection buffer. Send TWO complete requests in ONE write: the
    // FIRST handler re-enters the event loop, so onReadyRead()'s line loop must
    // re-look-up the buffer (not hold a stale iterator) and still process the SECOND
    // line — exercising the multi-line dangling-iterator guard, not just single-line.
    void reentrantHandlerSafe() {
        ackResult_ = true;
        QMetaObject::Connection conn = connect(srv_, &ControlServer::uiStateReceived, this,
            [](const QString&, bool*) { QCoreApplication::processEvents(); });
        const auto r = exchange(
            "{\"type\":\"setUiState\",\"state\":\"{\\\"x\\\":1}\"}\n"
            "{\"type\":\"setUiState\",\"state\":\"{\\\"y\\\":2}\"}", /*nLines*/ 2);
        disconnect(conn);
        QCOMPARE(r.size(), 2);
        QCOMPARE(r[0].value("type").toString(), QStringLiteral("ok"));
        QCOMPARE(r[1].value("type").toString(), QStringLiteral("ok"));
    }
};

QTEST_GUILESS_MAIN(TstControlServer)
#include "tst_control_server.moc"
