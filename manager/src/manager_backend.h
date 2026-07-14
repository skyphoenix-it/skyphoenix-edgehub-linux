#pragma once

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QObject>
#include <QProcess>
#include <QScreen>
#include <QString>
#include <QStringList>
#include <QTextStream>
#include <QTimer>
#include <QUrl>

#include <functional>

#include "path_sanitize.h"
#include "reconcile.h"
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
            qCritical() << "Manager: failed to load config";   // GCOVR_EXCL_LINE (defensive; core never fails to load a default config)

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
            if (m_nowMs() < m_ignoreWatchUntilMs) return;
            if (m_hubConnected) return;
            reloadConfig();                   // pick up the just-created config  // GCOVR_EXCL_LINE (offline external-change reload = inotify/timing glue)
        });
        connect(m_watcher, &QFileSystemWatcher::fileChanged, this, [this] {
            // Atomic saves rename over the file and drop the watch — re-add it.
            QTimer::singleShot(60, this, [this] {
                if (!m_watcher->files().contains(m_configPath) && QFile::exists(m_configPath))
                    m_watcher->addPath(m_configPath);
                if (m_nowMs() < m_ignoreWatchUntilMs) return; // our own write
                if (m_hubConnected) return;   // IPC keeps us in sync when connected  // GCOVR_EXCL_LINE
                reloadConfig();                                                        // GCOVR_EXCL_LINE (offline external-change reload = inotify/timing glue)
            });
        });

        // Live display hotplug → Display tab refresh.
        connect(qApp, &QGuiApplication::screenAdded, this, [this](QScreen*) { emit screensChanged(); });
        connect(qApp, &QGuiApplication::screenRemoved, this, [this](QScreen*) { emit screensChanged(); });

        tryConnectHub();
    }
    ~ManagerBackend() override {                    // GCOVR_EXCL_START (dtor teardown; brace-only lines gcov mis-attributes)
        if (m_config) xeneon_config_free(m_config);
    }                                               // GCOVR_EXCL_STOP

    // Inject a deterministic clock (milliseconds-since-epoch) so the suppression
    // windows are testable with zero real waiting. Defaults to the wall clock.
    void setClockForTest(std::function<qint64()> nowMs) { m_nowMs = std::move(nowMs); }

    // Test seam: expose the pending RX buffer size so a flood test can assert the
    // cap holds without reaching into private state. Not used in production.
    int rxBufferSizeForTest() const { return m_rxBuf.size(); }

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
        // GCOVR_EXCL_START (QProcess-launch glue: spawns the real hub binary + timed
        // reconnect nudges; the "already reachable" probe path above IS tested).
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
        // GCOVR_EXCL_STOP
    }

    // Ask a running hub to quit cleanly over the control socket. Returns false if
    // no hub is reachable to stop.
    Q_INVOKABLE bool stopHub() {
        if (m_sock->state() != QLocalSocket::ConnectedState) return false;
        writeMsg(QJsonObject{{"type", "shutdown"}});
        m_sock->flush();
        return true;
    }

    // Dev/doc affordances (headless capture) — compiled in only under
    // XENEON_QA_HOOKS; return inert defaults in production packages.
#ifdef XENEON_QA_HOOKS
    Q_INVOKABLE QString grabPath() const { return qEnvironmentVariable("XENEON_GRAB"); }
    Q_INVOKABLE int startTab() const { return qEnvironmentVariable("XENEON_TAB", "0").toInt(); }
    Q_INVOKABLE QString autoConfig() const { return qEnvironmentVariable("XENEON_CFG"); }
#else
    Q_INVOKABLE QString grabPath() const { return QString(); }
    Q_INVOKABLE int startTab() const { return 0; }
    Q_INVOKABLE QString autoConfig() const { return QString(); }
