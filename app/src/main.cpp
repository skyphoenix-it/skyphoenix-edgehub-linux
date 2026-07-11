#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QScreen>
#include <QWindow>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <QCommandLineParser>
#include <QObject>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <csignal>
#include <initializer_list>
#include <unistd.h>
#include <QSocketNotifier>

#include "xeneon_core.h"
#include "mpris_bridge.h"

// --- RAII string wrapper ---

class XeneonString {
    char* ptr;
public:
    explicit XeneonString(char* p) : ptr(p) {}
    ~XeneonString() { if (ptr) xeneon_string_free(ptr); }
    XeneonString(const XeneonString&) = delete;
    XeneonString& operator=(const XeneonString&) = delete;
    const char* c_str() const { return ptr; }
    QString qstring() const { return ptr ? QString::fromUtf8(ptr) : QString(); }
    bool isNull() const { return ptr == nullptr; }
    operator bool() const { return ptr != nullptr; }
};

// --- Global handle for signal handler access ---
static ConfigHandle* g_config = nullptr;

// --- Qt → Rust log bridge ---

static XeneonLogLevel qtMsgTypeToXeneon(QtMsgType type) {
    switch (type) {
    case QtDebugMsg:    return XENEON_LOG_DEBUG;
    case QtInfoMsg:     return XENEON_LOG_INFO;
    case QtWarningMsg:  return XENEON_LOG_WARN;
    case QtCriticalMsg: return XENEON_LOG_ERROR;
    case QtFatalMsg:    return XENEON_LOG_ERROR;
    }
    return XENEON_LOG_INFO;
}

static void qtLogBridge(QtMsgType type, const QMessageLogContext& ctx, const QString& msg) {
    const char* file = ctx.file ? ctx.file : "qml";
    int line = ctx.line ? ctx.line : 0;
    xeneon_logging_log(qtMsgTypeToXeneon(type), file, line, msg.toUtf8().constData());
}

// --- Metrics helper ---

static QJsonObject metricsToJson() {
    MetricsHandle* m = xeneon_metrics_collect();
    if (!m) return QJsonObject();
    XeneonString json(xeneon_metrics_to_json(m));
    xeneon_metrics_free(m);
    if (!json) return QJsonObject();
    QJsonDocument doc = QJsonDocument::fromJson(QByteArray(json.c_str()));
    return doc.object();
}

// --- Display helper ---

static QJsonObject screenToJson(QScreen* screen) {
    QJsonObject obj;
    obj["name"] = screen->name();
    obj["model"] = screen->model();
    obj["manufacturer"] = screen->manufacturer();
    obj["serialNumber"] = screen->serialNumber();
    obj["geometry"] = QJsonObject{
        {"x", screen->geometry().x()},
        {"y", screen->geometry().y()},
        {"width", screen->geometry().width()},
        {"height", screen->geometry().height()}
    };
    obj["availableGeometry"] = QJsonObject{
        {"x", screen->availableGeometry().x()},
        {"y", screen->availableGeometry().y()},
        {"width", screen->availableGeometry().width()},
        {"height", screen->availableGeometry().height()}
    };
    obj["logicalDpi"] = screen->logicalDotsPerInch();
    obj["physicalDpi"] = screen->physicalDotsPerInch();
    obj["devicePixelRatio"] = screen->devicePixelRatio();
    obj["refreshRate"] = screen->refreshRate();
    obj["physicalSize"] = QJsonObject{
        {"width", screen->physicalSize().width()},
        {"height", screen->physicalSize().height()}
    };
    obj["orientation"] = screen->orientation() == Qt::LandscapeOrientation ? "landscape"
                     : (screen->orientation() == Qt::PortraitOrientation ? "portrait"
                     : (screen->orientation() == Qt::InvertedLandscapeOrientation ? "inverted_landscape"
                     : "inverted_portrait"));
    obj["isPrimary"] = (screen == QGuiApplication::primaryScreen());
    obj["size"] = QJsonObject{
        {"width", screen->size().width()},
        {"height", screen->size().height()}
    };

    QByteArray identityData;
    identityData.append(screen->name().toUtf8());
    identityData.append(screen->model().toUtf8());
    identityData.append(screen->manufacturer().toUtf8());
    identityData.append(screen->serialNumber().toUtf8());
    XeneonString hash(xeneon_display_compute_edid_hash(
        reinterpret_cast<const uint8_t*>(identityData.constData()),
        identityData.size()));
    obj["edidHash"] = hash.qstring();

    obj["likelyXeneonEdge"] = (screen->model().contains("XENEON", Qt::CaseInsensitive)
        || screen->manufacturer().contains("Corsair", Qt::CaseInsensitive)
        || (screen->size().width() == 2560 && screen->size().height() == 720)
        || (screen->size().width() == 720 && screen->size().height() == 2560));

    return obj;
}

