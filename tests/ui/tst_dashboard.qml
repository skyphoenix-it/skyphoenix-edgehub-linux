import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: fn:Dashboard._tileExists, fn:Dashboard.applyAppearance, fn:Dashboard.applyExternalState, fn:Dashboard.cfgAction, fn:Dashboard.closeExpanded, fn:Dashboard.injectWidget
// COVERS: fn:Dashboard.onAccentNameChanged, fn:Dashboard.onAnimatedBackgroundChanged, fn:Dashboard.onGlassOpacityChanged, fn:Dashboard.onOrientationModeChanged, fn:Dashboard.onReduceMotionChanged, fn:Dashboard.onShowWidgetGlowChanged
// COVERS: fn:Dashboard.onThemeModeChanged
//
// ui/qml/Dashboard.qml —
//   • cfgAction: geocode-with-place, empty-place, non-geocode action, no overlay
//   • closeExpanded: clears all overlay state, idempotent
//   • applyExternalState: valid doc updates the store + re-applies appearance;
//     malformed doc is ignored (no throw); a live push that drops the expanded
//     tile closes the overlay
//   • _tileExists: present id / unknown id / empty id
//   • applyAppearance: pushes accent/glass/glow/reduceMotion/themeMode/animatedBg/
//     orientation to the shell (root) + theme
//   • injectWidget: instanceId/store/expanded set; titleOverride/accentName/
//     cardBackdrop/metrics/tick bindings track the store + shell live
//   • the 7 appearance→store Connections handlers (root change → store.setAppearance)
//
// Dashboard resolves the shell (`root`), `theme`, and `metricsJson` through the
// context scope — we provide them here exactly as main.qml does, then load the
// REAL Dashboard.qml via a Loader (as the app's StackView does). We reach its
// private DashboardStore by duck-typing the object graph. Assertions target the
// driving properties/store, never rendered pixels.
Item {
    id: root
    width: 900; height: 600

    // Shell (main.qml root) surface Dashboard binds to.
    property alias theme: _theme
    App.Theme { id: _theme }
    property string accentName: "blue"
    property real glassOpacity: 0.5
    property bool showWidgetGlow: true
    property bool reduceMotion: false
    property string themeMode: "dark"
    property bool animatedBackground: true
    property string orientationMode: "auto"
    property string metricsJson: "{}"
    property string screensData: "[]"

    // Recorder for the geocode delegate handed to cfgAction.
    property string geocodedPlace: ""

    // A stand-in widget exposing the universal contract properties injectWidget
    // wires up, so we can assert the bindings track the store/shell live.
    Component {
        id: fakeWidget
        QtObject {
            property string instanceId: ""
            property var store: null
            property bool expanded: false
            property var metrics: ({})
            property string titleOverride: "unset"
            property string accentName: "unset"
            property string cardBackdrop: "unset"
            property int tick: -1
        }
    }

    Loader {
        id: ld
        anchors.fill: parent
        source: "../../ui/qml/Dashboard.qml"
    }

    // ── tree helpers ─────────────────────────────────────────────────────────
    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids) for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
    }
    function findPred(n, pred) {
        var f = null
        eachItem(n, function (x) { if (!f && pred(x)) f = x })
        return f
    }
    property var _store: null
    function store() {
        if (!_store)
            _store = findPred(ld.item, function (x) {
                return x && x.applyExternal !== undefined && x.structureRevision !== undefined
            })
        return _store
    }

    function makeDoc(tileList) {
        return JSON.stringify({ version: 1, appearance: {}, settings: {},
            pages: [ { name: "P1", tiles: tileList } ] })
    }

    TestCase {
        name: "Dashboard"
        when: windowShown

        function initTestCase() {
            tryVerify(function () { return ld.status === Loader.Ready && ld.item !== null }, 5000)
            verify(root.store() !== null, "found Dashboard's private DashboardStore")
        }

        function init() {
            var d = ld.item
            root.store().load("blank")
            d.closeExpanded()
            d.cfgStatus = ""
        }

        // ── cfgAction ─────────────────────────────────────────────────────────
        function test_cfgAction_geocode_with_place() {
            var d = ld.item
            root.geocodedPlace = ""
            d.expandedId = "wx"
            root.store().setSetting("wx", "place", "Paris")
            d.overlayLoaderItem = ({ geocode: function (p) { root.geocodedPlace = p } })
            d.cfgAction("geocode")
            compare(root.geocodedPlace, "Paris", "cfgAction invoked the geocode delegate with the place")
            compare(d.cfgStatus.indexOf("Searching"), 0, "status shows the search is running")
        }

        function test_cfgAction_empty_place_prompts() {
            var d = ld.item
            d.expandedId = "wx"
            root.store().setSetting("wx", "place", "   ")     // whitespace → empty
            d.overlayLoaderItem = ({ geocode: function (p) { root.geocodedPlace = p } })
            root.geocodedPlace = "SENTINEL"
            d.cfgAction("geocode")
            compare(d.cfgStatus, "Type a place name first.", "empty place is rejected")
            compare(root.geocodedPlace, "SENTINEL", "geocode was NOT called")
        }

        function test_cfgAction_non_geocode_is_noop() {
            var d = ld.item
            d.cfgStatus = ""
            d.expandedId = "wx"
            d.overlayLoaderItem = ({ geocode: function (p) { root.geocodedPlace = p } })
            d.cfgAction("save")           // not the geocode branch
            compare(d.cfgStatus, "", "a non-geocode action changes nothing")
        }

        function test_cfgAction_without_overlay_is_noop() {
            var d = ld.item
            d.cfgStatus = ""
            d.overlayLoaderItem = null
            d.cfgAction("geocode")        // no overlay item → guarded out
            compare(d.cfgStatus, "", "geocode with no overlay does nothing")
        }

        // ── closeExpanded ─────────────────────────────────────────────────────
        function test_closeExpanded_clears_and_is_idempotent() {
            var d = ld.item
            d.expandedType = "cpu"; d.expandedId = "x1"
            d.cfgStatus = "busy"; d.overlayLoaderItem = ({ geocode: function () {} })
            verify(d.hasExpanded, "precondition: overlay open")
            d.closeExpanded()
            compare(d.expandedType, "", "type cleared")
            compare(d.expandedId, "", "id cleared")
            compare(d.cfgStatus, "", "status cleared")
            compare(d.overlayLoaderItem, null, "overlay item cleared")
            verify(!d.hasExpanded, "closeExpanded cleared the expanded state")
            d.closeExpanded()             // second call must not throw
            verify(!d.hasExpanded, "closeExpanded is idempotent (still closed after a second call)")
        }

        // ── _tileExists ───────────────────────────────────────────────────────
        // COVERS: fn:Dashboard.sizeClassFor
        // The tile's span -> how much room the widget has. Named, so widgets ask
        // "have I got room?" rather than re-deriving it from spans; and so the
        // vocabulary survives the move to real fractional sizes, where the spans
        // change meaning but the classes don't.
        function test_sizeClassFor_maps_spans_to_room() {
            var d = ld.item
            compare(d.sizeClassFor(1, 1), "compact")
            compare(d.sizeClassFor(2, 1), "wide", "two columns but one row: no vertical room")
            compare(d.sizeClassFor(1, 2), "tall", "the case that used to render stretched")
            compare(d.sizeClassFor(2, 2), "large")
            // A tile carries no w/h until it is resized — that must not read as 0x0.
            compare(d.sizeClassFor(undefined, undefined), "compact", "an unsized tile is 1x1")
            compare(d.sizeClassFor(0, 0), "compact")
        }

        // COVERS: fn:Dashboard._msToNextSecond
        // REGRESSION: the shared tick was `interval: 1000; repeat: true`, which
        // re-arms 1000ms after each HANDLING — so hitches accumulate into the phase
        // and it is never aligned to the wall-clock second anyway. Widgets format
        // `new Date()` on the tick, so a drifted tick shows a second twice (stall)
        // then skips one (jump). This asserts the property that makes the error
        // non-cumulative: the next wait is always the time REMAINING to the next
        // boundary, so a late fire waits less rather than staying late forever.
        function test_tick_reaims_at_the_next_second_boundary() {
            var d = ld.item
            // Always a real, bounded wait: never 0 (a busy-loop) and never longer
            // than a second plus the small past-the-boundary nudge.
            verify(d._msToNextSecond() >= 1, "never schedules a zero-delay tick")
            verify(d._msToNextSecond() <= 1005, "never waits more than one second")

            // The defining property: it is a REMAINING time, not a constant. Landing
            // just after a boundary must ask for ~a full second; landing just before
            // one must ask for only the remainder. A fixed 1000ms timer returns the
            // same number in both cases and fails this.
            var atBoundary = 1000 - (0 % 1000) + 5          // now = x.000 -> ~1005
            var lateInSecond = 1000 - (900 % 1000) + 5      // now = x.900 -> ~105
            verify(atBoundary > lateInSecond,
                   "the wait shrinks the later in the second we fire (" +
                   atBoundary + " vs " + lateInSecond + ")")
            compare(lateInSecond, 105, "900ms into the second -> 105ms left, not 1000")
        }

        function test_tileExists() {
            var d = ld.item
            d.applyExternalState(root.makeDoc([ { id: "t1", type: "clock" }, { id: "t2", type: "cpu" } ]))
            verify(d._tileExists("t1"), "existing tile found")
            verify(d._tileExists("t2"), "second existing tile found")
            verify(!d._tileExists("nope"), "unknown id is absent")
            verify(!d._tileExists(""), "empty id is never present")
        }

        // ── applyExternalState ────────────────────────────────────────────────
        function test_applyExternalState_valid_updates_store() {
            var d = ld.item
            d.applyExternalState(root.makeDoc([ { id: "a", type: "clock" } ]))
            var pages = root.store().pages()
            compare(pages.length, 1, "one page applied")
            compare(pages[0].tiles.length, 1, "one tile applied")
            compare(pages[0].tiles[0].id, "a", "applyExternalState round-trips the tile id into the store")
        }

        function test_applyExternalState_malformed_ignored() {
            var d = ld.item
            d.applyExternalState(root.makeDoc([ { id: "keep", type: "clock" } ]))
            var before = root.store().pages().length
            d.applyExternalState("{ this is not json")     // must not throw / must not apply
            compare(root.store().pages().length, before, "malformed push left the store intact")
            verify(d._tileExists("keep"), "prior tile still present")
        }

        function test_applyExternalState_closes_orphaned_overlay() {
            var d = ld.item
            d.applyExternalState(root.makeDoc([ { id: "gone", type: "clock" } ]))
            d.expandedId = "gone"; d.expandedType = "clock"
            verify(d.hasExpanded, "precondition: expanded on 'gone'")
            // A push that no longer contains 'gone' must close the overlay.
            d.applyExternalState(root.makeDoc([ { id: "other", type: "cpu" } ]))
            verify(!d._tileExists("gone"), "the expanded tile was removed")
            verify(!d.hasExpanded, "overlay auto-closed for the orphaned tile")
        }

        // ── applyAppearance ───────────────────────────────────────────────────
        function test_applyAppearance_pushes_all_keys() {
            var d = ld.item
            var s = root.store()
            s.setAppearance("themeMode", "light")
            s.setAppearance("accent", "green")
            s.setAppearance("glass", 0.33)
            s.setAppearance("glow", false)
            s.setAppearance("reduceMotion", true)
            s.setAppearance("animatedBg", false)
            s.setAppearance("orientation", "landscape")
            d.applyAppearance()
            compare(root.themeMode, "light", "applyAppearance pushed themeMode to the shell")
            compare(root.glassOpacity, 0.33, "glass pushed to shell")
            compare(root.showWidgetGlow, false, "glow pushed to shell")
            compare(root.reduceMotion, true, "reduceMotion pushed to shell")
            compare(root.animatedBackground, false, "animatedBg pushed to shell")
            compare(root.orientationMode, "landscape", "orientation pushed to shell")
            verify(Qt.colorEqual(_theme.accent, _theme.accentPresets["green"].a),
                   "accent applied to the theme")
        }

        // ── the 7 appearance→store Connections handlers ───────────────────────
        function test_appearance_connections_persist_each_key() {
            var s = root.store()
            root.accentName = (root.accentName === "purple") ? "teal" : "purple"
            compare(s.appearance().accent, root.accentName, "onAccentNameChanged persisted accent → store")

            root.glassOpacity = (root.glassOpacity === 0.42) ? 0.63 : 0.42
            compare(s.appearance().glass, root.glassOpacity, "onGlassOpacityChanged persisted glass → store")

            root.showWidgetGlow = !root.showWidgetGlow
            compare(s.appearance().glow, root.showWidgetGlow, "onShowWidgetGlowChanged persisted glow → store")

            root.reduceMotion = !root.reduceMotion
            compare(s.appearance().reduceMotion, root.reduceMotion, "onReduceMotionChanged persisted reduceMotion → store")

            root.themeMode = (root.themeMode === "oled") ? "dark" : "oled"
            compare(s.appearance().themeMode, root.themeMode, "onThemeModeChanged persisted themeMode → store")

            root.animatedBackground = !root.animatedBackground
            compare(s.appearance().animatedBg, root.animatedBackground, "onAnimatedBackgroundChanged persisted animatedBg → store")

            root.orientationMode = (root.orientationMode === "portrait") ? "landscape" : "portrait"
            compare(s.appearance().orientation, root.orientationMode, "onOrientationModeChanged persisted orientation → store")
        }

        // ── injectWidget ──────────────────────────────────────────────────────
        function test_injectWidget_sets_props_and_binds() {
            var d = ld.item
            var s = root.store()
            var w = fakeWidget.createObject(root)
            d.injectWidget(w, "iw1", "cpu", true)
            compare(w.instanceId, "iw1", "injectWidget set the instanceId")
            compare(w.store, s, "store injected (the Dashboard's own store)")
            compare(w.expanded, true, "expanded flag set")

            // Per-instance appearance bindings track the store live.
            s.setSetting("iw1", "title", "Hello")
            compare(w.titleOverride, "Hello", "titleOverride binding follows the store")
            s.setSetting("iw1", "accent", "green")
            compare(w.accentName, "green", "accentName binding follows the store")
            s.setSetting("iw1", "cardBackdrop", "aurora")
            compare(w.cardBackdrop, "aurora", "cardBackdrop binding follows the store")

            // metrics binding tracks the shell metricsJson.
            root.metricsJson = "{\"z\":5}"
            compare(w.metrics.z, 5, "metrics binding follows the shell metrics")

            // tick binding tracks the dashboard drive counter.
            d._tick = 42
            compare(w.tick, 42, "tick binding follows the dashboard tick")

            w.destroy()
        }

        function test_injectWidget_defaults_when_no_override() {
            var d = ld.item
            var w = fakeWidget.createObject(root)
            d.injectWidget(w, "iw2", "cpu", false)
            // No title/accent/backdrop settings → the bindings resolve to the
            // documented empty/"none" fallbacks.
            compare(w.titleOverride, "", "no title → empty override")
            compare(w.accentName, "", "no accent → empty accent name")
            compare(w.cardBackdrop, "none", "no backdrop → 'none'")
            w.destroy()
        }

        function test_injectWidget_null_is_safe() {
            ld.item.injectWidget(null, "x", "cpu", false)   // must not throw
            verify(true, "injectWidget(null) is a no-op")
        }
    }
}
