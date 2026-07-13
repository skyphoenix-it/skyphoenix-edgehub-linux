// Xeneon Edge Manager — a standalone companion desktop app to manage the Edge
// hub: build/reorder the widget layout, tune appearance, upload images, and set
// display/startup options. It edits the SAME config the hub reads (via the Rust
// core) and, when the hub is running, stays in live sync over the hub's local
// control socket (pushes its own edits, pulls the hub's). Works with or without
// the hub running.

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QScreen>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QDateTime>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QTextStream>
#include <QTimer>
#include <QImage>
#include <QQuickWindow>
#include <QQuickStyle>
#include <QLocalSocket>
#include <QProcess>

#include "xeneon_core.h"

// --- RAII string wrapper (mirrors the hub's) ---
class XeneonString {
    char* ptr;
public:
    explicit XeneonString(char* p) : ptr(p) {}
    ~XeneonString() { if (ptr) xeneon_string_free(ptr); }
    XeneonString(const XeneonString&) = delete;
    XeneonString& operator=(const XeneonString&) = delete;
    QString qstring() const { return ptr ? QString::fromUtf8(ptr) : QString(); }
};

// --- ManagerBackend ---
// Presents the SAME interface the hub's ConfigBridge exposes (uiState/
// saveUiState/starterLayout/configJson) so the shared DashboardStore.qml drives
// it unchanged, plus display/image/startup operations and LIVE two-way sync with
// a running hub (push our edits + pull the hub's over the control socket, plus a
// file watcher for the offline case).
class ManagerBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hubConnected READ hubConnected NOTIFY hubConnectedChanged)
public:
    explicit ManagerBackend(QObject* parent = nullptr) : QObject(parent) {
        m_config = xeneon_config_load();
        if (!m_config)
            qCritical() << "Manager: failed to load config";

        XeneonString cd(xeneon_config_dir());
        m_configPath = cd.qstring() + "/config.toml";

        m_sock = new QLocalSocket(this);
        connect(m_sock, &QLocalSocket::connected, this, [this] {
            m_hubConnected = true;
            emit hubConnectedChanged();
            // Correct reconnect order: PULL the hub's authoritative state FIRST,
            // then reconcile any edit buffered while the socket was down against it
            // (in onSocketReadyRead, when the reply arrives) before pushing.
            // Flushing the buffered edit here — BEFORE pulling — would clobber edits
            // made on the device while the Manager was offline.
            if (!m_pendingPush.isEmpty())
                m_pendingPushAwaitingHub = true;
            syncFromHub();
        });
        connect(m_sock, &QLocalSocket::disconnected, this, [this] {
            m_hubConnected = false; emit hubConnectedChanged();
        });
        connect(m_sock, &QLocalSocket::errorOccurred, this, [this](QLocalSocket::LocalSocketError) {
            m_hubConnected = false; emit hubConnectedChanged();
        });
        connect(m_sock, &QLocalSocket::readyRead, this, &ManagerBackend::onSocketReadyRead);

        // Reconnect loop so the "connected" indicator recovers when the hub starts
        // AFTER the Manager (or restarts) — the ctor connect alone isn't enough.
        auto* reconnect = new QTimer(this);
        reconnect->setInterval(2000);
        connect(reconnect, &QTimer::timeout, this, [this] { tryConnectHub(); });
        reconnect->start();

        // Gentle periodic pull so device-side edits on the hub appear in the
        // Manager (getUiState is cheap; QML only reloads when the state differs).
        auto* pull = new QTimer(this);
        pull->setInterval(4000);
        connect(pull, &QTimer::timeout, this, [this] { syncFromHub(); });
        pull->start();

        // Watch the config file so an OFFLINE external change (e.g. hub shutdown
        // save) is reflected. When the hub is connected we prefer getUiState.
        m_watcher = new QFileSystemWatcher(this);
        if (QFile::exists(m_configPath)) m_watcher->addPath(m_configPath);
        // Also watch the containing directory so that if config.toml does NOT exist
        // yet at startup, we arm the file watch the moment it first appears — without
        // this, later external writes to a config that was initially absent go unseen.
        const QString cfgDir = QFileInfo(m_configPath).absolutePath();
        QDir().mkpath(cfgDir);
        if (QFile::exists(cfgDir)) m_watcher->addPath(cfgDir);
        connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
            if (m_watcher->files().contains(m_configPath) || !QFile::exists(m_configPath))
                return;                       // already armed, or still absent
            m_watcher->addPath(m_configPath); // config just appeared — arm the watch
            if (QDateTime::currentMSecsSinceEpoch() < m_ignoreWatchUntilMs) return;
            if (m_hubConnected) return;
            reloadConfig();                   // pick up the just-created config
        });
        connect(m_watcher, &QFileSystemWatcher::fileChanged, this, [this] {
            // Atomic saves rename over the file and drop the watch — re-add it.
            QTimer::singleShot(60, this, [this] {
                if (!m_watcher->files().contains(m_configPath) && QFile::exists(m_configPath))
                    m_watcher->addPath(m_configPath);
                if (QDateTime::currentMSecsSinceEpoch() < m_ignoreWatchUntilMs) return; // our own write
                if (m_hubConnected) return;   // IPC keeps us in sync when connected
                reloadConfig();
            });
        });

        // Live display hotplug → Display tab refresh.
        connect(qApp, &QGuiApplication::screenAdded, this, [this](QScreen*) { emit screensChanged(); });
        connect(qApp, &QGuiApplication::screenRemoved, this, [this](QScreen*) { emit screensChanged(); });

        tryConnectHub();
    }
    ~ManagerBackend() override {
        if (m_config) xeneon_config_free(m_config);
    }

    bool hubConnected() const { return m_hubConnected; }

    // Launch the hub if it isn't already running. Returns false only when the
    // launch could not be started (missing binary). If a hub is already up (or
    // we're mid-connect to one), it's a no-op success — avoids a double instance.
    Q_INVOKABLE bool startHub() {
        if (m_hubConnected || m_sock->state() == QLocalSocket::ConnectedState)
            return true;
        // A hub may be running that we simply haven't connected to yet (e.g. the
        // Manager just started). Probe synchronously before spawning a duplicate.
        {
            QLocalSocket probe;
            probe.connectToServer(QStringLiteral("xeneon-edge-hub-ctl"));
            if (probe.waitForConnected(250)) {
                probe.disconnectFromServer();
                tryConnectHub();
                return true;
            }
        }
        const bool ok = QProcess::startDetached(hubBinaryPath(), QStringList{});
        if (!ok) {
            qWarning() << "Manager: failed to launch hub" << hubBinaryPath();
            return false;
        }
        // The hub needs a moment to come up and listen; nudge the connection a few
        // times so the "connected" state (and Stop button) appears promptly.
        for (int delay : {300, 700, 1200, 2000})
            QTimer::singleShot(delay, this, [this] { tryConnectHub(); });
        return true;
    }

    // Ask a running hub to quit cleanly over the control socket. Returns false if
    // no hub is reachable to stop.
    Q_INVOKABLE bool stopHub() {
        if (m_sock->state() != QLocalSocket::ConnectedState) return false;
        writeMsg(QJsonObject{{"type", "shutdown"}});
        m_sock->flush();
        return true;
    }

    // Dev/doc affordances (headless capture).
    Q_INVOKABLE QString grabPath() const { return qEnvironmentVariable("XENEON_GRAB"); }
    Q_INVOKABLE int startTab() const { return qEnvironmentVariable("XENEON_TAB", "0").toInt(); }
    Q_INVOKABLE QString autoConfig() const { return qEnvironmentVariable("XENEON_CFG"); }

    // Live system metrics (same source + JSON shape the hub uses).
    Q_INVOKABLE QString metricsJson() const {
        MetricsHandle* m = xeneon_metrics_collect();
        if (!m) return QStringLiteral("{}");
        XeneonString s(xeneon_metrics_to_json(m));
        xeneon_metrics_free(m);
        return s.qstring();
    }

    // ── configBridge-compatible surface (DashboardStore uses these) ──
    Q_INVOKABLE QString uiState() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_get_ui_state(m_config));
        return s.qstring();
    }
    Q_INVOKABLE bool saveUiState(const QString& json) {
        if (!m_config) return false;
        xeneon_config_set_ui_state(m_config, json.toUtf8().constData());
        markSelfWrite();
        bool ok = xeneon_config_save(m_config) == 0;
        if (!ok) qWarning() << "Manager: failed to persist UI state";
        pushLive(json);   // live-update a running hub (buffers if not yet connected)
        return ok;
    }
    Q_INVOKABLE QString starterLayout() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_get_starter_layout(m_config));
        return s.qstring();
    }
    Q_INVOKABLE QString configJson() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_to_json(m_config));
        return s.qstring();
    }
    // Pull the hub's current UI state over IPC (called on connect + window focus).
    Q_INVOKABLE void syncFromHub() {
        if (m_sock->state() == QLocalSocket::ConnectedState)
            writeMsg(QJsonObject{{"type", "getUiState"}});
    }

    // ── Display / startup settings ──
    Q_INVOKABLE QString screensJson() const {
        // Headless/offscreen exposes a single bogus 800x800 screen — hide it so the
        // Display tab doesn't offer a garbage target in dev/capture runs.
        if (QGuiApplication::platformName().contains("offscreen", Qt::CaseInsensitive))
            return QStringLiteral("[]");
        QJsonArray arr;
        const auto screens = QGuiApplication::screens();
        QScreen* primary = QGuiApplication::primaryScreen();
        for (auto* s : screens) {
            // Use the NATIVE/physical pixel resolution, not the logical (DPI-scaled)
            // size: QScreen::size() is in device-independent pixels, so on a scaled
            // display a 2560x720 Edge reports e.g. 1707x480 and the isEdge match (and
            // the resolution shown to the user) would be wrong. Multiplying by the
            // device pixel ratio recovers the real panel resolution.
            const qreal dpr = s->devicePixelRatio();
            const int nativeW = qRound(s->size().width() * dpr);
            const int nativeH = qRound(s->size().height() * dpr);
            arr.append(QJsonObject{
                {"name", s->name()},
                {"model", s->model()},
                {"manufacturer", s->manufacturer()},
                {"serial", s->serialNumber()},
                {"width", nativeW},
                {"height", nativeH},
                {"primary", s == primary},
                {"isEdge", (nativeW == 2560 && nativeH == 720)
                            || (nativeW == 720 && nativeH == 2560)
                            || s->model().contains("XENEON", Qt::CaseInsensitive)}
            });
        }
        return QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact));
    }
    Q_INVOKABLE QString targetConnector() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_get_target_connector(m_config)); return s.qstring();
    }
    Q_INVOKABLE QString targetModel() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_get_target_model(m_config)); return s.qstring();
    }
    Q_INVOKABLE bool setTargetDisplay(const QString& connector, const QString& model) {
        if (!m_config) return false;
        xeneon_config_set_target_connector(m_config, connector.toUtf8().constData());
        xeneon_config_set_target_model(m_config, model.toUtf8().constData());
        markSelfWrite();
        return xeneon_config_save(m_config) == 0;
    }
    Q_INVOKABLE bool setAutostart(bool enabled) {
        if (!m_config) return false;
        xeneon_config_set_autostart(m_config, enabled ? 1 : 0);
        // Install/remove the XDG entry AND persist the flag — both must succeed for
        // the switch to be honest. Report the combined result.
        bool fileOk = applyAutostart(enabled);
        markSelfWrite();
        bool saveOk = xeneon_config_save(m_config) == 0;
        if (!fileOk) qWarning() << "Manager: autostart .desktop write failed";
        return fileOk && saveOk;
    }
    // Effective autostart state = the XDG autostart entry actually exists.
    Q_INVOKABLE bool isAutostart() const {
        return QFile::exists(autostartPath());
    }

    // ── Images ──
    Q_INVOKABLE QString imagesDir() const {
        XeneonString cd(xeneon_config_dir());
        QString dir = cd.qstring() + "/images";
        QDir().mkpath(dir);
        return dir;
    }
    Q_INVOKABLE QStringList listImages() const {
        QDir d(imagesDir());
        return d.entryList({"*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp"},
                           QDir::Files, QDir::Time);
    }
    // Copy an image into the hub's images dir, keeping a unique name (never
    // silently overwrite an existing image with a colliding basename).
    Q_INVOKABLE QString importImage(const QString& fileUrl) {
        QString src = fileUrl;
        if (src.startsWith("file:")) src = QUrl(src).toLocalFile();
        QFileInfo fi(src);
        if (!fi.exists() || !fi.isReadable()) { qWarning() << "importImage: unreadable" << src; return QString(); }
        const QString dir = imagesDir();
        const QString base = fi.completeBaseName();
        const QString ext = fi.suffix();
        QString name = fi.fileName();
        QString dst = dir + "/" + name;
        for (int n = 1; QFile::exists(dst); ++n) {
            name = base + "-" + QString::number(n) + (ext.isEmpty() ? QString() : "." + ext);
            dst = dir + "/" + name;
        }
        if (!QFile::copy(src, dst)) { qWarning() << "importImage: copy failed" << src << "→" << dst; return QString(); }
        emit imagesChanged();
        return name;
    }
    Q_INVOKABLE bool deleteImage(const QString& name) {
        // Sanitize: collapse to a bare filename so a crafted name (e.g.
        // "../../.config/foo") can't traverse outside the images dir, then verify
        // the resolved path really stays within it before removing anything.
        const QString base = QFileInfo(name).fileName();
        if (base.isEmpty() || base == "." || base == "..") return false;
        const QString dirPath = QDir::cleanPath(QDir(imagesDir()).absolutePath());
        const QString target = QDir::cleanPath(dirPath + "/" + base);
        if (target != dirPath && !target.startsWith(dirPath + "/")) return false;
        bool ok = QFile::remove(target);
        if (ok) emit imagesChanged();
        return ok;
    }
    // Properly percent-encoded file:// URL for an image in the hub's images dir.
    // Building the URL here via QUrl ensures paths containing spaces or '#' survive
    // — naive "file://" + path string concatenation (as done in the QML) produces a
    // malformed URL that fails to load for those characters.
    Q_INVOKABLE QString imageUrl(const QString& name) const {
        const QString base = QFileInfo(name).fileName();
        if (base.isEmpty()) return QString();
        return QUrl::fromLocalFile(imagesDir() + "/" + base).toString();
    }

