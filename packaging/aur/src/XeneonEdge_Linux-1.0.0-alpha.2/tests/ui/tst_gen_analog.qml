import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: schema:showNumerals

// ─────────────────────────────────────────────────────────────────────────
// widget:analog — comprehensive coverage for AnalogClockWidget.qml plus its
// shared config surfaces (WidgetConfigSchema "analog" + DashboardStore).
//
// The face is drawn on a Canvas, so behaviour is verified two ways:
//   1. Derived properties/functions the widget exposes (cfg, showSeconds,
//      showNumerals, effAccent, title, big, showHeader).
//   2. Actual repaints, counted by connecting to the Canvas `painted()` signal
//      of the loaded widget instance. This lets us lock the "single-driver
//      rule" (the `active` flag) and the theme-reactivity contract.
//
// Assertions that FAIL do so because of a real bug in the widget (documented
// inline with BUG:) — those are intentionally left failing.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 480; height: 360

    // Normal, expanded host used by most tests.
    Item {
        id: box; anchors.fill: parent
        WidgetHarness { id: h; anchors.fill: parent; widgetFile: "AnalogClockWidget.qml"; expanded: true }
    }

    // A deliberately tiny host so Math.min(cx,cy)-6 <= 0 (rad<=0 branch).
    Item {
        width: 10; height: 10
        WidgetHarness { id: hTiny; anchors.fill: parent; widgetFile: "AnalogClockWidget.qml"; expanded: false }
    }

    // Shared config schema, instantiated directly (store/schema area).
    App.WidgetConfigSchema { id: sc }

    // ── Canvas paint probe ────────────────────────────────────────────────
    // We rebind `probe.target` to a widget's inner Canvas and count paints.
    property var probeCanvas: null
    property int paintCount: 0
    Connections {
        id: probe
        target: root.probeCanvas
        ignoreUnknownSignals: true
        function onPainted() { root.paintCount++ }
    }

    function findCanvas(node) {
        if (!node) return null
        var kids = node.children
        for (var i = 0; i < (kids ? kids.length : 0); i++) {
            var c = kids[i]
            if (c && typeof c.requestPaint === "function" && c.hasOwnProperty("canvasSize"))
                return c
            var found = findCanvas(c)
            if (found) return found
        }
        return null
    }

    // ─────────────────────────────────────────────────────────────────────
    TestCase {
        id: tc
        name: "AnalogClock"
        when: windowShown

        function initTestCase() {
            tryVerify(function () { return h.ready }, 3000)
            root.probeCanvas = root.findCanvas(h.item)
            verify(root.probeCanvas !== null, "found the widget's Canvas")
        }

        function init() {
            tryVerify(function () { return h.ready }, 3000)
            // Clear per-instance settings back to an empty document.
            var s = h.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            h.storeCtl._touchSettings()
            // Reset accent override + probe.
            h.item.accentName = ""
            h.theme.applyTheme("dark")
            root.paintCount = 0
        }
        function set(k, v) { h.storeCtl.setSetting("test-instance", k, v) }

        // Let any queued/async paints flush, then zero the counter so the next
        // measured action starts from a clean, deterministic baseline.
        function settle() { wait(150); root.paintCount = 0 }

        // Wait until at least one paint has happened since the baseline.
        function waitPaint(baseline, why) {
            tryVerify(function () { return root.paintCount > baseline }, 2000, why)
        }

        // ── Config plumbing ────────────────────────────────────────────────

        function test_defaults_when_settings_empty() {
            // BUG-free contract: with no settings the widget falls back to
            // showSeconds=true, showNumerals=false (matches the schema).
            var w = h.item
            compare(w.showSeconds, true, "default second hand on")
            compare(w.showNumerals, false, "default numerals off")
        }

        function test_schema_defaults_match_widget_fallback() {
            var s = sc.schemaFor("analog")
            var display = null
            for (var i = 0; i < s.sections.length; i++)
                if (s.sections[i].title === "Display") display = s.sections[i]
            verify(display !== null, "analog schema has a Display section")
            var seen = {}
            for (var j = 0; j < display.fields.length; j++)
                seen[display.fields[j].key] = display.fields[j].dflt
            compare(seen.showSeconds, true, "schema default showSeconds=true")
            compare(seen.showNumerals, false, "schema default showNumerals=false")
        }

        function test_showSeconds_honored() {
            var w = h.item
            set("showSeconds", false)
            compare(w.showSeconds, false, "showSeconds=false honored")
            set("showSeconds", true)
            compare(w.showSeconds, true, "showSeconds=true honored")
        }

        function test_showNumerals_honored() {
            var w = h.item
            set("showNumerals", true)
            compare(w.showNumerals, true, "showNumerals=true honored")
            set("showNumerals", false)
            compare(w.showNumerals, false, "showNumerals=false honored")
        }

        function test_cfg_reacts_to_store_revision() {
            var w = h.item
            var r0 = h.storeCtl.revision
            set("showNumerals", true)
            verify(h.storeCtl.revision > r0, "setSetting bumps store.revision")
            compare(w.cfg.showNumerals, true, "cfg re-reads after revision bump")
        }

        function test_cfg_is_a_snapshot_copy() {
            // cfg is JSON.parse(JSON.stringify(...)) — a copy, not the live obj.
            var w = h.item
            set("showNumerals", true)
            var snap = w.cfg
            snap.showNumerals = false          // mutate the copy
            compare(w.showNumerals, true, "mutating the cfg copy doesn't affect the widget")
        }

        // ── Identity / chrome ──────────────────────────────────────────────

        function test_title_and_icon() {
            var w = h.item
            compare(w.title, "Analog", "widget title")
            compare(w.iconName, "analog", "widget icon name")
        }

        function test_expanded_drives_big_and_header() {
            // Harness is expanded:true → big + header shown.
            var w = h.item
            compare(w.big, true, "expanded ⇒ big")
            compare(w.showHeader, true, "expanded ⇒ header shown")
        }

        // ── Accent (effAccent) ─────────────────────────────────────────────

        function test_default_effAccent_is_catSystem() {
            var w = h.item
            compare(String(w.effAccent), String(h.theme.catSystem),
                    "with no per-widget accent, effAccent = catSystem")
        }

        function test_accent_recolors_and_repaints() {
            var w = h.item
            settle()
            w.accentName = "red"
            compare(String(w.effAccent).toLowerCase(),
                    String(h.theme.accentPresets["red"].a).toLowerCase(),
                    "accentName=red ⇒ effAccent tracks the red preset")
            // onEffAccentChanged ⇒ a repaint.
            waitPaint(0, "changing the accent repaints the face")
        }

        // ── Repaint contract (paint probe) ─────────────────────────────────

        function test_tick_triggers_repaint() {
            var w = h.item
            settle()
            w.tick++
            waitPaint(0, "a tick repaints the canvas")
        }

        function test_showSeconds_change_repaints() {
            settle()
            set("showSeconds", false)   // onShowSecondsChanged ⇒ requestPaint
            waitPaint(0, "toggling the second hand repaints")
        }

        function test_showNumerals_change_repaints() {
            settle()
            set("showNumerals", true)   // onShowNumeralsChanged ⇒ requestPaint
            waitPaint(0, "toggling numerals repaints")
        }

        function test_resize_repaints() {
            // Component.onCompleted + onWidthChanged/onHeightChanged ⇒ paint.
            // Resize the top-level root (box/h/canvas are anchor-filled to it).
            settle()
            root.width = 460
            waitPaint(0, "a size change repaints the canvas")
            root.width = 480
        }

        // ── Real-bug locks (intentionally failing) ─────────────────────────

        function test_inactive_does_not_repaint() {
            // BUG (audit medium): `active` is declared (line 8) but never read.
            // The tile loader sets active=false for off-screen / expanded /
            // edit-mode tiles (single-driver rule, Dashboard.qml:14) so those
            // clocks should stop repainting. They don't — the tick Connections
            // (line 72) fires unconditionally. Correct behaviour: no repaint.
            var w = h.item
            h.active = false            // ⇒ item.active = false via harness binding
            compare(w.active, false, "widget received active=false")
            settle()
            w.tick++                    // a background tick while inactive
            wait(300)
            compare(root.paintCount, 0,
                    "an inactive clock must NOT repaint on tick (single-driver rule)")
            h.active = true
        }

        function test_theme_switch_repaints_face() {
            // BUG (audit low): onPaint reads theme.cardBorder / textTertiary /
            // textSecondary / textPrimary at paint time, but nothing watches
            // those roles — there is no Connections on `theme`. A dark→light
            // switch that leaves effAccent unchanged does NOT repaint, so the
            // ring/ticks/hands/numerals keep the old palette until the next
            // tick. Correct behaviour: the switch repaints the face.
            settle()
            h.theme.applyTheme("light")
            wait(300)
            verify(root.paintCount > 0,
                   "switching app theme should repaint the face with new role colors")
        }
    }

    // ── Edge case: zero-radius tile ───────────────────────────────────────
    TestCase {
        name: "AnalogClockTiny"
        when: windowShown

        function initTestCase() { tryVerify(function () { return hTiny.ready }, 3000) }

        function test_tiny_tile_paints_without_error() {
            // rad = min(cx,cy)-6 <= 0 on a 10x10 host → onPaint clears and
            // returns early. It must not throw and the widget stays valid.
            var w = hTiny.item
            verify(w !== null, "tiny widget loaded")
            verify(w.width <= 12 || w.height <= 12, "host is small enough for rad<=0")
            w.tick++            // force a paint through the rad<=0 branch
            wait(150)
            verify(hTiny.ready, "widget survives painting a zero-radius face")
        }
    }
}
