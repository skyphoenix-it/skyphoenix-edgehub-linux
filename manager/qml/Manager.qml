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
    // page visible without scrolling, ~half of the panel's 2560px tall).
    width: 1440
    height: 1300
    minimumWidth: 1120
    minimumHeight: 900
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
        readonly property color accent: "#58A6FF"
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

    // Shared hub model + registry.
    DashboardStore { id: store }
    WidgetCatalog { id: catalog }
    WallpaperCatalog { id: bundledWallpapers }
    BackgroundCatalog { id: bgCatalog }

    // Full design-system theme + a media stub, so the WYSIWYG clone renders the
    // REAL widgets exactly like the Edge. Driven from the store's appearance.
    Theme { id: theme }
    MockMedia { id: media }

    property int currentPageIndex: 0

    function syncTheme() {
        var a = store.appearance() || ({})
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
                Text { text: "Manager"; color: m.accent; font.pixelSize: 14; Layout.bottomMargin: 12 }

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

                // Hub connection status
                RowLayout {
                    spacing: 8
                    Rectangle { width: 10; height: 10; radius: 5
                        color: backend.hubConnected ? m.success : m.textSecondary }
                    Text { text: backend.hubConnected ? "Hub connected (live)" : "Hub offline (saved)"
                        color: m.textSecondary; font.pixelSize: 12 }
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
                            model: (store.revision, store.pages())
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
                        TextField {
                            id: pageName; Layout.preferredWidth: 240; Layout.preferredHeight: m.touch
                            text: { store.revision; var p = store.pages()[win.currentPageIndex]; return p ? p.name : "" }
                            color: m.textPrimary
                            background: Rectangle { radius: 8; color: m.panel; border.color: m.border; border.width: 1 }
                            onEditingFinished: store.renamePage(win.currentPageIndex, text)
                        }
                        Button { text: "Rename"; onClicked: store.renamePage(win.currentPageIndex, pageName.text) }
                        Item { Layout.fillWidth: true }
                        Button { text: "Remove page"; enabled: store.pageCount() > 1
                            onClicked: { store.removePage(win.currentPageIndex)
                                win.currentPageIndex = Math.max(0, win.currentPageIndex - 1) } }
                    }

                    // Per-page animated background (overrides the global default for THIS page).
                    Flow {
                        Layout.fillWidth: true; spacing: 8
                        Text { text: "Page background:"; color: m.textSecondary; font.pixelSize: 14
                            height: m.touch; verticalAlignment: Text.AlignVCenter }
                        Repeater {
                            model: [ { v: "", l: "Global" } ].concat(bgCatalog.styles)
                            delegate: Rectangle {
                                required property var modelData
                                width: bgLbl.implicitWidth + 24; height: m.touch; radius: m.radius
                                property var pbg: { store.revision; return store.pageBackground(win.currentPageIndex) }
                                // "Global" = no per-page override at all; a style is selected only
                                // when this page has no per-page wallpaper.
                                property bool sel: modelData.v === ""
                                    ? (!pbg.style && !pbg.wallpaper)
                                    : (!pbg.wallpaper && pbg.style === modelData.v)
                                color: sel ? m.accent : m.panel; border.width: 1; border.color: m.border
                                Text { id: bgLbl; anchors.centerIn: parent; text: modelData.l
                                    color: sel ? "#0D1117" : m.textPrimary; font.pixelSize: 13 }
                                MouseArea { anchors.fill: parent
                                    onClicked: {
                                        store.setPageBackground(win.currentPageIndex, "style", modelData.v)
                                        // Choosing an animated style clears this page's wallpaper override;
                                        // "Global" clears both so the page inherits global again.
                                        store.setPageBackground(win.currentPageIndex, "wallpaper", "")
                                    } }
                            }
                        }
                    }

                    // Per-page wallpaper (overrides the global wallpaper for THIS page).
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text { text: "Page wallpaper:"; color: m.textSecondary; font.pixelSize: 14
                            Layout.alignment: Qt.AlignVCenter }
                        // "Global" clears the per-page override.
                        Rectangle {
                            width: 40; height: 54; radius: m.radius
                            property bool sel: (store.revision, !(store.pageBackground(win.currentPageIndex).wallpaper))
                            color: m.panel; border.width: sel ? 3 : 1; border.color: sel ? m.accent : m.border
                            Text { anchors.centerIn: parent; text: "Global"; color: m.textSecondary; font.pixelSize: 9
                                horizontalAlignment: Text.AlignHCenter; width: parent.width - 4; wrapMode: Text.WordWrap }
                            MouseArea { anchors.fill: parent
                                onClicked: store.setPageBackground(win.currentPageIndex, "wallpaper", "") }
                        }
                        Repeater {
                            model: bundledWallpapers.items
                            delegate: Rectangle {
                                required property var modelData
                                width: 40; height: 54; radius: m.radius; clip: true
                                property bool sel: (store.revision, store.pageBackground(win.currentPageIndex).wallpaper === modelData.source)
                                border.width: sel ? 3 : 1; border.color: sel ? m.accent : m.border; color: m.panel
                                Image { anchors.fill: parent; anchors.margins: 2; source: modelData.source
                                    fillMode: Image.PreserveAspectCrop; asynchronous: true }
                                MouseArea { anchors.fill: parent
                                    onClicked: store.setPageBackground(win.currentPageIndex, "wallpaper", modelData.source) }
                            }
                        }
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
                            Button { text: "＋  Add widget"; Layout.fillWidth: true; Layout.preferredHeight: m.touch
                                onClicked: addPicker.open() }
                            Rectangle {
                                Layout.fillWidth: true; Layout.preferredHeight: hintCol.implicitHeight + 24
                                radius: m.radius; color: m.panel; border.width: 1; border.color: m.border
                                ColumnLayout {
                                    id: hintCol; anchors.fill: parent; anchors.margins: 12; spacing: 6
                                    Text { text: "This is your Edge"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                                    Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: m.textSecondary; font.pixelSize: 13
                                        text: "• Drag a tile onto another to reorder\n• Drag the ⤡ corner to resize (width & height)\n• Switch 1 / 2 columns above\n• ⚙ configure  ·  ✕ remove\nChanges apply live to the display." }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }

            // ═══ 2. APPEARANCE ═══
            Item {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 24; spacing: 18
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
                                Text { visible: parent.sel; anchors.top: parent.top; anchors.right: parent.right
                                    anchors.margins: 6; text: "✓"; color: m.accent; font.pixelSize: 18; font.bold: true }
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
                                width: 46; height: 46; radius: 23; color: modelData.c
                                border.width: (store.revision, store.appearance().accent === modelData.name) ? 3 : 0
                                border.color: m.textPrimary
                                MouseArea { anchors.fill: parent
                                    onClicked: store.setAppearance("accent", modelData.name) }
                            }
                        }
                    }

                    Text { text: "Default animated background"; color: m.textSecondary; font.pixelSize: 14 }
                    Text { text: "Picking one clears the global wallpaper (a wallpaper always wins over the animation)."
                        color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    Text { visible: !theme.decorative
                        text: "⚠  The High Contrast theme keeps backgrounds off for legibility — switch themes to see them."
                        color: m.danger; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    Flow {
                        Layout.fillWidth: true; spacing: 8
                        Repeater {
                            model: bgCatalog.styles
                            delegate: Rectangle {
                                required property var modelData
                                width: 150; height: m.touch; radius: m.radius
                                property bool sel: (store.revision,
                                    !store.appearance().wallpaper && (store.appearance().bgStyle || "orbs") === modelData.v)
                                color: sel ? m.accent : m.panel; border.width: 1; border.color: m.border
                                Text { anchors.centerIn: parent; text: modelData.l
                                    color: sel ? "#0D1117" : m.textPrimary; font.pixelSize: 14 }
                                MouseArea { anchors.fill: parent
                                    onClicked: { store.setAppearance("bgStyle", modelData.v); store.setAppearance("wallpaper", "") } }
                            }
                        }
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
                            onMoved: store.setAppearance("glass", value)
                        }
                    }

                    RowLayout {
                        spacing: 12
                        Switch {
                            text: "Widget glow"
                            checked: { store.revision; var g = store.appearance().glow; return g === undefined ? true : g }
                            onToggled: store.setAppearance("glow", checked)
                        }
                        Switch {
                            text: "Animated background"
                            checked: { store.revision; var g = store.appearance().animatedBg; return g === undefined ? true : g }
                            onToggled: store.setAppearance("animatedBg", checked)
                        }
                        Switch {
                            text: "Reduce motion"
                            checked: (store.revision, store.appearance().reduceMotion || false)
                            onToggled: store.setAppearance("reduceMotion", checked)
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // ═══ 3. IMAGES ═══
            Item {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 24; spacing: 16
                    Text { text: "Images"; color: m.textPrimary; font.pixelSize: 24; font.bold: true }
                    Text { text: "Upload images to the Edge (stored under the hub's config directory)."
                        color: m.textSecondary; font.pixelSize: 14 }

                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Button { text: "＋  Import image…"; Layout.preferredHeight: m.touch
                            onClicked: fileDialog.open() }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: { store.revision; var wp = store.appearance().wallpaper || ""
                                return wp.length ? "Wallpaper: " + wp.split("/").pop() : "No wallpaper set" }
                            color: m.textSecondary; font.pixelSize: 13; Layout.alignment: Qt.AlignVCenter
                        }
                        Button { text: "Clear wallpaper"; Layout.preferredHeight: m.touch
                            enabled: (store.revision, (store.appearance().wallpaper || "").length > 0)
                            onClicked: store.setAppearance("wallpaper", "") }
                    }

                    // Bundled "standard" wallpapers (ship with the app).
                    Text { text: "Standard wallpapers"; color: m.textSecondary; font.pixelSize: 14; font.bold: true }
                    Flow {
                        Layout.fillWidth: true; spacing: 8
                        Repeater {
                            model: bundledWallpapers.items
                            delegate: Rectangle {
                                required property var modelData
                                width: 96; height: 132; radius: m.radius; clip: true
                                property bool isWall: (store.revision, store.appearance().wallpaper === modelData.source)
                                color: m.panel; border.width: isWall ? 3 : 1; border.color: isWall ? m.accent : m.border
                                Image { anchors.fill: parent; anchors.margins: 2; source: modelData.source
                                    fillMode: Image.PreserveAspectCrop; asynchronous: true }
                                Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                                    height: 24; color: Qt.rgba(0, 0, 0, 0.5)
                                    Text { anchors.centerIn: parent; text: modelData.label + (parent.parent.isWall ? "  ✓" : "")
                                        color: "#fff"; font.pixelSize: 11 } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: store.setAppearance("wallpaper", modelData.source) }
                            }
                        }
                    }

                    Text { text: "Your images"; color: m.textSecondary; font.pixelSize: 14; font.bold: true }
                    ScrollView {
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                        GridView {
                            id: imgGrid
                            cellWidth: 190; cellHeight: 190
                            model: imagesModel
                            delegate: Rectangle {
                                id: imgCard
                                required property var modelData
                                width: 180; height: 180; radius: m.radius
                                property string fullPath: backend.imagesDir() + "/" + modelData
                                property bool isWall: (store.revision, store.appearance().wallpaper) === fullPath
                                color: m.panel; border.width: isWall ? 2 : 1
                                border.color: isWall ? m.accent : m.border
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 8; spacing: 4
                                    Image {
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        source: "file://" + imgCard.fullPath
                                        fillMode: Image.PreserveAspectCrop; asynchronous: true; clip: true
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        Button {
                                            text: imgCard.isWall ? "Wallpaper ✓" : "Set wallpaper"
                                            Layout.fillWidth: true; font.pixelSize: 12
                                            onClicked: store.setAppearance("wallpaper", imgCard.fullPath)
                                        }
                                        AppIcon { name: "ui-trash"; size: 18; color: m.danger
                                            MouseArea { anchors.fill: parent
                                                onClicked: { backend.deleteImage(imgCard.modelData); win.refreshImages() } } }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ═══ 4. DISPLAY ═══
            Item {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 24; spacing: 16
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
                                Button { text: modelData.name === win.currentTarget ? "Target ✓" : "Set as target"
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

                    Switch {
                        id: autostartSwitch; text: "Start the hub automatically on login"
                        checked: backend.isAutostart()
                        onToggled: backend.setAutostart(checked)
                    }
                    Item { Layout.fillHeight: true }
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
    }
}
