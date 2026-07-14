#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QScreen>
#include <QWindow>
#include <QQuickWindow>
#include <QImage>
#include <QTimer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <QCommandLineParser>
#include <QObject>
#include <QFile>
#include <QDir>
#include <QUrl>
#include <QTextStream>
#include <QQuickStyle>
#include <QPalette>

#include <cstdio>

#include "single_instance.h"
#include <QColor>
#include <csignal>
#include <unistd.h>
#include <QSocketNotifier>
#include <QThread>

#include "xeneon_core.h"
#include "mpris_bridge.h"
#include "control_server.h"
#include "orientation_sensor.h"
#include "xeneon_string.h"
#include "autostart.h"
#include "display_match.h"
#include "config_bridge.h"
#include "metrics_worker.h"

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

// --- Dark palette ---
// Qt Quick Controls that aren't hand-restyled draw their chrome (Switch/Slider/
// ScrollBar/Dialog button-boxes) from the application QPalette. Without a dark
// one they fall back to the style's default LIGHT gray on the dark UI. Build it
// from the same design tokens the QML theme uses.
static QPalette darkPalette() {
    const QColor window("#0D1117");
    const QColor base("#161B22");
    const QColor alt("#1C222B");
    const QColor button("#1C222B");
    const QColor text("#E6EDF3");
    const QColor muted("#8B949E");
    const QColor accent("#F26D6D");
    const QColor onAccent("#0D1117");

    QPalette pal;
    pal.setColor(QPalette::Window, window);
    pal.setColor(QPalette::WindowText, text);
    pal.setColor(QPalette::Base, base);
    pal.setColor(QPalette::AlternateBase, alt);
    pal.setColor(QPalette::Button, button);
    pal.setColor(QPalette::ButtonText, text);
    pal.setColor(QPalette::Text, text);
    pal.setColor(QPalette::PlaceholderText, muted);
    pal.setColor(QPalette::BrightText, text);
    pal.setColor(QPalette::ToolTipBase, base);
    pal.setColor(QPalette::ToolTipText, text);
    pal.setColor(QPalette::Highlight, accent);
    pal.setColor(QPalette::HighlightedText, onAccent);
    pal.setColor(QPalette::Link, accent);
    pal.setColor(QPalette::Disabled, QPalette::Text, muted);
    pal.setColor(QPalette::Disabled, QPalette::WindowText, muted);
    pal.setColor(QPalette::Disabled, QPalette::ButtonText, muted);
    pal.setColor(QPalette::Disabled, QPalette::Highlight, alt);
    return pal;
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
    {
        const QString on = orientationName(screen->orientation());
        obj["orientation"] = on.isEmpty() ? QStringLiteral("portrait") : on;
    }
    obj["isPrimary"] = (screen == QGuiApplication::primaryScreen());
    obj["size"] = QJsonObject{
        {"width", screen->size().width()},
        {"height", screen->size().height()}
    };

    obj["edidHash"] = screenIdentityHash(screen->name(), screen->model(),
                                         screen->manufacturer(), screen->serialNumber());

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
    ssize_t rc = ::write(sigFd[1], &c, 1);
    (void)rc;   // async-signal-safe; nothing useful to do on failure
}

// --- Find target display ---