signals:
    void hubConnectedChanged();
    void imagesChanged();
    void screensChanged();
    void configChanged();   // config reloaded (from the hub or disk) → QML re-reads

private slots:
    void onSocketReadyRead() {
        m_rxBuf += m_sock->readAll();
        int nl;
        while ((nl = m_rxBuf.indexOf('\n')) >= 0) {
            const QByteArray line = m_rxBuf.left(nl);
            m_rxBuf.remove(0, nl + 1);
            const QJsonObject o = QJsonDocument::fromJson(line).object();
            const QString type = o.value("type").toString();
            if (type == "uiState") {
                const QString st = o.value("state").toString();
                // ── Reconnect reconciliation ──
                // On the first pull after reconnecting, decide the fate of any edit
                // buffered while the socket was down BEFORE adopting or pushing.
                // If the hub's state changed while we were offline (a device-side
                // edit), the hub is authoritative and the stale buffered push is
                // dropped; otherwise the device didn't touch it and our offline edit
                // is applied. This pull → reconcile → push order is what prevents
                // clobbering device-side changes.
                if (m_pendingPushAwaitingHub) {
                    m_pendingPushAwaitingHub = false;
                    const bool hubChanged = !st.isEmpty() && !m_lastHubState.isEmpty()
                                            && st != m_lastHubState;
                    if (hubChanged) {
                        m_pendingPush.clear();     // hub is newer — drop the offline edit
                    } else if (!m_pendingPush.isEmpty()) {
                        const QString edit = m_pendingPush;
                        m_pendingPush.clear();
                        pushLive(edit);            // hub unchanged — apply our edit
                    }
                    if (!st.isEmpty()) m_lastHubState = st;
                }
                // Ignore pulled state briefly after we push, so a reply that
                // predates the hub applying our edit can't revert it.
                if (QDateTime::currentMSecsSinceEpoch() < m_suppressAdoptUntilMs)
                    continue;
                if (!st.isEmpty()) m_lastHubState = st;   // track the hub's live state
                if (!st.isEmpty() && m_config) {
                    // This IS the hub's live state — adopt it WITHOUT re-saving, and
                    // only tell QML to reload when it actually differs (so the gentle
                    // periodic pull doesn't churn the UI when nothing changed).
                    XeneonString cur(xeneon_config_get_ui_state(m_config));
                    if (cur.qstring() != st) {
                        xeneon_config_set_ui_state(m_config, st.toUtf8().constData());
                        emit configChanged();
                    }
                }
            } else if (type == "error") {
                qWarning() << "Manager: hub rejected update:" << o.value("message").toString();
            }
        }
    }

