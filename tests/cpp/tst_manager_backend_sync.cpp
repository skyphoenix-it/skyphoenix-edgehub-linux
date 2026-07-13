// Integration tests for ManagerBackend: live two-way sync with a fake hub over a
// REAL QLocalSocket, PULL-before-PUSH reconnect reconciliation, the post-push
// suppression window (driven by an INJECTED clock so there is zero real waiting),
// and the image import/delete/sanitize surface. Needs a QGuiApplication (offscreen).
#include <QtTest>
#include <QLocalServer>
#include <QLocalSocket>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QDir>
#include <QFile>
#include <QImage>

#include "manager_backend.h"

static const char* kSock = "xeneon-edge-hub-ctl";

// A minimal stand-in for the hub's ControlServer: records the requests it receives
// and lets the test push uiState replies on demand.
class FakeHub : public QObject {
    Q_OBJECT
public:
    QLocalServer server;
    QLocalSocket* client = nullptr;
    QByteArray rx;
    QString getReply;                 // state returned for getUiState
    QStringList received;             // request types, in order
    QStringList setStates;            // states received via setUiState
    bool holdGet = false;             // when true, DON'T auto-reply to getUiState…
    bool getPending = false;          // …record that one is owed, release it later

    bool start() {
        QLocalServer::removeServer(kSock);
        connect(&server, &QLocalServer::newConnection, this, [this] {
            client = server.nextPendingConnection();
            connect(client, &QLocalSocket::readyRead, this, &FakeHub::onRx);
        });
        return server.listen(kSock);
    }
    void sendUiState(const QString& state) {
        if (!client) return;
        client->write(QJsonDocument(QJsonObject{{"type", "uiState"}, {"state", state}})
                          .toJson(QJsonDocument::Compact));
        client->write("\n");
        client->flush();
    }
    // Release a getUiState reply that was withheld while holdGet was set.
    void releaseGet() {
        if (getPending) { getPending = false; sendUiState(getReply); }
    }
private slots:
    void onRx() {
        rx += client->readAll();
        int nl;
        while ((nl = rx.indexOf('\n')) >= 0) {
            const QByteArray line = rx.left(nl);
            rx.remove(0, nl + 1);
            const QJsonObject o = QJsonDocument::fromJson(line).object();
            const QString type = o.value("type").toString();
            received << type;
            if (type == "getUiState") {
                if (holdGet) getPending = true;   // slip an edit into the reply window
                else sendUiState(getReply);
            } else if (type == "setUiState") {
                setStates << o.value("state").toString();
            }
        }
    }
};

class TstManagerBackendSync : public QObject {
    Q_OBJECT
    qint64 clockMs_ = 100000;
private slots:

    // ── Image surface (no socket needed) ──
    void importImageUniqueNaming() {
        ManagerBackend b;
        const QString imgDir = b.imagesDir();
        // Fresh dir.
        for (const QString& f : QDir(imgDir).entryList(QDir::Files)) QFile::remove(imgDir + "/" + f);

        const QString src = QDir::tempPath() + "/xe-src.png";
        QImage(4, 4, QImage::Format_RGB32).save(src, "PNG");

        const QString n1 = b.importImage("file://" + src);
        QCOMPARE(n1, QStringLiteral("xe-src.png"));
        QVERIFY(QFile::exists(imgDir + "/" + n1));

        // A second import of the same basename must NOT overwrite → unique name.
        const QString n2 = b.importImage("file://" + src);
        QVERIFY(n2 != n1);
        QCOMPARE(n2, QStringLiteral("xe-src-1.png"));
        QVERIFY(QFile::exists(imgDir + "/" + n2));

        // Unreadable source → empty.
        QVERIFY(b.importImage("file:///no/such/file.png").isEmpty());
    }

