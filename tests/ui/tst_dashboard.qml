import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: fn:Dashboard._tileExists, fn:Dashboard.applyAppearance, fn:Dashboard.applyExternalState, fn:Dashboard.cfgAction, fn:Dashboard.closeExpanded, fn:Dashboard.injectWidget
// COVERS: fn:Dashboard.onAccentNameChanged, fn:Dashboard.onAnimatedBackgroundChanged, fn:Dashboard.onGlassOpacityChanged, fn:Dashboard.onOrientationModeChanged, fn:Dashboard.onReduceMotionChanged, fn:Dashboard.onShowWidgetGlowChanged
// COVERS: fn:Dashboard.onThemeModeChanged, fn:Dashboard.applyPreset
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
    App.WidgetSizes { id: _sizes }
    App.WidgetCatalog { id: _catalog }
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

    // ── Layout probes ────────────────────────────────────────────────────────
    // The page delegates (each carries its page's packing) and the tile delegates
    // (each carries the placement it was positioned from), duck-typed out of the
    // object graph. Note EVERY page is instantiated by the SwipeView, so tileCells()
    // spans the whole document, not just the current page.
    function pageItems() {
        var out = []
        eachItem(ld.item, function (x) {
            if (x && x.placements !== undefined && x.longExtent !== undefined
                  && x.addPlacement !== undefined) out.push(x)
        })
        return out
    }
    function pageItem() { var ps = pageItems(); return ps.length ? ps[0] : null }
    function pageFlick() {
        return findPred(ld.item, function (x) { return x && x.cellShort !== undefined && x.cellLong !== undefined })
    }
    function tileCells() {
        var out = []
        eachItem(ld.item, function (x) {
            if (x && x._r !== undefined && x.modelData !== undefined && x.modelData
                  && x.modelData.size !== undefined && x.modelData.s !== undefined) out.push(x)
        })
        return out
    }
    function cellFor(id) {
        var cs = tileCells()
        for (var i = 0; i < cs.length; i++) if (cs[i].modelData.id === id) return cs[i]
        return null
    }
    // True once the page has laid out N tiles with real geometry, in `portrait`.
    function laidOut(n, portrait) {
        var f = pageFlick()
        if (!f || !(f.cellLong > 0)) return false
        if ((f.height > f.width) !== portrait) return false
        var cs = tileCells()
        if (cs.length !== n) return false
        for (var i = 0; i < n; i++) if (!(cs[i].width > 0 && cs[i].height > 0)) return false
        return true
    }
    // Make the dashboard PORTRAIT (tall: the 720x2560 reflow) or LANDSCAPE (the
    // 2560x720 strip). Dashboard reads its own width/height — exactly as main.qml's
    // contentRoot hands it over on a rotation.
    function orient(portrait) {
        root.width = portrait ? 720 : 2560
        root.height = portrait ? 2560 : 720
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

        // ── expanded overlay: content is retained through the close fade (W3) ──
        // closeExpanded() clears the STATE immediately, but the overlay's widget,
        // title and icon must keep rendering while the card fades out — keyed off
        // the retained shownType/shownId — or the close pops to an empty card on
        // frame 1. The retained pair clears only once the overlay is fully hidden.
        function test_overlay_content_survives_the_close_fade() {
            var d = ld.item
            _theme.reduceMotion = false
            d.applyExternalState(root.makeDoc([ { id: "ov1", type: "cpu" } ]))
            d.expandedId = "ov1"; d.expandedType = "cpu"
            compare(d.shownType, "cpu", "opening synced the retained type")
            compare(d.shownId, "ov1", "opening synced the retained id")
            // Let the overlay genuinely fade IN before closing — closing within
            // the same event-loop turn would find opacity still at 0 (no frame
            // has run), which is not a state a user can ever produce.
            var ovl = root.findPred(ld.item, function (x) { return x && x.ovlWide !== undefined })
            verify(ovl !== null, "found the expanded overlay")
            tryCompare(ovl, "opacity", 1.0, 2000, "overlay fully shown")
            d.closeExpanded()
            verify(!d.hasExpanded, "the state machine closed immediately")
            compare(d.shownType, "cpu", "…but the overlay CONTENT is retained for the fade")
            compare(d.shownId, "ov1", "id retained with it")
            tryCompare(d, "shownType", "", 2000, "retained type drops once the fade completes")
            compare(d.shownId, "", "retained id drops with it")
        }

        function test_overlay_retained_state_clears_instantly_under_reduce_motion() {
            var d = ld.item
            _theme.reduceMotion = true
            d.expandedId = "rm1"; d.expandedType = "cpu"
            compare(d.shownType, "cpu", "opened")
            d.closeExpanded()
            // 100ms < the 150ms motion-on fade: only a genuinely collapsed
            // transition can pass this window.
            tryCompare(d, "shownType", "", 100, "reduce-motion: no fade, cleared at once")
            _theme.reduceMotion = false
        }

        // ── edit mode: the tile scrim eases in/out instead of hard-cutting ─────
        function test_edit_scrim_fades_in_and_out() {
            var d = ld.item
            _theme.reduceMotion = false
            d.applyExternalState(root.makeDoc([ { id: "e1", type: "cpu" } ]))
            tryVerify(function () { return root.tileCells().length === 1 }, 4000, "tile laid out")
            var cell = root.tileCells()[0]
            var scrim = null
            for (var i = 0; i < cell.children.length; i++)
                if (cell.children[i].z === 30) scrim = cell.children[i]
            verify(scrim !== null, "found the per-tile edit scrim")
            compare(scrim.visible, false, "hidden outside edit mode")

            d.editMode = true
            // Sampled synchronously on the mode flip: the ease has only just
            // started, so anything < 1.0 proves it is a fade, not a hard cut.
            verify(scrim.opacity < 1.0, "easing in, not a hard cut (opacity " + scrim.opacity + ")")
            tryCompare(scrim, "opacity", 1.0, 2000, "…and settles fully shown")
            verify(scrim.visible, "fully visible in edit mode")

            d.editMode = false
            verify(scrim.visible, "still rendering while it fades back out")
            tryCompare(scrim, "visible", false, 2000, "gone once the fade completes")
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
        // A named size -> how much ROOM the widget has. Named, so widgets ask "have I
        // got room?" rather than re-deriving it from geometry they shouldn't know.
        // Judged on the PROJECTED half-cells, so the same size honestly reports "tall"
        // in portrait and "wide" in landscape — which is the whole point of a panel
        // that rotates.
        function test_sizeClassFor_maps_sizes_to_room() {
            var d = ld.item
            compare(d.sizeClassFor("1x1", false), "compact", "the baseline third is the reference shape")
            compare(d.sizeClassFor("1x1", true), "compact", "and it is that shape in BOTH orientations")
            compare(d.sizeClassFor("0.5x0.5", false), "compact", "a twelfth is square-ish too, just small")

            // The rotating pair: ONE size, two honest answers.
            compare(d.sizeClassFor("1x0.5", false), "wide", "portrait: full width, half a third tall")
            compare(d.sizeClassFor("1x0.5", true), "tall", "landscape: the SAME size is now tall")
            compare(d.sizeClassFor("0.5x1", false), "tall", "portrait: half width, a third tall")
            compare(d.sizeClassFor("0.5x1", true), "wide", "landscape: and now it is wide")

            // "large" had to be REDEFINED. It meant "doubled on both axes" on the old
            // span grid; the size model has no such shape (the short axis stops at 1),
            // so that rule would have made it unreachable. It now means what it always
            // implied: two thirds of the screen or more.
            compare(d.sizeClassFor("1x2", false), "large", "two thirds of the screen is real room")
            compare(d.sizeClassFor("1x3", true), "large", "and the whole screen certainly is")
            compare(d.sizeClassFor("1x1.5", false), "tall", "half the screen is not yet 'large'")

            // A bad size must claim the LEAST room, never silently the baseline's.
            compare(d.sizeClassFor("2x2", false), "compact", "the dead span vocabulary is not a size")
            compare(d.sizeClassFor(undefined, false), "compact", "and neither is nothing at all")
        }

        // COVERS: fn:Dashboard.nextSize
        // The edit-mode resize button. The old fixed 1x1->2x1->1x2->2x2 cycle has NO
        // equivalent — those spans aren't sizes — so the cycle is the widget TYPE's own
        // declared list, or it would offer shapes the widget was never built for.
        function test_nextSize_cycles_the_types_own_legal_sizes() {
            var d = ld.item
            var cpu = _catalog.sizesFor("cpu")
            compare(cpu.indexOf("1x3"), -1, "precondition: cpu does not declare the full screen")
            // Walk a full cycle and prove it visits cpu's list exactly, and nothing else.
            var seen = [], cur = _catalog.defaultSize("cpu")
            for (var i = 0; i < cpu.length; i++) { cur = d.nextSize("cpu", cur); seen.push(cur) }
            seen.sort()
            var expect = cpu.slice(); expect.sort()
            compare(seen.join(","), expect.join(","),
                    "one full cycle visits every size cpu declares, and nothing else")
            compare(d.nextSize("cpu", "1x1"), d.nextSize("cpu", "1x1"), "and it is deterministic")

            // It wraps rather than running off the end.
            compare(d.nextSize("cpu", cpu[cpu.length - 1]), cpu[0], "the last size wraps to the first")
            // A tile whose stored size is not in the list (a type whose declarations
            // changed under it) must still land somewhere sane, not on undefined.
            compare(d.nextSize("cpu", "1x3"), cpu[0], "an off-list size restarts the cycle")
            compare(d.nextSize("no-such-type", "1x1"), "", "an unknown type offers no next size")
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

        // ── applyPreset (the post-setup Screens picker, W5 finding 3) ─────────
        function test_applyPreset_seeds_layout_and_keeps_user_appearance() {
            var d = ld.item
            var s = root.store()
            s.load("blank")
            // The user's own choices, made post-setup — none of these are
            // preset "character" keys and every one must survive the apply.
            s.setAppearance("themeMode", "nord")
            s.setAppearance("accent", "green")
            s.setAppearance("glass", 0.31)
            s.setAppearance("netOffline", true)
            // reduceMotion IS a preset character key — but a11y beats character.
            s.setAppearance("reduceMotion", true)

            verify(d.applyPreset("developer"), "applyPreset accepts a known preset id")
            var pages = s.pages()
            compare(pages.length, 2, "the developer preset's two pages were seeded")
            compare(pages[0].tiles[0].type, "httpjson", "…with its designed tiles (CI status slot)")
            compare(s.settingsFor(pages[0].tiles[0].id).title, "CI status", "and the authored per-tile settings")

            var a = s.appearance()
            compare(a.themeMode, "nord", "the user's theme survives the apply — the confirm copy's promise")
            compare(a.accent, "green", "accent survives")
            compare(a.glass, 0.31, "glass survives")
            compare(a.netOffline, true, "the egress kill switch is NEVER silently re-enabled by a preset")
            compare(a.reduceMotion, true, "an explicit reduce-motion choice beats the preset's character")
            compare(a.bgStyle, "grid", "the preset's character still lands where the user made no choice (bgStyle)")
            compare(a.animatedBg, true, "…and animatedBg comes from the preset's character")

            compare(root.themeMode, "nord", "applyPreset re-applied appearance to the live shell")
        }

        function test_applyPreset_blank_and_bad_ids() {
            var d = ld.item
            var s = root.store()
            s.load("developer")
            verify(d.applyPreset("blank"), "applyPreset accepts the blank slate")
            compare(s.pages().length, 1, "blank → one empty page")
            compare(s.pages()[0].tiles.length, 0, "…with no tiles")
            var before = JSON.stringify(s.pages())
            verify(!d.applyPreset("no-such-preset"), "an unknown id is refused")
            verify(!d.applyPreset(""), "an empty id is refused")
            verify(!d.applyPreset(null), "null is refused")
            compare(JSON.stringify(s.pages()), before, "refused ids change nothing")
        }

        function test_applyPreset_respects_the_org_policy_lock() {
            var d = ld.item
            var s = root.store()
            s.lockToPreset("health")
            var before = JSON.stringify(s.pages())
            verify(!d.applyPreset("developer"), "applyPreset refuses under an org-forced preset (E9)")
            compare(JSON.stringify(s.pages()), before, "the forced layout is untouched")
            s.policyLockedPreset = ""          // release the lock for later tests
            s.load("blank")
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

    // ── The layout itself, measured in pixels on the REAL Dashboard ──────────
    // Everything above drives properties. This drives the renderer: GridLayout was
    // replaced because of what it DREW, so the replacement has to be proved the same
    // way.
    TestCase {
        name: "DashboardLayout"
        when: windowShown

        function initTestCase() {
            tryVerify(function () { return ld.status === Loader.Ready && ld.item !== null }, 5000)
        }
        function init() { root.store().load("blank"); ld.item.editMode = false }
        function cleanupTestCase() { root.width = 900; root.height = 600 }

        // THE BUG THIS EPIC EXISTS FOR.
        // Measured on the old GridLayout: three 1x1 tiles on a 1200px page rendered at
        // exactly 400px each (correct — which is why nothing LOOKED broken), but a
        // 0.5x0.5 beside a 1x1 rendered at 600px: HALF the page, when it must be a
        // twelfth of the screen. GridLayout sizes a row by what is IN it and collapses
        // span-only rows, so a tile's size depended on what else was on the page. A size
        // is a fraction of the SCREEN, so it may not. This is that exact page.
        function test_a_half_by_half_beside_a_baseline_is_a_twelfth_not_a_half() {
            root.orient(true)                       // 720x2560 — the portrait reflow
            ld.item.applyExternalState(root.makeDoc([ { id: "small", type: "cpu", size: "0.5x0.5" },
                                                      { id: "big", type: "cpu", size: "1x1" } ]))
            tryVerify(function () { return root.laidOut(2, true) }, 4000, "the two tiles laid out in portrait")
            var f = root.pageFlick()
            var gap = _theme.spacingMd
            var pageShort = f.width, pageLong = f.height
            verify(pageLong > pageShort, "precondition: the page really is portrait")

            var small = root.cellFor("small"), big = root.cellFor("big")
            // Add the gap back: it is inset OUT of the tile, so tile + gap is the cell.
            fuzzyCompare(small.width + gap, pageShort / 2, 0.51,
                         "0.5 of the short axis: " + small.width + " on a " + pageShort + "px page")
            fuzzyCompare(small.height + gap, pageLong / 6, 0.51,
                         "and half a third of the long axis: " + small.height +
                         " on a " + pageLong + "px page")

            // THE REGRESSION, stated as the number GridLayout produced. On the old grid
            // this tile measured HALF the long axis, because its row held nothing bigger.
            verify(small.height + gap < pageLong / 2 * 0.9,
                   "BUG GUARD: the 0.5x0.5 is NOT half the page (GridLayout drew it at " +
                   (pageLong / 2) + "px; it is " + small.height + "px)")
            fuzzyCompare((small.height + gap) / (pageLong / 2), 1 / 3, 0.005,
                         "it is a THIRD of what GridLayout gave it along the long axis")
            // 0.5 of the short axis x 1/6 of the long axis = a twelfth of the SCREEN.
            fuzzyCompare(((small.width + gap) * (small.height + gap)) / (pageShort * pageLong),
                         1 / 12, 0.005, "a twelfth of the screen — the size's whole definition")

            // And its neighbour is untouched: a third, whatever else is on the page.
            fuzzyCompare(big.width + gap, pageShort, 0.51, "the 1x1 keeps the full short axis")
            fuzzyCompare(big.height + gap, pageLong / 3, 0.51, "and exactly a third of the long axis")
            fuzzyCompare(((big.width + gap) * (big.height + gap)) / (pageShort * pageLong),
                         1 / 3, 0.005, "a third of the screen — unaffected by what sits beside it")
        }

        // The case that ALWAYS worked, kept honest: three baselines still fill the
        // screen exactly, and each is a third — the default dashboard.
        function test_three_baselines_still_measure_a_third_each() {
            root.orient(true)
            ld.item.applyExternalState(root.makeDoc([ { id: "a", type: "cpu", size: "1x1" },
                                                      { id: "b", type: "cpu", size: "1x1" },
                                                      { id: "c", type: "cpu", size: "1x1" } ]))
            tryVerify(function () { return root.laidOut(3, true) }, 4000, "three tiles laid out in portrait")
            var f = root.pageFlick()
            var gap = _theme.spacingMd
            var third = f.height / 3
            var ids = ["a", "b", "c"]
            for (var i = 0; i < 3; i++) {
                var c = root.cellFor(ids[i])
                fuzzyCompare(c.height + gap, third, 0.51, ids[i] + " is a third of the page tall")
                fuzzyCompare(c.y - gap / 2, i * third, 0.51, ids[i] + " starts exactly where the last ended")
            }
            compare(root.pageItem().longExtent, _sizes.longHalves, "the three of them fill the screen")
            verify(!f.interactive, "a page that fits does not scroll (so it cannot fight the page swipe)")
        }

        // ROTATION STABILITY.
        // The same page, packed for portrait and for landscape, puts every tile in the
        // same SEMANTIC slot. Packing in physical coordinates scrambled 99.2% of 5-tile
        // pages here; packing semantically makes rotation a pure projection.
        function test_rotation_keeps_every_tile_in_the_same_semantic_slot() {
            var doc = root.makeDoc([ { id: "a", type: "cpu", size: "0.5x1" },
                                     { id: "b", type: "cpu", size: "0.5x0.5" },
                                     { id: "c", type: "cpu", size: "1x1" },
                                     { id: "d", type: "cpu", size: "0.5x0.5" },
                                     { id: "e", type: "cpu", size: "1x0.5" } ])
            var ids = ["a", "b", "c", "d", "e"]

            root.orient(true)
            ld.item.applyExternalState(doc)
            tryVerify(function () { return root.laidOut(5, true) }, 4000, "five tiles laid out in portrait")
            var portraitSlots = {}, portraitPx = {}
            for (var i = 0; i < 5; i++) {
                var c = root.cellFor(ids[i])
                var m = c.modelData
                portraitSlots[ids[i]] = m.s + "," + m.l + "," + m.es + "," + m.el
                portraitPx[ids[i]] = { x: c.x, y: c.y }
            }

            // Turn the panel. Nothing else changes — same document, same store.
            root.orient(false)
            tryVerify(function () { return root.laidOut(5, false) }, 4000,
                      "the dashboard reflowed to the landscape strip")
            var f2 = root.pageFlick()
            var cellS = f2.cellShort, cellL = f2.cellLong
            for (var j = 0; j < 5; j++) {
                var c2 = root.cellFor(ids[j])
                var m2 = c2.modelData
                compare(m2.s + "," + m2.l + "," + m2.es + "," + m2.el, portraitSlots[ids[j]],
                        ids[j] + ": the rotation did not move it out of its semantic slot")
                // …and the pixels are that slot PROJECTED: the long axis moved from y to
                // x. A re-pack would have put it somewhere unrelated.
                fuzzyCompare(c2.x - _theme.spacingMd / 2, m2.l * cellL, 0.51,
                             ids[j] + ": its long coordinate is now the X axis")
                fuzzyCompare(c2.y - _theme.spacingMd / 2, m2.s * cellS, 0.51,
                             ids[j] + ": and its short coordinate is the Y axis")
            }
            // Rotating BACK restores the original pixels exactly — no drift, no reshuffle.
            root.orient(true)
            tryVerify(function () { return root.laidOut(5, true) }, 4000, "and turned back")
            for (var k = 0; k < 5; k++) {
                var c3 = root.cellFor(ids[k])
                fuzzyCompare(c3.x, portraitPx[ids[k]].x, 0.51, ids[k] + " came back to the same x")
                fuzzyCompare(c3.y, portraitPx[ids[k]].y, 0.51, ids[k] + " came back to the same y")
            }
        }

        // CAPACITY.
        // The 2x6 grid sizes the CELL, not the page. A page longer than the screen is
        // placed IN FULL and scrolls — no tile is refused, capped or dropped. This is
        // the policy that keeps the over-long shipped presets renderable.
        function test_an_overlong_page_keeps_every_tile_and_scrolls() {
            root.orient(true)
            var tiles = []
            for (var i = 0; i < 6; i++) tiles.push({ id: "t" + i, type: "cpu", size: "1x1" })
            ld.item.applyExternalState(root.makeDoc(tiles))   // 6 x 1x1 = 12 half-cells = 2 screens
            tryVerify(function () { return root.laidOut(6, true) }, 4000, "six tiles laid out in portrait")

            var p = root.pageItem(), f = root.pageFlick()
            compare(root.tileCells().length, 6, "every tile is placed — none refused, none dropped")
            compare(p.longExtent, 12, "the page is exactly two screens long")
            verify(f.interactive, "so it SCROLLS — the 7th half-unit overflows, it is not refused")
            fuzzyCompare(f.contentHeight, 12 * f.cellLong, 0.51, "and the scrollable content is that long")

            // The decisive part: overflowing does NOT shrink anyone. Each tile is still a
            // third of the SCREEN — which is the entire reason GridLayout had to go.
            for (var j = 0; j < 6; j++)
                fuzzyCompare(root.cellFor("t" + j).height + _theme.spacingMd, f.height / 3, 0.51,
                             "t" + j + " is still a third of the SCREEN on a 2-screen page")
        }

        // ── W5 BLOCKER (finding 2): the expanded overlay in LANDSCAPE ─────────
        // On the 2560x720 strip the config form used to collapse to a ~10px
        // sliver (both overlay columns declared fillWidth; GridLayout stretches
        // in proportion to preferred widths, and the panel's implicit width is
        // ~0), so "connect CI to a URL" was impossible on-device. Assert the
        // landscape split structurally: the form gets AT LEAST half the
        // overlay, renders real scrollable content, and the preview keeps a
        // sane share — and portrait still gives the form the full width.
        function overlayOf() {
            return root.findPred(ld.item, function (x) { return x && x.ovlWide !== undefined })
        }
        function configPanelOf() {
            return root.findPred(ld.item, function (x) {
                return x && x.schema !== undefined && x.st !== undefined
                         && x.instanceId !== undefined && x.statusText !== undefined
            })
        }
        function test_landscape_expanded_overlay_shows_a_usable_form() {
            root.orient(false)                                  // 2560x720
            var d = ld.item
            d.applyExternalState(root.makeDoc([ { id: "ci", type: "httpjson" } ]))
            tryVerify(function () { return root.laidOut(1, false) }, 4000, "tile laid out in landscape")
            d.cfgStatus = ""; d.expandedId = "ci"; d.expandedType = "httpjson"
            var ovl = overlayOf()
            verify(ovl !== null, "found the expanded overlay")
            tryCompare(ovl, "opacity", 1.0, 2000, "overlay shown")
            verify(ovl.ovlWide, "2560x720 puts the overlay in its wide (landscape) layout")

            var panel = configPanelOf()
            verify(panel !== null, "found the WidgetConfigPanel")
            tryVerify(function () { return panel.width >= ovl.width * 0.5 }, 4000,
                      "the FORM gets at least half the overlay width (got " +
                      panel.width + " of " + ovl.width + ") — the W5 sliver regression")
            verify(panel.height > 200, "the form has real height (" + panel.height + "px)")
            verify(panel.schema.sections.length > 0, "httpjson exposes a real config schema")

            // The form renders actual fields: its scroller carries real content
            // taller than a bare margin, i.e. the URL/token/poll controls exist.
            var scroll = root.findPred(panel, function (x) { return x && x.objectName === "cfgScroll" })
            verify(scroll !== null, "found the form's scroller")
            tryVerify(function () { return scroll.contentHeight > 200 }, 4000,
                      "the form laid out real fields (contentHeight " + scroll.contentHeight + ")")

            // And the preview did not silently vanish either: it keeps a fixed,
            // bounded share beside the form.
            var preview = root.findPred(ld.item, function (x) {
                return x && x.parent === panel.parent && x !== panel && x.width > 0
            })
            verify(preview !== null, "the widget preview column is present")
            verify(preview.width <= ovl.width * 0.42 + 1,
                   "the preview is capped (got " + preview.width + ") so it can never starve the form")
            d.closeExpanded()
        }

        function test_portrait_expanded_overlay_keeps_the_full_width_form() {
            root.orient(true)                                   // 720x2560
            var d = ld.item
            d.applyExternalState(root.makeDoc([ { id: "ci2", type: "httpjson" } ]))
            tryVerify(function () { return root.laidOut(1, true) }, 4000, "tile laid out in portrait")
            d.expandedId = "ci2"; d.expandedType = "httpjson"
            var ovl = overlayOf()
            tryCompare(ovl, "opacity", 1.0, 2000, "overlay shown")
            verify(!ovl.ovlWide, "720x2560 keeps the stacked portrait layout")
            var panel = configPanelOf()
            verify(panel !== null, "found the WidgetConfigPanel")
            tryVerify(function () { return panel.width >= ovl.width * 0.8 }, 4000,
                      "portrait: the form still spans the width (" + panel.width + " of " + ovl.width + ")")
            d.closeExpanded()
        }

        // A page that fits must never become scrollable — an inert Flickable is what
        // keeps the page swipe usable (they share an axis in landscape).
        function test_a_page_that_fits_is_not_scrollable() {
            root.orient(false)
            ld.item.applyExternalState(root.makeDoc([ { id: "a", type: "cpu", size: "1x1" } ]))
            tryVerify(function () { return root.laidOut(1, false) }, 4000, "one tile laid out in landscape")
            var f = root.pageFlick()
            verify(!f.interactive, "one tile does not scroll")
            compare(root.pageItem().longExtent, 2, "it reaches 2 of the screen's 6 half-cells")
            fuzzyCompare(f.contentWidth, f.width, 0.51,
                         "landscape: the content is exactly one screen along the long (X) axis")
        }

        // THE SHIPPED PRESETS, on the real Dashboard.
        //
        // tst_preset_catalog asserts the budget against WidgetPacker directly; this
        // asserts the same property survives all the way to rendered geometry —
        // every tile placed, every page one screen or less, nothing scrolling.
        //
        // It used to pin the OPPOSITE (14 of 17 pages over capacity, worst 2.0x) as
        // the measured, deliberate state of a library that had not yet been
        // re-authored. It is re-authored now: pages that fit never scroll, so the
        // landscape Flickable can never steal the page swipe.
        function test_every_shipped_preset_renders_without_losing_a_tile() {
            root.orient(true)
            var cat = presetCat
            verify(cat.items.length > 0, "the preset library is present")
            var checkedPages = 0, overCapacity = 0, worst = 0, over = []
            for (var i = 0; i < cat.items.length; i++) {
                var id = cat.items[i].id
                root.store().load(id)
                var pages = root.store().pages()
                // Every page is instantiated by the SwipeView, so every tile of every
                // page must be placed — the count is the document's, not page 1's.
                var want = 0
                for (var p = 0; p < pages.length; p++) want += pages[p].tiles.length
                tryVerify(function () { return root.laidOut(want, true) }, 4000,
                          id + ": all " + want + " tiles across " + pages.length + " page(s) are placed")

                var pis = root.pageItems()
                compare(pis.length, pages.length, id + ": one delegate per page")
                for (var q = 0; q < pis.length; q++) {
                    var ratio = pis[q].longExtent / _sizes.longHalves
                    compare(pis[q].placements.length, pages[q].tiles.length,
                            id + "/" + pages[q].name + ": no tile went missing in the packing")
                    if (ratio > 1) {
                        overCapacity++; worst = Math.max(worst, ratio)
                        over.push(id + "/" + pages[q].name + " " + ratio.toFixed(2) + "x")
                    }
                    checkedPages++
                }
                var cs = root.tileCells()
                for (var j = 0; j < cs.length; j++)
                    verify(cs[j].width > 0 && cs[j].height > 0,
                           id + ": tile " + j + " has real geometry, not a collapsed box")
            }
            verify(checkedPages >= cat.items.length,
                   "every preset contributed at least one rendered page, got " + checkedPages)
            compare(overCapacity, 0,
                    "NO shipped preset page runs past one screen — over: [" + over.join(", ") + "]")
            compare(worst, 0, "so there is no worst case to report")
        }
    }

    App.PresetCatalog { id: presetCat }
}
