import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Widgets

// COVERS: schema:endHour, schema:progressStyle, schema:showPercent, schema:startHour

// ─────────────────────────────────────────────────────────────────────────
// Comprehensive tests for widget:eod — ui/qml/widgets/EndOfDayWidget.qml
// (the "End of Day" workday-progress widget) plus the shared config schema /
// ConfigField surface that drives its hour fields.
//
// Drives config through the shared DashboardStore (setSetting/patchSettings on
// "test-instance") exactly like the live dashboard, plus the Manager control
// socket path (store.applyExternal), and asserts on the widget's derived
// properties/functions (cfg, startHour, endHour, showPercent, progressStyle,
// validHours, frac, fmtDur(), remaining, setHours(), effAccent) and on the
// actual rendered Text/PillButton/RingProgress nodes.
//
// Several assertions encode the INTENDED behaviour and currently FAIL because
// of real bugs called out in the audit (out-of-range hours via the config
// stepper corrupt the window; ring-mode time text ignores effAccent; percent
// caption is not zero-padded like the editor; long remaining strings overflow
// the tile; the hour schema fields omit min/max; cross-midnight windows are
// silently rejected). Those failures are the point and are left in.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 520; height: 900

    // Expanded harness for the bulk of the logic + layout tests.
    WidgetHarness {
        id: hEod
        x: 0; y: 0; width: 480; height: 760
        widgetFile: "EndOfDayWidget.qml"; expanded: true
    }
    // A second, collapsed harness sized to a half-width portrait tile
    // (~344px on the 720px panel) for overflow/clipping checks.
    WidgetHarness {
        id: hCollapsed
        x: 0; y: 760; width: 344; height: 140
        widgetFile: "EndOfDayWidget.qml"; expanded: false
    }

    // Shared config-surface components, instantiated directly.
    App.WidgetConfigSchema { id: schema }

    // ConfigField needs a `theme` in scope to render its hour control; expose one.
    Item {
        id: cfEnv
        width: 1; height: 1
        property alias theme: cfTheme
        Component.onCompleted: cfStore.load("blank")   // seed a live `data` document
        App.Theme { id: cfTheme }
        App.DashboardStore { id: cfStore }
        Widgets.ConfigField {
            id: cfHour
            field: ({ key: "startHour", label: "Start hour", type: "hour", dflt: 9 })
            st: cfStore
            instanceId: "cf-inst"
        }
    }

    // ── Shared traversal helpers (root-level → visible to every TestCase) ────
    function collect(node, acc) {
        acc.push(node)
        var ch = node.children
        if (ch)
            for (var i = 0; i < ch.length; i++)
                if (ch[i]) collect(ch[i], acc)
        return acc
    }
    // Effective visibility: walk from node up to `top` (inclusive).
    function effVisible(node, top) {
        var n = node
        while (n) {
            if (n.visible === false) return false
            if (n === top) break
            n = n.parent
        }
        return true
    }
    // The single VISIBLE Text node whose text === `str`, or null.
    function visibleTextEq(top, str) {
        var all = collect(top, [])
        for (var i = 0; i < all.length; i++) {
            var o = all[i]
            if (o !== top && typeof o.text === "string" && o.text === str && effVisible(o, top))
                return o
        }
        return null
    }
    // The single VISIBLE Text node whose text CONTAINS `sub`, or null.
    function visibleTextContains(top, sub) {
        var all = collect(top, [])
        for (var i = 0; i < all.length; i++) {
            var o = all[i]
            if (o !== top && typeof o.text === "string" && o.text.indexOf(sub) >= 0 && effVisible(o, top))
                return o
        }
        return null
    }
    // All PillButton-like nodes (declare a string `label`).
    function pills(top) {
        var out = []
        var all = collect(top, [])
        for (var i = 0; i < all.length; i++) {
            var o = all[i]
            if (o !== top && typeof o.label === "string" && o.label !== ""
                    && o.hasOwnProperty("primary"))
                out.push(o)
        }
        return out
    }
    // The visible RingProgress node (has `value` + `progressColor`), or null.
    function visibleRing(top) {
        var all = collect(top, [])
        for (var i = 0; i < all.length; i++) {
            var o = all[i]
            if (o !== top && o.value !== undefined && o.progressColor !== undefined
                    && effVisible(o, top))
                return o
        }
        return null
    }

    function clear(h) {
        var s = h.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        h.storeCtl._touchSettings()
    }

    // ── frac / remaining time math (real wall clock) ─────────────────────────
    TestCase {
        name: "EodTimeMath"
        when: windowShown
        function init() { tryVerify(function () { return hEod.ready }, 3000); clear(hEod) }
        function patch(o) { hEod.storeCtl.patchSettings("test-instance", o) }

        function test_before_start_frac_zero_and_countdown() {
            var w = hEod.item
            var h = new Date().getHours()
            if (h > 21) { skip("no headroom before midnight to place a future start"); return }
            patch({ startHour: h + 1, endHour: h + 2 })
            compare(w.frac, 0, "before the workday, frac is 0")
            verify(w.remaining.indexOf("Starts in") === 0,
                   "before start shows 'Starts in Hh Mm' (got '" + w.remaining + "')")
        }

        function test_after_end_frac_one_and_done() {
            var w = hEod.item
            var h = new Date().getHours()
            if (h < 1) { skip("cannot place a window that already ended before 01:00"); return }
            patch({ startHour: 0, endHour: h })
            compare(w.frac, 1, "after the end, frac clamps to 1")
            compare(w.remaining, "Done! 🎉", "past the end shows the completion string")
        }

        function test_within_window_frac_and_live_remaining() {
            var w = hEod.item
            var h = new Date().getHours()
            if (h < 1 || h > 22) { skip("current hour leaves no symmetric window"); return }
            patch({ startHour: h - 1, endHour: h + 1 })
            verify(w.frac > 0 && w.frac < 1, "mid-window frac is in (0,1) (got " + w.frac + ")")
            verify(w.remaining !== "Set hours" && w.remaining !== "Done! 🎉"
                   && w.remaining.indexOf("Starts") !== 0,
                   "within the window shows a live duration (got '" + w.remaining + "')")
        }

        function test_tick_recomputes_frac_and_remaining() {
            var w = hEod.item
            var h = new Date().getHours()
            if (h < 1 || h > 22) { skip("no window available to observe the tick binding"); return }
            patch({ startHour: h - 1, endHour: h + 1 })
            var f0 = w.frac
            var r0 = w.remaining
            w.tick++            // the frac/remaining bindings reference w.tick
            verify(!isNaN(w.frac) && w.frac >= 0 && w.frac <= 1,
                   "frac stays valid after a tick (got " + w.frac + ")")
            verify(w.remaining.length > 0, "remaining recomputed after tick (got '" + w.remaining + "')")
        }

        function test_fmtDur_formats_hours_minutes() {
            var w = hEod.item
            compare(w.fmtDur(0), "0h 0m")
            compare(w.fmtDur(3600), "1h 0m")
            compare(w.fmtDur(3661), "1h 1m")
            compare(w.fmtDur(5400), "1h 30m")
            compare(w.fmtDur(45 * 60), "0h 45m")
        }
    }

    // ── Invalid / degenerate windows ────────────────────────────────────────
    TestCase {
        name: "EodInvalidWindow"
        when: windowShown
        function init() { tryVerify(function () { return hEod.ready }, 3000); clear(hEod) }
        function patch(o) { hEod.storeCtl.patchSettings("test-instance", o) }

        function test_end_before_start_is_set_hours() {
            var w = hEod.item
            patch({ startHour: 17, endHour: 9 })
            compare(w.frac, 0, "inverted window has frac 0")
            compare(w.remaining, "Set hours", "inverted window prompts to set hours")
        }
        function test_equal_hours_is_set_hours() {
            var w = hEod.item
            patch({ startHour: 10, endHour: 10 })
            compare(w.frac, 0, "zero-length window has frac 0")
            compare(w.remaining, "Set hours", "zero-length window prompts to set hours")
        }
        function test_validHours_flag_tracks_comparison() {
            var w = hEod.item
            patch({ startHour: 9, endHour: 17 })
            compare(w.validHours, true, "9→17 is valid")
            patch({ startHour: 17, endHour: 9 })
            compare(w.validHours, false, "17→9 is invalid")
        }
    }

    // ── setHours() clamping + 1-hour minimum span ───────────────────────────
    TestCase {
        name: "EodSetHours"
        when: windowShown
        function init() { tryVerify(function () { return hEod.ready }, 3000); clear(hEod) }
        function patch(o) { hEod.storeCtl.patchSettings("test-instance", o) }

        function test_cannot_invert_pushing_start_past_end() {
            var w = hEod.item
            patch({ startHour: 9, endHour: 17 })
            w.setHours(20, 17)   // move start beyond end
            verify(w.endHour > w.startHour, "end stays after start (start=" + w.startHour + " end=" + w.endHour + ")")
        }
        function test_cannot_invert_pulling_end_below_start() {
            var w = hEod.item
            patch({ startHour: 9, endHour: 17 })
            w.setHours(w.startHour, w.startHour - 2)
            verify(w.endHour > w.startHour, "end can't drop to/under start")
        }
        function test_one_hour_min_span_start_yields() {
            var w = hEod.item
            patch({ startHour: 16, endHour: 17 })
            w.setHours(17, 17)   // press Start+ into end
            compare(w.startHour, 16, "Start+ at the 1h floor keeps start at 16")
            compare(w.endHour, 17, "end unchanged")
        }
        function test_one_hour_min_span_end_yields() {
            var w = hEod.item
            patch({ startHour: 16, endHour: 17 })
            w.setHours(16, 16)   // press End- into start
            compare(w.endHour, 17, "End- at the 1h floor keeps end at 17")
            compare(w.startHour, 16, "start unchanged")
        }
        function test_setHours_clamps_upper_bounds() {
            var w = hEod.item
            w.setHours(25, 30)   // both out of range high
            compare(w.startHour, 23, "start clamps to 23")
            compare(w.endHour, 24, "end clamps to 24")
        }
        function test_setHours_clamps_lower_bounds() {
            var w = hEod.item
            w.setHours(-3, 5)    // start below 0
            compare(w.startHour, 0, "start clamps to 0")
            compare(w.endHour, 5, "end unchanged")
        }
        function test_setHours_clamps_end_high() {
            var w = hEod.item
            w.setHours(5, 100)
            compare(w.startHour, 5)
            compare(w.endHour, 24, "end clamps to 24")
        }
    }

    // ── endHour = 24 → next-day 00:00, full-day window ──────────────────────
    TestCase {
        name: "EodFullDay"
        when: windowShown
        function init() { tryVerify(function () { return hEod.ready }, 3000); clear(hEod) }
        function patch(o) { hEod.storeCtl.patchSettings("test-instance", o) }

        function test_full_day_window_is_valid() {
            var w = hEod.item
            patch({ startHour: 0, endHour: 24 })
            verify(w.frac > 0 && w.frac < 1,
                   "a 00:00–24:00 window produces a mid-day frac in (0,1) (got " + w.frac + ")")
            verify(w.remaining !== "Set hours" && w.remaining !== "Done! 🎉",
                   "full-day window shows a live remaining (got '" + w.remaining + "')")
        }
    }

    // ── BUG: out-of-range hours from the config stepper corrupt the window ──
    // The number stepper writes startHour/endHour straight into the store,
    // bypassing setHours()'s clamp; the widget must still refuse to break.
    TestCase {
        name: "EodConfigStepperRange"
        when: windowShown
        function init() { tryVerify(function () { return hEod.ready }, 3000); clear(hEod) }
        function patch(o) { hEod.storeCtl.patchSettings("test-instance", o) }

        function test_start_hour_25_is_clamped_not_stored_raw() {
            var w = hEod.item
            patch({ startHour: 25, endHour: 17 })   // as the stepper would write it
            verify(w.startHour >= 0 && w.startHour <= 23,
                   "a config-set startHour must be clamped to 0..23 (got " + w.startHour + ")")
        }
        function test_start_hour_25_does_not_silently_break_window() {
            var w = hEod.item
            patch({ startHour: 25, endHour: 17 })
            // setHours(25) normalises to tomorrow 01:00, dropping the window behind
            // the end and stranding the widget on 'Set hours' for plausible values.
            verify(w.remaining !== "Set hours",
                   "plausible-looking editor hours must not strand the widget (remaining='" + w.remaining + "')")
        }
        function test_negative_start_hour_is_clamped() {
            var w = hEod.item
            patch({ startHour: -1, endHour: 17 })
            verify(w.startHour >= 0,
                   "a config-set startHour must clamp at 0, not go negative (got " + w.startHour + ")")
        }
        function test_end_hour_100_is_clamped() {
            var w = hEod.item
            patch({ startHour: 9, endHour: 100 })
            verify(w.endHour <= 24,
                   "a config-set endHour must be clamped to <=24 (got " + w.endHour + ")")
        }
    }

    // ── Reactivity: schema keys + Manager control socket ────────────────────
    TestCase {
        name: "EodReactivity"
        when: windowShown
        function init() { tryVerify(function () { return hEod.ready }, 3000); clear(hEod) }
        function patch(o) { hEod.storeCtl.patchSettings("test-instance", o) }
        function set(k, v) { hEod.storeCtl.setSetting("test-instance", k, v) }

        function test_showPercent_honored() {
            var w = hEod.item
            set("showPercent", false); compare(w.showPercent, false, "showPercent off")
            set("showPercent", true);  compare(w.showPercent, true, "showPercent on")
        }
        function test_progressStyle_honored() {
            var w = hEod.item
            set("progressStyle", "ring"); compare(w.progressStyle, "ring")
            set("progressStyle", "bar");  compare(w.progressStyle, "bar")
        }
        function test_startEnd_hours_reactive_via_patch() {
            var w = hEod.item
            patch({ startHour: 8, endHour: 16 })
            compare(w.startHour, 8); compare(w.endHour, 16)
        }
        function test_control_socket_applyExternal_updates_cfg() {
            var w = hEod.item
            var doc = {
                version: 1,
                appearance: { themeMode: "oled", accent: "blue" },
                pages: [ { name: "Pushed", tiles: [ { id: "test-instance", type: "eod" } ] } ],
                settings: { "test-instance": { startHour: 7, endHour: 15, progressStyle: "ring", showPercent: false } }
            }
            var before = hEod.storeCtl.revision
            verify(hEod.storeCtl.applyExternal(JSON.stringify(doc)), "control-socket doc accepted")
            verify(hEod.storeCtl.revision > before, "revision bumped for reactivity")
            compare(w.startHour, 7, "pushed startHour picked up live")
            compare(w.endHour, 15, "pushed endHour picked up live")
            compare(w.progressStyle, "ring", "pushed progressStyle picked up live")
            compare(w.showPercent, false, "pushed showPercent picked up live")
        }
    }

    // ── Rendered display: percent caption, bar vs ring, accent recolour ─────
    TestCase {
        name: "EodDisplay"
        when: windowShown
        function init() {
            tryVerify(function () { return hEod.ready }, 3000)
            clear(hEod)
            hEod.item.accentName = ""
        }
        function patch(o) { hEod.storeCtl.patchSettings("test-instance", o) }

        function test_showPercent_toggles_caption_node() {
            var w = hEod.item
            patch({ startHour: 9, endHour: 17, progressStyle: "bar", showPercent: true })
            verify(visibleTextContains(w, "% of ") !== null, "percent caption visible when showPercent on")
            patch({ showPercent: false })
            verify(visibleTextContains(w, "% of ") === null, "percent caption hidden when showPercent off")
        }

        function test_progressStyle_switches_bar_and_ring() {
            var w = hEod.item
            patch({ startHour: 9, endHour: 17, progressStyle: "bar" })
            verify(visibleRing(w) === null, "no ring in bar mode")
            patch({ progressStyle: "ring" })
            verify(visibleRing(w) !== null, "ring shown in ring mode")
        }

        // The primary time text must honour a per-instance accent in BOTH modes.
        function test_time_text_uses_effAccent_in_bar_mode() {
            var w = hEod.item
            patch({ startHour: 9, endHour: 17, progressStyle: "bar" })
            w.accentName = "pink"
            var t = visibleTextEq(w, w.remaining)
            verify(t !== null, "found the visible remaining text (bar)")
            compare(String(t.color), String(w.effAccent),
                    "bar-mode time text is recoloured by effAccent")
        }
        // BUG (low): ring-mode centre time uses theme.textPrimary, not effAccent.
        function test_time_text_uses_effAccent_in_ring_mode() {
            var w = hEod.item
            patch({ startHour: 9, endHour: 17, progressStyle: "ring" })
            w.accentName = "pink"
            var t = visibleTextEq(w, w.remaining)
            verify(t !== null, "found the visible ring-centre remaining text")
            compare(String(t.color), String(w.effAccent),
                    "ring-mode time text should also honour effAccent")
        }

        // BUG (low): caption renders '9:00' / '24:00'; the editor renders '09:00'.
        function test_caption_hours_match_editor_zero_padding() {
            var w = hEod.item
            patch({ startHour: 9, endHour: 17, progressStyle: "bar", showPercent: true })
            var cap = visibleTextContains(w, "% of ")
            verify(cap !== null, "percent caption present")
            // What the on-device config editor renders for the same startHour:
            cfStore.setSetting("cf-inst", "startHour", 9)
            var editorStart = cfHour.numStr()          // "09:00"
            compare(editorStart, "09:00", "sanity: editor zero-pads the hour")
            verify(cap.text.indexOf(editorStart) >= 0,
                   "caption must format hours like the editor (caption='" + cap.text + "')")
        }
    }

    // ── BUG: long remaining strings overflow the collapsed tile ─────────────
    TestCase {
        name: "EodOverflow"
        when: windowShown
        function init() { tryVerify(function () { return hCollapsed.ready }, 3000); clear(hCollapsed) }
        function patch(o) { hCollapsed.storeCtl.patchSettings("test-instance", o) }

        function test_starts_in_string_fits_collapsed_tile() {
            var w = hCollapsed.item
            var h = new Date().getHours()
            if (h > 21) { skip("cannot place a future start to force a 'Starts in' string"); return }
            patch({ startHour: h + 1, endHour: h + 2 })
            verify(w.remaining.indexOf("Starts in") === 0, "setup produced a 'Starts in' string")
            var t = visibleTextEq(w, w.remaining)
            verify(t !== null, "found the visible remaining text")
            verify(t.paintedWidth <= hCollapsed.width,
                   "remaining text must fit the " + hCollapsed.width + "px tile (painted "
                   + Math.round(t.paintedWidth) + "px for '" + w.remaining + "')")
        }
        function test_set_hours_string_fits_collapsed_tile() {
            var w = hCollapsed.item
            patch({ startHour: 17, endHour: 9 })   // invalid → "Set hours"
            compare(w.remaining, "Set hours")
            var t = visibleTextEq(w, "Set hours")
            verify(t !== null, "found the 'Set hours' text")
            verify(t.paintedWidth <= hCollapsed.width,
                   "'Set hours' must fit the " + hCollapsed.width + "px tile (painted "
                   + Math.round(t.paintedWidth) + "px)")
        }
    }

    // ── Touch targets: Start/End pills ≥44px and fit the expanded tile ──────
    TestCase {
        name: "EodTouchTargets"
        when: windowShown
        function init() { tryVerify(function () { return hEod.ready }, 3000); clear(hEod) }
        function patch(o) { hEod.storeCtl.patchSettings("test-instance", o) }

        function test_four_pills_present_and_tall_enough() {
            var w = hEod.item
            patch({ startHour: 9, endHour: 17 })   // valid window keeps the row meaningful
            var ps = pills(w)
            compare(ps.length, 4, "Start −/+ and End −/+ pills are present")
            for (var i = 0; i < ps.length; i++)
                verify(ps[i].height >= 44,
                       "pill '" + ps[i].label + "' meets the 44px min (got " + ps[i].height + ")")
        }
        function test_pills_fit_within_tile_width() {
            var w = hEod.item
            patch({ startHour: 9, endHour: 17 })
            var ps = pills(w)
            var minX = 1e9, maxX = -1e9
            for (var i = 0; i < ps.length; i++) {
                var p = ps[i].mapToItem(w, 0, 0)
                minX = Math.min(minX, p.x)
                maxX = Math.max(maxX, p.x + ps[i].width)
            }
            verify(maxX - minX <= w.width,
                   "the four pills span <= tile width (span " + Math.round(maxX - minX)
                   + "px vs " + w.width + "px)")
        }
    }

    // ── BUG/limitation: cross-midnight (night-shift) windows ────────────────
    TestCase {
        name: "EodCrossMidnight"
        when: windowShown
        function init() { tryVerify(function () { return hEod.ready }, 3000); clear(hEod) }
        function patch(o) { hEod.storeCtl.patchSettings("test-instance", o) }

        function test_overnight_window_is_representable_or_signposted() {
            var w = hEod.item
            patch({ startHour: 22, endHour: 6 })   // 22:00 → 06:00 overnight shift
            // Either the window works (non-zero frac / real remaining) or the UI
            // communicates something clearer than the generic invalid 'Set hours'.
            verify(w.frac > 0 || w.remaining !== "Set hours",
                   "overnight window must work or be clearly signposted (frac=" + w.frac
                   + " remaining='" + w.remaining + "')")
        }
    }

    // ── DST: documented, not machine-testable without TZ control ─────────────
    TestCase {
        name: "EodDST"
        when: windowShown
        function init() { tryVerify(function () { return hEod.ready }, 3000); clear(hEod) }
        function test_dst_skew_documented() {
            // frac = (n - s)/(e - s) uses absolute ms against wall-clock endpoints,
            // so on a DST transition day the percent is off by up to an hour. This
            // cannot be reproduced deterministically inside qmltest (no TZ override).
            skip("DST-day skew requires a controlled timezone/clock; covered by audit note")
        }
    }

    // ── Shared config schema surface (instantiated directly) ────────────────
    TestCase {
        name: "EodSchema"
        when: windowShown

        function hourFields() {
            var s = schema.schemaFor("eod")
            var out = []
            for (var j = 0; j < s.sections.length; j++)
                for (var k = 0; k < (s.sections[j].fields || []).length; k++)
                    if (s.sections[j].fields[k].type === "hour")
                        out.push(s.sections[j].fields[k])
            return out
        }

        function test_eod_schema_exposes_start_and_end_hour() {
            var hs = hourFields()
            var keys = hs.map(function (f) { return f.key })
            verify(keys.indexOf("startHour") >= 0, "schema exposes startHour")
            verify(keys.indexOf("endHour") >= 0, "schema exposes endHour")
        }
        function test_eod_schema_exposes_display_keys() {
            var s = schema.schemaFor("eod")
            var keys = []
            for (var j = 0; j < s.sections.length; j++)
                for (var k = 0; k < (s.sections[j].fields || []).length; k++)
                    keys.push(s.sections[j].fields[k].key)
            verify(keys.indexOf("progressStyle") >= 0, "schema exposes progressStyle")
            verify(keys.indexOf("showPercent") >= 0, "schema exposes showPercent")
        }
        // BUG (medium): the hour fields omit min/max, so the stepper can drive
        // startHour/endHour out of 0..24 and corrupt the window.
        function test_hour_fields_declare_min_and_max() {
            var hs = hourFields()
            verify(hs.length >= 2, "found both hour fields")
            for (var i = 0; i < hs.length; i++) {
                verify(hs[i].min !== undefined,
                       "hour field '" + hs[i].key + "' must declare a min to bound the stepper")
                verify(hs[i].max !== undefined,
                       "hour field '" + hs[i].key + "' must declare a max to bound the stepper")
            }
        }
    }

    // ── ConfigField hour rendering (shared component, instantiated directly) ─
    TestCase {
        name: "EodConfigField"
        when: windowShown

        function test_hour_numStr_zero_pads_single_digit() {
            cfStore.setSetting("cf-inst", "startHour", 9)
            compare(cfHour.numStr(), "09:00", "single-digit hour is zero-padded")
        }
        function test_hour_numStr_two_digit() {
            cfStore.setSetting("cf-inst", "startHour", 17)
            compare(cfHour.numStr(), "17:00", "two-digit hour is unpadded")
        }
    }
}