    void deleteImageAndTraversal() {
        ManagerBackend b;
        const QString imgDir = b.imagesDir();
        const QString src = QDir::tempPath() + "/xe-del.png";
        QImage(4, 4, QImage::Format_RGB32).save(src, "PNG");
        const QString name = b.importImage("file://" + src);
        QVERIFY(QFile::exists(imgDir + "/" + name));

        // A crafted traversal name must not delete anything outside the images dir.
        const QString outside = QFileInfo(imgDir).absolutePath() + "/keep.txt";
        QFile kf(outside); QVERIFY(kf.open(QIODevice::WriteOnly)); kf.write("x"); kf.close();
        QVERIFY(!b.deleteImage("../keep.txt"));
        QVERIFY(QFile::exists(outside));      // untouched
        QFile::remove(outside);

        // A real image deletes.
        QVERIFY(b.deleteImage(name));
        QVERIFY(!QFile::exists(imgDir + "/" + name));
    }

    // ── Live push on save (connected) ──
    void livePushOnSave() {
        FakeHub hub; QVERIFY(hub.start());
        ManagerBackend b;
        b.setClockForTest([this] { return clockMs_; });
        QTRY_VERIFY_WITH_TIMEOUT(hub.client != nullptr, 5000);
        QTRY_VERIFY_WITH_TIMEOUT(b.hubConnected(), 5000);

        b.saveUiState(QStringLiteral("{\"pushed\":1}"));
        QTRY_VERIFY_WITH_TIMEOUT(!hub.setStates.isEmpty(), 5000);
        QCOMPARE(hub.setStates.last(), QStringLiteral("{\"pushed\":1}"));

        // startHub is a no-op success when a hub is already connected (no 2nd instance).
        QVERIFY(b.startHub());
        // stopHub over a connected socket asks the hub to quit (shutdown message).
        QVERIFY(b.stopHub());
        QTRY_VERIFY_WITH_TIMEOUT(hub.received.contains(QStringLiteral("shutdown")), 5000);
    }

    // ── Invokable/config/env surface exercised without a hub (single-writer offline). ──
    void invokableSurface() {
        ManagerBackend b;
        b.setClockForTest([this] { return clockMs_; });

        // Metrics + config getters return well-formed, non-null JSON strings.
        QVERIFY(b.metricsJson().startsWith('{'));
        QVERIFY(!b.configJson().isEmpty());
        b.saveUiState(QStringLiteral("{\"k\":1}"));            // offline persist
        QCOMPARE(b.uiState(), QStringLiteral("{\"k\":1}"));
        const QString starter = b.starterLayout();
        QVERIFY(starter.isEmpty() || starter.startsWith('{') || starter.startsWith('['));

        // Target display round-trips through the config.
        QVERIFY(b.setTargetDisplay(QStringLiteral("DP-2"), QStringLiteral("XENEON EDGE")));
        QCOMPARE(b.targetConnector(), QStringLiteral("DP-2"));
        QCOMPARE(b.targetModel(), QStringLiteral("XENEON EDGE"));

        // Offscreen platform hides the bogus 800x800 screen → "[]".
        QCOMPARE(b.screensJson(), QStringLiteral("[]"));

        // imageUrl: empty name → empty; a real name → a file:// URL for that file.
        QVERIFY(b.imageUrl(QString()).isEmpty());
        const QString url = b.imageUrl(QStringLiteral("a b.png"));
        QVERIFY(url.startsWith(QStringLiteral("file://")));
        QVERIFY(url.endsWith(QStringLiteral("a b.png")) || url.contains(QStringLiteral("%20")));
        // A path component is stripped to the bare filename (no traversal in the URL).
        QVERIFY(!b.imageUrl(QStringLiteral("../../etc/passwd")).contains(QStringLiteral("..")));

        // Dev affordances default to empty/0 when the env vars are unset.
        qunsetenv("XENEON_GRAB"); qunsetenv("XENEON_TAB"); qunsetenv("XENEON_CFG");
        QVERIFY(b.grabPath().isEmpty());
        QCOMPARE(b.startTab(), 0);
        QVERIFY(b.autoConfig().isEmpty());

        b.listImages();                 // returns without crashing (possibly empty)
        QVERIFY(!b.stopHub());          // no hub connected → honest false
    }

