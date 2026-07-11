import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: root
    // Start hidden. C++ positions the window on the target Xeneon screen,
    // then calls showFullScreen() / show(). This is critical for Wayland.
    visibility: Window.Hidden

    // Borderless when fullscreen; normal window decorations with --windowed
    flags: _windowedMode ? Qt.Window : (Qt.FramelessWindowHint | Qt.Window)

    // Properties exposed from C++
    property bool isFirstRun: _isFirstRun
    property string screensData: _screens
    property string metricsJson: _metricsJson
    property string themeMode: _themeMode
    property string targetEdidHash: _targetEdidHash
    property string targetConnector: _targetConnector
    property string targetModel: _targetModel
    property string configDir: _configDir
    property bool safeMode: _safeMode
    property bool startInDiagnostics: _startInDiagnostics !== undefined ? _startInDiagnostics : false
    property bool windowedMode: _windowedMode !== undefined ? _windowedMode : false
    property int targetScreenX: _targetScreenX !== undefined ? _targetScreenX : 0
    property int targetScreenY: _targetScreenY !== undefined ? _targetScreenY : 0
    property int targetScreenWidth: _targetScreenWidth !== undefined ? _targetScreenWidth : 1920
    property int targetScreenHeight: _targetScreenHeight !== undefined ? _targetScreenHeight : 1080

    // Screen hotplug properties
    property string screenAddedChanged: ""
    property string screenRemovedChanged: ""

    // React to screen hotplug events
    onScreenAddedChanged: function(name) {
        if (name) console.log("Screen added:", name);
    }
    onScreenRemovedChanged: function(name) {
        if (name) console.log("Screen removed:", name);
    }

    // Dashboard state
    property bool editMode: false
    property string currentPage: "main"
    property int currentPageIndex: 0

    // Reduced-motion preference (design system: all durations → 0ms)
    property bool reduceMotion: false

    // Theme object — exposed as property so child QML files can access it.
    // Encodes the full design system from docs/product/wireframes.md:
    // colors, spacing, radii, typography, touch targets, and motion tokens.
    QtObject {
        id: _theme

        // --- Color tokens ---
        property color backgroundColor: "#0D1117"
        property color cardBackground: "#161B22"
        property color cardBorder: "#30363D"
        property color textPrimary: "#E6EDF3"
        property color textSecondary: "#8B949E"
        property color accent: "#58A6FF"
        property color warning: "#D29922"
        property color error: "#F85149"
        property color success: "#3FB950"

        // --- Spacing tokens (logical px) ---
        property int spacingXs: 4
        property int spacingSm: 8
        property int spacingMd: 12   // grid gap
        property int spacingLg: 16   // card internal padding (min)
        property int spacingXl: 24   // card internal padding (max)

        // --- Radius tokens ---
        property int radiusSm: 8
        property int radiusMd: 12
        property int radiusLg: 16

        // --- Touch-target tokens (design system: 44/48/64) ---
        property int touchPrimary: 64     // Play, Pause, Add
        property int touchSecondary: 48   // Settings, Close
        property int touchTertiary: 44    // small toggles (absolute minimum)

        // --- Typography tokens (logical px) ---
        property int fontData: 40         // primary data (36–48)
        property int fontDataLarge: 48
        property int fontTitle: 17        // widget titles (16–18)
        property int fontLabel: 15        // secondary labels (14–16)
        property int fontCaption: 13
        property string fontMono: "JetBrains Mono, Fira Code, monospace"

        // --- Motion tokens (ms). Honor reduced motion. ---
        property int motionPage: root.reduceMotion ? 0 : 250   // page transition
        property int motionAdd: root.reduceMotion ? 0 : 200    // widget add scale-in
        property int motionRemove: root.reduceMotion ? 0 : 150 // widget remove fade
        property int motionEdit: root.reduceMotion ? 0 : 200   // edit enter/exit
        property int motionFast: root.reduceMotion ? 0 : 150   // press feedback

        function applyTheme(mode) {
            switch(mode) {
            case "light":
                backgroundColor = "#FFFFFF";
                cardBackground = "#F6F8FA";
                cardBorder = "#D0D7DE";
                textPrimary = "#1F2328";
                textSecondary = "#656D76";
                accent = "#0969DA";
                break;
            case "oled":
                backgroundColor = "#000000";
                cardBackground = "#0A0A0A";
                cardBorder = "#1A1A1A";
                textPrimary = "#E0E0E0";
                textSecondary = "#808080";
                accent = "#58A6FF";
                break;
            case "high_contrast":
                backgroundColor = "#000000";
                cardBackground = "#1A1A1A";
                cardBorder = "#FFFFFF";
                textPrimary = "#FFFFFF";
                textSecondary = "#CCCCCC";
                accent = "#FFFF00";
                break;
            default: // dark
                backgroundColor = "#0D1117";
                cardBackground = "#161B22";
                cardBorder = "#30363D";
                textPrimary = "#E6EDF3";
                textSecondary = "#8B949E";
                accent = "#58A6FF";
                break;
            }
        }

        Component.onCompleted: applyTheme(root.themeMode)
    }

    property alias theme: _theme

    // Touch-enabled tap handler for the entire window (exit fullscreen, etc.)
    TapHandler {
        onTapped: function(eventPoint, button) {
            // Three-finger tap → toggle diagnostics
            if (eventPoint.pointCount >= 3) {
                if (stackView.depth > 1) {
                    stackView.pop();
                } else {
                    stackView.push("qrc:/qml/Diagnostics.qml", {
                        "metricsJson": root.metricsJson,
                        "screensData": root.screensData
                    });
                }
            }
        }
        gesturePolicy: TapHandler.WithinBounds
    }

    // Long press handler for context menu on touch devices
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            if (stackView.depth <= 1) {
                stackView.push("qrc:/qml/Diagnostics.qml", {
                    "metricsJson": root.metricsJson,
                    "screensData": root.screensData
                });
            }
        }
    }

    // Navigation stack for main ↔ diagnostics
    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: isFirstRun ? "qrc:/qml/FirstRunWizard.qml" :
                     startInDiagnostics ? "qrc:/qml/Diagnostics.qml" :
                     "qrc:/qml/Dashboard.qml"
    }


    // Keyboard shortcuts
    Shortcut {
        sequence: "Ctrl+D"
        onActivated: {
            if (stackView.depth > 1) {
                stackView.pop();
            } else {
                stackView.push("qrc:/qml/Diagnostics.qml", {
                    "metricsJson": root.metricsJson,
                    "screensData": root.screensData
                });
            }
        }
    }
    Shortcut {
        sequence: "Ctrl+Q"
        onActivated: Qt.quit()
    }
    Shortcut {
        sequence: "F11"
        onActivated: {
            if (root.visibility === Window.FullScreen) {
                root.visibility = Window.Windowed;
            } else {
                root.visibility = Window.FullScreen;
            }
        }
    }

    Component.onCompleted: {
        console.log("Xeneon Edge Linux Hub v0.1.0 started");
        console.log("Config dir:", configDir);
        console.log("Theme mode:", themeMode);
        console.log("Is first run:", isFirstRun);
        console.log("Target screen:", targetScreenWidth + "x" + targetScreenHeight,
                     "at (" + targetScreenX + "," + targetScreenY + ")");
        if (safeMode) {
            console.log("Running in SAFE MODE");
        }
        if (windowedMode) {
            console.log("Windowed mode (--windowed)");
        }
        if (startInDiagnostics) {
            console.log("Starting in diagnostics mode (--diagnostics)");
        }
    }
}