private:
    static QString autostartPath() {
        return QDir::homePath() + "/.config/autostart/xeneon-edge-hub.desktop";
    }
    // Locate the hub executable: prefer the one shipped next to this Manager, else
    // rely on PATH (installed system-wide). Returns an absolute path when found.
    static QString hubBinaryPath() {
        const QString local = QCoreApplication::applicationDirPath() + "/xeneon-edge-hub";
        if (QFile::exists(local)) return local;
        return QStringLiteral("xeneon-edge-hub");   // resolved via PATH by QProcess
    }
    void markSelfWrite() { m_ignoreWatchUntilMs = QDateTime::currentMSecsSinceEpoch() + 900; }
    void tryConnectHub() {
        if (m_sock->state() == QLocalSocket::UnconnectedState)
            m_sock->connectToServer(QStringLiteral("xeneon-edge-hub-ctl"));
    }
    void writeMsg(const QJsonObject& o) {
        m_sock->write(QJsonDocument(o).toJson(QJsonDocument::Compact));
        m_sock->write("\n");
        m_sock->flush();
    }
    void pushLive(const QString& uiStateJson) {
        m_suppressAdoptUntilMs = QDateTime::currentMSecsSinceEpoch() + 1500;
        if (m_sock->state() == QLocalSocket::ConnectedState) {
            writeMsg(QJsonObject{{"type", "setUiState"}, {"state", uiStateJson}});
        } else {
            // connectToServer is async — buffer and flush on the `connected` signal
            // so the edit is never silently lost (was the "first save dropped" bug).
            m_pendingPush = uiStateJson;
            tryConnectHub();
        }
    }
    void reloadConfig() {
        ConfigHandle* fresh = xeneon_config_load();
        if (!fresh) return;
        if (m_config) xeneon_config_free(m_config);
        m_config = fresh;
        emit configChanged();
    }
    bool applyAutostart(bool enabled) {
        const QString path = autostartPath();
        if (!enabled) {
            // Removing a non-existent entry is already "off" (success); otherwise
            // report whether the removal actually succeeded rather than lying true.
            if (!QFile::exists(path)) return true;
            return QFile::remove(path);
        }
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) return false;
        const QString exec = hubBinaryPath();   // absolute when shipped locally, else PATH
        QTextStream ts(&f);
        ts << "[Desktop Entry]\nType=Application\nName=Xeneon Edge Hub\n"
           << "Exec=" << exec << "\nX-GNOME-Autostart-enabled=true\n";
        return true;
    }

    ConfigHandle* m_config = nullptr;
    QLocalSocket* m_sock = nullptr;
    QFileSystemWatcher* m_watcher = nullptr;
    QString m_configPath;
    QString m_pendingPush;          // edit buffered while the socket was down
    QString m_lastHubState;         // last UI state we know the hub held (for reconcile)
    QByteArray m_rxBuf;
    qint64 m_ignoreWatchUntilMs = 0;
    qint64 m_suppressAdoptUntilMs = 0;
    bool m_hubConnected = false;
    bool m_pendingPushAwaitingHub = false;  // reconcile buffered push on next pull
};

