// Xeneon Edge Manager — a standalone companion desktop app to manage the Edge
// hub: build/reorder the widget layout, tune appearance, upload images, and set
// display/startup options. It edits the SAME config the hub reads (via the Rust
// core) and, when the hub is running, pushes changes live over the hub's local
// control socket. Works whether or not the hub is running.

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
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QTextStream>
#include <QTimer>
#include <QImage>
#include <QQuickWindow>
#include <QQuickStyle>
#include <QLocalSocket>

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
// it unchanged, plus display/image/startup operations and the live push socket.
class ManagerBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hubConnected READ hubConnected NOTIFY hubConnectedChanged)
public:
    explicit ManagerBackend(QObject* parent = nullptr) : QObject(parent) {
        m_config = xeneon_config_load();
        if (!m_config) {
            qCritical() << "Manager: failed to load config";
        }
        m_sock = new QLocalSocket(this);
        connect(m_sock, &QLocalSocket::connected, this, [this] {
            m_hubConnected = true; emit hubConnectedChanged();
        });
        connect(m_sock, &QLocalSocket::disconnected, this, [this] {
            m_hubConnected = false; emit hubConnectedChanged();
        });
        connect(m_sock, &QLocalSocket::errorOccurred, this, [this](QLocalSocket::LocalSocketError) {
            m_hubConnected = false; emit hubConnectedChanged();
        });
        tryConnectHub();
    }
    ~ManagerBackend() override {
        if (m_config) xeneon_config_free(m_config);
    }

    bool hubConnected() const { return m_hubConnected; }

    // Dev/doc affordance: if XENEON_GRAB=<path> is set, the QML grabs the window
    // to that PNG and quits (used to capture the UI headlessly for review).
    Q_INVOKABLE QString grabPath() const { return qEnvironmentVariable("XENEON_GRAB"); }
    Q_INVOKABLE int startTab() const { return qEnvironmentVariable("XENEON_TAB", "0").toInt(); }
    Q_INVOKABLE QString autoConfig() const { return qEnvironmentVariable("XENEON_CFG"); }

    // Live system metrics (same source + JSON shape the hub uses), so the clone
    // preview shows real data.
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
        bool ok = xeneon_config_save(m_config) == 0;
        if (!ok) qWarning() << "Manager: failed to persist UI state";
        pushLive(json);   // live-update a running hub, if connected
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

    // ── Display / startup settings (main config; apply on hub restart) ──
    Q_INVOKABLE QString screensJson() const {
        QJsonArray arr;
        const auto screens = QGuiApplication::screens();
        QScreen* primary = QGuiApplication::primaryScreen();
        for (auto* s : screens) {
            arr.append(QJsonObject{
                {"name", s->name()},
                {"model", s->model()},
                {"manufacturer", s->manufacturer()},
                {"serial", s->serialNumber()},
                {"width", s->size().width()},
                {"height", s->size().height()},
                {"primary", s == primary},
                {"isEdge", (s->size().width() == 2560 && s->size().height() == 720)
                            || (s->size().width() == 720 && s->size().height() == 2560)
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
        return xeneon_config_save(m_config) == 0;
    }
    Q_INVOKABLE bool setAutostart(bool enabled) {
        if (!m_config) return false;
        xeneon_config_set_autostart(m_config, enabled ? 1 : 0);
        // Also install/remove the XDG autostart entry so the choice takes effect.
        applyAutostart(enabled);
        return xeneon_config_save(m_config) == 0;
    }
    // Effective autostart state = whether the XDG autostart entry is installed,
    // so the Manager's switch reflects reality on launch.
    Q_INVOKABLE bool isAutostart() const {
        return QFile::exists(QDir::homePath() + "/.config/autostart/xeneon-edge-hub.desktop");
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
    // Copy an image (from a file:// URL or path) into the hub's images dir.
    Q_INVOKABLE QString importImage(const QString& fileUrl) {
        QString src = fileUrl;
        if (src.startsWith("file:")) src = QUrl(src).toLocalFile();
        QFileInfo fi(src);
        if (!fi.exists() || !fi.isReadable()) { qWarning() << "importImage: unreadable" << src; return QString(); }
        QString dst = imagesDir() + "/" + fi.fileName();
        if (QFile::exists(dst)) QFile::remove(dst);
        if (!QFile::copy(src, dst)) { qWarning() << "importImage: copy failed" << src << "→" << dst; return QString(); }
        emit imagesChanged();
        return fi.fileName();
    }
    Q_INVOKABLE bool deleteImage(const QString& name) {
        bool ok = QFile::remove(imagesDir() + "/" + name);
        if (ok) emit imagesChanged();
        return ok;
    }

signals:
    void hubConnectedChanged();
    void imagesChanged();

private:
    void tryConnectHub() {
        if (m_sock->state() == QLocalSocket::UnconnectedState)
            m_sock->connectToServer(QStringLiteral("xeneon-edge-hub-ctl"));
    }
    void pushLive(const QString& uiStateJson) {
        if (m_sock->state() != QLocalSocket::ConnectedState) { tryConnectHub(); return; }
        QJsonObject msg{{"type", "setUiState"}, {"state", uiStateJson}};
        m_sock->write(QJsonDocument(msg).toJson(QJsonDocument::Compact));
        m_sock->write("\n");
        m_sock->flush();
    }
    void applyAutostart(bool enabled) {
        const QString dir = QDir::homePath() + "/.config/autostart";
        const QString path = dir + "/xeneon-edge-hub.desktop";
        if (!enabled) { QFile::remove(path); return; }
        QDir().mkpath(dir);
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) return;
        // Prefer the hub binary next to this Manager (both install to the same
        // bin dir); fall back to a bare name resolved via PATH.
        QString exec = QCoreApplication::applicationDirPath() + "/xeneon-edge-hub";
        if (!QFile::exists(exec)) exec = QStringLiteral("xeneon-edge-hub");
        QTextStream ts(&f);
        ts << "[Desktop Entry]\nType=Application\nName=Xeneon Edge Hub\n"
           << "Exec=" << exec << "\nX-GNOME-Autostart-enabled=true\n";
    }

    ConfigHandle* m_config = nullptr;
    QLocalSocket* m_sock = nullptr;
    bool m_hubConnected = false;
};

int main(int argc, char* argv[]) {
    xeneon_logging_init("info");
    QGuiApplication app(argc, argv);
    app.setApplicationName("Xeneon Edge Manager");
    app.setApplicationVersion("0.1.0");
    app.setOrganizationName("xeneon-edge-hub");

    // Use the Fusion style so Switch/Button/Slider/ComboBox render properly on the
    // desktop (the default Basic style makes switches look like broken checkboxes).
    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    // Declare the backend BEFORE the engine so it outlives it: locals are
    // destroyed in reverse order, and the engine holds context-property
    // references to the backend that must not dangle during QML teardown.
    ManagerBackend backend;
    QQmlApplicationEngine engine;
    // DashboardStore.qml resolves the shared persistence API under this name.
    engine.rootContext()->setContextProperty("configBridge", &backend);
    engine.rootContext()->setContextProperty("backend", &backend);

    engine.load(QUrl(QStringLiteral("qrc:/manager/Manager.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "Manager: failed to load QML";
        return 1;
    }

    // Doc/review capture: XENEON_GRAB=<path> renders the window to a PNG and
    // quits. Uses QQuickWindow::grabWindow() (reliable, works offscreen too).
    const QString grabPath = qEnvironmentVariable("XENEON_GRAB");
    if (!grabPath.isEmpty()) {
        auto* win = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
        if (win) {
            QTimer::singleShot(1800, [win, grabPath]() {
                const QImage img = win->grabWindow();
                if (!img.isNull() && img.save(grabPath))
                    qInfo() << "Manager: saved grab to" << grabPath;
                else
                    qWarning() << "Manager: grab failed";
                QCoreApplication::quit();
            });
        }
    }

    return app.exec();
}

#include "main.moc"