#endif

    // Build version, injected at compile time via -DXENEON_VERSION (git describe;
    // or the pkgver for packaged builds). Falls back to "dev" for syntax-only builds.
    Q_INVOKABLE QString appVersion() const {
#ifdef XENEON_VERSION
        return QStringLiteral(XENEON_VERSION);
#else
        return QStringLiteral("dev");
#endif
    }

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
        // Keep our in-memory copy current either way so uiState() reflects the edit.
        xeneon_config_set_ui_state(m_config, json.toUtf8().constData());
        // Single-writer: when the hub is connected it OWNS config.toml. Push the edit
        // over the control socket and let the hub persist it — do NOT also atomically
        // rename the file here, which would race the hub's writer (the two-writer save
        // race). When offline the Manager is the sole writer and persists directly, so
        // offline edits are never lost.
        if (m_hubConnected) {
            pushLive(json);   // hub applies + saves
            return true;
        }
        markSelfWrite();
        bool ok = xeneon_config_save(m_config) == 0;
        if (!ok) {
            qWarning() << "Manager: failed to persist UI state";
            emit saveError(QStringLiteral("Failed to save the layout"));
        }
        pushLive(json);   // buffers the edit if a hub appears later
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
        // GCOVR_EXCL_START (live-QScreen enumeration: requires real, non-offscreen
        // displays; tests run offscreen and take the "[]" branch above).
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
        // GCOVR_EXCL_STOP
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
        // Callers previously ignored this bool; a failed save was silent. Log + signal
        // so the failure is honest (and the return value stays truthful).
        const bool ok = xeneon_config_save(m_config) == 0;
        if (!ok) {
            qWarning() << "Manager: failed to persist target display";
            emit saveError(QStringLiteral("Failed to save the display target"));
        }
        return ok;
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
        if (!saveOk) qWarning() << "Manager: failed to persist autostart flag";
        if (!(fileOk && saveOk))
            emit saveError(QStringLiteral("Failed to update autostart"));
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
        // Guard the synchronous copy below: stat the source and reject anything over
        // the cap so a huge or slow network-mounted file can't freeze the GUI thread.
        if (fi.size() > kMaxImportBytes) {
            qWarning() << "importImage: rejecting oversized file" << src << fi.size()
                       << "bytes (cap" << kMaxImportBytes << ")";
            return QString();
        }
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
        // Sanitize: collapse to a bare filename inside the images dir so a crafted
        // name (e.g. "../../.config/foo") can't traverse outside it, then verify the
        // resolved path really stays within it before removing anything.
        const std::optional<QString> target = sanitizeImageName(name, imagesDir());
        if (!target) return false;
        bool ok = QFile::remove(*target);
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
    // Emitted when a persist/apply the user asked for did NOT succeed, so the QML
    // side can surface an honest error (a toast) instead of a silent no-op. The
    // C++ return values are already truthful; this makes the failure observable.
    void saveError(const QString& what);

