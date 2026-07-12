import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.VirtualKeyboard

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

    // Live UI-state pushed from the companion Manager app via the C++
    // ControlServer. Forward it to the dashboard for an immediate reload.
    property string externalUiState: ""
    onExternalUiStateChanged: {
        if (!externalUiState.length) return
        var item = stackView.currentItem
        if (item && item.applyExternalState)
            item.applyExternalState(externalUiState)
    }

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

    // Reduced-motion preference (design system: all durations → 0ms).
    property alias reduceMotion: _theme.reduceMotion

    // --- Runtime customization state (persisted best-effort) ---
    // These four are now aliases onto the shared Theme (single source of tokens),
    // so existing root.accentName / root.glassOpacity / … keep working and their
    // change signals still drive DashboardStore persistence.
    property alias accentName: _theme.accentName
    property alias glassOpacity: _theme.glassOpacity
    property alias showWidgetGlow: _theme.showWidgetGlow
    property bool animatedBackground: true   // subtle drifting orbs behind the grid

    // Shared design-system tokens (single source of truth; see ui/qml/Theme.qml).
    // Its runtime knobs (accent/glass/glow/reduceMotion) are aliased onto root above.
    Theme {
        id: _theme
        Component.onCompleted: applyTheme(root.themeMode)
    }

    property alias theme: _theme

    // ── Orientation ──────────────────────────────────────────────────────────
    // `orientationMode` (persisted appearance) is "auto" or a fixed value.
    //
    // AUTO = trust the compositor: the framebuffer is already oriented correctly,
    // so apply NO software rotation and let the grid reflow to the real aspect
    // (root width vs height) — this is what makes it flip when the compositor
    // rotates the output. MANUAL modes apply a fixed software rotation for
    // mountings the compositor can't correct. We deliberately do NOT rotate from
    // the raw orientation sensor: doing so double-rotated to an upside-down image,
    // so a mounting the compositor can't handle is selected explicitly instead.
    property string orientationMode: "auto"
    readonly property int contentRotation: {
        switch (orientationMode) {
        case "landscape": return 90
        case "inverted-portrait": return 180
        case "inverted-landscape": return 270
        case "portrait": return 0
        default: return 0    // auto
        }
    }

    // NOTE: Diagnostics is reached via the ⚙ button on the dashboard and the
    // Ctrl+D shortcut. Earlier there were whole-window TapHandlers here (3-finger
    // + right-click) — removed because a root-level gesture handler can delay
    // touch delivery to the widget buttons underneath, hurting responsiveness.

    // Rotating content container — rotates + reflows the whole UI to match the
    // device orientation. When rotated 90/270 it swaps width/height so the
    // dashboard inside lays out for the effective aspect (landscape → more cols).
    Item {
        id: contentRoot
        anchors.centerIn: parent
        readonly property bool swapped: root.contentRotation === 90 || root.contentRotation === 270
        width: swapped ? root.height : root.width
        height: swapped ? root.width : root.height
        rotation: root.contentRotation
        Behavior on rotation { NumberAnimation { duration: theme.motionPage; easing.type: Easing.InOutCubic } }

        // Navigation stack for main ↔ diagnostics
        StackView {
            id: stackView
            anchors.fill: parent
            initialItem: isFirstRun ? "qrc:/qml/FirstRunWizard.qml" :
                         startInDiagnostics ? "qrc:/qml/Diagnostics.qml" :
                         "qrc:/qml/Dashboard.qml"
        }

        // On-screen keyboard: this is a touchscreen device with no attached
        // physical keyboard, so any focused TextField needs a way to type.
        InputPanel {
            id: inputPanel
            z: 1000
            anchors.left: parent.left
            anchors.right: parent.right
            y: active ? contentRoot.height - height : contentRoot.height
            Behavior on y { NumberAnimation { duration: theme.motionEdit; easing.type: Easing.OutCubic } }
        }
    }


    // Keyboard shortcuts
    Shortcut {
        sequence: "Ctrl+D"
        onActivated: {
            if (stackView.depth > 1) {
                stackView.pop();
            } else {
                stackView.push("qrc:/qml/Diagnostics.qml", {
                    // Bind live so the Diagnostics overview keeps updating, rather
                    // than freezing at the first sample taken when Ctrl+D was pressed.
                    "metricsJson": Qt.binding(function () { return root.metricsJson }),
                    "screensData": root.screensData,
                    "configJson": (typeof configBridge !== "undefined" && configBridge) ? configBridge.configJson() : ""
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
