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
    property bool editMode: false

    // Expanded overlay state (empty type = nothing expanded).
    property string expandedType: ""
    property string expandedId: ""
    // Per-widget accent of the expanded tile (S7): resolve the instance's own
    // accent name to a colour, reactive to store.revision so an accent edit in
    // the config panel recolours the overlay live. Falls back to the theme
    // accent when the tile has no per-widget accent.
    property color  expandedColor: {
        store.revision
        if (dashboard.expandedId === "") return theme.accent
        var s = store.settingsFor(dashboard.expandedId)
        var name = (s && s.accent) ? s.accent : ""
        return (name !== "" && theme.accentPresets[name])
               ? theme.accentPresets[name].a : theme.accent
    }
    property bool hasExpanded: expandedType !== ""

    property var host: StackView.view
    property bool _applyingAppearance: false

    // Resolved background for the CURRENT page. A background is ONE coherent
    // choice — either a wallpaper image OR an animated style — resolved per page
    // then falling back to the global appearance. A per-page choice fully wins:
    // a page that picks an animated style suppresses any GLOBAL wallpaper on that
    // page (and vice-versa), so switching styles/wallpapers always takes effect.
    property var pageBg: {
        store.revision
        var idx = 0
        try { idx = swipeView.currentIndex } catch (e) { idx = 0 }
        var pages = store.pages()
        var p = (idx >= 0 && idx < pages.length) ? pages[idx] : ({})
        var pbg = p.bg || ({})
        var a = store.appearance() || ({})
        // Per-page override present? Honour exactly what the page chose.
        if (pbg.wallpaper) return { wallpaper: pbg.wallpaper, style: pbg.style || a.bgStyle || "orbs" }
        if (pbg.style)     return { wallpaper: "", style: pbg.style }
        // No per-page override → inherit the global choice.
        return { wallpaper: a.wallpaper || "", style: a.bgStyle || "orbs" }
    }
    // Wallpaper image path. Remote/scheme URLs pass through untouched; a local
    // file (absolute path or bare name in the images dir) is resolved through the
    // C++ configBridge.imageUrl() helper so paths containing spaces or '#' are
    // percent-encoded — naive "file://"+path concatenation produces a malformed
    // URL that fails to load for those characters. (The hub exposes configBridge,
    // not the Manager's `backend`.) Falls back to concatenation if absent.
    property string wallpaperSource: {
        var wp = dashboard.pageBg.wallpaper
        if (!wp || !wp.length) return ""
        wp = String(wp)
        if (wp.indexOf("://") >= 0) return wp
        if (typeof configBridge !== "undefined" && configBridge && configBridge.imageUrl)
            return configBridge.imageUrl(wp)
        return wp.charAt(0) === "/" ? "file://" + wp : wp
    }
    // Master "animate the backdrop" toggle (persisted via appearance).
    property bool animatedBg: root.animatedBackground

    // ── Background ─────────────────────────────────────────────────────────
    // Rich 3-stop gradient (theme-driven — vivid for the "fancy" themes).
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: theme.backgroundColor }
            GradientStop { position: 0.55; color: theme.backgroundColor2 }
            GradientStop { position: 1.0; color: theme.backgroundColor3 }
        }
    }
    // Animated backdrop for the current page (orbs / waves / stars / none),
    // shown when no wallpaper image is set. Motion honours the animate toggle
    // and reduce-motion; the style resolves per-page → global default.
    BackdropLayer {
        anchors.fill: parent
        // "Animated background" OFF now genuinely removes the backdrop (plain
        // gradient shows) rather than leaving it frozen — that's what the toggle
        // reads as. Reduce-motion, by contrast, KEEPS the backdrop but stops its
        // motion. Gating visible unloads the component entirely (zero cost) when a
        // wallpaper is set, in High-Contrast, or with the animation switched off.
        visible: dashboard.wallpaperSource === "" && theme.decorative && dashboard.animatedBg
        style: dashboard.pageBg.style
        accent: theme.accent
        running: !root.reduceMotion
    }
    // Optional wallpaper image (uploaded + assigned via the Manager). Sits over
    // the gradient with a scrim so cards and text stay legible.
    Image {
        id: wallpaper
        anchors.fill: parent
        source: dashboard.wallpaperSource
        visible: source != ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; cache: true
    }
    Rectangle {
        anchors.fill: parent; visible: wallpaper.visible
        // Light scrim only — enough to keep out-of-card text legible without
        // washing the wallpaper out. Card legibility comes from the frosted glass.
        color: Qt.rgba(theme.backgroundColor.r, theme.backgroundColor.g, theme.backgroundColor.b, 0.28)
    }
    // Accent glow wash — subtle vibrancy/depth (skipped in high-contrast).
    Rectangle {
        anchors.fill: parent
        opacity: theme.decorative ? 0.10 : 0.0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: theme.accent }
            GradientStop { position: 0.5; color: "transparent" }
            GradientStop { position: 1.0; color: theme.accent2 }
        }
    }

    // Drive time-based widgets once per second. Runs unconditionally: this is an
    // always-on secondary-display dashboard that is rarely the "active" window, and
    // gating on Qt.application.active previously froze updates (and, since the scene
    // then never changed, the compositor stopped presenting frames — which made
    // taps appear to do nothing for seconds).
    // SELF-CORRECTING, and it has to be: a plain `interval: 1000; repeat: true`
    // re-arms 1000ms after each HANDLING, so every frame hitch, GC pause or load
    // spike is added to the phase and never given back. It is also never aligned to
    // the wall-clock second to begin with. Widgets format `new Date()` when this
    // fires, so a drifting tick renders the same second twice (the clock appears to
    // stall) and then skips one (it appears to jump two). Re-aiming at the next real
    // boundary every tick makes the error non-cumulative: a late fire simply shortens
    // the next wait. The +5ms lands us just PAST the boundary — Qt may fire a hair
    // early, and formatting at 999.7ms would show the second we just left.
    function _msToNextSecond() { return Math.max(1, 1000 - (Date.now() % 1000) + 5) }
    Timer {
        id: secondTick
        repeat: false
        running: false
        onTriggered: { dashboard._tick++; interval = dashboard._msToNextSecond(); start() }
        Component.onCompleted: { interval = dashboard._msToNextSecond(); start() }
    }

    DashboardStore { id: store }
    WidgetCatalog { id: catalog }
    // The single app-global egress gate. Every net widget routes through this one
    // instance (injected below), so the offline switch + host allowlist + request
    // counters are global. `offline` is driven by an appearance flag (set by a
    // future global toggle / managed config); default off.
    NetHub {
        id: netHub
        offline: { var _ = store.revision; return store.appearance().netOffline === true }
        // E7: the hub's ConfigBridge resolves ${env:}/file: credential refs. The
        // Manager has no configBridge (and does no egress), and the QML test
        // harness has none either — NetHub fails a ref closed when it is absent
        // rather than sending the reference as a token.
        secretResolver: (typeof configBridge !== "undefined") ? configBridge : null
    }
    WidgetConfigSchema { id: cfgSchema }

    // Colour + sizing tokens for the shared ConfigField / WidgetConfigPanel,
    // derived from the theme (re-evaluates when the theme changes) and sized for
    // touch (larger controls than the desktop Manager).
    property var cfgCol: ({
        textPrimary: theme.textPrimary, textSecondary: theme.textSecondary,
        bg: theme.backgroundColor, accent: theme.accent, border: theme.cardBorder,
        panel: theme.cardBackground, panelAlt: theme.cardBackgroundAlt,
        radius: theme.radiusMd, ctlH: 58, fontBase: 17
    })

    // Geocode status shown in the weather config panel.
    property string cfgStatus: ""
    function cfgAction(action) {
        if (action === "geocode" && overlayLoaderItem && overlayLoaderItem.hasOwnProperty("geocode")) {
            var place = store.settingsFor(expandedId).place || ""
            if (!place.trim().length) { cfgStatus = "Type a place name first."; return }
            cfgStatus = "Searching for “" + place + "”…"
            overlayLoaderItem.geocode(place)
        }
    }
    property var overlayLoaderItem: null

    // Close the expanded overlay + clear its transient state (shared by the
    // header back button and the reachable bottom "Done" bar).
    function closeExpanded() {
        dashboard.expandedType = ""
        dashboard.expandedId = ""
        dashboard.cfgStatus = ""
        dashboard.overlayLoaderItem = null
    }

    Component.onCompleted: {
        store.load(typeof configBridge !== "undefined" && configBridge ? configBridge.starterLayout() : "")
        applyAppearance()
        // QA: auto-open a widget's expanded config view (XENEON_EXPAND=<type>).
        if (typeof _expandType !== "undefined" && _expandType) {
            var pages = store.pages()
            for (var p = 0; p < pages.length; p++)
                for (var t = 0; t < (pages[p].tiles || []).length; t++)
                    if (pages[p].tiles[t].type === _expandType) {
                        dashboard.expandedId = pages[p].tiles[t].id
                        dashboard.expandedType = _expandType
                        return
                    }
        }
    }


    // Apply a UI-state document pushed live from the companion Manager app.
    // Called by main.qml when the C++ ControlServer receives a new layout.
    function applyExternalState(json) {
        if (store.applyExternal(json)) {
            applyAppearance()
            // A live push may have removed (or replaced) the tile we're currently
            // expanded on. Leaving the overlay open would let its config panel keep
            // writing to an instanceId that no longer exists on any page — an orphan
            // settings entry. Close the overlay when its tile is gone.
            if (dashboard.hasExpanded && !_tileExists(dashboard.expandedId))
                closeExpanded()
        }
    }

    // True if a tile with this instance id still exists on some page.
    function _tileExists(id) {
        if (!id) return false
        var pages = store.pages()
        for (var p = 0; p < pages.length; p++) {
            var tiles = pages[p].tiles || []
            for (var t = 0; t < tiles.length; t++)
                if (tiles[t].id === id) return true
        }
        return false
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
        if (a.animatedBg !== undefined) root.animatedBackground = a.animatedBg
        if (a.orientation) root.orientationMode = a.orientation
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
        function onAnimatedBackgroundChanged() { store.setAppearance("animatedBg", root.animatedBackground) }
        function onOrientationModeChanged() { store.setAppearance("orientation", root.orientationMode) }
    }

    // ── Fallback tile (error boundary for unknown / unavailable widgets) ─────
    Component {
        id: fallbackTile
        WidgetChrome {
            property var metrics: ({})
            property bool expanded: false
            property bool active: true
            property var store: null
            property string instanceId: ""
            title: "Unavailable"; iconName: "ui-warning"; accentColor: theme.textTertiary
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
        if (item.hasOwnProperty("netHub")) item.netHub = netHub
        // Real IANA zones (app/src/timezone_bridge.h). Absent in the QML test
        // harness and in any standalone host, where the clock falls back to its
        // stored fixed offset rather than rendering a confidently wrong time.
        if (item.hasOwnProperty("timeZones"))
            item.timeZones = (typeof timeZones !== "undefined") ? timeZones : null
        item.expanded = isExpanded
        item.metrics = Qt.binding(function () { return dashboard.metrics })
        if (item.hasOwnProperty("titleOverride"))
            item.titleOverride = Qt.binding(function () {
                store.revision; var s = store.settingsFor(id); return (s && s.title) ? s.title : ""
            })
        // Per-widget appearance (universal — any widget's WidgetChrome honours these).
        if (item.hasOwnProperty("accentName"))
            item.accentName = Qt.binding(function () {
                store.revision; var s = store.settingsFor(id); return (s && s.accent) ? s.accent : ""
            })
        if (item.hasOwnProperty("cardBackdrop"))
            item.cardBackdrop = Qt.binding(function () {
                store.revision; var s = store.settingsFor(id); return (s && s.cardBackdrop) ? s.cardBackdrop : "none"
            })
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
                // Bind to structureRevision (not revision): only page/tile structure
                // changes rebuild the tiles; per-widget settings edits don't.
                model: store.structureRevision, store.pages()
                delegate: Item {
                    id: pageItem
                    required property int index
                    required property var modelData
                    property var tiles: modelData.tiles || []

                    // Column count: per-page override → global setting → 1.
                    // Clamped so columns never get impractically narrow for the width.
                    property int cols: {
                        store.revision
                        var fit = Math.max(1, Math.floor(width / 300))
                        // Honour the per-page override → global gridCols → 1 in BOTH
                        // orientations. Landscape (after orientation reflow) is wide so
                        // it allows more, shorter columns (cap 4) than portrait (cap 6),
                        // but still respects the user's chosen column count rather than
                        // ignoring it.
                        var want = (modelData.cols && modelData.cols > 0)
                                   ? modelData.cols : (store.appearance().gridCols || 1)
                        var cap = (width > height) ? 4 : 6
                        return Math.max(1, Math.min(want, fit, cap))
                    }

                    // Scrollable page body: when the tiles' combined minimum height
                    // exceeds the page, the Flickable scrolls (so bottom widgets stay
                    // reachable) — otherwise the grid just fills the page and the
                    // Flickable stays inert so it never competes with the horizontal
                    // page-swipe.
                    Flickable {
                        id: pageFlick
                        anchors.fill: parent
                        clip: true
                        contentWidth: width
                        contentHeight: pageGrid.height
                        flickableDirection: Flickable.VerticalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: pageGrid.implicitHeight > height + 1

                    GridLayout {
                        id: pageGrid
                        width: pageFlick.width
                        // Fill the page when content fits; grow to natural height (and
                        // let the Flickable scroll) when it overflows.
                        height: Math.max(pageFlick.height, implicitHeight)
                        columns: pageItem.cols
                        rowSpacing: theme.spacingMd
                        columnSpacing: theme.spacingMd

                        Repeater {
                            model: pageItem.tiles
                            delegate: Item {
                                id: cell
                                required property int index
                                required property var modelData
                                property int rowSpan: Math.max(1, modelData.h || 1)
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.columnSpan: Math.max(1, Math.min(modelData.w || 1, pageItem.cols))
                                Layout.rowSpan: rowSpan
                                Layout.minimumHeight: 120 * rowSpan + theme.spacingMd * (rowSpan - 1)

                                scale: tapMA.pressed && !dashboard.editMode ? 0.98 : 1.0
                                Behavior on scale { NumberAnimation { duration: theme.motionFast; easing.type: Easing.OutCubic } }

                                // Body taps NO LONGER open config — only the top-right
                                // corner button does (see below). This frees the whole
                                // widget body for the widget's own in-place controls
                                // (start a timer, log a glass, toggle a task…) so basic
                                // usability lives on the tile and only "advanced" settings
                                // require opening the config view. Kept as a disabled
                                // sibling only so `scale: tapMA.pressed` stays valid.
                                MouseArea {
                                    id: tapMA
                                    anchors.fill: parent
                                    enabled: false
                                }

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

                                // Error boundary: a tile whose type is unknown/removed
                                // renders the fallback card instead of a blank, confusing tile.
                                Loader {
                                    anchors.fill: parent
                                    active: tileLd.wId !== "" && tileLd.wType !== "" && catalog.source(tileLd.wType) === ""
                                    sourceComponent: dashboard.fallbackTile
                                }

                                // Expand affordance + explicit hit-target. Full-bleed
                                // interactive widgets (Media transport, Tasks, Notes…)
                                // cover the underlying tapMA with their own MouseAreas,
                                // so tapping their body can't reach the expand handler.
                                // This touch-sized corner target sits ON TOP (z:20) and
                                // always opens the expanded view. The small low-opacity
                                // icon is a glanceable hint kept from fighting a widget's
                                // own top-right status. Hidden in edit mode.
                                Item {
                                    anchors.right: parent.right; anchors.top: parent.top
                                    width: theme.touchSecondary; height: theme.touchSecondary
                                    z: 20
                                    visible: !dashboard.editMode
                                    Rectangle {
                                        anchors.fill: parent; anchors.margins: theme.spacingXs
                                        radius: theme.radiusSm
                                        color: cfgMA.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                                    }
                                    AppIcon {
                                        anchors.right: parent.right; anchors.top: parent.top
                                        anchors.margins: theme.spacingSm
                                        name: "ui-expand"; size: theme.iconSm
                                        color: theme.textTertiary
                                        opacity: cfgMA.containsMouse ? 0.95 : 0.55
                                    }
                                    MouseArea {
                                        id: cfgMA
                                        anchors.fill: parent
                                        enabled: !dashboard.editMode
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            dashboard.cfgStatus = ""
                                            dashboard.expandedId = cell.modelData.id
                                            dashboard.expandedType = cell.modelData.type
                                        }
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
                                            AppIcon { anchors.centerIn: parent; name: "ui-caret-left"; size: theme.iconMd; color: theme.textPrimary }
                                            MouseArea { anchors.fill: parent; onClicked: store.moveTile(pageItem.index, cell.index, cell.index - 1) }
                                        }
                                        // remove
                                        Rectangle {
                                            Layout.preferredWidth: theme.touchPrimary; Layout.preferredHeight: theme.touchPrimary
                                            radius: width / 2; color: Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.2)
                                            border.width: 2; border.color: theme.error
                                            AppIcon { anchors.centerIn: parent; name: "ui-trash"; size: 26; color: theme.error }
                                            MouseArea { anchors.fill: parent; onClicked: store.removeTile(pageItem.index, cell.modelData.id) }
                                        }
                                        // move right
                                        Rectangle {
                                            Layout.preferredWidth: theme.touchSecondary; Layout.preferredHeight: theme.touchSecondary
                                            radius: width / 2; color: theme.cardBackgroundAlt; border.width: 1; border.color: theme.cardBorder
                                            visible: cell.index < pageItem.tiles.length - 1
                                            AppIcon { anchors.centerIn: parent; name: "ui-caret-right"; size: theme.iconMd; color: theme.textPrimary }
                                            MouseArea { anchors.fill: parent; onClicked: store.moveTile(pageItem.index, cell.index, cell.index + 1) }
                                        }
                                        // resize cycle: 1x1 -> 2x1 -> 1x2 -> 2x2 -> 1x1
                                        Rectangle {
                                            Layout.preferredWidth: theme.touchSecondary; Layout.preferredHeight: theme.touchSecondary
                                            radius: width / 2; color: theme.cardBackgroundAlt; border.width: 1; border.color: theme.cardBorder
                                            AppIcon { anchors.centerIn: parent; name: "ui-resize"; size: theme.iconMd; color: theme.textPrimary }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    var w = cell.modelData.w || 1
                                                    var h = cell.modelData.h || 1
                                                    var nw = 1, nh = 1
                                                    if (w === 1 && h === 1) { nw = 2; nh = 1 }
                                                    else if (w === 2 && h === 1) { nw = 1; nh = 2 }
                                                    else if (w === 1 && h === 2) { nw = 2; nh = 2 }
                                                    else { nw = 1; nh = 1 }
                                                    store.setTileSize(pageItem.index, cell.modelData.id, nw, nh)
                                                }
                                            }
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
                                    AppIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "ui-plus"; size: 40; color: theme.accent }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Add widget"; font.pixelSize: 14; color: theme.textSecondary }
                                }
                                MouseArea { anchors.fill: parent; onClicked: { picker.pageIndex = pageItem.index; picker.shown = true } }
                            }
                        }
                    }
                    }

                    // Empty-page hint. Gated on this being the CURRENT page: after a
                    // live state-swap (Manager push → applyExternal rebuilds the page
                    // Repeater) an off-screen empty page's delegate can momentarily
                    // sit at x=0 and overlap the current page; only the current page
                    // should ever show its hint anyway.
                    Text {
                        anchors.centerIn: parent
                        visible: pageItem.tiles.length === 0 && !dashboard.editMode
                                 && pageItem.index === swipeView.currentIndex
                        text: "This page is empty.\nTap Edit to add widgets."
                        horizontalAlignment: Text.AlignHCenter
                        color: theme.textTertiary; font.pixelSize: 16
                    }
                }
            }
        }

        // ── Bottom bar ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: theme.touchPrimary
            spacing: theme.spacingSm

            Text {
                Layout.preferredWidth: theme.touchSecondary * 1.8
                // structureRevision dep so a page rename refreshes the label.
                // Guard the index against a mid-rebuild transient (currentIndex can
                // momentarily be -1 or point past a shrunken pages() array) so we
                // never dereference an undefined page.
                text: {
                    store.structureRevision
                    var i = swipeView.currentIndex
                    var ps = store.pages()
                    return (i >= 0 && i < ps.length && ps[i]) ? (ps[i].name || "") : ""
                }
                font.pixelSize: theme.fontLabel; font.weight: Font.DemiBold
                font.family: theme.fontDisplay; color: theme.textSecondary
                elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
            }

            PageIndicator {
                Layout.alignment: Qt.AlignCenter; Layout.fillWidth: true
                count: swipeView.count; currentIndex: swipeView.currentIndex
                interactive: true
                onCurrentIndexChanged: if (currentIndex !== swipeView.currentIndex) swipeView.currentIndex = currentIndex
                // A tall, transparent hit area (>=44px) carrying a small visual pill,
                // so the dots are actually tappable on a touchscreen.
                delegate: Item {
                    required property int index
                    implicitWidth: (index === swipeView.currentIndex ? 36 : 16) + 10
                    implicitHeight: 44
                    Rectangle {
                        anchors.centerIn: parent
                        width: index === swipeView.currentIndex ? 36 : 14
                        height: 14; radius: 7; color: theme.accent
                        opacity: index === swipeView.currentIndex ? 0.95 : 0.3
                        Behavior on width { NumberAnimation { duration: theme.motionFast } }
                        Behavior on opacity { NumberAnimation { duration: theme.motionFast } }
                    }
                }
            }

            // Add page (edit mode) — jump to the new page so the add lands visibly.
            BarButton { iconName: "ui-add-page"; visible: dashboard.editMode
                        onClicked: { store.addPage(""); swipeView.currentIndex = store.pageCount() - 1 } }
            // Remove current page (edit mode, keep ≥1) — re-clamp the index so the
            // view never points past the new end after deleting the last page.
            BarButton { iconName: "ui-del-page"; visible: dashboard.editMode && store.pageCount() > 1
                        onClicked: { var i = swipeView.currentIndex; store.removePage(i)
                                     swipeView.currentIndex = Math.max(0, Math.min(i, store.pageCount() - 1)) } }
            // Edit toggle
            BarButton {
                iconName: dashboard.editMode ? "ui-check" : "ui-edit"
                highlighted: dashboard.editMode
                onClicked: { dashboard.editMode = !dashboard.editMode; if (!dashboard.editMode) store.flushNow() }
            }
            // Appearance
            BarButton { iconName: "ui-palette"; onClicked: settings.shown = true }
            // Diagnostics
            BarButton {
                iconName: "ui-settings"
                // Guard against stacking multiple Diagnostics pages on repeat taps.
                onClicked: if (dashboard.host && dashboard.host.depth <= 1) dashboard.host.push("qrc:/qml/Diagnostics.qml", {
                    "metricsJson": Qt.binding(function () { return metricsJson }),
                    "screensData": screensData,
                    "configJson": (typeof configBridge !== "undefined" && configBridge) ? configBridge.configJson() : ""
                })
            }
        }
    }

    // Small reusable bottom-bar button.
    component BarButton: Rectangle {
        id: barBtn
        property string iconName: ""
        property bool highlighted: false
        signal clicked()
        Layout.preferredWidth: theme.touchPrimary
        Layout.preferredHeight: theme.touchPrimary
        radius: theme.radiusLg
        color: highlighted ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.22)
                           : (bMA.pressed ? theme.cardBackgroundAlt : (bMA.containsMouse ? theme.cardBackground : "transparent"))
        border.width: highlighted ? 2 : 1; border.color: highlighted ? theme.accent : theme.cardBorder
        scale: bMA.pressed ? 0.93 : 1.0
        Behavior on scale { NumberAnimation { duration: theme.motionFast } }
        AppIcon { anchors.centerIn: parent; name: barBtn.iconName; size: theme.iconLg
            color: barBtn.highlighted ? theme.accent : theme.textPrimary }
        MouseArea { id: bMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: barBtn.clicked() }
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
                AppIcon { anchors.centerIn: parent; name: "ui-caret-left"; size: theme.iconMd; color: theme.textPrimary }
                MouseArea { id: backMA; anchors.fill: parent; onClicked: dashboard.closeExpanded() }
            }
            Column {
                id: titleCol
                anchors.left: backBtn.right; anchors.leftMargin: theme.spacingLg
                anchors.right: parent.right; anchors.top: parent.top
                spacing: 3
                Row {
                    spacing: theme.spacingSm
                    AppIcon { anchors.verticalCenter: parent.verticalCenter; name: dashboard.expandedType
                        size: theme.fontTitle + 10; color: dashboard.expandedColor }
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

        // Content — FILLS the whole area below the header: a live preview of the
        // widget plus a full, scrollable configuration panel (descriptions +
        // every option). Portrait stacks them; landscape places them side by side.
        property bool ovlWide: overlay.width > overlay.height

        GridLayout {
            id: ovlBody
            anchors.top: ovlHeader.bottom; anchors.topMargin: theme.spacingMd
            anchors.left: parent.left; anchors.right: parent.right
            anchors.bottom: ovlDoneBar.top; anchors.bottomMargin: theme.spacingMd
            anchors.leftMargin: theme.spacingLg; anchors.rightMargin: theme.spacingLg
            columns: overlay.ovlWide ? 2 : 1
            rowSpacing: theme.spacingMd; columnSpacing: theme.spacingMd

            // ── Live, interactive widget ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: overlay.ovlWide
                Layout.preferredWidth: overlay.ovlWide ? overlay.width * 0.46 : -1
                Layout.preferredHeight: overlay.ovlWide ? -1 : Math.min(overlay.height * 0.46, 1080)
                spacing: theme.spacingSm

                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
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
                            // expanded=true → the widget shows its full, INTERACTIVE
                            // layout (e.g. Focus's Start/preset controls), usable here.
                            dashboard.injectWidget(item, dashboard.expandedId, dashboard.expandedType, true)
                            dashboard.overlayLoaderItem = item
                            if (item) {
                                item.active = true
                                if (item.hasOwnProperty("chromeless")) item.chromeless = true
                                // The overlay header already shows the title/icon.
                                if (item.hasOwnProperty("showHeader")) item.showHeader = false
                            }
                        }
                    }
                }
                // Reset this widget to its defaults.
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: theme.touchSecondary
                    radius: theme.radiusMd; color: resetMA.pressed ? theme.cardBackgroundAlt : theme.cardBackground
                    border.width: 1; border.color: theme.cardBorder
                    Text {
                        anchors.centerIn: parent; text: "Reset to defaults"
                        color: theme.textSecondary; font.pixelSize: theme.fontLabel
                    }
                    MouseArea {
                        id: resetMA; anchors.fill: parent
                        // Deep-clones the defaults (so array/object defaults aren't
                        // shared across widgets) + drops stale keys — see the store.
                        onClicked: {
                            store.resetSettings(dashboard.expandedId, catalog.defaults(dashboard.expandedType))
                            dashboard.cfgStatus = ""
                        }
                    }
                }
            }

            // ── Configuration panel ──
            WidgetConfigPanel {
                Layout.fillWidth: true; Layout.fillHeight: true
                schema: cfgSchema.schemaFor(dashboard.expandedType)
                st: store
                instanceId: dashboard.expandedId
                col: dashboard.cfgCol
                statusText: dashboard.cfgStatus
                onActionRequested: (a) => dashboard.cfgAction(a)
            }
        }

        // Reachable close: a full-width "Done" bar pinned to the BOTTOM of the
        // overlay. On a 2560px-tall portrait panel the top-left back button is out
        // of one-handed reach, so this is the primary way out of the expanded view.
        Rectangle {
            id: ovlDoneBar
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: theme.spacingLg
            height: theme.touchPrimary
            radius: theme.radiusMd
            color: doneMA.pressed ? Qt.darker(theme.accent, 1.2) : theme.accent
            RowLayout {
                anchors.centerIn: parent; spacing: theme.spacingSm
                AppIcon { name: "ui-check"; size: theme.iconMd; color: theme.backgroundColor }
                Text { text: "Done"; color: theme.backgroundColor; font.pixelSize: theme.fontTitle
                    font.bold: true; font.family: theme.fontDisplay }
            }
            MouseArea { id: doneMA; anchors.fill: parent; onClicked: dashboard.closeExpanded() }
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
                        AppIcon { anchors.centerIn: parent; name: "ui-close"; size: theme.iconSm; color: theme.textPrimary }
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
                                            // Touchscreens have no hover — react to `pressed` so a tap
                                            // gives real feedback (containsMouse alone did nothing).
                                            color: pickMA.pressed ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.22)
                                                   : (pickMA.containsMouse ? theme.cardBackgroundAlt : theme.backgroundColor)
                                            border.width: 1
                                            border.color: pickMA.pressed ? theme.accent : theme.cardBorder
                                            scale: pickMA.pressed ? 0.97 : 1.0
                                            Behavior on scale { NumberAnimation { duration: theme.motionFast } }
                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: theme.spacingSm; spacing: theme.spacingSm
                                                AppIcon { name: modelData.type; size: 24; color: theme.textSecondary }
                                                Text { text: modelData.title; font.pixelSize: 15; color: theme.textPrimary; Layout.fillWidth: true; elide: Text.ElideRight }
                                                AppIcon { name: "ui-plus"; size: 20; color: theme.accent }
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