// --- Signal handler ---
// Uses a self-pipe to safely forward POSIX signals to the Qt event loop.
// Calling QCoreApplication::quit() or doing I/O from a signal handler
// is NOT async-signal-safe and can deadlock or corrupt state.

static int sigFd[2] = {-1, -1};

static void signalHandler(int sig) {
    // ONLY async-signal-safe operations: write the signal number to the pipe
    char c = static_cast<char>(sig);
    ::write(sigFd[1], &c, 1);
}

// --- Find target display ---

static QScreen* findTargetScreen(ConfigHandle* config) {
    XeneonString targetHash(xeneon_config_get_target_edid_hash(config));
    XeneonString targetModel(xeneon_config_get_target_model(config));
    XeneonString targetConnector(xeneon_config_get_target_connector(config));

    auto screens = QGuiApplication::screens();

    qInfo() << "Finding target screen among" << screens.size() << "screens"
            << "(hash:" << (targetHash ? targetHash.c_str() : "none")
            << "model:" << (targetModel ? targetModel.c_str() : "none")
            << "connector:" << (targetConnector ? targetConnector.c_str() : "none") << ")";

    // Try EDID hash match first
    if (targetHash) {
        for (auto* s : screens) {
            QByteArray id;
            id.append(s->name().toUtf8());
            id.append(s->model().toUtf8());
            id.append(s->manufacturer().toUtf8());
            id.append(s->serialNumber().toUtf8());
            XeneonString hash(xeneon_display_compute_edid_hash(
                reinterpret_cast<const uint8_t*>(id.constData()), id.size()));
            if (hash.qstring() == targetHash.qstring()) {
                qInfo() << "Target found by EDID hash:" << s->name();
                return s;
            }
        }
    }

    // Try model name match
    if (targetModel) {
        for (auto* s : screens) {
            if (s->model() == targetModel.qstring()) {
                qInfo() << "Target found by model:" << s->name();
                return s;
            }
        }
    }

    // Try connector match
    if (targetConnector) {
        for (auto* s : screens) {
            if (s->name() == targetConnector.qstring()) {
                qInfo() << "Target found by connector:" << s->name();
                return s;
            }
        }
    }

    // Fallback: find XENEON model substring
    for (auto* s : screens) {
        if (s->model().contains("XENEON", Qt::CaseInsensitive)) {
            qInfo() << "Target found by XENEON model substring:" << s->name();
            return s;
        }
    }

    // Fallback: find Xeneon-typical resolution (2560x720 or 720x2560)
    for (auto* s : screens) {
        int w = s->size().width(), h = s->size().height();
        if ((w == 2560 && h == 720) || (w == 720 && h == 2560)) {
            qInfo() << "Target found by Xeneon-typical resolution:" << s->name()
                    << w << "x" << h;
            return s;
        }
    }

    qWarning() << "No Xeneon Edge detected, falling back to primary screen:"
               << QGuiApplication::primaryScreen()->name();
    return QGuiApplication::primaryScreen();
}