int main(int argc, char* argv[]) {
    xeneon_logging_init("info");
    QGuiApplication app(argc, argv);
    app.setApplicationName("Xeneon Edge Manager");
    app.setApplicationVersion("0.1.0");
    app.setOrganizationName("xeneon-edge-hub");

    // Fusion style so Switch/Button/Slider render properly on the desktop.
    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    // Declare the backend BEFORE the engine so it outlives it (locals destroy in
    // reverse order; the engine holds context-property references to the backend).
    ManagerBackend backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("configBridge", &backend);
    engine.rootContext()->setContextProperty("backend", &backend);

    engine.load(QUrl(QStringLiteral("qrc:/manager/Manager.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "Manager: failed to load QML";
        return 1;
    }

    // Doc/review capture: XENEON_GRAB=<path> renders the window to a PNG and quits.
    const QString grabPath = qEnvironmentVariable("XENEON_GRAB");
    if (!grabPath.isEmpty()) {
        QObject* root = engine.rootObjects().first();
        QTimer::singleShot(1800, [root, grabPath]() {
            auto* win = qobject_cast<QQuickWindow*>(root);
            if (win) {
                const QImage img = win->grabWindow();
                if (!img.isNull() && img.save(grabPath))
                    qInfo() << "Manager: saved grab to" << grabPath;
                else
                    qWarning() << "Manager: grab failed";
            } else {
                qWarning() << "Manager: grab skipped (root is not a window)";
            }
            QCoreApplication::quit();   // always quit so a headless run never hangs
        });
    }

    return app.exec();
}

#include "main.moc"