private slots:
    void onSocketReadyRead() {
        m_rxBuf += m_sock->readAll();
        int nl;
        while ((nl = m_rxBuf.indexOf('\n')) >= 0) {
            const QByteArray line = m_rxBuf.left(nl);
            m_rxBuf.remove(0, nl + 1);
            if (line.trimmed().isEmpty()) continue;   // keep-alive / blank framing
            // Parse defensively: a malformed or non-object line is LOGGED and skipped
            // (was silently swallowed). The newline framing already consumed the bad
            // line, so a single garbage message can't desync the rest of the stream.
            QJsonParseError perr{};
            const QJsonDocument doc = QJsonDocument::fromJson(line, &perr);
            if (doc.isNull() || !doc.isObject()) {
                qWarning() << "Manager: ignoring malformed IPC line:"
                           << perr.errorString() << "(" << line.left(120) << ")";
                continue;
            }
            const QJsonObject o = doc.object();
            const QString type = o.value("type").toString();
            if (type == "uiState") {
                const QString st = o.value("state").toString();
                // ── Reconnect reconciliation ──
                // On the first pull after reconnecting, decide the fate of any edit
                // buffered while the socket was down BEFORE adopting or pushing.
                // If the hub's state changed while we were offline (a device-side
                // edit) — OR we have no prior baseline yet the hub reports a non-empty
                // state — the hub is authoritative and the stale buffered push is
                // dropped; otherwise the device didn't touch it and our offline edit
                // is applied. This pull → reconcile → push order is what prevents
                // clobbering device-side changes.
                if (m_pendingPushAwaitingHub) {
                    m_pendingPushAwaitingHub = false;
                    const ReconcileAction a = reconcileOnPull(
                        true, !m_pendingPush.isEmpty(), st, m_lastHubState,
                        m_nowMs() < m_suppressAdoptUntilMs);
                    if (a == ReconcileAction::DropEdit) {
                        m_pendingPush.clear();     // hub is newer — drop the offline edit
                    } else if (a == ReconcileAction::KeepAndPushEdit) {
                        const QString edit = m_pendingPush;
                        m_pendingPush.clear();
                        pushLive(edit);            // hub unchanged — apply our edit
                    }
                    if (!st.isEmpty()) m_lastHubState = st;
                }
                // Ignore pulled state briefly after we push, so a reply that
                // predates the hub applying our edit can't revert it.
                if (m_nowMs() < m_suppressAdoptUntilMs)
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
                qWarning() << "Manager: hub rejected update:" << o.value("message").toString();  // GCOVR_EXCL_LINE (hub-side reject log; no observable client effect)
            }
        }
        // Cap an unterminated flood: whatever remains is a partial line with no
        // newline. A stuck or hostile peer that never sends '\n' would otherwise grow
        // m_rxBuf without bound (OOM). Drop the partial buffer past the cap and resync
        // on the next newline.
        if (m_rxBuf.size() > kMaxRxBufBytes) {
            qWarning() << "Manager: RX buffer exceeded" << kMaxRxBufBytes
                       << "bytes without a newline — dropping" << m_rxBuf.size()
                       << "buffered bytes and resyncing";
            m_rxBuf.clear();
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
    void markSelfWrite() { m_ignoreWatchUntilMs = m_nowMs() + 900; }
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
        m_suppressAdoptUntilMs = m_nowMs() + 1500;
        if (m_sock->state() == QLocalSocket::ConnectedState) {
            // A live edit on a CONNECTED socket SUPERSEDES any edit that was buffered
            // while offline: a newer live edit always wins over an older buffered one.
            // Clear the pending offline push AND its awaiting-reconcile flag so that a
            // getUiState reply still in flight from the reconnect can't resurrect and
            // re-push the OLDER buffered edit over this newer one — the stale-repush
            // edit-loss heisenbug (edit A buffered, connect arms reconcile, live edit B
            // pushes here, then the reply reconciles with A and re-pushes it, losing B).
            m_pendingPush.clear();
            m_pendingPushAwaitingHub = false;
            writeMsg(QJsonObject{{"type", "setUiState"}, {"state", uiStateJson}});
            // The hub will apply + persist this, so its authoritative state is now
            // uiStateJson. Record it as our baseline: otherwise, if the hub restarts
            // shortly after (before the periodic pull refreshes the baseline) and we
            // reconnect with a NEWER offline edit buffered, reconcileOnPull would see
            // the hub reporting THIS push against a stale older baseline, judge it a
            // foreign device-side change, and DROP the newer offline edit.
            m_lastHubState = uiStateJson;
        } else {
            // connectToServer is async — buffer and flush on the `connected` signal
            // so the edit is never silently lost (was the "first save dropped" bug).
            m_pendingPush = uiStateJson;
            tryConnectHub();
        }
    }
    // GCOVR_EXCL_START (only reached from the offline file-watcher reload path above,
    // which is inotify/timing-dependent FS glue).
    void reloadConfig() {
        ConfigHandle* fresh = xeneon_config_load();
        if (!fresh) return;
        if (m_config) xeneon_config_free(m_config);
        m_config = fresh;
        emit configChanged();
    }
    // GCOVR_EXCL_STOP
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

    // Drop an unterminated RX flood past ~1 MB (see onSocketReadyRead).
    static constexpr int kMaxRxBufBytes = 1 << 20;              // 1 MiB
    // Reject import sources larger than this so a huge/network file can't freeze
    // the GUI thread inside the synchronous QFile::copy (see importImage).
    static constexpr qint64 kMaxImportBytes = 25LL << 20;       // 25 MiB

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
    // Injectable clock (ms since epoch); defaults to the wall clock. Overridable in
    // tests via setClockForTest so the suppression windows need no real waiting.
    std::function<qint64()> m_nowMs = [] { return QDateTime::currentMSecsSinceEpoch(); };
};
