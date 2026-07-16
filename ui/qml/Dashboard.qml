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
    // RETAINED copies of the expanded type/id that hold the overlay's CONTENT
    // through the close fade. closeExpanded() clears expandedType immediately
    // (that is the state machine), but if the loader/header keyed off it, the
    // widget, title and icon would vanish on frame 1 while the empty overlay
    // card was still fading out — a visible pop. These clear only once the
    // overlay is fully hidden (see the overlay's onVisibleChanged); under
    // reduce-motion the fade is 0ms, so they clear in the same event.
    property string shownType: ""
    property string shownId: ""
    onExpandedTypeChanged: {
        if (expandedType === "") return
        shownType = expandedType
        shownId = expandedId
        // Reopened while the previous overlay content was still fading (same
        // type → the Loader never reloads, so onLoaded will not refire):
        // re-inject so the live item is bound to the CURRENT instance id and
        // re-registered as the overlay item.
        if (ovlLoader.item) {
            dashboard.injectWidget(ovlLoader.item, shownId, shownType, true)
            dashboard.overlayLoaderItem = ovlLoader.item
        }
    }
    // Per-widget accent of the expanded tile (S7): resolve the instance's own
    // accent name to a colour, reactive to store.revision so an accent edit in
    // the config panel recolours the overlay live. Falls back to the theme
    // accent when the tile has no per-widget accent.
    property color  expandedColor: {
        store.revision
        // Keyed off the RETAINED id so the overlay's accent wash holds through
        // the close fade instead of snapping back to the theme accent.
        if (dashboard.shownId === "") return theme.accent
        var s = store.settingsFor(dashboard.shownId)
        var name = (s && s.accent) ? s.accent : ""
        return (name !== "" && theme.accentPresets[name])
               ? theme.accentPresets[name].a : theme.accent
    }
    property bool hasExpanded: expandedType !== ""

    property var host: StackView.view
    property bool _applyingAppearance: false

    // ── Managed / org policy (E9) ────────────────────────────────────────────
    // Read ONCE at creation: the policy file is root-owned and static for the
    // life of the process (ConfigBridge caches it too). No bridge (QML test
    // harness, Manager) or no policy file ⇒ inactive ⇒ behaviour is
    // byte-for-byte the unmanaged default.
    readonly property var orgPolicy: (typeof configBridge !== "undefined" && configBridge
                                      && configBridge.policy)
                                     ? configBridge.policy() : ({ "active": false })
    readonly property bool managed: orgPolicy && orgPolicy.active === true

    // False only when an ACTIVE policy disables this widget type. Consulted by
    // the tile loaders (a disabled type renders the fallback card, never the
    // widget), the expanded overlay, and the picker filter below.
    function policyAllowsWidget(type) {
        if (!dashboard.managed) return true
        var dis = dashboard.orgPolicy.disabledWidgetTypes
        return !(dis && dis.length && dis.indexOf(type) >= 0)
    }
    // The add-picker's model for one category, with policy-disabled types
    // removed — "hidden from picker", not greyed out: an option the user can
    // never have should not be advertised.
    function policyFilteredWidgets(category) {
        var all = catalog.inCategory(category)
        if (!dashboard.managed) return all
        var out = []
        for (var i = 0; i < all.length; i++)
            if (policyAllowsWidget(all[i].type)) out.push(all[i])
        return out
    }

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
        // effectiveReduceMotion, not the raw persisted flag: the OS reduce-motion
        // signal and the explicit on/off preference must stop the backdrop too.
        running: !theme.effectiveReduceMotion
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
        // Async decode means the image lands a beat after the page shows —
        // fade it over the gradient instead of letting it pop in fully formed.
        // (Instant under reduce-motion; a cached source skips Loading entirely.)
        opacity: status === Image.Ready ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: theme.motionSlow } }
    }
    Rectangle {
        anchors.fill: parent; visible: wallpaper.visible
        // Ride the wallpaper's own fade so the scrim can't darken the plain
        // gradient before the image has arrived.
        opacity: wallpaper.opacity
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
    WidgetSizes { id: sizes }
    WidgetPacker { id: packer }
    // The curated screen library — consumed post-setup by the PresetPicker
    // below (W5 finding 3: it used to have no consumer outside the wizard).
    PresetCatalog { id: presetLib }
    // The single app-global egress gate. Every net widget routes through this one
    // instance (injected below), so the offline switch + host allowlist + request
    // counters are global. `offline` is driven by an appearance flag (set by a
    // future global toggle / managed config); default off.
    NetHub {
        id: netHub
        // POLICY PIN (E9): an active org policy with net_offline=true holds the
        // kill switch ON no matter what the user's appearance flag says — this
        // is what makes the no-egress attestation enforceable rather than
        // advisory. Without a policy, the user's own flag governs, exactly as
        // before.
        offline: {
            var _ = store.revision
            if (dashboard.managed && dashboard.orgPolicy.netOffline === true) return true
            return store.appearance().netOffline === true
        }
        // POLICY PIN (E9): allowHosts comes from the org policy and nowhere
        // else — no user-config path assigns this property, so the binding IS
        // the pin and user config cannot widen it. (NetHub.request()'s
        // per-request opts.allow would take precedence over this list; no
        // shipped widget passes it — see docs/security/managed-config.md.)
        allowHosts: (dashboard.managed && dashboard.orgPolicy.allowedHosts)
                    ? dashboard.orgPolicy.allowedHosts : []
        // E7: the hub's ConfigBridge resolves ${env:}/file: credential refs. The
        // Manager has no configBridge (and does no egress), and the QML test
        // harness has none either — NetHub fails a ref closed when it is absent
        // rather than sending the reference as a token.
        secretResolver: (typeof configBridge !== "undefined") ? configBridge : null
    }
    // E10: the opt-in update check. OFF by default (the `updateCheck` appearance
    // flag is written by SettingsPanel); with a default config this constructs
    // no request — the no-egress attestation depends on that. When enabled, its
    // single GET rides the same NetHub gate as every widget.
    UpdateChecker {
        id: updateChecker
        netHub: netHub
        enabled: { var _ = store.revision; return store.appearance().updateCheck === true }
        currentVersion: (typeof configBridge !== "undefined" && configBridge && configBridge.appVersion)
                        ? configBridge.appVersion() : ""
        envResolver: (typeof configBridge !== "undefined") ? configBridge : null
    }
    // Re-check daily while opted in. The Timer lives here (an Item can host
    // children on every Qt 6) rather than inside the QtObject service.
    Timer {
        interval: 24 * 60 * 60 * 1000; repeat: true
        running: updateChecker.enabled
        onTriggered: updateChecker.check()
    }
    WidgetConfigSchema { id: cfgSchema }

    // ── Tier-0 user widgets (E3) ─────────────────────────────────────────────
    // Validates manifests scanned from $XDG_DATA_HOME/xeneon-edge-hub/widgets
    // and feeds WidgetCatalog.userItems (see docs/widgets/manifest-spec.md).
    // Gated by the `enableUserWidgets` appearance flag, DEFAULT OFF — the
    // attested default configuration never scans the directory.
    UserWidgetCatalog {
        id: userCatalog
        sizesModel: sizes
        shippedTypes: {
            var out = []
            for (var i = 0; i < catalog.items.length; i++) out.push(catalog.items[i].type)
            return out
        }
        urlResolver: (typeof configBridge !== "undefined" && configBridge && configBridge.imageUrl)
                     ? function (p) { return configBridge.imageUrl(p) } : null
    }
    // Test seam: replaces ConfigBridge.listUserWidgets as the scan source, so
    // the offscreen suite can both feed fixtures and PROVE the flag-off path
    // performs no scan at all (the provider is never invoked).
    property var userWidgetProvider: null

    // Whether Tier-0 user widgets are enabled. A plain config read (managed
    // config can pin it), default FALSE. Registration must happen BEFORE the
    // store loads — persisted tile sizes validate against declared `sizes` —
    // so before the store is loaded this peeks at the same persisted document
    // store.load() is about to read.
    function _userWidgetsFlag() {
        // The org policy vetoes user widgets OUTRIGHT — before the user's own
        // preference is even consulted. Policy beating preference is the
        // definition of a managed session, and putting the veto here (not at a
        // call site) means every present and future load path inherits it.
        if (dashboard.managed && dashboard.orgPolicy.disableUserWidgets === true)
            return false
        if (store.loaded) return store.appearance().enableUserWidgets === true
        if (typeof configBridge !== "undefined" && configBridge && configBridge.uiState) {
            try {
                var doc = JSON.parse(configBridge.uiState() || "{}")
                return !!(doc && doc.appearance && doc.appearance.enableUserWidgets === true)
            } catch (e) { return false }
        }
        return false
    }

    // (Re)load user widgets into BOTH catalog instances — the dashboard's own
    // (tiles, picker, overlay) and the store's private one (size validation on
    // addTile/setTileSize/load). Flag off → everything cleared and NO scan
    // happens. Returns how many user widgets are registered.
    function _loadUserWidgets() {
        if (!dashboard._userWidgetsFlag()) {
            userCatalog.clear()
        } else {
            var raw = dashboard.userWidgetProvider ? dashboard.userWidgetProvider()
                    : ((typeof configBridge !== "undefined" && configBridge && configBridge.listUserWidgets)
                       ? configBridge.listUserWidgets() : [])
            userCatalog.load(raw)
        }
        catalog.userItems = userCatalog.items
        store._catalog.userItems = userCatalog.items
        return userCatalog.items.length
    }

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

    // Apply a preset from the post-setup Screens picker (W5 finding 3): the
    // store's normal seed path (resetTo), with two deliberate twists.
    //
    //  • POLICY (E9): an org-forced preset wins over any interactive choice.
    //    The picker surface is already absent under the lock, but the guard
    //    lives HERE so no other caller can ever bypass the policy.
    //  • "Your theme stays" — and it must stay across RESTART, not just live.
    //    A preset document carries only its character keys (bgStyle/
    //    animatedBg/reduceMotion/glow/presetSurface), so resetTo() would drop
    //    every other persisted appearance key: themeMode/accent would fall
    //    back to the stale legacy [theme] values on the next launch (W5
    //    finding 15), and — worse — a user's netOffline/updateCheck/
    //    enableUserWidgets choices would silently revert to defaults. So every
    //    prior appearance key the preset does not define is carried over.
    //  • Accessibility beats character: an explicit prior reduce-motion
    //    choice survives even though presets DO define reduceMotion. Post-
    //    setup, that flag is the user's a11y setting; a preset that silently
    //    re-enabled motion would repeat the W3 bug class the calm work fixed.
    //    (In the wizard the preset's character applies untouched — there is
    //    no prior choice to protect there.)
    //
    // Returns whether the preset was applied.
    function applyPreset(presetId) {
        if (store.policyLockedPreset !== "") return false
        var id = String(presetId || "")
        if (id === "") return false
        if (id !== "blank" && !presetLib.has(id)) return false
        var prev = store.appearance()
        var keep = {}
        for (var k in prev) keep[k] = prev[k]
        store.resetTo(id)
        for (var kk in keep)
            if (store.appearance()[kk] === undefined)
                store.setAppearance(kk, keep[kk])
        if (keep.reduceMotion !== undefined)
            store.setAppearance("reduceMotion", keep.reduceMotion)
        applyAppearance()
        // Land the user on the new layout's first page, not an out-of-range
        // index left over from a longer document.
        swipeView.currentIndex = 0
        return true
    }

    // Close the expanded overlay + clear its transient state (shared by the
    // header back button and the reachable bottom "Done" bar).
    function closeExpanded() {
        dashboard.expandedType = ""
        dashboard.expandedId = ""
        dashboard.cfgStatus = ""
        dashboard.overlayLoaderItem = null
    }

    Component.onCompleted: {
        // User widgets FIRST: load() coerces every persisted tile size against
        // the type's declared sizes, so user types must already be registered
        // or their tiles would be coerced to the baseline as "unknown".
        // (_userWidgetsFlag itself honours the org policy's veto.)
        _loadUserWidgets()
        // E9: an org-forced preset replaces the saved layout for this session
        // (the store's lock also stops every disk write, so the user's own
        // layout survives underneath and comes back if the policy is removed).
        if (dashboard.managed && dashboard.orgPolicy.forcePreset)
            store.lockToPreset(dashboard.orgPolicy.forcePreset)
        else
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
            // The pushed appearance may have flipped `enableUserWidgets` (e.g.
            // a managed config forcing it off): re-run the loader so the flag
            // takes effect live — off clears the registry without any scan.
            _loadUserWidgets()
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

    // How much ROOM a named size gives, in the vocabulary widgets already speak
    // (WidgetChrome: compact/wide/tall/large/full). Named rather than numeric so a
    // widget asks "have I got room?" instead of re-deriving it from geometry it
    // shouldn't know about.
    //
    // It is judged on the PROJECTED half-cells, so it answers about the shape the
    // widget will actually be handed: a half-cell is roughly square (~348x409
    // portrait, ~423x306 landscape), so counting them is a fair proxy for shape, and
    // the same size honestly reports "tall" in portrait and "wide" in landscape —
    // which is the point of a rotating panel.
    //
    // "large" had to be redefined. It was coined for the old span grid, where it
    // meant "doubled on BOTH axes"; the size model has no such shape (the short axis
    // stops at 1), so under the old rule it would have become unreachable. It now
    // means what it always implied — the sizes with room to spare: two thirds of the
    // screen or more (>= 8 of the 12 half-cells), i.e. `1x2` and `1x3`.
    function sizeClassFor(size, landscape) {
        var u = sizes.halfUnits(size, landscape)
        if (!u) return "compact"                      // unknown size → assume the least room
        if (u.w * u.h >= 8) return "large"
        if (u.w > u.h) return "wide"
        if (u.h > u.w) return "tall"
        return "compact"
    }

    // The next size in this type's own legal list, wrapping around — the edit-mode
    // resize button. The old fixed 1x1→2x1→1x2→2x2 cycle has NO equivalent: those
    // spans are not sizes, and every widget type now declares which sizes it can
    // honestly render, so the cycle has to be the type's own list or it would offer
    // shapes the widget was never built for. A type with one size stays put. (The
    // picker sheet that shows the whole list at once is a later phase; this keeps
    // the button honest in the meantime.)
    function nextSize(type, current) {
        var legal = catalog.sizesFor(type)
        if (!legal.length) return ""
        var i = legal.indexOf(current)
        return legal[(i + 1) % legal.length]          // indexOf -1 → wraps to legal[0]
    }

    // Inject the shared bindings into a freshly-loaded widget instance. Used by
    // both the tile loaders and the expanded overlay so they share state.
    //
    // sizeClassFn is a getter, BOUND rather than read once: a resize rewrites the
    // tile's size (and a rotation reshapes it), and a value captured at load would
    // silently go stale.
    function injectWidget(item, id, type, isExpanded, sizeClassFn) {
        if (!item) return
        store.ensureSettings(id, catalog.defaults(type))
        item.instanceId = id
        item.store = store
        // How much room it has. The overlay is the whole screen; a tile gets its
        // span's class. This is DELIBERATELY not `expanded`: see WidgetChrome —
        // expanded is a mode, sizeClass is room, and every widget used to conflate
        // them by declaring `big: expanded`.
        if (item.hasOwnProperty("sizeClass")) {
            if (isExpanded) item.sizeClass = "full"
            else if (sizeClassFn) item.sizeClass = Qt.binding(sizeClassFn)
        }
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

                    // Which physical axis the long axis lands on. This is the ONLY
                    // place orientation enters a page's layout: the packing below is
                    // orientation-free, so a rotation re-projects it rather than
                    // re-packing — the dashboard turns WITH the panel instead of
                    // reshuffling under the user. (See WidgetPacker.)
                    property bool landscape: width > height

                    // The page's ONE packing, in semantic (short, long) space. Keyed on
                    // structureRevision like the old tile Repeater: only add/remove/
                    // move/resize re-packs, not a settings keystroke.
                    property var placements: {
                        store.structureRevision
                        return packer.pack(pageItem.tiles)
                    }
                    // How far the page reaches along the long axis, in half-cells.
                    // 6 (WidgetSizes.longHalves) is exactly one screen.
                    property int longExtent: packer.longExtent(pageItem.placements)

                    // Where the next widget would land: the same packing with one more
                    // baseline tile on the end. Drives the edit-mode "Add widget" slot.
                    property var addPlacement: {
                        store.structureRevision
                        var virt = (pageItem.tiles || []).slice()
                        virt.push({ id: "", type: "", size: sizes.baseline })
                        var ps = packer.pack(virt)
                        return ps[ps.length - 1]
                    }
                    // The extent that must be REACHABLE. In edit mode the add slot can
                    // sit past the last tile (and past the screen), and an affordance you
                    // cannot scroll to is not one.
                    property int reachExtent: dashboard.editMode
                        ? Math.max(pageItem.longExtent, pageItem.addPlacement.l + pageItem.addPlacement.el)
                        : pageItem.longExtent

                    // Scrollable page body. CAPACITY POLICY: a page is NEVER capped and
                    // a tile is NEVER refused or dropped — a page longer than the screen
                    // simply scrolls, exactly as it does today.
                    //
                    // The fixed 2x6 grid sizes the CELL, not the page: `1x1` must be a
                    // third of the DISPLAY no matter what else is on the page (that is
                    // the whole size model, and precisely what GridLayout could not do),
                    // so the cell is screen/(2x6) and a 7th half-unit lands past the
                    // screen edge rather than shrinking its neighbours. Capping instead
                    // would refuse 15 of the 17 shipped preset pages outright, and
                    // dropping tiles to fit is silent data loss — neither is a trade
                    // worth making for a page that can just scroll.
                    //
                    // The scroll axis follows the LONG axis, so it is vertical in
                    // portrait (720x2560) and HORIZONTAL in the default landscape strip
                    // (2560x720) — see the report: a horizontal page scroll shares an
                    // axis with the SwipeView's page swipe. `interactive` is therefore
                    // false unless the page genuinely overflows, so it never competes on
                    // a page that fits.
                    Flickable {
                        id: pageFlick
                        anchors.fill: parent
                        clip: true
                        // The cell, derived from the SCREEN and nothing else.
                        readonly property real cellShort: (pageItem.landscape ? height : width) / sizes.shortHalves
                        readonly property real cellLong: (pageItem.landscape ? width : height) / sizes.longHalves
                        readonly property real contentLong:
                            Math.max(pageItem.landscape ? width : height, pageItem.reachExtent * cellLong)
                        contentWidth: pageItem.landscape ? contentLong : width
                        contentHeight: pageItem.landscape ? height : contentLong
                        flickableDirection: pageItem.landscape ? Flickable.HorizontalFlick
                                                               : Flickable.VerticalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: pageItem.reachExtent > sizes.longHalves

                    Item {
                        id: pageGrid
                        width: pageFlick.contentWidth
                        height: pageFlick.contentHeight

                        Repeater {
                            model: pageItem.placements
                            delegate: Item {
                                id: cell
                                // NOT the Repeater's `index`: that counts placements, and
                                // every store call here addresses the TILE array. The
                                // placement carries `idx` for exactly that.
                                required property var modelData   // a WidgetPacker placement

                                // Absolute placement: the packed semantic slot projected
                                // onto physical axes at the screen-derived cell size.
                                readonly property var _r: packer.rect(cell.modelData, pageItem.landscape,
                                                                      pageFlick.cellShort, pageFlick.cellLong,
                                                                      theme.spacingMd)
                                x: _r.x; y: _r.y
                                width: _r.width; height: _r.height

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
                                            && dashboard.policyAllowsWidget(wType)
                                    source: active ? catalog.source(wType) : ""
                                    onLoaded: {
                                        dashboard.injectWidget(item, wId, wType, false,
                                            function () { return dashboard.sizeClassFor(cell.modelData.size, pageItem.landscape) })
                                        if (item) item.active = Qt.binding(function () { return !dashboard.hasExpanded && !dashboard.editMode })
                                    }
                                }

                                // Error boundary: a tile whose type is unknown/removed —
                                // or disabled by org policy (E9) — renders the fallback
                                // card instead of a blank, confusing tile.
                                Loader {
                                    anchors.fill: parent
                                    active: tileLd.wId !== "" && tileLd.wType !== ""
                                            && (catalog.source(tileLd.wType) === ""
                                                || !dashboard.policyAllowsWidget(tileLd.wType))
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
                                    // Fade with the edit-mode change instead of blinking
                                    // out on the same frame the edit scrim appears.
                                    opacity: dashboard.editMode ? 0.0 : 1.0
                                    visible: opacity > 0.01
                                    Behavior on opacity { NumberAnimation { duration: theme.motionEdit } }
                                    Rectangle {
                                        anchors.fill: parent; anchors.margins: theme.spacingXs
                                        radius: theme.radiusSm
                                        // `pressed`, not just hover: this is a touchscreen —
                                        // a finger on the target must light it up.
                                        color: cfgMA.pressed ? Qt.rgba(1, 1, 1, 0.16)
                                             : cfgMA.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                                        Behavior on color { ColorAnimation { duration: theme.motionFast } }
                                    }
                                    AppIcon {
                                        anchors.right: parent.right; anchors.top: parent.top
                                        anchors.margins: theme.spacingSm
                                        name: "ui-expand"; size: theme.iconSm
                                        color: theme.textTertiary
                                        opacity: (cfgMA.pressed || cfgMA.containsMouse) ? 0.95 : 0.55
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
                                    // Fade in/out with the mode switch — the scrim +
                                    // controls used to appear on a hard cut, which is
                                    // exactly the "abrupt property jump" class of clunk.
                                    // motionEdit is already 0 under reduce-motion.
                                    opacity: dashboard.editMode ? 1.0 : 0.0
                                    visible: opacity > 0.01
                                    Behavior on opacity { NumberAnimation { duration: theme.motionEdit } }
                                    radius: theme.radiusLg
                                    color: Qt.rgba(0, 0, 0, 0.35)
                                    border.width: 2; border.color: theme.accent
                                    z: 30

                                    // wobble to signal editability (effectiveReduceMotion:
                                    // the OS signal / explicit preference must stop it too)
                                    RotationAnimation on rotation {
                                        running: dashboard.editMode && !theme.effectiveReduceMotion
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
                                            // `idx` is the tile's index in the store's tile
                                            // ARRAY, which is what moveTile addresses —
                                            // the delegate's own index counts placements,
                                            // and the two only coincide by luck.
                                            visible: cell.modelData.idx > 0
                                            AppIcon { anchors.centerIn: parent; name: "ui-caret-left"; size: theme.iconMd; color: theme.textPrimary }
                                            MouseArea { anchors.fill: parent
                                                onClicked: store.moveTile(pageItem.index, cell.modelData.idx, cell.modelData.idx - 1) }
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
                                            visible: cell.modelData.idx < pageItem.tiles.length - 1
                                            AppIcon { anchors.centerIn: parent; name: "ui-caret-right"; size: theme.iconMd; color: theme.textPrimary }
                                            MouseArea { anchors.fill: parent
                                                onClicked: store.moveTile(pageItem.index, cell.modelData.idx, cell.modelData.idx + 1) }
                                        }
                                        // Resize: step through THIS widget type's own legal
                                        // sizes. Hidden for a type with only one — a button
                                        // that provably cannot do anything should not be
                                        // offered.
                                        Rectangle {
                                            Layout.preferredWidth: theme.touchSecondary; Layout.preferredHeight: theme.touchSecondary
                                            radius: width / 2; color: theme.cardBackgroundAlt; border.width: 1; border.color: theme.cardBorder
                                            visible: catalog.sizesFor(cell.modelData.type).length > 1
                                            AppIcon { anchors.centerIn: parent; name: "ui-resize"; size: theme.iconMd; color: theme.textPrimary }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: store.setTileSize(pageItem.index, cell.modelData.id,
                                                                             dashboard.nextSize(cell.modelData.type,
                                                                                                cell.modelData.size))
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // "Add widget" placeholder tile (edit mode only). It sits in the
                        // slot the next widget would ACTUALLY land in — it is packed by
                        // the same packer, as a real baseline tile — so the affordance
                        // shows where the thing it adds will go rather than guessing.
                        Loader {
                            id: addTile
                            active: dashboard.editMode
                            visible: dashboard.editMode
                            readonly property var _r: packer.rect(pageItem.addPlacement, pageItem.landscape,
                                                                  pageFlick.cellShort, pageFlick.cellLong,
                                                                  theme.spacingMd)
                            x: _r.x; y: _r.y
                            width: _r.width; height: _r.height
                            sourceComponent: Rectangle {
                                radius: theme.radiusLg
                                color: "transparent"
                                border.width: 2; border.color: theme.cardBorder
                                // Enter softly when edit mode opens (0ms under
                                // reduce-motion via the token).
                                NumberAnimation on opacity {
                                    from: 0; to: 1
                                    duration: theme.motionAdd; easing.type: Easing.OutCubic
                                }
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

            // E9: ONE always-visible line saying the hub is under org
            // management — in the bottom bar, not buried in a submenu.
            Text {
                visible: dashboard.managed
                text: "Managed by your organization"
                color: theme.textTertiary; font.pixelSize: theme.fontLabel
                font.family: theme.fontDisplay
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                Layout.maximumWidth: theme.touchSecondary * 4
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
                    "configJson": (typeof configBridge !== "undefined" && configBridge) ? configBridge.configJson() : "",
                    // User-widget loader report: enabled state + loaded entries
                    // + every skipped directory with its reason.
                    "userWidgetsJson": userCatalog.reportJson(dashboard._userWidgetsFlag(),
                        (typeof configBridge !== "undefined" && configBridge && configBridge.userWidgetsDir)
                            ? configBridge.userWidgetsDir() : "")
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
        Behavior on opacity { NumberAnimation { duration: theme.motionFast; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: theme.motionPage; easing.type: Easing.OutCubic } }
        // The fade is over → NOW drop the retained content (see shownType above).
        onVisibleChanged: if (!visible) { dashboard.shownType = ""; dashboard.shownId = "" }

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
                    // shownType (not expandedType): the header must hold its
                    // icon/title/description through the close fade.
                    AppIcon { anchors.verticalCenter: parent.verticalCenter
                        readonly property var ic: catalog.iconFor(dashboard.shownType)
                        name: ic.name; iconSource: ic.source
                        size: theme.fontTitle + 10; color: dashboard.expandedColor }
                    Text { text: catalog.title(dashboard.shownType); font.pixelSize: theme.fontTitle + 8
                        font.bold: true; font.family: theme.fontDisplay; color: theme.textPrimary }
                }
                Text {
                    width: parent.width
                    text: catalog.desc(dashboard.shownType)
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
            // W5 BLOCKER (finding 2): in landscape both columns declared
            // fillWidth, and a GridLayout hands the stretch out in proportion
            // to preferred widths — the preview's 0.46×width against the
            // config panel's implicit ~0 — so the FORM collapsed to a ~10px
            // sliver and on-device configuration ("connect CI to a URL",
            // per-widget backdrop…) was impossible on a landscape mount.
            // The landscape split is now explicit: the preview takes a FIXED
            // 38% (fillWidth off, width capped) and the form fills every
            // remaining pixel, with a hard minimum of half the overlay so no
            // future sibling can starve it again. Portrait is unchanged:
            // preview stacked on top (≤46% height), form full-width below.
            ColumnLayout {
                Layout.fillWidth: !overlay.ovlWide
                Layout.fillHeight: overlay.ovlWide
                Layout.preferredWidth: overlay.ovlWide ? Math.round(overlay.width * 0.38) : -1
                Layout.maximumWidth: overlay.ovlWide ? Math.round(overlay.width * 0.38)
                                                     : Number.POSITIVE_INFINITY
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
                        // Keyed off the RETAINED type: the widget stays rendered
                        // (frozen, inactive) through the close fade instead of
                        // popping to an empty card on frame 1, and unloads only
                        // once the overlay is fully hidden.
                        active: dashboard.shownType !== "" && catalog.source(dashboard.shownType) !== ""
                                && dashboard.policyAllowsWidget(dashboard.shownType)
                        source: active ? catalog.source(dashboard.shownType) : ""
                        onLoaded: {
                            // expanded=true → the widget shows its full, INTERACTIVE
                            // layout (e.g. Focus's Start/preset controls), usable here.
                            dashboard.injectWidget(item, dashboard.shownId, dashboard.shownType, true)
                            dashboard.overlayLoaderItem = item
                            if (item) {
                                // Bound (not set once): the instant the overlay
                                // starts closing this drops to false, so the
                                // fading copy can never drive shared state in
                                // parallel with the re-activated tile behind it
                                // (the single-driver rule).
                                item.active = Qt.binding(function () { return dashboard.hasExpanded })
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
                            store.resetSettings(dashboard.shownId, catalog.defaults(dashboard.shownType))
                            dashboard.cfgStatus = ""
                        }
                    }
                }
            }

            // ── Configuration panel ──
            WidgetConfigPanel {
                Layout.fillWidth: true; Layout.fillHeight: true
                // The form may never be starved below half the overlay in
                // landscape — this panel is the only way to configure a
                // widget on-device (W5 blocker 2).
                Layout.minimumWidth: overlay.ovlWide ? Math.round(overlay.width * 0.5) : 0
                // User widgets carry their form in the manifest; shipped ones
                // in WidgetConfigSchema. Both compose the same General/About/
                // Appearance sections.
                schema: userCatalog.isUser(dashboard.shownType)
                        ? userCatalog.schemaFor(dashboard.shownType, cfgSchema)
                        : cfgSchema.schemaFor(dashboard.shownType)
                st: store
                instanceId: dashboard.shownId
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
            // Same entrance as the SettingsPanel sheet, so every modal in the hub
            // arrives the same way (scale-up + fade, instant under reduce-motion).
            scale: picker.shown ? 1.0 : 0.96
            Behavior on scale { NumberAnimation { duration: theme.motionPage; easing.type: Easing.OutCubic } }
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
                                // E9: policy-disabled types are absent, not greyed out; a
                                // category the policy empties disappears with them.
                                property var allowedItems: dashboard.policyFilteredWidgets(modelData)
                                visible: allowedItems.length > 0
                                Layout.fillWidth: true; spacing: theme.spacingSm
                                Text { text: modelData; font.pixelSize: 14; font.bold: true; color: theme.textSecondary }
                                Flow {
                                    Layout.fillWidth: true; spacing: theme.spacingSm
                                    Repeater {
                                        model: allowedItems
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
                                                // iconFor: shipped types resolve by type; user types
                                                // carry their own file or the bundled fallback glyph.
                                                AppIcon {
                                                    readonly property var ic: catalog.iconFor(modelData.type)
                                                    name: ic.name; iconSource: ic.source
                                                    size: 24; color: theme.textSecondary
                                                }
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
        updateChecker: updateChecker
        // Under an org-forced preset the Screens entry is absent (E9).
        presetsLocked: store.policyLockedPreset !== ""
        onCloseRequested: shown = false
        onPresetsRequested: { settings.shown = false; presetPicker.shown = true }
    }

    // Post-setup preset library ("Screens", W5 finding 3) — opened from the
    // settings sheet; applying routes through applyPreset() above.
    PresetPicker {
        id: presetPicker
        catalog: presetLib
        locked: store.policyLockedPreset !== ""
        onApplyRequested: (pid) => { if (dashboard.applyPreset(pid)) presetPicker.shown = false }
        onCloseRequested: shown = false
    }
}
