import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// Xeneon Edge Manager — companion desktop UI. Reuses the hub's DashboardStore
// (persistence + mutations) and WidgetCatalog (available widgets). Every edit
// flows through the store, which persists via `configBridge` (the C++
// ManagerBackend) and pushes live to a running hub.
ApplicationWindow {
    id: win
    // Open large enough that the fit-to-fit Edge clone reads clearly (the whole
    // page visible without scrolling, ~half of the panel's 2560px tall), but
    // never larger than the screen — clamp so it fits smaller laptop displays.
    width: Math.min(1440, Screen.desktopAvailableWidth - 80)
    height: Math.min(1300, Screen.desktopAvailableHeight - 80)
    minimumWidth: Math.min(1120, Screen.desktopAvailableWidth - 40)
    minimumHeight: Math.min(760, Screen.desktopAvailableHeight - 40)
    visible: true
    title: "Xeneon Edge Manager"
    color: m.bg

    // --- Local design tokens (kept consistent with the hub) ---
    QtObject {
        id: m
        readonly property color bg: "#0D1117"
        readonly property color panel: "#161B22"
        readonly property color panelAlt: "#1C222B"
        readonly property color border: "#30363D"
        readonly property color textPrimary: "#E6EDF3"
        readonly property color textSecondary: "#8B949E"
        // Chrome stays dark, but the ACCENT follows the user's chosen Edge accent
        // so selection highlights match what they picked (falls back to blue).
        readonly property color accent: theme.accent
        readonly property color textOnAccent: "#0D1117"    // legible text on the accent
        readonly property color success: "#3FB950"
        readonly property color danger: "#F85149"
        readonly property int radius: 12
        readonly property int touch: 44
        readonly property var accentPresets: [
            { name: "blue", c: "#58A6FF" }, { name: "purple", c: "#A371F7" },
            { name: "green", c: "#3FB950" }, { name: "orange", c: "#F0883E" },
            { name: "pink", c: "#F778BA" }, { name: "teal", c: "#56D4DD" },
            { name: "red", c: "#F85149" }, { name: "gold", c: "#E3B341" }
        ]
    }

    // ── Reusable, token-styled controls (inline so they capture `m`/`theme`) ──
    // Replaces the default Fusion Switch/Button, which ignored the chosen accent
    // and clashed with the hand-drawn UI. MButton also takes an optional AppIcon
    // so callers stop hand-typing emoji glyphs.
    component MButton: Button {
        id: mbtn
        property string iconName: ""
        property bool primary: false
        property color tone: primary ? m.accent : m.panel
        implicitHeight: 40; hoverEnabled: true
        contentItem: Item {
            implicitWidth: mbtnRow.implicitWidth; implicitHeight: mbtnRow.implicitHeight
            Row {
                id: mbtnRow; anchors.centerIn: parent; spacing: 8
                AppIcon {
                    visible: mbtn.iconName !== ""; name: mbtn.iconName; size: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: mbtn.primary ? m.textOnAccent : m.textPrimary
                }
                Text {
                    text: mbtn.text; anchors.verticalCenter: parent.verticalCenter
                    color: mbtn.primary ? m.textOnAccent : m.textPrimary
                    font.pixelSize: 14; font.bold: mbtn.primary
                }
            }
        }
        background: Rectangle {
            radius: m.radius
            color: mbtn.primary
                   ? (mbtn.down ? Qt.darker(mbtn.tone, 1.2) : (mbtn.hovered ? Qt.lighter(mbtn.tone, 1.1) : mbtn.tone))
                   : (mbtn.down || mbtn.hovered ? m.panelAlt : m.panel)
            border.width: mbtn.primary ? 0 : 1
            border.color: m.border
        }
    }

    component MSwitch: Switch {
        id: msw
        implicitHeight: 30
        indicator: Rectangle {
            implicitWidth: 46; implicitHeight: 26; radius: 13
            x: msw.leftPadding; anchors.verticalCenter: parent.verticalCenter
            color: msw.checked ? m.accent : m.panelAlt
            border.width: 1; border.color: msw.checked ? m.accent : m.border
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
                x: msw.checked ? parent.width - width - 3 : 3
                y: 3; width: 20; height: 20; radius: 10
                color: msw.checked ? m.textOnAccent : m.textSecondary
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
        }
        contentItem: Text {
            text: msw.text; color: m.textPrimary; font.pixelSize: 14
            verticalAlignment: Text.AlignVCenter
            leftPadding: msw.indicator.width + 10
        }
    }

    // Shared hub model + registry.
    DashboardStore { id: store }
    WidgetCatalog { id: catalog }
    WallpaperCatalog { id: bundledWallpapers }
    BackgroundCatalog { id: bgCatalog }

    // Colour tokens + the user's uploaded images, for the shared BackgroundPicker.
    readonly property var mCol: ({ textPrimary: m.textPrimary, textSecondary: m.textSecondary,
        panel: m.panel, panelAlt: m.panelAlt, border: m.border, accent: m.accent, radius: m.radius })
    property var uploadedWallpapers: {
        var out = []
        for (var i = 0; i < imagesModel.count; i++) {
            var nm = imagesModel.get(i).modelData
            out.push({ label: nm, source: backend.imageUrl(nm) })
        }
        return out
    }

    // Full design-system theme + a media stub, so the WYSIWYG clone renders the
    // REAL widgets exactly like the Edge. Driven from the store's appearance.
    Theme { id: theme }
    MockMedia { id: media }

    property int currentPageIndex: 0
    // Transient "Starting hub…" feedback: set when the user hits Start, cleared
    // when the hub connects (see the backend Connections) or a safety timeout.
    property bool hubStarting: false
    Timer { id: hubStartTimeout; interval: 8000; repeat: false
        onTriggered: win.hubStarting = false }

    function currentPageName() {
        var p = store.pages()[currentPageIndex]
        return p ? p.name : ""
    }
    // Keep the rename field in step with the selected page WITHOUT a `text:` binding
    // (a binding breaks the moment the user types, which caused wrong-page renames).
    onCurrentPageIndexChanged: pageName.text = currentPageName()

    // Guard against re-applying the whole theme on every store bump: the store
    // fires `changed()` on every keystroke/tile edit, but only appearance changes
    // need a re-theme. Skip when the appearance payload is byte-identical.
    property string _appearanceSig: ""
    function syncTheme() {
        var a = store.appearance() || ({})
        var sig = JSON.stringify(a)
        if (sig === _appearanceSig) return
        _appearanceSig = sig
        theme.applyTheme(a.themeMode || "dark")
        if (a.accent) theme.applyAccent(a.accent)
        theme.glassOpacity = a.glass !== undefined ? a.glass : 0.55
        theme.showWidgetGlow = a.glow !== undefined ? a.glow : true
        theme.reduceMotion = a.reduceMotion || false
    }
    Connections { target: store; function onChanged() { win.syncTheme() } }

    Component.onCompleted: { store.load(backend.starterLayout()); syncTheme(); refreshImages() }

    // Capture helper: XENEON_CFG=<type> auto-opens that widget's config dialog.
    Timer {
        interval: 500; running: backend.autoConfig().length > 0; repeat: false
        onTriggered: {
            var t = backend.autoConfig(), pages = store.pages()
            for (var p = 0; p < pages.length; p++) {
                var ts = pages[p].tiles || []
                for (var i = 0; i < ts.length; i++)
                    if (ts[i].type === t) { win.currentPageIndex = p; cfgDialog.openFor(ts[i].id, t); return }
            }
        }
    }

    // Helper: current page's tiles (revision-reactive).
    function pageTiles() {
        store.revision
        var pages = store.pages()
        if (currentPageIndex < 0 || currentPageIndex >= pages.length) return []
        return pages[currentPageIndex].tiles || []
    }

    // ── Root layout: sidebar + content ──
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar
        Rectangle {
            Layout.preferredWidth: 240
            Layout.fillHeight: true
            color: m.panel
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                Text { text: "Xeneon Edge"; color: m.textPrimary; font.pixelSize: 20; font.bold: true }
                Text { text: "Manager"; color: m.accent; font.pixelSize: 14 }
                Text {
                    text: (backend && backend.appVersion ? backend.appVersion() : "?")
                    color: m.textSecondary; font.pixelSize: 11; font.family: theme.fontMono
                    Layout.bottomMargin: 12; Layout.fillWidth: true; elide: Text.ElideRight
                }

                Repeater {
                    model: [ { l: "Layout", i: "ui-layout" }, { l: "Appearance", i: "ui-palette" },
                             { l: "Images", i: "ui-image" }, { l: "Display", i: "ui-display" } ]
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: m.radius
                        color: nav.currentIndex === index ? m.accent
                               : (navMA.containsMouse ? m.panelAlt : "transparent")
                        RowLayout {
                            anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left
                            anchors.leftMargin: 14; spacing: 10
                            AppIcon { name: modelData.i; size: 20
                                color: nav.currentIndex === index ? "#0D1117" : m.textSecondary }
                            Text {
                                text: modelData.l
                                color: nav.currentIndex === index ? "#0D1117" : m.textPrimary
                                font.pixelSize: 15; font.bold: nav.currentIndex === index
                            }
                        }
                        MouseArea { id: navMA; anchors.fill: parent; hoverEnabled: true
                            onClicked: nav.currentIndex = index }
                    }
                }

                Item { Layout.fillHeight: true }

                // Hub connection status + Start/Stop control.
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 10
                    RowLayout {
                        spacing: 8; Layout.fillWidth: true
                        Rectangle { width: 10; height: 10; radius: 5
                            color: backend.hubConnected ? m.success
                                   : (win.hubStarting ? m.accent : m.textSecondary) }
                        Text {
                            Layout.fillWidth: true
                            text: backend.hubConnected ? "Hub connected (live)"
                                  : (win.hubStarting ? "Starting hub…" : "Hub offline (saved)")
                            color: m.textSecondary; font.pixelSize: 12; elide: Text.ElideRight
                        }
                    }
                    MButton {
                        Layout.fillWidth: true; implicitHeight: 36
                        enabled: !win.hubStarting
                        text: backend.hubConnected ? "Stop hub" : "Start hub"
                        iconName: backend.hubConnected ? "ui-close" : "ui-play"
                        primary: !backend.hubConnected
                        onClicked: {
                            if (backend.hubConnected) {
                                backend.stopHub()
                            } else {
                                win.hubStarting = true
                                if (!backend.startHub()) win.hubStarting = false
                                else hubStartTimeout.restart()
                            }
                        }
                    }
                }
            }
        }

        // Content
        StackLayout {
            id: nav
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: backend.startTab()

            // ═══ 1. LAYOUT ═══
            Item {
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 16

                    Text { text: "Layout"; color: m.textPrimary; font.pixelSize: 24; font.bold: true }
                    Text { text: "Arrange the widgets shown on each page of your Edge."
                        color: m.textSecondary; font.pixelSize: 14 }

                    // Page selector
                    Flow {
                        Layout.fillWidth: true; spacing: 8
                        Repeater {
                            // Structural list — rebuild only when pages are added/
                            // removed/renamed, not on every settings keystroke [S11].
                            model: (store.structureRevision, store.pages())
                            delegate: Rectangle {
                                required property int index
                                required property var modelData
                                width: pageLbl.implicitWidth + 32; height: m.touch
                                radius: m.radius
                                color: win.currentPageIndex === index ? m.accent : m.panel
                                border.width: 1; border.color: m.border
                                Text { id: pageLbl; anchors.centerIn: parent; text: modelData.name
                                    color: win.currentPageIndex === index ? "#0D1117" : m.textPrimary
                                    font.pixelSize: 14; font.bold: win.currentPageIndex === index }
                                MouseArea { anchors.fill: parent; onClicked: win.currentPageIndex = index }
                            }
                        }
                        Rectangle {
                            width: m.touch; height: m.touch; radius: m.radius
                            color: m.panel; border.width: 1; border.color: m.border
                            AppIcon { anchors.centerIn: parent; name: "ui-plus"; color: m.accent; size: 22 }
                            MouseArea { anchors.fill: parent
                                onClicked: { store.addPage(""); win.currentPageIndex = store.pageCount() - 1 } }
                        }
                    }

                    // Page tools
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text { text: "Page name:"; color: m.textSecondary; font.pixelSize: 13
                            Layout.alignment: Qt.AlignVCenter }
                        TextField {
                            id: pageName; Layout.preferredWidth: 240; Layout.preferredHeight: m.touch
                            color: m.textPrimary; selectByMouse: true
                            Component.onCompleted: text = win.currentPageName()
                            background: Rectangle { radius: 8; color: m.panel; border.width: 1
                                border.color: pageName.activeFocus ? m.accent : m.border }
                            // Commit on Enter/blur, then reflect the validated (trimmed/
                            // de-duped) name the store actually stored.
                            onEditingFinished: {
                                store.renamePage(win.currentPageIndex, text)
                                text = win.currentPageName()
                            }
                        }
                        Item { Layout.fillWidth: true }
                        MButton { text: "Remove page"; iconName: "ui-trash"
                            enabled: (store.revision, store.pageCount() > 1)
                            onClicked: {
                                var removed = win.currentPageIndex
                                store.removePage(removed)
                                // Stay on the page that slid into this slot (clamped).
                                win.currentPageIndex = Math.min(removed, store.pageCount() - 1)
                            } }
                    }

                    // This page's background — one control, overrides the global
                    // default for THIS page ("Use global" drops the override).
                    Text { text: "This page's background"; color: m.textPrimary; font.pixelSize: 14; font.bold: true
                        Layout.topMargin: 4 }
                    Text { text: "Overrides the global default (set in Appearance) for the current page only."
                        color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    BackgroundPicker {
                        Layout.fillWidth: true
                        store: store; pageIndex: win.currentPageIndex; col: win.mCol
                        bgCatalog: bgCatalog; wpCatalog: bundledWallpapers; uploadedImages: win.uploadedWallpapers
                    }

                    // Per-page columns (overrides the global default).
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text { text: "Columns:"; color: m.textSecondary; font.pixelSize: 14; Layout.alignment: Qt.AlignVCenter }
                        Repeater {
                            model: [ { v: 0, l: "Global" }, { v: 1, l: "1 column" }, { v: 2, l: "2 columns" } ]
                            delegate: Rectangle {
                                required property var modelData
                                width: colLbl.implicitWidth + 24; height: m.touch; radius: m.radius
                                property bool sel: (store.revision, store.pageColumns(win.currentPageIndex)) === modelData.v
                                color: sel ? m.accent : m.panel; border.width: 1; border.color: m.border
                                Text { id: colLbl; anchors.centerIn: parent; text: modelData.l
                                    color: sel ? "#0D1117" : m.textPrimary; font.pixelSize: 13 }
                                MouseArea { anchors.fill: parent
                                    onClicked: store.setPageColumns(win.currentPageIndex, modelData.v) }
                            }
                        }
                    }

                    // Tiles on the current page
                    RowLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 16

                        // Live WYSIWYG clone of the Edge — drag tiles to reorder,
                        // drag the bottom handle to resize, ⚙ to configure, ✕ to remove.
                        EdgeClone {
                            id: edgeClone
                            Layout.fillHeight: true
                            Layout.preferredWidth: 440
                            pageIndex: win.currentPageIndex
                            onConfigRequested: (tileId, tileType) => cfgDialog.openFor(tileId, tileType)
                        }

                        // Helper column.
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: 12
                            MButton { text: "Add widget"; iconName: "ui-plus"; primary: true
                                Layout.fillWidth: true; Layout.preferredHeight: m.touch
                                onClicked: addPicker.open() }
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: hintCol.implicitHeight + 24
                                radius: m.radius; color: m.panel; border.width: 1; border.color: m.border
                                ColumnLayout {
                                    id: hintCol; anchors.fill: parent; anchors.margins: 12; spacing: 6
                                    Text { text: "This is your Edge"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                                    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: m.textSecondary; font.pixelSize: 13
                                        text: "• Tap a tile (or ⚙) to configure it\n• Drag a tile onto another to reorder\n• Drag the ⤡ corner to resize (width & height)\n• Switch 1 / 2 columns above\n• ✕ removes a tile\nChanges apply live to the display." }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }

            // ═══ 2. APPEARANCE ═══
            Item {
              ScrollView {
                id: apScroll
                anchors.fill: parent; clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: apScroll.availableWidth - 48
                    x: 24; y: 24; spacing: 18
                    Text { text: "Appearance"; color: m.textPrimary; font.pixelSize: 24; font.bold: true }

                    Text { text: "Theme"; color: m.textSecondary; font.pixelSize: 14 }
                    Flow {
                        Layout.fillWidth: true; spacing: 10
                        Repeater {
                            model: [
                                { k: "dark",          n: "Dark",     c1: "#161B22", c2: "#0A0E14" },
                                { k: "midnight",      n: "Midnight", c1: "#1B1247", c2: "#070A1C" },
                                { k: "aurora",        n: "Aurora",   c1: "#0C2E3A", c2: "#111C40" },
                                { k: "sunset",        n: "Sunset",   c1: "#3A1230", c2: "#40161C" },
                                { k: "nebula",        n: "Nebula",   c1: "#2A1048", c2: "#120A2E" },
                                { k: "oled",          n: "OLED",     c1: "#0A0A0A", c2: "#000000" },
                                { k: "light",         n: "Light",    c1: "#F6F8FA", c2: "#E4E9F0" },
                                { k: "high_contrast", n: "Contrast", c1: "#1A1A1A", c2: "#000000" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: 150; height: 80; radius: m.radius; clip: true
                                property bool sel: (store.revision, store.appearance().themeMode || "dark") === modelData.k
                                border.width: sel ? 3 : 1; border.color: sel ? m.accent : m.border
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: modelData.c1 }
                                    GradientStop { position: 1.0; color: modelData.c2 }
                                }
                                Text { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8
                                    text: modelData.n; font.pixelSize: 14; font.bold: true
                                    color: modelData.k === "light" ? "#1F2328" : "#FFFFFF" }
                                Rectangle { visible: parent.sel; anchors.top: parent.top; anchors.right: parent.right
                                    anchors.margins: 6; width: 22; height: 22; radius: 11; color: m.accent
                                    AppIcon { anchors.centerIn: parent; name: "ui-check"; size: 13; color: m.textOnAccent } }
                                MouseArea { anchors.fill: parent
                                    onClicked: store.setAppearance("themeMode", modelData.k) }
                            }
                        }
                    }

                    Text { text: "Accent"; color: m.textSecondary; font.pixelSize: 14 }
                    Flow {
                        Layout.fillWidth: true; spacing: 10
                        Repeater {
                            model: m.accentPresets
                            delegate: Rectangle {
                                required property var modelData
                                property bool sel: (store.revision, store.appearance().accent === modelData.name)
                                width: 46; height: 46; radius: 23; color: modelData.c
                                border.width: sel ? 3 : 0
                                border.color: m.textPrimary
                                AppIcon { visible: parent.sel; anchors.centerIn: parent
                                    name: "ui-check"; size: 20; color: "#FFFFFF" }
                                MouseArea { anchors.fill: parent
                                    onClicked: store.setAppearance("accent", modelData.name) }
                            }
                        }
                    }

                    Text { text: "Background (global default)"; color: m.textPrimary; font.pixelSize: 15; font.bold: true
                        Layout.topMargin: 4 }
                    Text { text: "Pick an animated style OR a wallpaper — this is the default for every page. A page can override it in the Layout tab."
                        color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    RowLayout { visible: !theme.decorative; Layout.fillWidth: true; spacing: 6
                        AppIcon { name: "ui-warning"; size: 14; color: m.danger; Layout.alignment: Qt.AlignTop }
                        Text { text: "The High Contrast theme keeps backgrounds off for legibility — switch themes to see them."
                            color: m.danger; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap } }
                    BackgroundPicker {
                        Layout.fillWidth: true
                        store: store; pageIndex: -1; col: win.mCol
                        bgCatalog: bgCatalog; wpCatalog: bundledWallpapers; uploadedImages: win.uploadedWallpapers
                    }

                    Text { text: "Layout columns (default)"; color: m.textSecondary; font.pixelSize: 14 }
                    Flow {
                        Layout.fillWidth: true; spacing: 8
                        Repeater {
                            model: [ { v: 1, l: "1 column" }, { v: 2, l: "2 columns" } ]
                            delegate: Rectangle {
                                required property var modelData
                                width: 150; height: m.touch; radius: m.radius
                                property bool sel: (store.revision, store.appearance().gridCols || 1) === modelData.v
                                color: sel ? m.accent : m.panel; border.width: 1; border.color: m.border
                                Text { anchors.centerIn: parent; text: modelData.l
                                    color: sel ? "#0D1117" : m.textPrimary; font.pixelSize: 14 }
                                MouseArea { anchors.fill: parent
                                    onClicked: store.setAppearance("gridCols", modelData.v) }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        Text { text: "Glassiness"; color: m.textSecondary; font.pixelSize: 14; Layout.preferredWidth: 120 }
                        Slider {
                            id: glassSlider; Layout.fillWidth: true; from: 0; to: 1
                            value: { store.revision; var g = store.appearance().glass; return g === undefined ? 0.55 : g }
                            // Live-preview the theme while dragging (cheap: opacity only),
                            // but debounce the persisted store write so we don't reapply the
                            // whole theme + save on every frame.
                            onMoved: { theme.glassOpacity = value; glassCommit.restart() }
                            Timer { id: glassCommit; interval: 180; repeat: false
                                onTriggered: {
                                    store.setAppearance("glass", glassSlider.value)
                                    // Restore the `value:` binding that dragging severed, so a
                                    // later store/hub push still moves the slider [S2]. Store
                                    // now equals the slider, so this re-bind causes no jump.
                                    glassSlider.value = Qt.binding(function() { store.revision; var g = store.appearance().glass; return g === undefined ? 0.55 : g })
                                } }
                        }
                        Text { text: Math.round(glassSlider.value * 100) + "%"
                            color: m.textPrimary; font.pixelSize: 13; font.bold: true
                            Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                    }

                    RowLayout {
                        spacing: 20
                        // A Switch severs its `checked:` binding on first toggle, so
                        // without re-asserting it here a later store/hub push could
                        // never move the control again [S2]. Re-bind after each write.
                        MSwitch {
                            text: "Widget glow"
                            checked: { store.revision; var g = store.appearance().glow; return g === undefined ? true : g }
                            onToggled: {
                                store.setAppearance("glow", checked)
                                checked = Qt.binding(function() { store.revision; var g = store.appearance().glow; return g === undefined ? true : g })
                            }
                        }
                        MSwitch {
                            text: "Animated background"
                            checked: { store.revision; var g = store.appearance().animatedBg; return g === undefined ? true : g }
                            onToggled: {
                                store.setAppearance("animatedBg", checked)
                                checked = Qt.binding(function() { store.revision; var g = store.appearance().animatedBg; return g === undefined ? true : g })
                            }
                        }
                        MSwitch {
                            text: "Reduce motion"
                            checked: (store.revision, store.appearance().reduceMotion || false)
                            onToggled: {
                                store.setAppearance("reduceMotion", checked)
                                checked = Qt.binding(function() { store.revision; return store.appearance().reduceMotion || false })
                            }
                        }
                    }
                    Item { Layout.preferredHeight: 12 }   // bottom padding
                }
              }
            }

            // ═══ 3. IMAGES ═══
            Item {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 24; spacing: 16
                    Text { text: "Images"; color: m.textPrimary; font.pixelSize: 24; font.bold: true }
                    Text { text: "Upload your own images here — they then appear as wallpaper options in the background picker (Appearance → Background, or per-page in Layout)."
                        color: m.textSecondary; font.pixelSize: 14; Layout.fillWidth: true; wrapMode: Text.WordWrap }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        MButton { text: "Import image…"; iconName: "ui-plus"; primary: true
                            Layout.preferredHeight: m.touch; onClicked: fileDialog.open() }
                        Item { Layout.fillWidth: true }
                    }

                    Text { text: "Your images"; color: m.textSecondary; font.pixelSize: 14; font.bold: true }
                    Text { text: "Click an image to use it as the wallpaper."
                        color: m.textSecondary; font.pixelSize: 12; visible: imagesModel.count > 0 }
                    // Empty state.
                    Text { visible: imagesModel.count === 0; Layout.fillWidth: true; Layout.topMargin: 24
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: "No images yet — use “Import image…” to add one."
                        color: m.textSecondary; font.pixelSize: 14 }
                    ScrollView {
                        visible: imagesModel.count > 0
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                        GridView {
                            id: imgGrid
                            cellWidth: 190; cellHeight: 190
                            model: imagesModel
                            delegate: Rectangle {
                                id: imgCard
                                required property var modelData
                                width: 180; height: 180; radius: m.radius
                                // Wallpapers are stored as file:// URLs (matching the
                                // BackgroundPicker), so compare against that form.
                                property string fullPath: backend.imageUrl(modelData)
                                property bool isWall: (store.revision, store.appearance().wallpaper) === fullPath
                                color: cardMA.containsMouse ? m.panelAlt : m.panel
                                border.width: isWall ? 3 : 1; border.color: isWall ? m.accent : m.border
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 8; spacing: 4
                                    Image {
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        source: imgCard.fullPath
                                        fillMode: Image.PreserveAspectCrop; asynchronous: true; clip: true
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        AppIcon { visible: imgCard.isWall; name: "ui-check"; size: 14; color: m.accent }
                                        Text { text: imgCard.isWall ? "wallpaper" : imgCard.modelData
                                            color: imgCard.isWall ? m.accent : m.textSecondary; font.pixelSize: 11
                                            elide: Text.ElideRight; Layout.fillWidth: true }
                                        // Bigger, padded delete hit target.
                                        Rectangle { Layout.preferredWidth: 30; Layout.preferredHeight: 26; radius: 6
                                            color: delMA.containsMouse ? Qt.rgba(m.danger.r, m.danger.g, m.danger.b, 0.18) : "transparent"
                                            AppIcon { anchors.centerIn: parent; name: "ui-trash"; size: 16; color: m.danger }
                                            MouseArea { id: delMA; anchors.fill: parent; hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: win.confirmDeleteImage(imgCard.modelData, imgCard.fullPath) } }
                                    }
                                }
                                // Click the card body → set as wallpaper.
                                MouseArea { id: cardMA; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    // Let the trash button win.
                                    onClicked: (mouse) => store.setAppearance("wallpaper", imgCard.fullPath)
                                    z: -1 }
                            }
                        }
                    }
                }
            }

            // ═══ 4. DISPLAY ═══
            Item {
              ScrollView {
                id: dpScroll
                anchors.fill: parent; clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: dpScroll.availableWidth - 48
                    x: 24; y: 24; spacing: 16
                    Text { text: "Display & Startup"; color: m.textPrimary; font.pixelSize: 24; font.bold: true }
                    Text { text: "Choose which screen the hub runs on. Applies next time the hub starts."
                        color: m.textSecondary; font.pixelSize: 14 }

                    Repeater {
                        model: win.screens
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; Layout.preferredHeight: 64
                            radius: m.radius; color: m.panel
                            border.width: modelData.name === win.currentTarget ? 2 : 1
                            border.color: modelData.name === win.currentTarget ? m.accent : m.border
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 12; spacing: 12
                                AppIcon { name: "ui-display"; color: m.textPrimary; size: 22 }
                                ColumnLayout {
                                    spacing: 0; Layout.fillWidth: true
                                    Text { text: (modelData.model || modelData.name) + (modelData.isEdge ? "  · Xeneon Edge" : "")
                                        color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                                    Text { text: modelData.name + "  ·  " + modelData.width + "×" + modelData.height
                                        color: m.textSecondary; font.pixelSize: 12 }
                                }
                                MButton {
                                    property bool isTarget: modelData.name === win.currentTarget
                                    text: isTarget ? "Target" : "Set as target"
                                    iconName: isTarget ? "ui-check" : ""
                                    primary: isTarget
                                    onClicked: { backend.setTargetDisplay(modelData.name, modelData.model)
                                        win.currentTarget = modelData.name } }
                            }
                        }
                    }

                    Text { text: "Orientation"; color: m.textSecondary; font.pixelSize: 14; Layout.topMargin: 8 }
                    Text { text: "Pick a fixed mode to rotate the dashboard for a wall/arm mount. Auto follows the system only when an orientation sensor is present."
                        color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    Flow {
                        Layout.fillWidth: true; spacing: 8
                        Repeater {
                            model: [ { v: "auto", l: "Auto" }, { v: "portrait", l: "Portrait" },
                                     { v: "landscape", l: "Landscape" }, { v: "inverted-portrait", l: "Portrait (flipped)" },
                                     { v: "inverted-landscape", l: "Landscape (flipped)" } ]
                            delegate: Rectangle {
                                required property var modelData
                                width: oriLbl.implicitWidth + 24; height: m.touch; radius: m.radius
                                property bool sel: (store.revision, store.appearance().orientation || "auto") === modelData.v
                                color: sel ? m.accent : m.panel; border.width: 1; border.color: m.border
                                Text { id: oriLbl; anchors.centerIn: parent; text: modelData.l
                                    color: sel ? "#0D1117" : m.textPrimary; font.pixelSize: 13 }
                                MouseArea { anchors.fill: parent
                                    onClicked: store.setAppearance("orientation", modelData.v) }
                            }
                        }
                    }

                    MSwitch {
                        id: autostartSwitch; text: "Start the hub automatically on login"
                        checked: backend.isAutostart()
                        // Toggling severs the `checked:` binding; re-read the backend's
                        // real state (the write can fail) so the control never diverges
                        // and onActiveChanged can keep refreshing it [S2].
                        onToggled: {
                            backend.setAutostart(checked)
                            checked = backend.isAutostart()
                        }
                    }
                    Item { Layout.preferredHeight: 12 }   // bottom padding
                }
              }
            }
        }
    }

    // ── Add-widget picker ──
    Dialog {
        id: addPicker
        title: "Add a widget"
        modal: true
        anchors.centerIn: parent
        width: 720; height: 560
        standardButtons: Dialog.Close
        background: Rectangle { color: m.panel; radius: m.radius; border.width: 1; border.color: m.border }
        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: addPicker.availableWidth
                spacing: 12
                Repeater {
                    model: catalog.categories()
                    delegate: ColumnLayout {
                        required property string modelData
                        Layout.fillWidth: true; spacing: 8
                        Text { text: modelData; color: m.textSecondary; font.pixelSize: 14; font.bold: true }
                        Flow {
                            Layout.fillWidth: true; spacing: 8
                            Repeater {
                                model: catalog.inCategory(modelData)
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 150; height: 84; radius: m.radius
                                    color: itemMA.containsMouse ? m.panelAlt : m.bg
                                    border.width: 1; border.color: m.border
                                    ColumnLayout {
                                        anchors.centerIn: parent; spacing: 4
                                        AppIcon { Layout.alignment: Qt.AlignHCenter; name: modelData.type; size: 26; color: m.textPrimary }
                                        Text { Layout.alignment: Qt.AlignHCenter; text: modelData.title
                                            color: m.textPrimary; font.pixelSize: 13 }
                                    }
                                    MouseArea { id: itemMA; anchors.fill: parent; hoverEnabled: true
                                        onClicked: { store.addTile(win.currentPageIndex, modelData.type); addPicker.close() } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Per-widget configure (schema-driven form + live preview) ──
    WidgetConfigDialog { id: cfgDialog }

    // ── Image import dialog + model ──
    FileDialog {
        id: fileDialog
        title: "Choose an image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)"]
        onAccepted: { backend.importImage(selectedFile); win.refreshImages() }
    }

    // Reusable confirm dialog (destructive actions).
    Dialog {
        id: confirmDialog
        property string message: ""
        property var onConfirm: null
        anchors.centerIn: parent
        modal: true; title: "Please confirm"
        standardButtons: Dialog.Yes | Dialog.No
        background: Rectangle { color: m.panel; radius: m.radius; border.width: 1; border.color: m.border }
        contentItem: Text { text: confirmDialog.message; color: m.textPrimary
            wrapMode: Text.WordWrap; padding: 14; font.pixelSize: 14 }
        onAccepted: if (onConfirm) onConfirm()
    }

    // Delete an image, clearing the wallpaper anywhere it points at that file.
    function confirmDeleteImage(name, fullPath) {
        confirmDialog.message = "Delete “" + name + "”? This can't be undone."
        confirmDialog.onConfirm = function () {
            if (store.appearance().wallpaper === fullPath) store.setAppearance("wallpaper", "")
            var pages = store.pages()
            for (var i = 0; i < pages.length; i++)
                if (store.pageBackground(i).wallpaper === fullPath)
                    store.setPageBackground(i, "wallpaper", "")
            backend.deleteImage(name)
            win.refreshImages()
        }
        confirmDialog.open()
    }

    ListModel { id: imagesModel }
    function refreshImages() {
        imagesModel.clear()
        var list = backend.listImages()
        for (var i = 0; i < list.length; i++) imagesModel.append({ modelData: list[i] })
    }

    // Display target state.
    property var screens: {
        try { return JSON.parse(backend.screensJson()) } catch (e) { return [] }
    }
    property string currentTarget: backend.targetConnector()

    Connections {
        target: backend
        function onImagesChanged() { win.refreshImages() }
        // The hub (or disk) changed the config externally — adopt it live.
        function onConfigChanged() {
            store.load(backend.starterLayout())
            win.syncTheme()
            win.refreshImages()
            if (win.currentPageIndex >= store.pageCount())
                win.currentPageIndex = Math.max(0, store.pageCount() - 1)
            pageName.text = win.currentPageName()
        }
        // Display hotplug.
        function onScreensChanged() {
            try { win.screens = JSON.parse(backend.screensJson() || "[]") } catch (e) { win.screens = [] }
            win.currentTarget = backend.targetConnector()
        }
        // Clear the "Starting hub…" state once the hub actually connects.
        function onHubConnectedChanged() { if (backend.hubConnected) win.hubStarting = false }
    }

    // Pull the hub's latest + refresh live state whenever the Manager regains focus.
    onActiveChanged: if (active) {
        backend.syncFromHub()
        try { win.screens = JSON.parse(backend.screensJson() || "[]") } catch (e) {}
        if (autostartSwitch) autostartSwitch.checked = backend.isAutostart()
    }
}