// --- Autostart: install/remove an XDG autostart .desktop entry ---
// Writes ~/.config/autostart/xeneon-edge-hub.desktop pointing at the current
// binary, so "start on login" actually takes effect (previously a no-op).
static bool applyAutostart(bool enabled) {
    const QString dir = QDir::homePath() + "/.config/autostart";
    const QString path = dir + "/xeneon-edge-hub.desktop";
    if (!enabled) {
        QFile::remove(path);
        return true;
    }
    if (!QDir().mkpath(dir))
        return false;
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "Could not write autostart entry:" << path;
        return false;
    }
    QTextStream ts(&f);
    ts << "[Desktop Entry]\n"
       << "Type=Application\n"
       << "Name=Xeneon Edge Linux Hub\n"
       << "Comment=Native Linux widget platform for secondary touchscreen displays\n"
       << "Exec=" << QCoreApplication::applicationFilePath() << "\n"
       << "Icon=xeneon-edge-hub\n"
       << "Categories=Utility;\n"
       << "Terminal=false\n"
       << "X-GNOME-Autostart-enabled=true\n";
    f.close();
    qInfo() << "Autostart entry written:" << path;
    return true;
}

// --- WizardBridge: QObject exposed to QML for first-run persistence ---

class WizardBridge : public QObject {
    Q_OBJECT
public:
    explicit WizardBridge(ConfigHandle* config, QObject* parent = nullptr)
        : QObject(parent), m_config(config) {}

    Q_INVOKABLE bool completeWizard(const QString& edidHash, const QString& connector,
                                     const QString& model, const QString& layout,
                                     const QString& themeMode, const QString& themeAccent,
                                     bool autostart, bool reconnect, bool notifyDisconnect) {
        if (!m_config) return false;

        // Persist display identity
        if (!edidHash.isEmpty())
            xeneon_config_set_target_edid_hash(m_config, edidHash.toUtf8().constData());
        if (!connector.isEmpty())
            xeneon_config_set_target_connector(m_config, connector.toUtf8().constData());
        if (!model.isEmpty())
            xeneon_config_set_target_model(m_config, model.toUtf8().constData());

        // Persist layout choice
        if (!layout.isEmpty())
            xeneon_config_set_starter_layout(m_config, layout.toUtf8().constData());

        // Persist theme
        if (!themeMode.isEmpty())
            xeneon_config_set_theme_mode(m_config, themeMode.toUtf8().constData());
        if (!themeAccent.isEmpty())
            xeneon_config_set_theme_accent(m_config, themeAccent.toUtf8().constData());

        // Persist startup preferences
        xeneon_config_set_autostart(m_config, autostart ? 1 : 0);
        xeneon_config_set_reconnect(m_config, reconnect ? 1 : 0);
        xeneon_config_set_notify_disconnect(m_config, notifyDisconnect ? 1 : 0);

        // Actually install/remove the XDG autostart entry to match the choice.
        applyAutostart(autostart);

        // Mark first-run complete
        xeneon_config_set_first_run_complete(m_config);

        // Save to disk
        int saved = xeneon_config_save(m_config);
        if (saved == 0) {
            qInfo() << "Wizard complete. Target:" << model << "Layout:" << layout
                     << "Theme:" << themeMode << "Autostart:" << autostart;
        } else {
            qWarning() << "Wizard complete but config save failed";
        }
        return saved == 0;
    }

private:
    ConfigHandle* m_config;
};

// --- ConfigBridge: runtime config access for QML (layout persistence, etc.) ---

class ConfigBridge : public QObject {
    Q_OBJECT
public:
    explicit ConfigBridge(ConfigHandle* config, QObject* parent = nullptr)
        : QObject(parent), m_config(config) {}

    // Opaque UI-state JSON (dashboard layout + per-widget settings + appearance).
    Q_INVOKABLE QString uiState() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_get_ui_state(m_config));
        return s.qstring();
    }

    // Persist the UI-state JSON and flush to disk atomically. Returns success.
    Q_INVOKABLE bool saveUiState(const QString& json) {
        if (!m_config) return false;
        xeneon_config_set_ui_state(m_config, json.toUtf8().constData());
        bool ok = xeneon_config_save(m_config) == 0;
        if (!ok) qWarning() << "Failed to persist UI state";
        return ok;
    }

    // Starter layout id chosen during the wizard ("productivity"/"gaming"/…).
    Q_INVOKABLE QString starterLayout() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_get_starter_layout(m_config));
        return s.qstring();
    }

    // Full pretty-printed config JSON (for the Diagnostics → Config tab).
    Q_INVOKABLE QString configJson() const {
        if (!m_config) return QString();
        XeneonString s(xeneon_config_to_json(m_config));
        return s.qstring();
    }

