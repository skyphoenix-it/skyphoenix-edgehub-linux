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
        // Route to whichever stack item can apply it (the Dashboard), even when
        // Diagnostics or the wizard is on top — otherwise a live Manager push is
        // silently dropped while any other page is showing.
        var target = stackView.find(function (item) { return item && item.applyExternalState })
        if (target) target.applyExternalState(externalUiState)
    }

    // React to screen hotplug events
    onScreenAddedChanged: function(name) {
        if (name) console.log("Screen added:", name);
    }
    onScreenRemovedChanged: function(name) {
        if (name) console.log("Screen removed:", name);
    }

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
    // AUTO follows the Edge's built-in orientation sensor: C++ reads it over the
    // vendor HID pipe and pushes the correct content rotation into `sensorRotation`
    // (0/90/180/270); we rotate + reflow the UI to match so it stays upright as the
    // panel turns. MANUAL modes ignore the sensor and apply a fixed rotation (for
    // wall/arm mounts). Until the sensor reports (or if the hidraw node isn't
    // readable) `sensorRotation` is -1 and auto stays at 0.
    property int sensorRotation: -1          // raw value pushed from C++ OrientationSensor
    // Debounced sensor value: the raw reading must hold steady briefly before we
    // rotate, so jitter near an orientation boundary doesn't thrash the whole UI
    // (each change triggers a 560ms rotate + a fade/scale dip).
    property int _stableSensorRotation: -1
    onSensorRotationChanged: {
        if (root.sensorRotation < 0) return
        if (root._stableSensorRotation < 0) root._stableSensorRotation = root.sensorRotation // apply the first reading promptly
        else sensorDebounce.restart()
    }
    Timer {
        id: sensorDebounce; interval: 350; repeat: false
        onTriggered: root._stableSensorRotation = root.sensorRotation
    }
    property string orientationMode: "auto"
    readonly property int contentRotation: {
        switch (orientationMode) {
        case "portrait": return 0
        case "landscape": return 90
        case "inverted-portrait": return 180
        case "inverted-landscape": return 270
        default: return _stableSensorRotation >= 0 ? _stableSensorRotation : 0   // auto
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
        transformOrigin: Item.Center
        readonly property bool swapped: root.contentRotation === 90 || root.contentRotation === 270
        width: swapped ? root.height : root.width
        height: swapped ? root.width : root.height
        rotation: root.contentRotation
        // Always turn the SHORT way (0°↔270° goes -90°, not +270°) with a soft ease.
        Behavior on rotation {
            RotationAnimation {
                direction: RotationAnimation.Shortest
                duration: root.reduceMotion ? 0 : 560
                easing.type: Easing.InOutCubic
            }
        }
        // Soften the reflow: as it re-orients, dip opacity + scale slightly so the
        // aspect swap (portrait↔landscape grid) is masked behind a smooth fade.
        Connections {
            target: root
            function onContentRotationChanged() {
                // Dismiss the on-screen keyboard before re-orienting so it can't
                // flash while the container height swaps underneath it.
                Qt.inputMethod.hide()
                if (!root.reduceMotion) reorientFx.restart()
            }
        }
        SequentialAnimation {
            id: reorientFx
            ParallelAnimation {
                NumberAnimation { target: contentRoot; property: "opacity"; to: 0.25; duration: 210; easing.type: Easing.InQuad }
                NumberAnimation { target: contentRoot; property: "scale"; to: 0.93; duration: 210; easing.type: Easing.InQuad }
            }
            ParallelAnimation {
                NumberAnimation { target: contentRoot; property: "opacity"; to: 1.0; duration: 360; easing.type: Easing.OutQuad }
                NumberAnimation { target: contentRoot; property: "scale"; to: 1.0; duration: 360; easing.type: Easing.OutCubic }
            }
        }

        // Navigation stack for main ↔ diagnostics
        StackView {
            id: stackView
            anchors.fill: parent
            initialItem: isFirstRun ? "qrc:/qml/FirstRunWizard.qml" :
                         startInDiagnostics ? "qrc:/qml/Diagnostics.qml" :
                         "qrc:/qml/Dashboard.qml"

            // Keep the focused input above the on-screen keyboard: lift the whole
            // stack by exactly the overlap between the text cursor and the keyboard
            // top (0 when the cursor is already clear). Without this, inputs in the
            // bottom half of a 2560px panel are fully hidden behind the VK.
            transform: Translate {
                y: {
                    if (!inputPanel.active) return 0
                    var kbTop = contentRoot.height - inputPanel.height
                    var cur = Qt.inputMethod.cursorRectangle
                    var need = (cur.y + cur.height + theme.spacingLg) - kbTop
                    return need > 0 ? -need : 0
                }
                Behavior on y { NumberAnimation { duration: theme.motionEdit; easing.type: Easing.OutCubic } }
            }
        }

        // On-screen keyboard: this is a touchscreen device with no attached
        // physical keyboard, so any focused TextField needs a way to type.
        InputPanel {
            id: inputPanel
            z: 1000
            anchors.left: parent.left
            anchors.right: parent.right
            // Only render when the keyboard is actually active, so it can never
            // flash during a rotation (when contentRoot's height changes under it).
            visible: inputPanel.active
            y: active ? contentRoot.height - height : contentRoot.height
            // Slide only for genuine show/hide — not when the container resizes
            // on rotation (which would otherwise re-animate the hidden panel).
            Behavior on y { enabled: inputPanel.active; NumberAnimation { duration: theme.motionEdit; easing.type: Easing.OutCubic } }
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
