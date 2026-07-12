import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ─────────────────────────────────────────────────────────────────────────
// Dashboard — registry-driven, persistent, touch-editable widget canvas for
// the Xeneon Edge (2560×720).
//
//   • Layout + per-widget state live in DashboardStore (persisted via config).
//   • Each widget is a file registered in WidgetCatalog and loaded into a tile.
//     The SAME widget file + SAME persisted settings object back both the tile
//     and its full-screen expanded view, so their state is shared.
//   • Edit mode: add (catalog picker), remove, reorder, and add/remove pages.
//   • A single-driver rule (`active`) stops background tiles' timers while the
//     expanded overlay is open, so shared countdowns never double-run.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: dashboard
    anchors.fill: parent

    property int _tick: 0
    property var metrics: {
        try { return JSON.parse(metricsJson || "{}") } catch (e) { return {} }
    }
    property bool isLandscape: width > height
    property bool editMode: false

    // Expanded overlay state (empty type = nothing expanded).
    property string expandedType: ""
    property string expandedId: ""
    property color  expandedColor: theme.accent
    property bool hasExpanded: expandedType !== ""

    property var host: StackView.view
    property bool _applyingAppearance: false

    function fmtBytes(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB"
        if (b >= 1048576) return (b / 1048576).toFixed(0) + " MB"
        if (b >= 1024) return (b / 1024).toFixed(0) + " KB"
        return b + " B"
    }
    function fmtRate(bps) {
        if (bps >= 1048576) return (bps / 1048576).toFixed(1) + " MB/s"
        if (bps >= 1024) return (bps / 1024).toFixed(0) + " KB/s"
        return Math.round(bps) + " B/s"
    }

    // ── Background ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: theme.backgroundColor }
            GradientStop { position: 1.0; color: theme.backgroundColor2 }
        }
    }
    Rectangle {
        anchors.fill: parent
        opacity: 0.06
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: theme.accent }
            GradientStop { position: 0.5; color: "transparent" }
            GradientStop { position: 1.0; color: theme.accent2 }
        }
    }

    Timer { interval: 1000; running: Qt.application.active; repeat: true; onTriggered: dashboard._tick++ }

    DashboardStore { id: store }
    WidgetCatalog { id: catalog }

    Component.onCompleted: {
        store.load(typeof configBridge !== "undefined" && configBridge ? configBridge.starterLayout() : "")
        applyAppearance()
    }


    // Apply persisted appearance to the shared theme (main.qml root).
    function applyAppearance() {
        _applyingAppearance = true
        var a = store.appearance()
        if (a.themeMode) root.themeMode = a.themeMode
        theme.applyTheme(a.themeMode ? a.themeMode : root.themeMode)
        if (a.accent) theme.applyAccent(a.accent)
        if (a.glass !== undefined) root.glassOpacity = a.glass
        if (a.glow !== undefined) root.showWidgetGlow = a.glow
        if (a.reduceMotion !== undefined) root.reduceMotion = a.reduceMotion
        _applyingAppearance = false
    }

    // Persist appearance changes made through the SettingsPanel.
    Connections {
        target: root
        enabled: store.loaded && !dashboard._applyingAppearance
        function onAccentNameChanged() { store.setAppearance("accent", root.accentName) }
        function onGlassOpacityChanged() { store.setAppearance("glass", root.glassOpacity) }
        function onShowWidgetGlowChanged() { store.setAppearance("glow", root.showWidgetGlow) }
        function onReduceMotionChanged() { store.setAppearance("reduceMotion", root.reduceMotion) }
        function onThemeModeChanged() { store.setAppearance("themeMode", root.themeMode) }
    }

    // ── Fallback tile (error boundary for unknown / unavailable widgets) ─────
    Component {
        id: fallbackTile
        WidgetChrome {
            property var metrics: ({})
            property var settings: ({})
            property bool expanded: false
            property bool active: true
            property var store: null
            property string instanceId: ""
            title: "Unavailable"; icon: "❓"; accentColor: theme.textTertiary
            Text {
                anchors.centerIn: parent; width: parent.width * 0.85
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: "This widget isn't available."
                color: theme.textSecondary; font.pixelSize: 13
            }
        }
    }

    // Inject the shared bindings into a freshly-loaded widget instance. Used by
    // both the tile loaders and the expanded overlay so they share state.
    function injectWidget(item, id, type, isExpanded) {
        if (!item) return
        store.ensureSettings(id, catalog.defaults(type))
        item.instanceId = id
        item.store = store
        item.expanded = isExpanded
        item.metrics = Qt.binding(function () { return dashboard.metrics })
        item.settings = Qt.binding(function () { store.revision; return store.settingsFor(id) })
        if (item.hasOwnProperty("tick"))
            item.tick = Qt.binding(function () { return dashboard._tick })
    }

    // ── Pages ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.spacingMd
        spacing: theme.spacingSm

        SwipeView {
            id: swipeView
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            interactive: !dashboard.editMode

            Repeater {
                model: store.revision, store.pages()
                delegate: Item {
                    id: pageItem
                    required property int index
                    required property var modelData
                    property var tiles: modelData.tiles || []

                    // Responsive grid: aim for ~380px-wide tiles, capped at 6 cols.
                    property int cols: Math.max(1, Math.min(6, Math.floor(width / 380)))

                    GridLayout {
                        anchors.fill: parent
                        columns: pageItem.cols
                        rowSpacing: theme.spacingMd
                        columnSpacing: theme.spacingMd

                        Repeater {
                            model: pageItem.tiles
                            delegate: Item {
                                id: cell
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 120

                                scale: tapMA.pressed && !dashboard.editMode ? 0.98 : 1.0
                                Behavior on scale { NumberAnimation { duration: theme.motionFast; easing.type: Easing.OutCubic } }

                                Loader {
                                    id: tileLd
                                    anchors.fill: parent
                                    clip: true
                                    property string wId: cell.modelData.id
                                    property string wType: cell.modelData.type
                                    active: wId !== "" && wType !== "" && catalog.source(wType) !== ""
                                    source: active ? catalog.source(wType) : ""
                                    onLoaded: {
                                        dashboard.injectWidget(item, wId, wType, false)
                                        if (item) item.active = Qt.binding(function () { return !dashboard.hasExpanded && !dashboard.editMode })
                                    }
                                }

                                // Expand affordance (glanceable hint, hidden in edit mode)
                                Text {
                                    anchors.right: parent.right; anchors.top: parent.top
                                    anchors.margins: theme.spacingMd
                                    text: "⤢"; font.pixelSize: 15
                                    color: theme.textTertiary; opacity: 0.5; z: 20
                                    visible: !dashboard.editMode
                                }

                                // Tap to expand (disabled while editing)
                                MouseArea {
                                    id: tapMA
                                    anchors.fill: parent
                                    enabled: !dashboard.editMode
                                    onClicked: {
                                        // Set id/color BEFORE type: assigning expandedType triggers the
                                        // (synchronous) overlay load + injectWidget, which reads expandedId.
                                        dashboard.expandedId = cell.modelData.id
                                        dashboard.expandedColor = theme.accent
                                        dashboard.expandedType = cell.modelData.type
                                    }
                                }

                                // ── Edit-mode overlay: reorder + remove ──
                                Rectangle {
                                    anchors.fill: parent
                                    visible: dashboard.editMode
                                    radius: theme.radiusLg
                                    color: Qt.rgba(0, 0, 0, 0.35)
                                    border.width: 2; border.color: theme.accent
                                    z: 30

                                    // wobble to signal editability
                                    RotationAnimation on rotation {
                                        running: dashboard.editMode && !root.reduceMotion
                                        loops: Animation.Infinite
                                        from: -0.4; to: 0.4; duration: 320
                                        easing.type: Easing.InOutSine
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: theme.spacingMd
                                        // move left
                                        Rectangle {
                                            Layout.preferredWidth: theme.touchSecondary; Layout.preferredHeight: theme.touchSecondary
                                            radius: width / 2; color: theme.cardBackgroundAlt; border.width: 1; border.color: theme.cardBorder
                                            visible: cell.index > 0
                                            Text { anchors.centerIn: parent; text: "◀"; font.pixelSize: 20; color: theme.textPrimary }
                                            MouseArea { anchors.fill: parent; onClicked: store.moveTile(pageItem.index, cell.index, cell.index - 1) }
                                        }
                                        // remove
                                        Rectangle {
                                            Layout.preferredWidth: theme.touchPrimary; Layout.preferredHeight: theme.touchPrimary
                                            radius: width / 2; color: Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.2)
                                            border.width: 2; border.color: theme.error
                                            Text { anchors.centerIn: parent; text: "🗑"; font.pixelSize: 24 }
                                            MouseArea { anchors.fill: parent; onClicked: store.removeTile(pageItem.index, cell.modelData.id) }
                                        }
                                        // move right
                                        Rectangle {
                                            Layout.preferredWidth: theme.touchSecondary; Layout.preferredHeight: theme.touchSecondary
                                            radius: width / 2; color: theme.cardBackgroundAlt; border.width: 1; border.color: theme.cardBorder
                                            visible: cell.index < pageItem.tiles.length - 1
                                            Text { anchors.centerIn: parent; text: "▶"; font.pixelSize: 20; color: theme.textPrimary }
                                            MouseArea { anchors.fill: parent; onClicked: store.moveTile(pageItem.index, cell.index, cell.index + 1) }
                                        }
                                    }
                                }
                            }
                        }

                        // "Add widget" placeholder tile (edit mode only).
                        // visible:false makes GridLayout skip it so tiles fill the
                        // page height when not editing.
                        Loader {
                            active: dashboard.editMode
                            visible: dashboard.editMode
                            Layout.fillWidth: true; Layout.fillHeight: true
                            Layout.minimumHeight: 120
                            sourceComponent: Rectangle {
                                radius: theme.radiusLg
                                color: "transparent"
                                border.width: 2; border.color: theme.cardBorder
                                Column {
                                    anchors.centerIn: parent; spacing: 6
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "＋"; font.pixelSize: 40; color: theme.accent }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Add widget"; font.pixelSize: 14; color: theme.textSecondary }
                                }
                                MouseArea { anchors.fill: parent; onClicked: { picker.pageIndex = pageItem.index; picker.shown = true } }
                            }
                        }
                    }

                    // Empty-page hint
                    Text {
                        anchors.centerIn: parent
                        visible: pageItem.tiles.length === 0 && !dashboard.editMode
                        text: "This page is empty.\nTap ✎ Edit to add widgets."
                        horizontalAlignment: Text.AlignHCenter
                        color: theme.textTertiary; font.pixelSize: 16
                    }
                }
            }
        }

        // ── Bottom bar ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: theme.touchSecondary
            spacing: theme.spacingMd

            Text {
                Layout.preferredWidth: theme.touchSecondary * 2.4
                text: store.pageCount() > 0 && swipeView.currentIndex < store.pageCount()
                      ? store.pages()[swipeView.currentIndex].name : ""
                font.pixelSize: theme.fontLabel; font.weight: Font.DemiBold
                font.family: theme.fontDisplay; color: theme.textSecondary
                elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
            }

            PageIndicator {
                Layout.alignment: Qt.AlignCenter; Layout.fillWidth: true
                count: swipeView.count; currentIndex: swipeView.currentIndex
                interactive: true
                onCurrentIndexChanged: if (currentIndex !== swipeView.currentIndex) swipeView.currentIndex = currentIndex
                delegate: Rectangle {
                    required property int index
                    implicitWidth: index === swipeView.currentIndex ? 22 : 10
                    implicitHeight: 10; radius: 5; color: theme.accent
                    opacity: index === swipeView.currentIndex ? 0.95 : 0.3
                    Behavior on implicitWidth { NumberAnimation { duration: theme.motionFast } }
                    Behavior on opacity { NumberAnimation { duration: theme.motionFast } }
                }
            }

            // Add page (edit mode)
            BarButton { glyph: "＋📄"; visible: dashboard.editMode; onClicked: store.addPage("") }
            // Remove current page (edit mode, keep ≥1)
            BarButton { glyph: "🗑📄"; visible: dashboard.editMode && store.pageCount() > 1
                        onClicked: { var i = swipeView.currentIndex; store.removePage(i) } }
            // Edit toggle
            BarButton {
                glyph: dashboard.editMode ? "✓" : "✎"
                highlighted: dashboard.editMode
                onClicked: { dashboard.editMode = !dashboard.editMode; if (!dashboard.editMode) store.flushNow() }
            }
            // Appearance
            BarButton { glyph: "🎨"; onClicked: settings.shown = true }
            // Diagnostics
            BarButton {
                glyph: "⚙"
                onClicked: if (dashboard.host) dashboard.host.push("qrc:/qml/Diagnostics.qml", {
                    "metricsJson": Qt.binding(function () { return metricsJson }),
                    "screensData": screensData,
                    "configJson": (typeof configBridge !== "undefined" && configBridge) ? configBridge.configJson() : ""
                })
            }
        }
    }

    // Small reusable bottom-bar button.
    component BarButton: Rectangle {
        property string glyph: ""
        property bool highlighted: false
        signal clicked()
        Layout.preferredWidth: theme.touchSecondary
        Layout.preferredHeight: theme.touchSecondary
        radius: theme.radiusMd
        color: highlighted ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.22)
                           : (bMA.containsMouse ? theme.cardBackground : "transparent")
        border.width: 1; border.color: highlighted ? theme.accent : theme.cardBorder
        Text { anchors.centerIn: parent; text: glyph; font.pixelSize: 20; color: theme.textPrimary }
        MouseArea { id: bMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    // ── Expanded overlay (shares the tile's persisted settings) ──────────────
    Rectangle {
        id: overlay
        anchors.fill: parent
        z: 100
        visible: dashboard.hasExpanded || opacity > 0.01
        opacity: dashboard.hasExpanded ? 1.0 : 0.0
        scale: dashboard.hasExpanded ? 1.0 : 0.97
        Behavior on opacity { NumberAnimation { duration: theme.motionFast } }
        Behavior on scale { NumberAnimation { duration: theme.motionPage; easing.type: Easing.OutCubic } }

        // Backdrop
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: theme.backgroundColor }
                GradientStop { position: 1.0; color: theme.backgroundColor2 }
            }
        }
        Rectangle {
            anchors.fill: parent; opacity: 0.09
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: dashboard.expandedColor }
                GradientStop { position: 0.45; color: "transparent" }
            }
        }

        // Modal input barrier — absorbs every tap so nothing reaches the
        // dashboard behind. Declared before the header/content, which stay on top.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onClicked: {}
            onPressed: {}
        }

        // Header: back button + title + description
        Item {
            id: ovlHeader
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            anchors.margins: theme.spacingLg
            height: Math.max(theme.touchSecondary, titleCol.implicitHeight)

            Rectangle {
                id: backBtn
                anchors.left: parent.left; anchors.top: parent.top
                width: theme.touchSecondary; height: theme.touchSecondary; radius: theme.radiusMd
                color: backMA.pressed ? theme.cardBackgroundAlt : theme.cardBackground
                border.width: 1; border.color: theme.cardBorder
                Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 26; color: theme.textPrimary }
                MouseArea { id: backMA; anchors.fill: parent; onClicked: { dashboard.expandedType = ""; dashboard.expandedId = "" } }
            }
            Column {
                id: titleCol
                anchors.left: backBtn.right; anchors.leftMargin: theme.spacingLg
                anchors.right: parent.right; anchors.top: parent.top
                spacing: 3
                Row {
                    spacing: theme.spacingSm
                    Text { text: catalog.icon(dashboard.expandedType); font.pixelSize: theme.fontTitle + 8 }
                    Text { text: catalog.title(dashboard.expandedType); font.pixelSize: theme.fontTitle + 8
                        font.bold: true; font.family: theme.fontDisplay; color: theme.textPrimary }
                }
                Text {
                    width: parent.width
                    text: catalog.desc(dashboard.expandedType)
                    font.pixelSize: theme.fontLabel; color: theme.textSecondary
                    wrapMode: Text.WordWrap; visible: text.length > 0
                }
            }
        }

        // Content — a card that FILLS the whole area below the header.
        Rectangle {
            id: ovlCard
            anchors.top: ovlHeader.bottom; anchors.topMargin: theme.spacingMd
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.leftMargin: theme.spacingLg; anchors.rightMargin: theme.spacingLg
            anchors.bottomMargin: theme.spacingLg
            radius: theme.radiusLg
            color: theme.cardFill()
            border.width: 1; border.color: theme.cardBorder
            clip: true

            Loader {
                id: ovlLoader
                anchors.fill: parent
                anchors.margins: theme.spacingLg
                active: dashboard.hasExpanded && catalog.source(dashboard.expandedType) !== ""
                source: active ? catalog.source(dashboard.expandedType) : ""
                onLoaded: {
                    dashboard.injectWidget(item, dashboard.expandedId, dashboard.expandedType, true)
                    if (item) {
                        item.active = true
                        // Card chrome is provided by ovlCard; hide the widget's own.
                        if (item.hasOwnProperty("showHeader")) item.showHeader = false
                        if (item.hasOwnProperty("chromeless")) item.chromeless = true
                    }
                }
            }
        }
    }

    // ── Add-widget picker (edit mode) ────────────────────────────────────────
    Rectangle {
        id: picker
        anchors.fill: parent; z: 200
        property bool shown: false
        property int pageIndex: 0
        visible: shown || opacity > 0.01
        opacity: shown ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: theme.motionFast } }
        color: Qt.rgba(0, 0, 0, 0.6)
        MouseArea { anchors.fill: parent; onClicked: picker.shown = false }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.9, 1100); height: Math.min(parent.height * 0.85, 620)
            radius: theme.radiusXl; color: theme.cardBackground; border.width: 1; border.color: theme.cardBorder
            MouseArea { anchors.fill: parent } // swallow clicks

            ColumnLayout {
                anchors.fill: parent; anchors.margins: theme.spacingLg; spacing: theme.spacingMd
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Add a widget"; font.pixelSize: 22; font.bold: true; color: theme.textPrimary; Layout.fillWidth: true }
                    Rectangle {
                        width: theme.touchSecondary; height: theme.touchSecondary; radius: width / 2; color: theme.cardBackgroundAlt
                        Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 20; color: theme.textPrimary }
                        MouseArea { anchors.fill: parent; onClicked: picker.shown = false }
                    }
                }
                Flickable {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    contentHeight: pickerCol.implicitHeight
                    ColumnLayout {
                        id: pickerCol; width: parent.width; spacing: theme.spacingMd
                        Repeater {
                            model: catalog.categories()
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true; spacing: theme.spacingSm
                                Text { text: modelData; font.pixelSize: 14; font.bold: true; color: theme.textSecondary }
                                Flow {
                                    Layout.fillWidth: true; spacing: theme.spacingSm
                                    Repeater {
                                        model: catalog.inCategory(modelData)
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 200; height: theme.touchPrimary; radius: theme.radiusMd
                                            color: pickMA.containsMouse ? theme.cardBackgroundAlt : theme.backgroundColor
                                            border.width: 1; border.color: theme.cardBorder
                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: theme.spacingSm; spacing: theme.spacingSm
                                                Text { text: modelData.icon; font.pixelSize: 22 }
                                                Text { text: modelData.title; font.pixelSize: 15; color: theme.textPrimary; Layout.fillWidth: true; elide: Text.ElideRight }
                                                Text { text: "＋"; font.pixelSize: 20; color: theme.accent }
                                            }
                                            MouseArea {
                                                id: pickMA; anchors.fill: parent; hoverEnabled: true
                                                onClicked: { store.addTile(picker.pageIndex, modelData.type); picker.shown = false }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Appearance / settings overlay
    SettingsPanel {
        id: settings
        onCloseRequested: shown = false
    }
}