private:
    ConfigHandle* m_config;
};

int main(int argc, char *argv[]) {
    // Initialize Rust core logging FIRST
    xeneon_logging_init("info");

    // Install Qt → Rust log bridge
    qInstallMessageHandler(qtLogBridge);

    QGuiApplication app(argc, argv);
    app.setApplicationName("Xeneon Edge Linux Hub");
    app.setApplicationVersion("0.1.0");
    app.setOrganizationName("xeneon-edge-hub");

    // Self-pipe for signal handling: forward POSIX signals to Qt event loop safely
    if (::pipe(sigFd) == 0) {
        QSocketNotifier* sigNotifier = new QSocketNotifier(sigFd[0], QSocketNotifier::Read, &app);
        QObject::connect(sigNotifier, &QSocketNotifier::activated, [&](int) {
            char c;
            if (::read(sigFd[0], &c, 1) == 1) {
                int sig = static_cast<int>(c);
                qInfo() << "Received signal" << sig << "- shutting down gracefully";
                if (g_config) {
                    xeneon_config_save(g_config);
                }
                QCoreApplication::quit();
            }
        });
        signal(SIGINT, signalHandler);
        signal(SIGTERM, signalHandler);
        signal(SIGHUP, signalHandler);
    } else {
        qWarning() << "Failed to create self-pipe for signal handling";
    }

    // CLI arguments
    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addVersionOption();
    QCommandLineOption resetOpt("reset", "Reset all configuration to defaults");
    QCommandLineOption safeModeOpt("safe-mode", "Start in safe mode (all widgets disabled)");
    QCommandLineOption resetWizardOpt("reset-wizard", "Re-run the first-run wizard");
    QCommandLineOption diagOpt("diagnostics", "Start directly in diagnostics view");
    QCommandLineOption windowedOpt("windowed", "Run in windowed mode instead of borderless fullscreen");
    parser.addOption(resetOpt);
    parser.addOption(safeModeOpt);
    parser.addOption(resetWizardOpt);
    parser.addOption(diagOpt);
    parser.addOption(windowedOpt);
    parser.process(app);

    // Load configuration
    ConfigHandle* config = nullptr;
    if (parser.isSet(resetOpt)) {
        config = xeneon_config_reset();
        qInfo() << "Configuration reset to defaults";
    } else {
        config = xeneon_config_load();
    }
    if (!config) {
        qCritical() << "Failed to load configuration";
        return 1;
    }
    g_config = config;

    int isFirstRun = xeneon_config_is_first_run(config);
    if (parser.isSet(resetWizardOpt)) {
        isFirstRun = 1;
    }

    // Collect display information
    QJsonArray screensArray;
    auto screens = QGuiApplication::screens();
    for (auto* screen : screens) {
        screensArray.append(screenToJson(screen));
    }

    // Find target display for fullscreen placement
    QScreen* targetScreen = findTargetScreen(config);

    // Collect system metrics for initial display
    QJsonObject metricsJson = metricsToJson();

    // Create QML engine
    QQmlApplicationEngine engine;

    // Expose data to QML
    engine.rootContext()->setContextProperty("_isFirstRun", isFirstRun);
    engine.rootContext()->setContextProperty("_screens", QJsonDocument(screensArray).toJson(QJsonDocument::Compact));
    engine.rootContext()->setContextProperty("_metricsJson", QJsonDocument(metricsJson).toJson(QJsonDocument::Compact));
    engine.rootContext()->setContextProperty("_safeMode", parser.isSet(safeModeOpt));
    engine.rootContext()->setContextProperty("_startInDiagnostics", parser.isSet(diagOpt));
    engine.rootContext()->setContextProperty("_windowedMode", parser.isSet(windowedOpt));

    // Config path for diagnostics
    XeneonString configDir(xeneon_config_dir());
    engine.rootContext()->setContextProperty("_configDir", configDir.qstring());

    // Theme mode
    XeneonString themeMode(xeneon_config_get_theme_mode(config));
    engine.rootContext()->setContextProperty("_themeMode", themeMode.qstring());

    // Expose target display info
    XeneonString targetHash(xeneon_config_get_target_edid_hash(config));
    XeneonString targetConnector(xeneon_config_get_target_connector(config));
    XeneonString targetModel(xeneon_config_get_target_model(config));
    engine.rootContext()->setContextProperty("_targetEdidHash", targetHash.qstring());
    engine.rootContext()->setContextProperty("_targetConnector", targetConnector.qstring());
    engine.rootContext()->setContextProperty("_targetModel", targetModel.qstring());

    // Target screen geometry for window placement
    if (targetScreen) {
        engine.rootContext()->setContextProperty("_targetScreenX", targetScreen->geometry().x());
        engine.rootContext()->setContextProperty("_targetScreenY", targetScreen->geometry().y());
        engine.rootContext()->setContextProperty("_targetScreenWidth", targetScreen->geometry().width());
        engine.rootContext()->setContextProperty("_targetScreenHeight", targetScreen->geometry().height());
    }

    // Expose WizardBridge for first-run config persistence
    // Parent to engine so it's cleaned up when the engine is destroyed
    WizardBridge* wizardBridge = new WizardBridge(config, &engine);
    engine.rootContext()->setContextProperty("wizardBridge", wizardBridge);

    // Expose ConfigBridge for runtime layout/state persistence + diagnostics.
    ConfigBridge* configBridge = new ConfigBridge(config, &engine);
    engine.rootContext()->setContextProperty("configBridge", configBridge);

    // Expose the MPRIS media bridge (Now Playing + transport control).
    MprisBridge* mediaBridge = new MprisBridge(&engine);
    engine.rootContext()->setContextProperty("media", mediaBridge);

    // Load main QML
    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "Failed to load QML";
        xeneon_config_free(config);
        return 1;
    }

    // Window placement: QML starts invisible and Windowed (see main.qml).
    // C++ positions it on the target screen FIRST, then shows it.
    // This is critical for Wayland where the compositor controls placement.
    QWindow* mainWindow = qobject_cast<QWindow*>(engine.rootObjects().first());
    if (mainWindow) {
        QRect geo = targetScreen ? targetScreen->geometry()
                                 : QGuiApplication::primaryScreen()->geometry();
        qInfo() << "Placing window on" << (targetScreen ? targetScreen->name() : "primary")
                << "model:" << (targetScreen ? targetScreen->model() : "none")
                << "at" << geo.x() << "," << geo.y()
                << geo.width() << "x" << geo.height();

        // Position on the target screen BEFORE making visible
        mainWindow->setScreen(targetScreen ? targetScreen : QGuiApplication::primaryScreen());
        mainWindow->setPosition(geo.x(), geo.y());
        mainWindow->resize(geo.width(), geo.height());

        if (!parser.isSet(windowedOpt)) {
            // Now safe to go fullscreen — we're on the right screen
            mainWindow->showFullScreen();
            mainWindow->setVisible(true);
            qInfo() << "Fullscreen on" << mainWindow->screen()->name();
        } else {
            mainWindow->show();
            mainWindow->setVisible(true);
            qInfo() << "Windowed on" << mainWindow->screen()->name();
        }
    }

    // Metrics update timer (every 2 seconds)
    QTimer metricsTimer;
    QObject::connect(&metricsTimer, &QTimer::timeout, [&engine]() {
        QJsonObject m = metricsToJson();
        for (auto* obj : engine.rootObjects()) {
            obj->setProperty("metricsJson", QJsonDocument(m).toJson(QJsonDocument::Compact));
        }
    });
    metricsTimer.start(2000);

    // Screen change monitoring
    QObject::connect(&app, &QGuiApplication::screenAdded, [&engine](QScreen* screen) {
        qInfo() << "Screen added:" << screen->name();
        for (auto* obj : engine.rootObjects()) {
            obj->setProperty("screenAddedChanged", screen->name());
        }
    });
    QObject::connect(&app, &QGuiApplication::screenRemoved, [&engine](QScreen* screen) {
        qInfo() << "Screen removed:" << screen->name();
        for (auto* obj : engine.rootObjects()) {
            obj->setProperty("screenRemovedChanged", screen->name());
        }
    });

    int result = app.exec();

    // Save configuration on clean exit
    xeneon_config_save(config);
    xeneon_config_free(config);
    g_config = nullptr;

    return result;
}

#include "main.moc"