    // ── Autostart install/remove via the Manager surface (HOME = per-test temp). ──
    void autostartSurface() {
        ManagerBackend b;
        const QString entry = QDir::homePath() + "/.config/autostart/xeneon-edge-hub.desktop";
        QFile::remove(entry);
        QVERIFY(!b.isAutostart());
        QVERIFY(b.setAutostart(true));
        QVERIFY(b.isAutostart());
        QVERIFY(QFile::exists(entry));
        QVERIFY(b.setAutostart(false));
        QVERIFY(!b.isAutostart());
        QVERIFY(!QFile::exists(entry));
        // Disabling again when already absent is honest success (nothing to remove).
        QVERIFY(b.setAutostart(false));
        QVERIFY(!b.isAutostart());
    }

    // ── Adopt the hub's pushed state once outside the suppression window ──
    void adoptFromHub() {
        FakeHub hub; hub.getReply = QString(); QVERIFY(hub.start());
        ManagerBackend b;
        b.setClockForTest([this] { return clockMs_; });
        QTRY_VERIFY_WITH_TIMEOUT(b.hubConnected(), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(hub.client != nullptr, 5000);

        QSignalSpy spy(&b, &ManagerBackend::configChanged);
        hub.sendUiState(QStringLiteral("{\"fromhub\":7}"));
        QTRY_VERIFY_WITH_TIMEOUT(spy.count() >= 1, 5000);
        QCOMPARE(b.uiState(), QStringLiteral("{\"fromhub\":7}"));
    }

    // ── Suppression window: a stale hub reply right after our push is IGNORED, while
    //    a later reply past the window is adopted. De-flaked: instead of a bare qWait
    //    (which could pass simply because the stale line hadn't arrived yet), we send
    //    BOTH the stale and the fresh state in ONE write so they are received and
    //    processed IN ORDER, and use a counting clock that evaluates the first inbound
    //    line in-window and the second past it. Fresh being adopted PROVES both lines
    //    were processed; exactly ONE configChanged PROVES the stale one was ignored. ──
    void suppressionWindow() {
        FakeHub hub; hub.getReply = QString(); QVERIFY(hub.start());
        ManagerBackend b;
        b.setClockForTest([this] { return clockMs_; });
        QTRY_VERIFY_WITH_TIMEOUT(b.hubConnected(), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(hub.client != nullptr, 5000);

        clockMs_ = 100000;
        b.saveUiState(QStringLiteral("{\"mine\":1}"));   // sets suppress until 101500
        QTRY_VERIFY_WITH_TIMEOUT(!hub.setStates.isEmpty(), 5000);
        QCOMPARE(b.uiState(), QStringLiteral("{\"mine\":1}"));

        // Drain the initial (empty) pull reply so the counting clock below maps 1:1
        // onto exactly the two inbound lines we are about to send.
        QTest::qWait(50);

        // Counting clock: the 1st inbound uiState (stale) is evaluated in-window
        // (100000 < 101500 → IGNORED); the 2nd (fresh) is past the window (200000 →
        // ADOPTED). Both are delivered in one write, so they process in order.
        int tick = 0;
        b.setClockForTest([&tick] { return tick++ == 0 ? qint64(100000) : qint64(200000); });

        QSignalSpy spy(&b, &ManagerBackend::configChanged);
        QByteArray twoMsgs;
        twoMsgs += QJsonDocument(QJsonObject{{"type", "uiState"}, {"state", "{\"stale\":2}"}})
                       .toJson(QJsonDocument::Compact) + "\n";
        twoMsgs += QJsonDocument(QJsonObject{{"type", "uiState"}, {"state", "{\"fresh\":3}"}})
                       .toJson(QJsonDocument::Compact) + "\n";
        hub.client->write(twoMsgs);
        hub.client->flush();

        // Fresh is adopted → both lines were received & processed, in order…
        QTRY_VERIFY_WITH_TIMEOUT(b.uiState() == QStringLiteral("{\"fresh\":3}"), 5000);
        // …and the in-window stale line produced NO adoption (only fresh did).
        QCOMPARE(spy.count(), 1);
    }

    // ── #7 regression: a live edit on a CONNECTED socket must SUPERSEDE an older edit
    //    buffered while offline. Reproduce the stale-repush edit-loss window: buffer
    //    edit A offline; on reconnect the getUiState reply is HELD; slip a live edit B
    //    in; then release the reply — the reconcile must NOT re-push the stale A over
    //    the newer B. Without the fix, B is lost (final hub state reverts to A). ──
    void connectedEditSupersedesBufferedOfflineEdit() {
        ManagerBackend b;
        b.setClockForTest([this] { return clockMs_; });
        clockMs_ = 100000;
        b.saveUiState(QStringLiteral("{\"A\":1}"));   // offline → buffered pending edit

        // Bring the hub up but HOLD its getUiState reply, so we sit inside the reconnect
        // window (pull sent, not yet answered) — exactly where the heisenbug lives.
        FakeHub hub; hub.holdGet = true; hub.getReply = QString();
        QVERIFY(hub.start());
        QVERIFY(b.startHub());
        QTRY_VERIFY_WITH_TIMEOUT(b.hubConnected(), 8000);
        QTRY_VERIFY_WITH_TIMEOUT(hub.received.contains(QStringLiteral("getUiState")), 8000);
        QVERIFY(hub.getPending);   // reply is genuinely withheld → we're in the window

        // Live edit B on the CONNECTED socket must win over the buffered A.
        b.saveUiState(QStringLiteral("{\"B\":2}"));
        QTRY_VERIFY_WITH_TIMEOUT(hub.setStates.contains(QStringLiteral("{\"B\":2}")), 8000);

        // Release the held pull reply: the (now superseded) reconcile must NOT re-push A.
        hub.releaseGet();
        QTest::qWait(200);   // give any (buggy) stale re-push time to arrive

        QVERIFY(!hub.setStates.isEmpty());
        QCOMPARE(hub.setStates.last(), QStringLiteral("{\"B\":2}"));   // newer edit wins
        const int bIdx = hub.setStates.lastIndexOf(QStringLiteral("{\"B\":2}"));
        QVERIFY2(!hub.setStates.mid(bIdx + 1).contains(QStringLiteral("{\"A\":1}")),
                 "stale buffered edit A was re-pushed AFTER the newer live edit B");
    }

    // ── #7 companion: DropEdit integration. After a real disconnect the hub's state
    //    CHANGED (differs from the tracked lastHubState); on reconnect the buffered
    //    offline edit is stale and must be DROPPED — no setUiState is sent. ──
    void reconnectDropsStaleEditWhenHubChanged() {
        FakeHub hub; hub.getReply = QStringLiteral("{\"OLD\":1}"); QVERIFY(hub.start());
        ManagerBackend b;
        b.setClockForTest([this] { return clockMs_; });
        clockMs_ = 100000;
        QTRY_VERIFY_WITH_TIMEOUT(b.hubConnected(), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(hub.client != nullptr, 5000);
        // First pull establishes the tracked baseline: lastHubState = OLD.
        QTRY_VERIFY_WITH_TIMEOUT(b.uiState() == QStringLiteral("{\"OLD\":1}"), 5000);

        // Drop the connection so the next edit buffers as an offline (pending) edit.
        hub.client->abort();
        QTRY_VERIFY_WITH_TIMEOUT(!b.hubConnected(), 5000);

        // The hub CHANGED while we were offline (device-side edit): OLD → NEW.
        hub.getReply = QStringLiteral("{\"NEW\":9}");
        hub.setStates.clear();
        hub.received.clear();

        // Offline edit buffers AND triggers a reconnect (tryConnectHub in pushLive).
        b.saveUiState(QStringLiteral("{\"stale\":42}"));

        // On reconnect the pull returns NEW ≠ OLD → the stale buffered edit is DROPPED,
        // so NO setUiState is ever sent.
        QTRY_VERIFY_WITH_TIMEOUT(hub.received.contains(QStringLiteral("getUiState")), 8000);
        QTest::qWait(200);
        QVERIFY2(hub.setStates.isEmpty(), "stale buffered edit must be dropped, not pushed");
    }

    // ── PULL-before-PUSH: an edit made while OFFLINE is buffered, and on reconnect
    //    the hub is pulled FIRST; since the hub didn't change, our edit is (re)pushed
    //    rather than lost — and getUiState is seen before setUiState. ──
    void reconnectKeepsOfflineEdit() {
        // No server yet → the save buffers as a pending offline edit.
        ManagerBackend b;
        b.setClockForTest([this] { return clockMs_; });
        b.saveUiState(QStringLiteral("{\"offline\":42}"));

        // Bring the hub up and force a connect.
        FakeHub hub; hub.getReply = QString(); QVERIFY(hub.start());
        clockMs_ = 500000;   // well past any suppression window
        QVERIFY(b.startHub());

        QTRY_VERIFY_WITH_TIMEOUT(!hub.setStates.isEmpty(), 8000);
        QCOMPARE(hub.setStates.last(), QStringLiteral("{\"offline\":42}"));
        // PULL happened before the PUSH.
        QVERIFY(hub.received.indexOf("getUiState") >= 0);
        QVERIFY(hub.received.indexOf("getUiState") < hub.received.lastIndexOf("setUiState"));
    }

    // ── Single-writer: when the hub is connected it owns config.toml. A saveUiState
    //    must push over IPC and must NOT also write the file itself (the two-writer
    //    save race is removed). We observe the socket push AND the absence of a file. ──
    void connectedSaveIsIpcOnlyNoFileWrite() {
        XeneonString cd(xeneon_config_dir());
        const QString cfg = cd.qstring() + "/config.toml";
        QFile::remove(cfg);                       // start from a known no-file state

        FakeHub hub; QVERIFY(hub.start());
        ManagerBackend b;
        b.setClockForTest([this] { return clockMs_; });
        QTRY_VERIFY_WITH_TIMEOUT(b.hubConnected(), 5000);

        b.saveUiState(QStringLiteral("{\"connected\":9}"));
        // Pushed over the socket…
        QTRY_VERIFY_WITH_TIMEOUT(!hub.setStates.isEmpty(), 5000);
        QCOMPARE(hub.setStates.last(), QStringLiteral("{\"connected\":9}"));
        // …and the in-memory copy reflects the edit…
        QCOMPARE(b.uiState(), QStringLiteral("{\"connected\":9}"));
        // …but the Manager did NOT persist config.toml itself (hub is the writer).
        QVERIFY(!QFile::exists(cfg));
    }

    // ── Offline: with no hub reachable, the Manager is the sole writer and persists
    //    the edit directly so offline editing is preserved. ──
    void disconnectedSaveWritesFile() {
        XeneonString cd(xeneon_config_dir());
        const QString cfg = cd.qstring() + "/config.toml";
        QFile::remove(cfg);

        ManagerBackend b;                          // no FakeHub → stays disconnected
        b.setClockForTest([this] { return clockMs_; });
        QVERIFY(!b.hubConnected());

        QVERIFY(b.saveUiState(QStringLiteral("{\"offline\":5}")));
        QVERIFY(QFile::exists(cfg));               // sole writer persisted directly
    }
};

QTEST_MAIN(TstManagerBackendSync)
#include "tst_manager_backend_sync.moc"
