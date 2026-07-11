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

    // --- Runtime customization state (persisted best-effort) ---
    property string accentName: "blue"
    property real glassOpacity: 0.55   // 0 = solid cards, 1 = very glassy
    property bool showWidgetGlow: true

    // Theme object — exposed as property so child QML files can access it.
    // Encodes the full design system from docs/product/wireframes.md:
    // colors, spacing, radii, typography, touch targets, and motion tokens.
    QtObject {
        id: _theme

        // --- Color tokens ---
        property color backgroundColor: "#0D1117"
        property color backgroundColor2: "#0A0E14"   // gradient partner for bg
        property color cardBackground: "#161B22"
        property color cardBackgroundAlt: "#1C222B"   // elevated / secondary surface
        property color cardBorder: "#30363D"
        property color textPrimary: "#E6EDF3"
        property color textSecondary: "#8B949E"
        property color textTertiary: "#6E7681"
        property color accent: "#58A6FF"
        property color accent2: "#7EE787"             // secondary accent for gradients
        property color warning: "#D29922"
        property color error: "#F85149"
        property color success: "#3FB950"

        // --- Category accent colors (uniform visual language) ---
        property color catSystem: "#58A6FF"       // System / hardware
        property color catProductivity: "#A371F7" // Productivity / focus
        property color catInfo: "#3FB950"          // Information / data
        property color catEntertainment: "#F778BA" // Entertainment / media
        property color catGaming: "#F0883E"        // Gaming
        property color catServices: "#56D4DD"      // Network services

        // --- Named accent presets (user-selectable) ---
        readonly property var accentPresets: ({
            "blue":   { a: "#58A6FF", b: "#79C0FF" },
            "purple": { a: "#A371F7", b: "#D2A8FF" },
            "green":  { a: "#3FB950", b: "#7EE787" },
            "orange": { a: "#F0883E", b: "#FFA657" },
            "pink":   { a: "#F778BA", b: "#FF9BCE" },
            "teal":   { a: "#56D4DD", b: "#76E3EA" },
            "red":    { a: "#F85149", b: "#FF7B72" },
            "gold":   { a: "#E3B341", b: "#F2CC60" }
        })

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
        property int radiusXl: 22

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
        property string fontDisplay: "Inter, Segoe UI, Roboto, sans-serif"

        // --- Glass / elevation tokens ---
        property real glass: root.glassOpacity
        property bool glow: root.showWidgetGlow
        // Card fill respects the glass setting (more transparent = glassier).
        function cardFill() {
            return Qt.rgba(cardBackground.r, cardBackground.g, cardBackground.b,
                           0.35 + (1.0 - root.glassOpacity) * 0.65)
        }

        // --- Motion tokens (ms). Honor reduced motion. ---
        property int motionPage: root.reduceMotion ? 0 : 250   // page transition
        property int motionAdd: root.reduceMotion ? 0 : 200    // widget add scale-in
        property int motionRemove: root.reduceMotion ? 0 : 150 // widget remove fade
        property int motionEdit: root.reduceMotion ? 0 : 200   // edit enter/exit
        property int motionFast: root.reduceMotion ? 0 : 150   // press feedback
        property int motionSlow: root.reduceMotion ? 0 : 500

        // Apply a named accent preset at runtime.
        function applyAccent(name) {
            var p = accentPresets[name] || accentPresets["blue"]
            accent = p.a
            accent2 = p.b
            root.accentName = name
        }

        function applyTheme(mode) {
            switch(mode) {
            case "light":
                backgroundColor = "#FFFFFF";
                backgroundColor2 = "#EEF1F5";
                cardBackground = "#F6F8FA";
                cardBackgroundAlt = "#ECEFF3";
                cardBorder = "#D0D7DE";
                textPrimary = "#1F2328";
                textSecondary = "#656D76";
                textTertiary = "#8C959F";
                break;
            case "oled":
                backgroundColor = "#000000";
                backgroundColor2 = "#000000";
                cardBackground = "#0A0A0A";
                cardBackgroundAlt = "#121212";
                cardBorder = "#1A1A1A";
                textPrimary = "#E0E0E0";
                textSecondary = "#808080";
                textTertiary = "#5A5A5A";
                break;
            case "high_contrast":
                backgroundColor = "#000000";
                backgroundColor2 = "#000000";
                cardBackground = "#1A1A1A";
                cardBackgroundAlt = "#242424";
                cardBorder = "#FFFFFF";
                textPrimary = "#FFFFFF";
                textSecondary = "#CCCCCC";
                textTertiary = "#AAAAAA";
                break;
            default: // dark
                backgroundColor = "#0D1117";
                backgroundColor2 = "#0A0E14";
                cardBackground = "#161B22";
                cardBackgroundAlt = "#1C222B";
                cardBorder = "#30363D";
                textPrimary = "#E6EDF3";
                textSecondary = "#8B949E";
                textTertiary = "#6E7681";
                break;
            }
            applyAccent(root.accentName);
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