// Positive identity match ONLY (hash → model → connector → XENEON → resolution).
// Returns nullptr when nothing matches — NO primary-screen fallback. Used to decide
// whether a hotplugged screen is genuinely the Edge: the primary fallback must not
// count as a match there, or plugging in an unrelated (primary) monitor while the
// Edge is absent would hijack it fullscreen.
static QScreen* findTargetScreenStrict(ConfigHandle* config) {
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
            const QString hash = screenIdentityHash(s->name(), s->model(),
                                                    s->manufacturer(), s->serialNumber());
            if (hash == targetHash.qstring()) {
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

    return nullptr;   // no positive match — caller decides on the fallback
}

// Boot-time placement helper: the positive identity match, else the primary screen
// as a last resort so the hub still shows somewhere on first run / Edge-absent boot.
static QScreen* findTargetScreen(ConfigHandle* config) {
    QScreen* s = findTargetScreenStrict(config);
    if (s)
        return s;
    QScreen* primary = QGuiApplication::primaryScreen();
    qWarning() << "No Xeneon Edge detected, falling back to primary screen:"
               << (primary ? primary->name() : QStringLiteral("<none>"));
    return primary;
}

int main(int argc, char *argv[]) {
    // Allow QML XMLHttpRequest to read local file:// paths — the KPI widget's
    // "local file" source (a bare number or JSON on disk) relies on it. This is
    // a LOCAL read only; it opens no network path (remote egress is separately
    // gated by NetHub), so it does not weaken the no-telemetry guarantee.
    qputenv("QML_XHR_ALLOW_FILE_READ", "1");

    // Initialize Rust core logging FIRST
    xeneon_logging_init("info");

    // Install Qt → Rust log bridge
    qInstallMessageHandler(qtLogBridge);

    QGuiApplication app(argc, argv);
    app.setApplicationName("Xeneon Edge Linux Hub");
    app.setApplicationVersion("0.1.0");
    app.setOrganizationName("xeneon-edge-hub");

    // Fusion style + dark palette so on-device config controls (Switch/Slider/
    // ScrollBar/Dialog button-boxes) render dark instead of the default light gray.
    QQuickStyle::setStyle(QStringLiteral("Fusion"));
    QGuiApplication::setPalette(darkPalette());

    // QA automation hooks (screenshot capture + auto-expand + single-instance
    // bypass) are compiled in ONLY when XENEON_QA_HOOKS is defined (CI / tests /
    // marketing builds). In production packages these stay empty/false, so the
    // env vars are inert — no screenshot/automation surface ships.
#ifdef XENEON_QA_HOOKS
    const bool    qaGrabMode = qEnvironmentVariableIsSet("XENEON_GRAB");
    const QString qaGrabPath = qEnvironmentVariable("XENEON_GRAB");
    const QString qaExpand   = qEnvironmentVariable("XENEON_EXPAND");
#else
    const bool    qaGrabMode = false;
    const QString qaGrabPath;
    const QString qaExpand;
#endif

    // Single-instance guard — two hubs racing the shared config.toml corrupt it.
    // Skipped in grab mode so headless QA captures run alongside a real instance.
    auto instanceLock = xeneon::acquireSingleInstance(
        QStringLiteral("hub"), qaGrabMode);
    if (!instanceLock) {
        // fprintf (not qWarning): Qt's default handler routes to journald when
        // stderr isn't a TTY, so a plain write guarantees the user sees why the
        // second instance didn't open.
        std::fprintf(stderr, "Another Xeneon Edge Hub is already running - exiting.\n");
        std::fflush(stderr);
        return 0;
    }

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

    // Collect display information. A single builder so the initial snapshot and
    // every hotplug refresh serialize screens identically (S9: the list was frozen
    // at boot — the Display/Diagnostics tabs never saw a plugged/unplugged screen).
    auto buildScreensJson = []() -> QByteArray {
        QJsonArray arr;
        for (auto* screen : QGuiApplication::screens())
            arr.append(screenToJson(screen));
        return QJsonDocument(arr).toJson(QJsonDocument::Compact);
    };

    // Find target display for fullscreen placement
    QScreen* targetScreen = findTargetScreen(config);

    // Collect system metrics for initial display
    QJsonObject metricsJson = metricsToJson();

    // Create QML engine
    QQmlApplicationEngine engine;

    // Expose data to QML
    engine.rootContext()->setContextProperty("_isFirstRun", isFirstRun);
    engine.rootContext()->setContextProperty("_screens", buildScreensJson());
    engine.rootContext()->setContextProperty("_metricsJson", QJsonDocument(metricsJson).toJson(QJsonDocument::Compact));
    engine.rootContext()->setContextProperty("_safeMode", parser.isSet(safeModeOpt));
    engine.rootContext()->setContextProperty("_startInDiagnostics", parser.isSet(diagOpt));
    engine.rootContext()->setContextProperty("_windowedMode", parser.isSet(windowedOpt));
    // QA affordance: XENEON_EXPAND=<type> auto-opens that widget's expanded
    // config view on the first matching tile (mirrors the Manager's XENEON_CFG).
    engine.rootContext()->setContextProperty("_expandType", qaExpand);

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

    // Live control endpoint for the companion "Xeneon Edge Manager" app. It can
    // push a new layout/appearance document, which we persist and live-reload.
    ControlServer* controlServer = new ControlServer(&engine);
    controlServer->setStateProvider([configBridge]() { return configBridge->uiState(); });
    QObject::connect(controlServer, &ControlServer::uiStateReceived, &engine,
                     [configBridge, &engine](const QString& json, bool* ok) {
        // *ok reports the apply result back to ControlServer so the socket ack is
        // honest (was: always "ok"). Same-thread direct connection, so it's set on
        // return. Set on BOTH paths.
        if (!configBridge->applyExternalUiState(json)) {
            qWarning() << "Failed to apply externally pushed UI state";
            if (ok) *ok = false;
            return;
        }
        if (ok) *ok = true;
        // Trigger a live reload in QML (main.qml forwards this to the dashboard).
        for (auto* obj : engine.rootObjects())
            obj->setProperty("externalUiState", json);
    // EXPLICIT Qt::DirectConnection is REQUIRED, not incidental: both the ack
    // correctness and the validity of the `bool* ok` argument depend on SAME-THREAD
    // synchronous delivery — the slot must run and write *ok BEFORE handleLine() reads
    // it (the pointer is into handleLine's stack frame). If ControlServer were ever
    // moved to another thread, an auto/queued connection would (a) deliver AFTER emit
    // returns → the ack always reports false, and (b) write *ok into a since-unwound
    // stack frame → a use-after-free. Keep this Direct.
    }, Qt::DirectConnection);
    // Manager "Stop hub" → quit cleanly. Defer briefly so the "ok" ack flushes to
    // the socket before the event loop tears down.
    QObject::connect(controlServer, &ControlServer::shutdownRequested, &engine, [] {
        qInfo() << "Hub: shutdown requested by Manager";
        QTimer::singleShot(80, qApp, &QCoreApplication::quit);
    });
    controlServer->start();

    // Load main QML
    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "Failed to load QML";
        g_config = nullptr;   // clear before free so a late signal can't touch it
        xeneon_config_free(config);
        return 1;
    }

    // Window placement: QML starts invisible and Windowed (see main.qml).
    // C++ positions it on the target screen FIRST, then shows it.
    // This is critical for Wayland where the compositor controls placement.
    QWindow* mainWindow = qobject_cast<QWindow*>(engine.rootObjects().first());
    // Prefer the detected Edge; otherwise the primary. Either may be null on a
    // headless/no-display host, so guard before dereferencing.
    QScreen* placeScreen = targetScreen ? targetScreen : QGuiApplication::primaryScreen();
    if (mainWindow && placeScreen) {
        QRect geo = placeScreen->geometry();
        qInfo() << "Placing window on" << placeScreen->name()
                << "model:" << placeScreen->model()
                << "at" << geo.x() << "," << geo.y()
                << geo.width() << "x" << geo.height();

        // Position on the target screen BEFORE making visible
        mainWindow->setScreen(placeScreen);
        mainWindow->setPosition(geo.x(), geo.y());
        mainWindow->resize(geo.width(), geo.height());

        if (!parser.isSet(windowedOpt)) {
            // Now safe to go fullscreen — we're on the right screen
            mainWindow->showFullScreen();
            mainWindow->setVisible(true);
            qInfo() << "Fullscreen on" << (mainWindow->screen() ? mainWindow->screen()->name() : QStringLiteral("(unknown screen)"));
        } else {
            mainWindow->show();
            mainWindow->setVisible(true);
            qInfo() << "Windowed on" << (mainWindow->screen() ? mainWindow->screen()->name() : QStringLiteral("(unknown screen)"));
        }
    }

    // Live orientation from the Edge's built-in sensor (read over its vendor HID
    // pipe). In "auto" mode QML rotates + reflows the UI to match. The manual
    // orientation modes ignore this and apply a fixed rotation instead.
    auto* orientation = new OrientationSensor(&app);
    auto pushRotation = [&engine](int rot) {
        for (auto* obj : engine.rootObjects())
            obj->setProperty("sensorRotation", rot);
    };
    QObject::connect(orientation, &OrientationSensor::rotationChanged, &engine,
                     [pushRotation](int rot) {
        qInfo() << "Orientation sensor: content rotation" << rot << "deg";
        pushRotation(rot);
    });
    if (orientation->start() && orientation->rotation() >= 0)
        pushRotation(orientation->rotation());

    // Metrics on a dedicated worker thread (every 2s), so the Rust FFI collection
    // + JSON serialization never janks the GUI event loop. Results arrive on the
    // GUI thread via a queued signal and are pushed onto the QML roots. `metricsThread`
    // is declared BEFORE `metricsWorker` so the worker is destroyed first (while the
    // QThread object is still alive), after we join the thread below.
    QThread metricsThread;
    MetricsWorker metricsWorker;
    metricsWorker.moveToThread(&metricsThread);
    QObject::connect(&metricsThread, &QThread::started, &metricsWorker, &MetricsWorker::begin);
    QObject::connect(&metricsWorker, &MetricsWorker::metricsReady, &engine,
                     [&engine](const QByteArray& json) {
        for (auto* obj : engine.rootObjects())
            obj->setProperty("metricsJson", json);
    }, Qt::QueuedConnection);
    metricsThread.start();

    // Screen change monitoring. Pass &engine as the context object so these
    // connections are severed when the engine is destroyed — otherwise the
    // QGuiApplication (which outlives the engine) emits screenRemoved during its
    // own teardown and the lambda dereferences a freed engine.
    // On any hotplug, rebuild the FULL screen list and push it as `screensData`
    // (a proper notifiable string property) so the Display/Diagnostics tabs reflect
    // the live topology instead of the boot snapshot. The old code only set a
    // screen-name marker and never refreshed the list itself (S9). The distinct
    // added/removed name markers are kept for logging/toast affordances in QML.
    auto pushScreens = [&engine, buildScreensJson]() {
        const QByteArray json = buildScreensJson();
        for (auto* obj : engine.rootObjects())
            obj->setProperty("screensData", json);
    };

    // S10: honor the display disconnect/reconnect keys on live hotplug.
    //  - notify_disconnect → surface a "display disconnected" notice when the
    //    TARGET screen vanishes.
    //  - fallback_behavior "hide" → blank/hide the hub window on target loss.
    //  - reconnect          → re-run the target match and migrate the window back
    //    onto the Edge when it returns.
    // `targetScreen` is tracked live so we know which physical screen is ours, and
    // `targetHidden` remembers a fallback-hide so we can un-hide on reconnect.
    const bool windowedMode = parser.isSet(windowedOpt);
    bool targetHidden = false;
    QObject::connect(&app, &QGuiApplication::screenAdded, &engine,
                     [&engine, config, &targetScreen, &targetHidden, &mainWindow,
                      windowedMode, pushScreens](QScreen* screen) {
        qInfo() << "Screen added:" << screen->name();
        const bool reconnectEnabled = xeneon_config_get_reconnect(config) == 1;
        // STRICT match (no primary fallback): only migrate onto the hotplugged
        // screen when it POSITIVELY identifies as the target. Otherwise plugging in
        // any unrelated (primary) monitor while the Edge is absent would make the hub
        // hijack it fullscreen and mislabel it as the target.
        QScreen* newTarget = findTargetScreenStrict(config);
        if (newTarget && shouldReconnectToScreen(reconnectEnabled, newTarget == screen) && mainWindow) {
            qInfo() << "Hub: target display returned — migrating window to" << screen->name();
            targetScreen = screen;
            const QRect geo = screen->geometry();
            mainWindow->setScreen(screen);
            mainWindow->setPosition(geo.x(), geo.y());
            mainWindow->resize(geo.width(), geo.height());
            if (windowedMode) mainWindow->show();
            else              mainWindow->showFullScreen();
            mainWindow->setVisible(true);
            targetHidden = false;
        }
        for (auto* obj : engine.rootObjects())
            obj->setProperty("screenAddedChanged", screen->name());
        pushScreens();
    });
    QObject::connect(&app, &QGuiApplication::screenRemoved, &engine,
                     [&engine, config, &targetScreen, &targetHidden, &mainWindow,
                      pushScreens](QScreen* screen) {
        qInfo() << "Screen removed:" << screen->name();
        const bool wasTarget = (screen == targetScreen);
        XeneonString fb(xeneon_config_get_fallback_behavior(config));
        const bool notifyDisconnect = xeneon_config_get_notify_disconnect(config) == 1;
        const DisconnectDecision d = decideOnScreenRemoved(wasTarget, fb.qstring(), notifyDisconnect);
        if (d.notify) {
            qWarning() << "Hub: target display disconnected:" << screen->name();
            for (auto* obj : engine.rootObjects())
                obj->setProperty("displayDisconnected", screen->name());
        }
        if (d.hideWindow && mainWindow) {
            qInfo() << "Hub: hiding window (fallback=hide) after target loss";
            mainWindow->setVisible(false);
            targetHidden = true;
        }
        if (wasTarget) targetScreen = nullptr;   // target gone until it returns
        for (auto* obj : engine.rootObjects())
            obj->setProperty("screenRemovedChanged", screen->name());
        pushScreens();
    });
    // A primary-screen swap (e.g. the Edge becomes/stops being primary) changes the
    // isPrimary flags without an add/remove, so refresh on that too.
    QObject::connect(&app, &QGuiApplication::primaryScreenChanged, &engine,
                     [pushScreens](QScreen*) { pushScreens(); });

    // QA capture: XENEON_GRAB=<path> renders the window to a PNG and quits (mirrors
    // the Manager). Optional XENEON_GRAB_W / XENEON_GRAB_H resize the window first so
    // a tall portrait shell renders fully on a smaller dev monitor. Always quits, so
    // a headless/bg run can never hang (addresses the earlier no-fallback-quit note).
    const QString grabPath = qaGrabPath;   // empty unless built with XENEON_QA_HOOKS
    if (!grabPath.isEmpty()) {
        if (mainWindow) {
            const int gw = qEnvironmentVariable("XENEON_GRAB_W", "0").toInt();
            const int gh = qEnvironmentVariable("XENEON_GRAB_H", "0").toInt();
            if (gw > 0 && gh > 0) {
                mainWindow->setVisibility(QWindow::Windowed);
                mainWindow->resize(gw, gh);
            }
        }
        QObject* root = engine.rootObjects().first();
        QTimer::singleShot(2200, [root, grabPath]() {
            auto* win = qobject_cast<QQuickWindow*>(root);
            if (win) {
                const QImage img = win->grabWindow();
                if (!img.isNull() && img.save(grabPath))
                    qInfo() << "Hub: saved grab to" << grabPath;
                else
                    qWarning() << "Hub: grab failed";
            } else {
                qWarning() << "Hub: grab skipped (root is not a window)";
            }
            QCoreApplication::quit();
        });
    }

    int result = app.exec();

    // Stop the metrics worker (delete its timer on the worker thread) and join the
    // thread before any stack teardown, so no metrics callback fires into a
    // half-destroyed engine.
    QMetaObject::invokeMethod(&metricsWorker, "stop", Qt::BlockingQueuedConnection);
    metricsThread.quit();
    metricsThread.wait();

    // Save configuration on clean exit while the handle is still valid.
    xeneon_config_save(config);

    // Detach the QML bridges from the config handle BEFORE freeing it. The
    // engine is a stack object destroyed after this scope returns; a late
    // Component.onDestruction handler calling configBridge.saveUiState()/uiState()
    // would otherwise dereference freed memory. Clear g_config first so the
    // signal handler can't touch it either.
    configBridge->detach();
    wizardBridge->detach();
    g_config = nullptr;
    xeneon_config_free(config);

    return result;
}
