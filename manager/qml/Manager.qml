import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

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
    title: "EdgeHub Manager"
    color: m.bg

    // Drive the Qt palette from the chrome tokens so the native Fusion controls
    // that aren't hand-styled (scrollbars, combo popups, text selection, tooltips)
    // follow the Manager theme instead of the app's compiled-in dark palette.
    palette.window: m.bg
    palette.windowText: m.textPrimary
    palette.base: m.panel
    palette.alternateBase: m.panelAlt
    palette.button: m.panelAlt
    palette.buttonText: m.textPrimary
    palette.text: m.textPrimary
    palette.brightText: m.textPrimary
    palette.highlight: m.accent
    palette.highlightedText: m.textOnAccent
    palette.mid: m.border
    palette.midlight: m.panelAlt
    palette.light: m.panelAlt
    palette.dark: m.border
    palette.shadow: m.border
    palette.placeholderText: m.textSecondary
    palette.toolTipBase: m.panel
    palette.toolTipText: m.textPrimary

    // Manager chrome theme — this app's OWN look, separate from the Edge dashboard
    // theme it edits. Persisted locally (QSettings). Dark / Light / Default, where
    // Default is the warm SKYPhoenix palette (corporate orange/red) that suits the
    // colour logo and ships as the out-of-box look. The preview keeps using `theme`.
    Settings { id: appSettings; category: "ManagerChrome"; property string chromeTheme: "default" }

    // --- Local design tokens (the Manager's own chrome; three switchable themes) ---
    QtObject {
        id: m
        readonly property var _pal: ({
            "dark":    { bg: "#0D1117", panel: "#161B22", panelAlt: "#1C222B", border: "#30363D",
                         textPrimary: "#E6EDF3", textSecondary: "#8B949E", success: "#3FB950", danger: "#F85149" },
            "light":   { bg: "#F6F8FA", panel: "#FFFFFF", panelAlt: "#EFF2F5", border: "#D0D7DE",
                         textPrimary: "#1F2328", textSecondary: "#59636E", success: "#1A7F37", danger: "#CF222E" },
            "default": { bg: "#FAF4EC", panel: "#FFFDFA", panelAlt: "#F3E9DC", border: "#E6D5C3",
                         textPrimary: "#2A1D16", textSecondary: "#8A7361", success: "#2E7D32", danger: "#B92D26" }
        })
        readonly property var _p: _pal[appSettings.chromeTheme] || _pal["dark"]
        readonly property color bg: _p.bg
        readonly property color panel: _p.panel
        readonly property color panelAlt: _p.panelAlt
        readonly property color border: _p.border
        readonly property color textPrimary: _p.textPrimary
        readonly property color textSecondary: _p.textSecondary
        // Default uses the corporate orange; Dark/Light follow the chosen Edge accent.
        readonly property color accent: appSettings.chromeTheme === "default" ? "#ED6D1F" : theme.accent
        readonly property color textOnAccent: appSettings.chromeTheme === "default" ? "#241407" : "#0D1117"
        readonly property color success: _p.success
        readonly property color danger: _p.danger
        readonly property int radius: 12
        readonly property int touch: 44
        readonly property var accentPresets: [
            { name: "blue", c: "#58A6FF" }, { name: "purple", c: "#A371F7" },
            { name: "green", c: "#3FB950" }, { name: "orange", c: "#F0883E" },
            { name: "pink", c: "#F778BA" }, { name: "teal", c: "#56D4DD" },
            { name: "red", c: "#F85149" }, { name: "gold", c: "#E3B341" },
            { name: "cyan", c: "#22D3EE" }, { name: "indigo", c: "#818CF8" },
            { name: "mint", c: "#34D399" }, { name: "coral", c: "#FB7185" },
            { name: "amber", c: "#FBBF24" }, { name: "magenta", c: "#E879F9" }
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

    // MScroll — a ScrollView with a usable mouse-wheel step. A plain QQC2 ScrollView
    // under a Wayland/high-resolution wheel scrolls only a few pixels per notch (the
    // "20 notches to reach the bottom" bug). This WheelHandler moves ~130px per notch
    // (angleDelta 120 × 1.1), matching the hub's WidgetConfigPanel; it consumes the
    // event so the internal Flickable doesn't also scroll (no double-step).
    component MScroll: ScrollView {
        id: msv
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function (ev) {
                var f = msv.contentItem
                if (!f) return
                var dy = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y
                var maxY = Math.max(0, f.contentHeight - f.height)
                f.contentY = Math.max(0, Math.min(maxY, f.contentY - dy * 1.1))
                ev.accepted = true
            }
        }
    }

    // Shared hub model + registry.
    DashboardStore { id: store }
    WidgetCatalog { id: catalog }
    WallpaperCatalog { id: bundledWallpapers }
    BackgroundCatalog { id: bgCatalog }
    // The curated "screens" library — the same presets the hub's first-run wizard
    // and preset picker use. The Manager is the full control surface, so it can
    // start a page set from a preset too (applied via store.resetTo → persisted
    // + pushed live to a running hub).
    PresetCatalog { id: presetLib }

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
    // systemReduceMotion mirrors the hub's main.qml: the OS reduce-motion probe
    // (XDG portal, injected as `systemSettings`) must reach the Manager's theme
    // too, or the previews keep animating while the real Edge stands still.
    // typeof-guard: the QML test harness hosts Manager.qml without the probe.
    Theme {
        id: theme
        systemReduceMotion: (typeof systemSettings !== "undefined" && systemSettings)
            ? systemSettings.reduceMotion : false
    }
    MockMedia { id: media }

    // One phrase for "does an edit reach the panel right now?" — reused by the
    // Layout hint card and the Appearance preview so they can never disagree
    // with the sidebar's connection dot again.
    readonly property string liveNote: backend.hubConnected
        ? "Hub connected — changes appear on the Edge immediately."
        : "Hub offline — changes are saved and appear when the hub starts."

    // Scope pill ("Whole Edge" / "This page only" / …): the audit's core finding
    // was that no control said what it would affect, so scope becomes a visible,
    // uniform part of every section header rather than prose.
    //
    // The pills are a VOCABULARY, and a vocabulary needs definitions: the audit's
    // F3 was that "Whole Edge" and "All pages" both appeared, both meant global,
    // and nothing said which was broader (the difference is real — a page can
    // override the background but not the theme — it was just never stated). So a
    // pill now carries `detail`, the precise rule, on hover. `scopeDetail()` is the
    // single source of that text: pass a label from `scopeLabels` and the wording
    // can never drift between two sections claiming the same scope.
    readonly property var scopeLabels: ({
        widget: "This widget only", page: "This page only", pages: "All pages",
        edge: "Whole Edge", computer: "This computer", window: "This window only"
    })
    function scopeDetail(label) {
        switch (label) {
        case "This widget only": return "Changes this one tile. Other widgets of the same type are untouched."
        case "This page only":   return "Changes this page only. Your other pages are untouched."
        case "All pages":        return "The default for every page — but a page can override it (Layout → “This page's background”)."
        case "Whole Edge":       return "Changes every page and every widget. There is no per-page override for this."
        case "This computer":    return "Changes this computer's hub, not the Edge layout. Other machines are untouched."
        case "This window only": return "Changes the Manager window you're looking at. Your Edge is untouched."
        }
        return ""
    }
    component ScopeTag: Rectangle {
        id: stag
        objectName: "scopePill"          // test seam: every pill is findable as one set
        property string label: ""
        implicitWidth: stLbl.implicitWidth + 18; implicitHeight: 22; radius: 11
        color: "transparent"; border.width: 1; border.color: m.accent
        Text { id: stLbl; anchors.centerIn: parent; text: stag.label
            color: m.accent; font.pixelSize: 11; font.bold: true }
        // Hovering the pill spells the rule out, so the short label can stay short.
        ToolTip.visible: stMA.containsMouse && ToolTip.text !== ""
        ToolTip.delay: 250
        ToolTip.text: win.scopeDetail(stag.label)
        MouseArea { id: stMA; anchors.fill: parent; hoverEnabled: true }
    }

    property int currentPageIndex: 0
    // Appearance: the Edge theme is chosen from a compact dropdown (Hybrid design)
    // instead of a 29-swatch grid that dominated the tab. This is the single source
    // of the theme list — the dropdown and the tests both read it.
    readonly property var apThemeModel: [
        { k: "dark",          n: "Dark",       c1: "#161B22", c2: "#0A0E14" },
        { k: "midnight",      n: "Midnight",   c1: "#1B1247", c2: "#070A1C" },
        { k: "aurora",        n: "Aurora",     c1: "#0C2E3A", c2: "#111C40" },
        { k: "sunset",        n: "Sunset",     c1: "#3A1230", c2: "#40161C" },
        { k: "nebula",        n: "Nebula",     c1: "#2A1048", c2: "#120A2E" },
        { k: "synthwave",     n: "Synthwave",  c1: "#2D0B45", c2: "#0F0524", pro: true },
        { k: "cyberpunk",     n: "Cyberpunk",  c1: "#0A2A26", c2: "#020A08", pro: true },
        { k: "deep_forest",   n: "Forest",     c1: "#143021", c2: "#06120A" },
        { k: "deep_ocean",    n: "Ocean",      c1: "#0A2A3F", c2: "#020A14" },
        { k: "ember",         n: "Ember",      c1: "#3A1509", c2: "#0F0705" },
        { k: "vaporwave",     n: "Vaporwave",  c1: "#3A1A52", c2: "#140A20", pro: true },
        { k: "rose_gold",     n: "Rose Gold",  c1: "#3A1E2C", c2: "#170C12" },
        { k: "matrix",        n: "Matrix",     c1: "#0A160A", c2: "#000000", pro: true },
        { k: "nord",          n: "Nord",       c1: "#3B4252", c2: "#272B35" },
        { k: "dracula",       n: "Dracula",    c1: "#343746", c2: "#21222C" },
        { k: "solarized",     n: "Solarized",  c1: "#073642", c2: "#00212B" },
        { k: "gruvbox",       n: "Gruvbox",    c1: "#32302F", c2: "#1D2021" },
        { k: "catppuccin",    n: "Catppuccin", c1: "#181825", c2: "#11111B" },
        { k: "tokyonight",    n: "Tokyo Night",c1: "#24283B", c2: "#16161E" },
        { k: "arch",          n: "Arch",       c1: "#1B2129", c2: "#14181D", pro: true },
        { k: "cachyos",       n: "CachyOS",    c1: "#1C221A", c2: "#131611", pro: true },
        { k: "debian",        n: "Debian",     c1: "#1F1922", c2: "#16121A", pro: true },
        { k: "fedora",        n: "Fedora",     c1: "#152034", c2: "#0E1626", pro: true },
        { k: "popos",         n: "Pop!_OS",    c1: "#262322", c2: "#1E1C1B", pro: true },
        { k: "aubergine",     n: "Aubergine",  c1: "#3A0F2A", c2: "#2C0A20" },
        { k: "crimson",       n: "Crimson",    c1: "#16080B", c2: "#0B0507" },
        { k: "oled",          n: "OLED",       c1: "#0A0A0A", c2: "#000000" },
        { k: "light",         n: "Light",      c1: "#F6F8FA", c2: "#E4E9F0" },
        { k: "high_contrast", n: "Contrast",   c1: "#1A1A1A", c2: "#000000" }
    ]
    function _themeDef(key) {
        for (var i = 0; i < apThemeModel.length; i++)
            if (apThemeModel[i].k === key) return apThemeModel[i]
        return null
    }
    // Commit an Edge theme: a locked Pro theme opens the licence dialog instead of
    // applying (free users can still hover-preview it). Otherwise persist it.
    function commitTheme(key) {
        var d = win._themeDef(key)
        if (d && d.pro === true && !win.isPro) { win.endThemePreview(); licenseDialog.open(); return }
        store.setAppearance("themeMode", key)
    }
    // Transient "Starting hub…" feedback: set when the user hits Start, cleared
    // when the hub connects (see the backend Connections) or a safety timeout.
    property bool hubStarting: false
    Timer { id: hubStartTimeout; interval: 8000; repeat: false
        onTriggered: win.hubStarting = false }

    function currentPageName() {
        var p = store.pages()[currentPageIndex]
        return p ? p.name : ""
    }
    // Commit whatever is typed in the rename field to the page the field belongs to
    // (`pageName.forIndex`, NOT the current page — the two differ exactly when the
    // user switches page mid-edit, which is the case that used to lose the name).
    //
    // Audit F1: the field committed on `editingFinished` alone. Nothing else in the
    // pane takes keyboard focus (the chips and buttons are MouseAreas), so it never
    // blurred: typing "Yen" and clicking another page chip ran the index handler,
    // which overwrote the field with the new page's name — the rename was gone,
    // silently. Every neighbouring control applies instantly, so an Enter-only
    // contract is unguessable. Now every path out of the field commits it.
    function commitRename() {
        var i = pageName.forIndex
        var pages = store.pages()
        if (i < 0 || i >= pages.length) return
        // No-op guard: this runs on every page switch, and renamePage() bumps the
        // structure revision (rebuilding every chip + tile) even for an equal name.
        if (pageName.text === pages[i].name) return
        store.renamePage(i, pageName.text)
        // Reflect the validated (trimmed / de-duped) name the store actually stored.
        if (i === win.currentPageIndex) pageName.text = win.currentPageName()
    }
    // Keep the rename field in step with the selected page WITHOUT a `text:` binding
    // (a binding breaks the moment the user types, which caused wrong-page renames).
    onCurrentPageIndexChanged: {
        commitRename()                       // save the previous page's edit first
        pageName.forIndex = currentPageIndex
        pageName.text = currentPageName()
    }

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

    // ── Licence (Pro tier) state, kept fresh ──
    // Parsed from the backend's stored-key status. Re-read whenever the key
    // changes (activate/remove) so the About card and any gated affordance
    // update without a manual refresh. Never trust a cached bool — the tier is
    // always recomputed from the signed key by the Rust verifier.
    property var licStatus: ({ state: "unlicensed", tier: "free" })
    property bool isPro: licStatus.tier === "pro"
    function refreshLicense() {
        try { win.licStatus = JSON.parse(backend.licenseStatusJson()) }
        catch (e) { win.licStatus = ({ state: "unlicensed", tier: "free" }) }
    }
    Connections {
        target: backend
        function onLicenseChanged() { win.refreshLicense() }
        function onConfigChanged() { win.refreshLicense() }
    }

    // ── Hover previews (show, then commit) ──
    // Hovering a theme/accent swatch applies it to the Manager's theme instance
    // ONLY — the live preview pane repaints, the store (and hence the Edge and
    // disk) is untouched until the user clicks. endThemePreview() restores the
    // stored appearance; it must void the signature guard first or syncTheme()
    // would skip the "unchanged" payload and strand the hover colours.
    function previewTheme(mode) {
        theme.applyTheme(mode)
        var a = store.appearance() || ({})
        if (a.accent) theme.applyAccent(a.accent)   // applyTheme resets the accent
    }
    function previewAccent(name) { theme.applyAccent(name) }
    function endThemePreview() { _appearanceSig = ""; syncTheme() }

    // Hover-preview is DEBOUNCED. Wheel-scrolling the swatch grid drags many
    // swatches under a stationary cursor, firing onContainsMouseChanged for each
    // one; routed straight to previewTheme() that was a storm of ~20 theme
    // property writes per swatch per frame — the other half of the scroll lag the
    // audit found. Coalescing to the LAST hover after a short idle collapses the
    // storm to a single applyTheme and is imperceptible for a genuine hover.
    property string _hoverKind: ""     // "theme" | "accent"
    property string _hoverKey: ""      // "" → restore the committed appearance
    Timer {
        id: hoverPreviewTimer; interval: 45; repeat: false
        onTriggered: {
            if (win._hoverKey === "") { win.endThemePreview(); return }
            if (win._hoverKind === "accent") win.previewAccent(win._hoverKey)
            else win.previewTheme(win._hoverKey)
        }
    }
    function hoverPreview(kind, key, on) {
        win._hoverKind = kind
        win._hoverKey = on ? key : ""
        hoverPreviewTimer.restart()
    }

    // Add a curated "screen" as a NEW page (additive) — never replaces the user's
    // other pages, and never touches the global theme/accent. store.appendPreset
    // persists + pushes live to a running hub, and returns the new page index so we
    // land the user on the screen they just added.
    function applyPresetScreen(presetId) {
        if (!presetLib.has(presetId)) return
        var idx = store.appendPreset(presetId)
        if (idx < 0) return
        // Sync the rename field to the new page BEFORE moving currentPageIndex —
        // onCurrentPageIndexChanged runs commitRename(), which would otherwise write
        // the STALE field text onto the freshly-added page (e.g. renaming its page
        // to a leftover name). Setting forIndex+text to the target makes that
        // commitRename a no-op.
        pageName.forIndex = idx
        pageName.text = store.pages()[idx].name
        win.currentPageIndex = idx
    }
    function confirmApplyPreset(presetId, title) {
        // Additive and non-destructive, but a light confirm sets the expectation:
        // a page is ADDED, the rest of the layout and the theme stay put.
        confirmDialog.message = "Add the “" + title + "” screen as a new page? "
            + "Your other pages and your theme are untouched."
        confirmDialog.onConfirm = function () { win.applyPresetScreen(presetId) }
        confirmDialog.open()
    }

    // Reset every page + widget to the default layout (a clean starting point).
    // Uploaded images live on disk and are untouched.
    function confirmResetLayout() {
        confirmDialog.message = "Reset every page and widget to the default layout? "
            + "This can't be undone. Your uploaded images are kept."
        confirmDialog.onConfirm = function () {
            store.resetTo("starter")   // the recommended few-screen default
            // Sync the rename field to page 0 BEFORE moving currentPageIndex, so
            // onCurrentPageIndexChanged's commitRename can't write the stale field
            // onto a reset page (see applyPresetScreen).
            pageName.forIndex = 0
            pageName.text = store.pages()[0].name
            win.currentPageIndex = 0
        }
        confirmDialog.open()
    }

    // Removing a page discards its widgets and their settings — the only
    // destructive click in the Manager that skipped the confirm dialog.
    function confirmRemovePage() {
        var idx = currentPageIndex
        var n = pageTiles().length
        confirmDialog.message = "Remove page “" + currentPageName() + "”"
            + (n > 0 ? " and its " + n + " widget" + (n === 1 ? "" : "s") : "")
            + "? This can't be undone."
        confirmDialog.onConfirm = function () {
            store.removePage(idx)
            // Stay on the page that slid into this slot (clamped).
            win.currentPageIndex = Math.min(idx, store.pageCount() - 1)
        }
        confirmDialog.open()
    }

    Component.onCompleted: { store.load(backend.starterLayout()); syncTheme(); refreshImages(); refreshLicense() }

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
            // maximumWidth, not just preferredWidth: a child wider than 240 (a long
            // label + a scope pill on one row) otherwise widens the whole sidebar and
            // steals it from the content pane.
            Layout.preferredWidth: 240
            Layout.maximumWidth: 240
            Layout.fillHeight: true
            color: m.panel
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                // Brand lockup, top to bottom: the "EdgeHub" wordmark in the company
                // brand face, a small "by SKYPhoenix IT" maker line, then the logo
                // small beneath — the order Simon asked for. The logo variant follows
                // the surface it sits on so it stays legible: white on a dark
                // background, black on a light one, the colour lockup on the neutral
                // Default chrome. The version lives in the About view.
                Text {
                    text: "EdgeHub"; color: m.textPrimary
                    font.family: theme.fontBrand; font.pixelSize: 30; font.bold: true
                    font.letterSpacing: 0.5
                }
                Text {
                    text: "by SKYPhoenix IT"; color: m.textSecondary
                    font.family: theme.fontMono; font.pixelSize: 10; font.letterSpacing: 0.5
                }
                Image {
                    Layout.preferredWidth: 104; Layout.preferredHeight: 44
                    Layout.topMargin: 6; Layout.bottomMargin: 12
                    fillMode: Image.PreserveAspectFit; horizontalAlignment: Image.AlignLeft
                    smooth: true; asynchronous: true; mipmap: true
                    source: appSettings.chromeTheme === "light" ? "qrc:/manager/branding/sky-black.png"
                          : appSettings.chromeTheme === "default" ? "qrc:/manager/branding/sky-color.png"
                          : "qrc:/manager/branding/sky-white.png"
                }

                Repeater {
                    model: [ { l: "Layout", i: "ui-layout" }, { l: "Appearance", i: "ui-palette" },
                             { l: "Images", i: "ui-image" }, { l: "Display", i: "ui-display" },
                             { l: "About", i: "ui-settings" } ]
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
                                color: nav.currentIndex === index ? m.textOnAccent : m.textSecondary }
                            Text {
                                text: modelData.l
                                color: nav.currentIndex === index ? m.textOnAccent : m.textPrimary
                                font.pixelSize: 15; font.bold: nav.currentIndex === index
                            }
                        }
                        MouseArea { id: navMA; anchors.fill: parent; hoverEnabled: true
                            onClicked: nav.currentIndex = index }
                    }
                }

                Item { Layout.fillHeight: true }

                // The "Manager window style" control used to live HERE in the
                // sidebar, far from Appearance → "Edge theme" — the audit's top
                // confusion (two unlabelled "theme" controls in two places). It now
                // sits inside the Appearance tab beside the Edge theme, so both
                // theme pickers are together with unmistakable scope pills.

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
            // Leaving the Layout tab is also a way out of the rename field that
            // never blurs it — commit rather than strand the edit (audit F1).
            onCurrentIndexChanged: win.commitRename()

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
                                color: win.currentPageIndex === index ? m.accent
                                       : (pgMA.containsMouse ? m.panelAlt : m.panel)
                                border.width: 1; border.color: m.border
                                Text { id: pageLbl; anchors.centerIn: parent; text: modelData.name
                                    color: win.currentPageIndex === index ? m.textOnAccent : m.textPrimary
                                    font.pixelSize: 14; font.bold: win.currentPageIndex === index }
                                MouseArea { id: pgMA; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.currentPageIndex = index }
                            }
                        }
                        Rectangle {
                            width: m.touch; height: m.touch; radius: m.radius
                            color: addPgMA.containsMouse ? m.panelAlt : m.panel
                            border.width: 1; border.color: m.border
                            AppIcon { anchors.centerIn: parent; name: "ui-plus"; color: m.accent; size: 22 }
                            MouseArea { id: addPgMA; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
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
                            // The page this text belongs to. Held separately from
                            // currentPageIndex so a mid-edit page switch can still
                            // commit to the RIGHT page (audit F1).
                            property int forIndex: 0
                            Component.onCompleted: { forIndex = win.currentPageIndex; text = win.currentPageName() }
                            background: Rectangle { radius: 8; color: m.panel; border.width: 1
                                border.color: pageName.activeFocus ? m.accent : m.border }
                            onEditingFinished: win.commitRename()
                        }
                        ScopeTag { label: win.scopeLabels.page; Layout.alignment: Qt.AlignVCenter }
                        Item { Layout.fillWidth: true }
                        MButton { text: "Remove page"; iconName: "ui-trash"
                            enabled: (store.revision, store.pageCount() > 1)
                            onClicked: win.confirmRemovePage() }
                    }

                    // The page background override moved into the helper column
                    // beside the clone: it is a per-page appearance choice, and in
                    // the audit it dominated the tab and buried the layout tool.

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
                            // Pause the live preview while the helper column scrolls, so an
                            // animated preview doesn't repaint every scroll frame.
                            scrolling: helperScroll.contentItem ? helperScroll.contentItem.moving : false
                            onConfigRequested: (tileId, tileType) => cfgDialog.openFor(tileId, tileType)
                        }

                        // Helper column: add + how-to + this page's background.
                        MScroll {
                            id: helperScroll
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            contentWidth: availableWidth
                            ColumnLayout {
                                width: helperScroll.availableWidth
                                spacing: 12
                                MButton { text: "Add widget"; iconName: "ui-plus"; primary: true
                                    Layout.fillWidth: true; Layout.preferredHeight: m.touch
                                    onClicked: addPicker.open() }
                                MButton { text: "Start from a preset screen…"; iconName: "ui-layout"
                                    Layout.fillWidth: true; Layout.preferredHeight: m.touch
                                    onClicked: presetDialog.open() }

                                // Per-page column layout. One screen never scrolls, so
                                // "2 columns" reflows this page's widgets to half width
                                // (two across) and new widgets default to half width too;
                                // "1 column" makes them full width again. A switch that
                                // would overflow the screen is refused by the store, so
                                // the buttons never create a page you cannot see.
                                RowLayout {
                                    Layout.topMargin: 6; spacing: 8
                                    Text { text: "Columns"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                                    ScopeTag { label: win.scopeLabels.page }
                                }
                                Text { text: "How many widgets sit side by side on this page. Switching reflows the widgets already here to fit — a page always stays one screen (it never scrolls)."
                                    color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Repeater {
                                        model: [ { n: 1, l: "1 column" }, { n: 2, l: "2 columns" } ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true; height: m.touch; radius: m.radius
                                            property bool sel: (store.structureRevision,
                                                store.pageColumns(win.currentPageIndex)) === modelData.n
                                            color: sel ? m.accent : (colMA.containsMouse ? m.panelAlt : m.panel)
                                            border.width: 1; border.color: m.border
                                            Text { anchors.centerIn: parent; text: modelData.l
                                                color: parent.sel ? m.textOnAccent : m.textPrimary; font.pixelSize: 13 }
                                            MouseArea { id: colMA; anchors.fill: parent; hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: store.setPageColumns(win.currentPageIndex, modelData.n) }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true; Layout.preferredHeight: hintCol.implicitHeight + 24
                                    radius: m.radius; color: m.panel; border.width: 1; border.color: m.border
                                    ColumnLayout {
                                        id: hintCol; anchors.fill: parent; anchors.margins: 12; spacing: 6
                                        Text { text: "This is your Edge"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; color: m.textSecondary; font.pixelSize: 13
                                            text: "• Click a tile (or ⚙) to configure that widget\n• Drag a tile onto another to reorder\n• Drag the ⤡ corner to resize\n• ✕ removes the widget from this page" }
                                        Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: 12
                                            text: win.liveNote
                                            color: backend.hubConnected ? m.success : m.textSecondary }
                                    }
                                }
                                RowLayout {
                                    Layout.topMargin: 6; spacing: 8
                                    Text { text: "This page's background"; color: m.textPrimary
                                        font.pixelSize: 15; font.bold: true }
                                    ScopeTag { label: win.scopeLabels.page }
                                }
                                Text { text: "Overrides the Edge-wide background from Appearance, for this page alone. “Use global” returns to the shared one."
                                    color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                BackgroundPicker {
                                    Layout.fillWidth: true
                                    store: store; pageIndex: win.currentPageIndex; col: win.mCol
                                    bgCatalog: bgCatalog; wpCatalog: bundledWallpapers; uploadedImages: win.uploadedWallpapers
                                }
                                Item { Layout.preferredHeight: 8 }
                            }
                        }
                    }
                }
            }

            // ═══ 2. APPEARANCE ═══
            // Two panes: controls left, a live Edge preview right. The audit's
            // second-biggest finding: every control here changes the Edge, but the
            // only rendering of the Edge lived on the Layout tab — so theme/accent/
            // glass picks gave zero visible feedback. Now they repaint the preview
            // as you hover, before anything is committed.
            Item {
              RowLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 20

               MScroll {
                id: apScroll
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: apScroll.availableWidth
                    spacing: 18
                    Text { text: "Appearance"; color: m.textPrimary; font.pixelSize: 24; font.bold: true }
                    // Audit F2: this line used to promise "Hover a swatch to try it —
                    // nothing is applied until you click" for the WHOLE tab, but the
                    // Background chips two sections down commit on click with no
                    // try-on. A user trusting the header would change their background
                    // while "trying" it. Say what is true, and name the sections it is
                    // true of. (Giving the background chips a real hover preview would
                    // be the better fix — it needs BackgroundPicker, which this
                    // workstream does not own. Recorded in the audit.)
                    Text { text: "How your Edge looks. Hover a theme or accent to try it in the preview — those two apply only when you click. Every other control here applies as soon as you change it."
                        color: m.textSecondary; font.pixelSize: 14; Layout.fillWidth: true; wrapMode: Text.WordWrap }

                    RowLayout {
                        Layout.topMargin: 4; spacing: 8
                        Text { text: "Edge theme"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                        ScopeTag { label: win.scopeLabels.edge }
                    }
                    Text { text: "The colour palette for every page and widget. Hover an option to try it in the preview; click to apply. (The Manager window's own style is a separate control below.)"
                        color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }

                    // Theme dropdown (Hybrid appearance): a compact field that opens a
                    // scrollable list of swatch + name rows. Pro themes are badged and,
                    // if locked, selecting opens the licence dialog (commitTheme). Hover
                    // previews live; closing the popup without committing restores.
                    Rectangle {
                        id: themeField
                        objectName: "themeDropdownField"
                        Layout.fillWidth: true; implicitHeight: 46; radius: m.radius
                        color: themeFieldMA.containsMouse ? m.panelAlt : m.panel
                        border.width: 1; border.color: themePopup.visible ? m.accent : m.border
                        readonly property string curKey: (store.revision, store.appearance().themeMode || "dark")
                        readonly property var curDef: win._themeDef(themeField.curKey)
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                            Rectangle {
                                width: 28; height: 28; radius: 6; border.width: 1; border.color: m.border
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: themeField.curDef ? themeField.curDef.c1 : "#161B22" }
                                    GradientStop { position: 1.0; color: themeField.curDef ? themeField.curDef.c2 : "#0A0E14" }
                                }
                            }
                            Text {
                                Layout.fillWidth: true; elide: Text.ElideRight
                                text: (themeField.curDef ? themeField.curDef.n : themeField.curKey)
                                color: m.textPrimary; font.pixelSize: 14
                            }
                            Text { text: themePopup.visible ? "▴" : "▾"; color: m.textSecondary; font.pixelSize: 14 }
                        }
                        MouseArea {
                            id: themeFieldMA; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: themePopup.visible ? themePopup.close() : themePopup.open()
                        }
                        Popup {
                            id: themePopup
                            y: themeField.height + 4; x: 0; width: themeField.width
                            implicitHeight: Math.min(380, themeList.contentHeight + 12)
                            padding: 6; modal: false; focus: true
                            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                            background: Rectangle { color: m.panel; radius: m.radius; border.width: 1; border.color: m.border }
                            // Restore the committed appearance if the user only hovered.
                            onClosed: win.endThemePreview()
                            contentItem: ListView {
                                id: themeList
                                clip: true; implicitHeight: contentHeight
                                model: win.apThemeModel
                                currentIndex: -1
                                ScrollBar.vertical: ScrollBar {
                                    policy: themeList.contentHeight > themeList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool locked: (modelData.pro === true) && !win.isPro
                                    readonly property bool sel: (store.revision, (store.appearance().themeMode || "dark") === modelData.k)
                                    width: ListView.view ? ListView.view.width : 0
                                    height: 42; radius: 8
                                    color: rowMA.containsMouse ? m.panelAlt : "transparent"
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 10
                                        Rectangle {
                                            width: 26; height: 26; radius: 6; border.width: 1; border.color: m.border
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: modelData.c1 }
                                                GradientStop { position: 1.0; color: modelData.c2 } }
                                        }
                                        Text { Layout.fillWidth: true; elide: Text.ElideRight
                                            text: modelData.n; color: m.textPrimary
                                            font.pixelSize: 14; font.bold: sel }
                                        Rectangle {
                                            visible: locked
                                            implicitWidth: proL.implicitWidth + 12; implicitHeight: 18; radius: 9
                                            color: Qt.rgba(0, 0, 0, 0.30)
                                            Text { id: proL; anchors.centerIn: parent; text: "PRO"
                                                color: m.textSecondary; font.pixelSize: 10; font.bold: true }
                                        }
                                        AppIcon { visible: sel; name: "ui-check"; size: 16; color: m.accent }
                                    }
                                    MouseArea {
                                        id: rowMA; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onContainsMouseChanged: win.hoverPreview("theme", modelData.k, containsMouse)
                                        onClicked: { win.commitTheme(modelData.k); themePopup.close() }
                                    }
                                }
                            }
                        }
                    }

                    // Manager window style — moved here from the sidebar so it sits
                    // right beside the Edge theme. The scope pill makes the
                    // difference explicit: this restyles ONLY the Manager window on
                    // your PC; it never touches the Edge.
                    RowLayout {
                        Layout.topMargin: 4; spacing: 8
                        Text { text: "Manager window style"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                        ScopeTag { label: win.scopeLabels.window }
                    }
                    Text { text: "The look of THIS companion window on your PC — separate from the Edge theme above. Default is the warm SKYPhoenix palette."
                        color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Repeater {
                            model: [ { k: "dark", l: "Dark" }, { k: "light", l: "Light" }, { k: "default", l: "Default" } ]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true; implicitHeight: 40; radius: 8
                                property bool sel: appSettings.chromeTheme === modelData.k
                                color: sel ? m.accent : m.panelAlt
                                border.width: 1; border.color: sel ? m.accent : m.border
                                Text {
                                    anchors.centerIn: parent; text: modelData.l
                                    color: sel ? m.textOnAccent : m.textSecondary
                                    font.pixelSize: 13; font.bold: sel
                                }
                                MouseArea {
                                    anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: appSettings.chromeTheme = modelData.k
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.topMargin: 4; spacing: 8
                        Text { text: "Accent colour"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                        ScopeTag { label: win.scopeLabels.edge }
                    }
                    Text { text: "The highlight colour for rings, buttons and charts. A widget can override it just for itself (⚙ → Widget appearance)."
                        color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    Flow {
                        Layout.fillWidth: true; spacing: 10
                        Repeater {
                            model: m.accentPresets
                            delegate: Rectangle {
                                required property var modelData
                                property bool sel: (store.revision, store.appearance().accent === modelData.name)
                                width: 46; height: 46; radius: 23; color: modelData.c
                                border.width: sel ? 3 : (accMA.containsMouse ? 2 : 0)
                                border.color: m.textPrimary
                                AppIcon { visible: parent.sel; anchors.centerIn: parent
                                    name: "ui-check"; size: 20; color: "#FFFFFF" }
                                // The circles carried no names — hover says which is which.
                                ToolTip.visible: accMA.containsMouse
                                ToolTip.delay: 350
                                ToolTip.text: modelData.name
                                MouseArea { id: accMA; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: win.hoverPreview("accent", modelData.name, containsMouse)
                                    onClicked: store.setAppearance("accent", modelData.name) }
                            }
                        }
                    }

                    RowLayout {
                        Layout.topMargin: 4; spacing: 8
                        Text { text: "Background"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                        ScopeTag { label: win.scopeLabels.pages }
                    }
                    Text { text: "Pick an animated style OR a wallpaper — the default every page starts from. One page can go its own way in Layout → “This page's background”."
                        color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    RowLayout { visible: !theme.decorative; Layout.fillWidth: true; spacing: 6
                        AppIcon { name: "ui-warning"; size: 14; color: m.danger; Layout.alignment: Qt.AlignTop }
                        Text { text: "The High Contrast theme keeps backgrounds off for legibility — switch themes to see them."
                            color: m.danger; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap } }
                    BackgroundPicker {
                        Layout.fillWidth: true
                        store: store; pageIndex: -1; col: win.mCol
                        bgCatalog: bgCatalog; wpCatalog: bundledWallpapers; uploadedImages: win.uploadedWallpapers
                        // Hover a style chip → preview it live in the clone without
                        // committing (finally makes the tab's "hover to try" true for
                        // backgrounds too — audit F2).
                        onPreviewStyle: (v) => theme.previewBgStyle = v
                        onPreviewEnded: theme.previewBgStyle = ""
                    }

                    // A default "Layout columns" picker stood here, alongside the
                    // per-page override. Both are gone for the same reason: the grid
                    // is fixed at WidgetSizes.shortHalves across the short axis, so
                    // `1x1` means one third of the screen on every page.

                    RowLayout {
                        Layout.topMargin: 4; spacing: 8
                        Text { text: "Effects"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                        ScopeTag { label: win.scopeLabels.edge }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        Text { text: "Glassiness"; color: m.textSecondary; font.pixelSize: 14; Layout.preferredWidth: 120 }
                        Slider {
                            id: glassSlider; Layout.fillWidth: true; from: 0; to: 1
                            // Bind to theme.glassOpacity — a STABLE Theme property kept in
                            // step with the store by syncTheme() — NOT to store.revision.
                            // The Appearance preview renders live cpu/gpu/ram widgets that
                            // write sparkline history every ~2s, bumping store.revision; a
                            // revision-bound value re-evaluated on every bump and snapped the
                            // handle back to the (debounced, stale) stored value mid-drag —
                            // the "can't move the slider" bug. theme.glassOpacity only moves
                            // when we move it, so the drag holds (this mirrors the working hub
                            // slider, SettingsPanel.qml).
                            value: theme.glassOpacity
                            // Token-styled groove/handle so the raw Fusion control follows
                            // the chosen accent instead of the default light gray.
                            background: Rectangle {
                                x: glassSlider.leftPadding
                                y: glassSlider.topPadding + glassSlider.availableHeight / 2 - height / 2
                                // implicit* MUST be set: the Slider derives its own implicit
                                // size (and thus its hit area) from the background/handle. A
                                // Rectangle's implicit size is 0, so without these the whole
                                // Slider collapsed to ~0 height and could not be pressed or
                                // dragged — the real "stuck at 55%" bug.
                                implicitWidth: 200; implicitHeight: 6
                                width: glassSlider.availableWidth; height: 6; radius: 3
                                color: m.panelAlt; border.width: 1; border.color: m.border
                                Rectangle {
                                    width: glassSlider.visualPosition * parent.width; height: parent.height
                                    radius: 3; color: m.accent
                                }
                            }
                            handle: Rectangle {
                                x: glassSlider.leftPadding + glassSlider.visualPosition * (glassSlider.availableWidth - width)
                                y: glassSlider.topPadding + glassSlider.availableHeight / 2 - height / 2
                                // See background: implicit size gives the Slider a real hit area.
                                implicitWidth: 20; implicitHeight: 20
                                width: 20; height: 20; radius: 10
                                color: glassSlider.pressed ? Qt.lighter(m.accent, 1.15) : m.textOnAccent
                                border.width: 2; border.color: m.accent
                            }
                            // Live-preview the theme while dragging (cheap: opacity only),
                            // but debounce the persisted store write so we don't reapply the
                            // whole theme + save on every frame.
                            onMoved: {
                                theme.glassOpacity = value
                                // Re-assert the binding the drag severs so external/hub
                                // pushes still move the handle [S2]; value === theme.glassOpacity
                                // right now, so this causes no jump.
                                value = Qt.binding(function() { return theme.glassOpacity })
                                glassCommit.restart()
                            }
                            Timer { id: glassCommit; interval: 180; repeat: false
                                onTriggered: {
                                    store.setAppearance("glass", glassSlider.value)
                                    glassSlider.value = Qt.binding(function() { return theme.glassOpacity })
                                } }
                        }
                        Text { text: Math.round(glassSlider.value * 100) + "%"
                            color: m.textPrimary; font.pixelSize: 13; font.bold: true
                            Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                    }

                    Text { text: "How see-through widget cards are: 0% solid, 100% pure glass."
                        color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }

                    ColumnLayout {
                        spacing: 12
                        // A Switch severs its `checked:` binding on first toggle, so
                        // without re-asserting it here a later store/hub push could
                        // never move the control again [S2]. Re-bind after each write.
                        // One-line consequence note under each switch: their labels
                        // alone did not say what would visibly change, or that
                        // "Reduce motion" beats the other two.
                        ColumnLayout {
                            spacing: 2
                            MSwitch {
                                text: "Widget glow"
                                checked: { store.revision; var g = store.appearance().glow; return g === undefined ? true : g }
                                onToggled: {
                                    store.setAppearance("glow", checked)
                                    checked = Qt.binding(function() { store.revision; var g = store.appearance().glow; return g === undefined ? true : g })
                                }
                            }
                            Text { text: "A soft coloured halo behind each widget card."
                                color: m.textSecondary; font.pixelSize: 12; Layout.leftMargin: 56
                                Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        }
                        ColumnLayout {
                            spacing: 2
                            MSwitch {
                                text: "Animated background"
                                checked: { store.revision; var g = store.appearance().animatedBg; return g === undefined ? true : g }
                                onToggled: {
                                    store.setAppearance("animatedBg", checked)
                                    checked = Qt.binding(function() { store.revision; var g = store.appearance().animatedBg; return g === undefined ? true : g })
                                }
                            }
                            Text { text: "Lets the background style above move. Off = it stands still. Not used while a wallpaper is set."
                                color: m.textSecondary; font.pixelSize: 12; Layout.leftMargin: 56
                                Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        }
                        ColumnLayout {
                            spacing: 2
                            MSwitch {
                                text: "Reduce motion"
                                checked: (store.revision, store.appearance().reduceMotion || false)
                                onToggled: {
                                    store.setAppearance("reduceMotion", checked)
                                    checked = Qt.binding(function() { store.revision; return store.appearance().reduceMotion || false })
                                }
                            }
                            Text { text: "Calms the whole Edge: stills backgrounds and widget animations. Wins over the two switches above."
                                color: m.textSecondary; font.pixelSize: 12; Layout.leftMargin: 56
                                Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        }
                    }
                    Item { Layout.preferredHeight: 12 }   // bottom padding
                }
               }

                // ── Live preview pane (the same WYSIWYG clone as Layout, read-only) ──
                ColumnLayout {
                    Layout.preferredWidth: 400; Layout.maximumWidth: 400; Layout.fillHeight: true
                    spacing: 8
                    Text { text: "Live preview"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                    // Page chips so "which page am I looking at?" has an answer —
                    // and per-page overrides can be checked without leaving the tab.
                    Flow {
                        Layout.fillWidth: true; spacing: 6
                        Repeater {
                            model: (store.structureRevision, store.pages())
                            delegate: Rectangle {
                                required property int index
                                required property var modelData
                                width: apPgLbl.implicitWidth + 24; height: m.touch; radius: 8
                                color: win.currentPageIndex === index ? m.accent
                                       : (apPgMA.containsMouse ? m.panelAlt : m.panel)
                                border.width: 1; border.color: m.border
                                Text { id: apPgLbl; anchors.centerIn: parent; text: modelData.name
                                    color: win.currentPageIndex === index ? m.textOnAccent : m.textSecondary
                                    font.pixelSize: 12; font.bold: win.currentPageIndex === index }
                                MouseArea { id: apPgMA; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.currentPageIndex = index }
                            }
                        }
                    }
                    EdgeClone {
                        editable: false
                        Layout.fillWidth: true; Layout.fillHeight: true
                        pageIndex: win.currentPageIndex
                        // Pause the live preview while the Appearance controls scroll.
                        scrolling: apScroll.contentItem ? apScroll.contentItem.moving : false
                    }
                    Text { text: win.liveNote; color: backend.hubConnected ? m.success : m.textSecondary
                        font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
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

                    // Audit F6: clicking a card writes appearance.wallpaper — the
                    // biggest unlabelled scope jump in the app. The tab had no pill,
                    // no preview, and copy ("use it as the wallpaper") that never said
                    // every page changes. Say the scope, and say where to undo it.
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text { text: "Your images"; color: m.textSecondary; font.pixelSize: 14; font.bold: true }
                        ScopeTag { visible: imagesModel.count > 0; label: win.scopeLabels.pages }
                        Item { Layout.fillWidth: true }
                    }
                    Text { text: "Click an image to make it the wallpaper on every page. To use one on a single page instead, go to Layout → “This page's background”."
                        color: m.textSecondary; font.pixelSize: 12; visible: imagesModel.count > 0
                        Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    // Empty state. The trailing filler keeps the column top-packed while the
                    // grid is hidden — without it the few remaining rows spread out
                    // over the full tab height (audit finding F8).
                    Text { visible: imagesModel.count === 0; Layout.fillWidth: true; Layout.topMargin: 24
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                        text: "No images yet — use “Import image…” to add one."
                        color: m.textSecondary; font.pixelSize: 14 }
                    Item { visible: imagesModel.count === 0; Layout.fillHeight: true }
                    GridView {
                        id: imgGrid
                        visible: imagesModel.count > 0
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                        cellWidth: 190; cellHeight: 190
                        model: imagesModel
                        // Usable mouse-wheel step (see MScroll) — a GridView is a
                        // Flickable too and hits the same tiny-per-notch problem.
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: function (ev) {
                                var dy = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y
                                var maxY = Math.max(0, imgGrid.contentHeight - imgGrid.height)
                                imgGrid.contentY = Math.max(0, Math.min(maxY, imgGrid.contentY - dy * 1.1))
                                ev.accepted = true
                            }
                        }
                        ScrollBar.vertical: ScrollBar {
                            policy: imgGrid.contentHeight > imgGrid.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle { implicitWidth: 6; radius: 3; color: m.border }
                        }
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

            // ═══ 4. DISPLAY ═══
            Item {
              MScroll {
                id: dpScroll
                anchors.fill: parent; clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: dpScroll.availableWidth - 48
                    x: 24; y: 24; spacing: 16
                    Text { text: "Display & Startup"; color: m.textPrimary; font.pixelSize: 24; font.bold: true }
                    // Audit F7: "Applies next time the hub starts" used to sit HERE,
                    // as the tab subtitle — above Orientation (which pushes live) and
                    // the autostart switch (immediate). Read as tab-level guidance it
                    // simply wasn't true, so it moved down onto the screen picker,
                    // which is the only thing it describes.
                    Text { text: "Where the hub runs, how it's turned, and whether it starts itself."
                        color: m.textSecondary; font.pixelSize: 14; Layout.fillWidth: true; wrapMode: Text.WordWrap }

                    RowLayout {
                        Layout.topMargin: 8; spacing: 8
                        Text { text: "Screen the hub runs on"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                        ScopeTag { label: win.scopeLabels.computer }
                    }
                    Text { text: "Applies next time the hub starts — a running hub stays where it is."
                        color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }

                    // Audit F8 / W5 #13: with no screens the tab showed a sentence
                    // about choosing a screen, then blank space, then Orientation —
                    // so Orientation read as the answer to "choose which screen".
                    Rectangle {
                        objectName: "screensEmpty"
                        visible: win.screens.length === 0
                        Layout.fillWidth: true; Layout.preferredHeight: 64
                        radius: m.radius; color: m.panel
                        border.width: 1; border.color: m.border
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 12
                            AppIcon { name: "ui-display"; color: m.textSecondary; size: 22 }
                            Text {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                                text: "No screens detected. Connect your Xeneon Edge (or any display) and it will appear here."
                                color: m.textSecondary; font.pixelSize: 13
                            }
                        }
                    }

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

                    RowLayout {
                        Layout.topMargin: 8; spacing: 8
                        Text { text: "Orientation"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                        ScopeTag { label: win.scopeLabels.edge }
                    }
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
                                color: sel ? m.accent : (oriMA.containsMouse ? m.panelAlt : m.panel)
                                border.width: 1; border.color: m.border
                                Text { id: oriLbl; anchors.centerIn: parent; text: modelData.l
                                    color: sel ? m.textOnAccent : m.textPrimary; font.pixelSize: 13 }
                                MouseArea { id: oriMA; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: store.setAppearance("orientation", modelData.v) }
                            }
                        }
                    }

                    // Audit F8: the one control that reaches outside the Edge entirely
                    // (it writes a login autostart entry) carried no scope and no note.
                    RowLayout {
                        Layout.topMargin: 8; spacing: 8
                        Text { text: "Startup"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                        ScopeTag { label: win.scopeLabels.computer }
                    }
                    ColumnLayout {
                        spacing: 2
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
                        Text { text: "Adds the hub to this computer's login startup. Takes effect at your next login; it doesn't start or stop the hub now."
                            color: m.textSecondary; font.pixelSize: 12; Layout.leftMargin: 56
                            Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }

                    // ── Software updates (opt-in) ──
                    // Mirrors the hub's own toggle so it is DISCOVERABLE here in the
                    // full-control Manager (the hub buries it in the on-panel
                    // settings — "where is autoupdate?"). Off by default: EdgeHub
                    // never phones home on its own. The Manager only sets the flag;
                    // the actual check runs on the hub through its audited network
                    // gate, so the Manager adds no new egress surface.
                    RowLayout {
                        Layout.topMargin: 8; spacing: 8
                        Text { text: "Software updates"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                        ScopeTag { label: win.scopeLabels.edge }
                    }
                    ColumnLayout {
                        spacing: 2
                        MSwitch {
                            id: updateSwitch
                            text: "Check for updates automatically"
                            checked: { store.revision; return store.appearance().updateCheck === true }
                            onToggled: {
                                store.setAppearance("updateCheck", checked)
                                checked = Qt.binding(function () { store.revision; return store.appearance().updateCheck === true })
                            }
                        }
                        Text { text: "Off by default — EdgeHub never checks on its own. When on, the Edge asks GitHub for the latest release tag through its audited network gate (nothing identifying is sent) and shows the result on the display itself. Install updates with your package manager."
                            color: m.textSecondary; font.pixelSize: 12; Layout.leftMargin: 56
                            Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }

                    // ── Troubleshooting / reset ──
                    RowLayout {
                        Layout.topMargin: 8; spacing: 8
                        Text { text: "Troubleshooting"; color: m.textPrimary; font.pixelSize: 15; font.bold: true }
                        ScopeTag { label: win.scopeLabels.edge }
                    }
                    Text { text: "Start over from a clean default layout. Your uploaded images are kept — only pages and widgets are reset."
                        color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        MButton { objectName: "resetLayoutBtn"; text: "Reset to default layout"; iconName: "ui-trash"
                            onClicked: win.confirmResetLayout() }
                        Item { Layout.fillWidth: true }
                    }

                    Item { Layout.preferredHeight: 12 }   // bottom padding
                }
              }
            }

            // ═══ 5. ABOUT ═══
            Item {
              MScroll {
                id: abScroll
                anchors.fill: parent; clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: abScroll.availableWidth - 48
                    x: 24; y: 24; spacing: 14

                    Text { text: "About"; color: m.textPrimary; font.pixelSize: 24; font.bold: true }

                    // Brand card: theme-aware logo + wordmark + maker line.
                    Rectangle {
                        Layout.fillWidth: true; Layout.topMargin: 4
                        radius: m.radius; color: m.panel
                        border.width: 1; border.color: m.border
                        implicitHeight: aboutBrand.implicitHeight + 40
                        ColumnLayout {
                            id: aboutBrand
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 20; spacing: 4
                            Text {
                                text: "EdgeHub"; color: m.textPrimary
                                font.family: theme.fontBrand; font.pixelSize: 40; font.bold: true
                                font.letterSpacing: 0.5
                            }
                            Text {
                                text: "by SKYPhoenix IT"; color: m.textSecondary
                                font.family: theme.fontMono; font.pixelSize: 12; font.letterSpacing: 0.5
                            }
                            Image {
                                Layout.preferredWidth: 150; Layout.preferredHeight: 60
                                Layout.topMargin: 8
                                fillMode: Image.PreserveAspectFit; horizontalAlignment: Image.AlignLeft
                                smooth: true; asynchronous: true; mipmap: true
                                source: appSettings.chromeTheme === "light" ? "qrc:/manager/branding/sky-black.png"
                                      : appSettings.chromeTheme === "default" ? "qrc:/manager/branding/sky-color.png"
                                      : "qrc:/manager/branding/sky-white.png"
                            }
                        }
                    }

                    // Version + description.
                    RowLayout {
                        Layout.fillWidth: true; Layout.topMargin: 6; spacing: 8
                        Text { text: "Version:"; color: m.textSecondary; font.pixelSize: 14 }
                        Text {
                            text: (backend && backend.appVersion ? backend.appVersion() : "?")
                            color: m.textPrimary; font.pixelSize: 14; font.family: theme.fontMono
                            Layout.fillWidth: true; elide: Text.ElideRight
                        }
                    }
                    Text {
                        text: "A native Linux widget dashboard for your second screen."
                        color: m.textPrimary; font.pixelSize: 14
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                    }

                    // ── Licence card ──
                    // Free by default; Pro when a valid key is stored. Everything
                    // functional is free — Pro unlocks the premium theme/preset
                    // packs and custom user widgets. "expired" is worded as
                    // renew-not-broken (the signature was genuine).
                    Rectangle {
                        Layout.fillWidth: true; Layout.topMargin: 8
                        radius: m.radius; color: m.panel
                        border.width: 1
                        border.color: win.isPro ? m.accent : m.border
                        implicitHeight: licCol.implicitHeight + 32
                        ColumnLayout {
                            id: licCol
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.top: parent.top; anchors.margins: 16; spacing: 8
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                AppIcon {
                                    name: win.isPro ? "ui-check" : "ui-settings"
                                    size: 22; color: win.isPro ? m.accent : m.textSecondary
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                ColumnLayout {
                                    spacing: 1; Layout.fillWidth: true
                                    Text {
                                        text: win.isPro ? "Xeneon Edge Pro"
                                            : win.licStatus.state === "expired" ? "Pro licence expired"
                                            : "Free tier"
                                        color: m.textPrimary; font.pixelSize: 17; font.bold: true
                                    }
                                    Text {
                                        text: win.isPro
                                              ? ("Thank you" + (win.licStatus.issuedTo
                                                   ? ", " + win.licStatus.issuedTo : "") + " — premium unlocked.")
                                            : win.licStatus.state === "expired"
                                              ? "Renew to keep the premium extras. Your dashboards keep working."
                                            : "Everything works. Pro adds premium themes, preset packs and custom widgets."
                                        color: m.textSecondary; font.pixelSize: 12
                                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                MButton {
                                    text: win.isPro ? "Manage licence" : "Activate Pro"
                                    iconName: "ui-settings"
                                    onClicked: licenseDialog.open()
                                }
                                MButton {
                                    visible: !win.isPro
                                    text: "Get Pro"; iconName: "ui-display"
                                    onClicked: Qt.openUrlExternally(
                                        "https://github.com/skyphoenix-it/XeneonEdge_Linux#pro")
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }

                    // Links.
                    RowLayout {
                        Layout.fillWidth: true; Layout.topMargin: 6; spacing: 8
                        MButton {
                            text: "Website"; iconName: "ui-display"
                            onClicked: Qt.openUrlExternally("https://www.skyphoenix-it.com")
                        }
                        MButton {
                            text: "GitHub"; iconName: "ui-settings"
                            // The same URL the PKGBUILD, the metainfo and SECURITY.md
                            // already ship. It was "#" — a button that silently did
                            // nothing, which is worse than no button: the user clicks
                            // it, gets no browser and no error, and concludes the app
                            // is broken rather than the link.
                            onClicked: Qt.openUrlExternally(
                                "https://github.com/skyphoenix-it/XeneonEdge_Linux")
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Text {
                        text: "www.skyphoenix-it.com"
                        color: m.textSecondary; font.pixelSize: 12; font.family: theme.fontMono
                    }

                    // ── Diagnostics (for support) ──
                    // The Manager's honest view: connection, displays, and the raw
                    // config on demand. Live network egress counters are a hub-runtime
                    // tally shown on the Edge itself (the hub's own Diagnostics), so
                    // they're pointed to here, never faked with zeros.
                    Rectangle {
                        Layout.fillWidth: true; Layout.topMargin: 8
                        radius: m.radius; color: m.panel; border.width: 1; border.color: m.border
                        implicitHeight: diagCol.implicitHeight + 32
                        ColumnLayout {
                            id: diagCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 16; spacing: 8
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                AppIcon { name: "ui-settings"; size: 18; color: m.textSecondary; Layout.alignment: Qt.AlignVCenter }
                                Text { text: "Diagnostics"; color: m.textPrimary; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
                                MButton { text: diagBox.visible ? "Hide config" : "Show config"
                                    onClicked: diagBox.visible = !diagBox.visible }
                            }
                            Text { text: (backend.hubConnected ? "Hub connected (live)" : "Hub offline (saved)")
                                    + "  ·  " + win.screens.length + " display" + (win.screens.length === 1 ? "" : "s")
                                    + (win.currentTarget.length ? "  ·  target " + win.currentTarget : "")
                                color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            Text { text: "Live network egress counters are shown on the Edge itself (the hub's Diagnostics) — the Manager makes no network requests of its own."
                                color: m.textSecondary; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            Rectangle {
                                id: diagBox; visible: false
                                Layout.fillWidth: true; Layout.preferredHeight: 220
                                radius: m.radius; color: m.bg; border.width: 1; border.color: m.border
                                ScrollView {
                                    anchors.fill: parent; anchors.margins: 8; clip: true
                                    contentWidth: availableWidth
                                    Text {
                                        width: diagBox.width - 16
                                        // Only fetch the config when the box is actually
                                        // shown, and guard the method (the QML test mock
                                        // backend doesn't implement configJson()).
                                        text: {
                                            if (!diagBox.visible) return ""
                                            var _ = store.revision
                                            return (backend && backend.configJson) ? backend.configJson()
                                                                                    : "(config unavailable)"
                                        }
                                        color: m.textSecondary; font.family: theme.fontMono; font.pixelSize: 10
                                        wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        text: "© 2026 SKYPhoenix IT · Independent product"
                        color: m.textSecondary; font.pixelSize: 12
                        Layout.topMargin: 8; Layout.fillWidth: true; wrapMode: Text.WordWrap
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
        width: Math.min(parent ? parent.width * 0.9 : 720, 760)
        height: Math.min(parent ? parent.height * 0.85 : 560, 620)
        standardButtons: Dialog.Close
        background: Rectangle { color: m.panel; radius: m.radius; border.width: 1; border.color: m.border }
        // Audit F4: the picker never said WHICH page the widget lands on — with
        // three pages the only clue was remembering where you were. Name the page
        // and pill the scope, like every other control.
        header: Rectangle {
            color: "transparent"; implicitHeight: 68
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; spacing: 12
                AppIcon { name: "ui-plus"; size: 24; color: m.accent; Layout.alignment: Qt.AlignVCenter }
                ColumnLayout {
                    spacing: 1; Layout.fillWidth: true
                    Text { text: "Add a widget"; color: m.textPrimary; font.pixelSize: 19; font.bold: true }
                    Text {
                        objectName: "addPickerTarget"
                        text: "Adds to the page “" + (store.structureRevision, win.currentPageName()) + "”."
                        color: m.textSecondary; font.pixelSize: 12
                        elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
                ScopeTag { label: win.scopeLabels.page; Layout.alignment: Qt.AlignVCenter }
            }
        }
        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: addPicker.availableWidth
                spacing: 12
                // One screen never scrolls: when the page is full, say so and disable
                // the widgets that will not fit rather than letting a click do nothing.
                Rectangle {
                    Layout.fillWidth: true
                    visible: (store.structureRevision, store.pageIsFull(win.currentPageIndex))
                    implicitHeight: fullRowM.implicitHeight + 16
                    radius: m.radius
                    color: Qt.rgba(m.danger.r, m.danger.g, m.danger.b, 0.12)
                    border.width: 1; border.color: Qt.rgba(m.danger.r, m.danger.g, m.danger.b, 0.5)
                    RowLayout {
                        id: fullRowM
                        anchors.fill: parent; anchors.margins: 8; spacing: 8
                        AppIcon { name: "ui-warning"; size: 18; color: m.danger; Layout.alignment: Qt.AlignVCenter }
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: "This screen is full. Remove or shrink a widget to make room — a page never scrolls."
                            color: m.textPrimary; font.pixelSize: 13
                        }
                    }
                }
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
                                    readonly property bool fits: (store.structureRevision,
                                        store.addWouldFit(win.currentPageIndex, modelData.type))
                                    width: 150; height: 84; radius: m.radius
                                    opacity: fits ? 1.0 : 0.4
                                    color: itemMA.containsMouse ? m.panelAlt : m.bg
                                    border.width: 1; border.color: m.border
                                    ColumnLayout {
                                        anchors.centerIn: parent; spacing: 4
                                        AppIcon { Layout.alignment: Qt.AlignHCenter; name: modelData.type; size: 26; color: m.textPrimary }
                                        Text { Layout.alignment: Qt.AlignHCenter; text: modelData.title
                                            color: m.textPrimary; font.pixelSize: 13 }
                                    }
                                    MouseArea { id: itemMA; anchors.fill: parent; hoverEnabled: true
                                        enabled: parent.fits
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { store.addTile(win.currentPageIndex, modelData.type); addPicker.close() } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Preset "screens" picker ──
    // The full curated library, applied as a whole page set (store.resetTo →
    // persisted + pushed live). Parity with the hub's first-run / preset picker,
    // brought into the Manager so a page set can be started from the PC.
    Dialog {
        id: presetDialog
        title: "Start from a preset screen"
        modal: true; anchors.centerIn: parent
        width: Math.min(parent ? parent.width * 0.9 : 760, 820)
        height: Math.min(parent ? parent.height * 0.85 : 620, 700)
        standardButtons: Dialog.Close
        background: Rectangle { color: m.panel; radius: m.radius; border.width: 1; border.color: m.border }
        header: Rectangle {
            color: "transparent"; implicitHeight: 68
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; spacing: 12
                AppIcon { name: "ui-layout"; size: 24; color: m.accent; Layout.alignment: Qt.AlignVCenter }
                ColumnLayout {
                    spacing: 1; Layout.fillWidth: true
                    Text { text: "Start from a preset screen"; color: m.textPrimary; font.pixelSize: 19; font.bold: true }
                    Text { text: "Replaces every page with a ready-made set. You can tweak it afterwards."
                        color: m.textSecondary; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                ScopeTag { label: win.scopeLabels.edge; Layout.alignment: Qt.AlignVCenter }
            }
        }
        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: presetDialog.availableWidth
                spacing: 10
                Repeater {
                    model: presetLib.list()
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: presetRow.implicitHeight + 24
                        radius: m.radius; color: presetMA.containsMouse ? m.panelAlt : m.bg
                        border.width: 1; border.color: m.border
                        RowLayout {
                            id: presetRow
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 14
                            Text { text: modelData.icon || "🎛"; font.pixelSize: 30
                                Layout.alignment: Qt.AlignVCenter }
                            ColumnLayout {
                                spacing: 2; Layout.fillWidth: true
                                Text { text: modelData.title; color: m.textPrimary
                                    font.pixelSize: 16; font.bold: true }
                                Text { text: modelData.blurb || ""; color: m.textSecondary
                                    font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            }
                            MButton { text: "Use this"; iconName: "ui-check"; primary: true
                                Layout.alignment: Qt.AlignVCenter
                                onClicked: { presetDialog.close()
                                    win.confirmApplyPreset(modelData.id, modelData.title) } }
                        }
                        MouseArea { id: presetMA; anchors.fill: parent; hoverEnabled: true; z: -1 }
                    }
                }
            }
        }
    }

    // ── Per-widget configure (schema-driven form + live preview) ──
    WidgetConfigDialog { id: cfgDialog }

    // ── Licence entry / management ──
    // Paste a key → live preview (verified offline, no network) → Activate. The
    // preview is what makes this safe to commit: the user sees "unlocks Pro for
    // <name>" (or why not) BEFORE it is stored. Storing routes through
    // backend.setLicenseKey, which respects the single-writer rule (pushes to the
    // hub over IPC when connected so the tier re-gates live; writes directly when
    // offline).
    Dialog {
        id: licenseDialog
        modal: true; anchors.centerIn: parent
        width: Math.min(parent ? parent.width * 0.9 : 640, 640)
        standardButtons: Dialog.NoButton
        background: Rectangle { color: m.panel; radius: m.radius; border.width: 1; border.color: m.border }

        // The candidate the user has typed, and its offline-verified status.
        property string candidate: ""
        property var preview: ({ state: "unlicensed", tier: "free" })
        function reVerify() {
            var k = keyField.text.trim()
            licenseDialog.candidate = k
            if (k.length === 0) { licenseDialog.preview = ({ state: "unlicensed", tier: "free" }); return }
            try { licenseDialog.preview = JSON.parse(backend.verifyLicenseCandidate(k)) }
            catch (e) { licenseDialog.preview = ({ state: "unlicensed", tier: "free" }) }
        }
        onOpened: { keyField.text = ""; licenseDialog.reVerify(); keyField.forceActiveFocus() }

        header: Rectangle {
            color: "transparent"; implicitHeight: 60
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; spacing: 12
                AppIcon { name: "ui-settings"; size: 22; color: m.accent; Layout.alignment: Qt.AlignVCenter }
                Text { text: win.isPro ? "Manage your Pro licence" : "Activate Xeneon Edge Pro"
                    color: m.textPrimary; font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
            }
        }

        contentItem: ColumnLayout {
            spacing: 12
            Text {
                text: "Paste the licence key from your purchase e-mail. It is verified on "
                    + "this device — nothing is sent anywhere."
                color: m.textSecondary; font.pixelSize: 13
                Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
            Rectangle {
                Layout.fillWidth: true; radius: m.radius
                color: m.bg; border.width: 1
                border.color: keyField.activeFocus ? m.accent : m.border
                implicitHeight: 92
                TextArea {
                    id: keyField
                    anchors.fill: parent; anchors.margins: 8
                    wrapMode: TextArea.WrapAnywhere
                    placeholderText: "XE1.…"
                    color: m.textPrimary; font.family: theme.fontMono; font.pixelSize: 13
                    selectByMouse: true
                    background: null
                    onTextChanged: licenseDialog.reVerify()
                }
            }
            // Live verdict.
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                visible: licenseDialog.candidate.length > 0
                readonly property bool ok: licenseDialog.preview.tier === "pro"
                readonly property bool expired: licenseDialog.preview.state === "expired"
                AppIcon {
                    name: parent.ok ? "ui-check" : "ui-warning"
                    size: 18; color: parent.ok ? m.accent : (parent.expired ? m.danger : m.textSecondary)
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    color: m.textPrimary; font.pixelSize: 13
                    text: parent.ok
                          ? ("Valid — unlocks Pro"
                             + (licenseDialog.preview.issuedTo ? " for " + licenseDialog.preview.issuedTo : "") + ".")
                        : parent.expired
                          ? "This key has expired. Renew to reactivate Pro."
                        : "Not a valid licence key for this product."
                }
            }
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: 4; spacing: 8
                MButton {
                    visible: win.isPro || win.licStatus.state === "expired"
                    text: "Remove licence"; iconName: "ui-trash"
                    onClicked: { backend.clearLicenseKey(); licenseDialog.close() }
                }
                Item { Layout.fillWidth: true }
                MButton {
                    text: "Cancel"; onClicked: licenseDialog.close()
                }
                MButton {
                    text: "Activate"; iconName: "ui-check"
                    // Only enabled when the pasted key actually unlocks Pro — no
                    // point storing a key the verifier rejects.
                    enabled: licenseDialog.preview.tier === "pro"
                    onClicked: {
                        if (backend.setLicenseKey(licenseDialog.candidate))
                            licenseDialog.close()
                    }
                }
            }
        }
    }

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
        header: Rectangle {
            color: "transparent"; implicitHeight: 52
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18; spacing: 10
                AppIcon { name: "ui-warning"; size: 20; color: m.danger; Layout.alignment: Qt.AlignVCenter }
                Text { text: "Please confirm"; color: m.textPrimary; font.pixelSize: 17; font.bold: true
                    Layout.fillWidth: true }
            }
        }
        contentItem: Text { text: confirmDialog.message; color: m.textPrimary
            wrapMode: Text.WordWrap; padding: 18; font.pixelSize: 14
            // Cap the width so a long message wraps instead of stretching the dialog wide.
            width: Math.min(implicitWidth, 360) }
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

    // objectName is a test seam: EdgeClone owns a ListModel too (its placement
    // model), so "the ListModel in the Manager tree" no longer identifies this one.
    ListModel { id: imagesModel; objectName: "imagesModel" }
    function refreshImages() {
        imagesModel.clear()
        var list = backend.listImages()
        for (var i = 0; i < list.length; i++) imagesModel.append({ modelData: list[i] })
    }

    // Display target state.
    property var screens: {
        // Array.isArray guard: screensJson() should be an array, but a valid
        // non-array JSON ("{}") would otherwise reach the Repeater model as an object.
        try { var s = JSON.parse(backend.screensJson()); return Array.isArray(s) ? s : [] }
        catch (e) { return [] }
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
            pageName.forIndex = win.currentPageIndex
            pageName.text = win.currentPageName()
        }
        // Display hotplug.
        function onScreensChanged() {
            try { var s = JSON.parse(backend.screensJson() || "[]"); win.screens = Array.isArray(s) ? s : [] } catch (e) { win.screens = [] }
            win.currentTarget = backend.targetConnector()
        }
        // Clear the "Starting hub…" state once the hub actually connects.
        function onHubConnectedChanged() { if (backend.hubConnected) win.hubStarting = false }
    }

    // Pull the hub's latest + refresh live state whenever the Manager regains focus.
    onActiveChanged: if (active) {
        backend.syncFromHub()
        try { var s = JSON.parse(backend.screensJson() || "[]"); if (Array.isArray(s)) win.screens = s } catch (e) {}
        if (autostartSwitch) autostartSwitch.checked = backend.isAutostart()
    }
}
