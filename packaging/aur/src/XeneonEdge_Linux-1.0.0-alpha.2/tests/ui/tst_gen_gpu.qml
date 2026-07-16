import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Wg

// Comprehensive coverage for the GPU widget (ui/qml/widgets/GpuWidget.qml).
//
// Exercises: availability (N/A) logic, percent reading + ring value + clamping,
// temperature header status, ring-colour escalation on both the load path and
// the thermal path, config defaults + live reactivity (showTemp / showHistory /
// warnTemp), history accumulation / cap / pause, the shared MetricGauge gauge,
// the "gpu" config schema, and the universal appearance keys (accent / title).
//
// Assertions that encode the *intended* behaviour but fail against the current
// code are deliberate — they pin real bugs called out in the audit:
//   • the header amber threshold (warnTemp-17) and the ring amber threshold
//     (warnTemp-12) disagree by 5°C, so a warning-coloured number can sit inside
//     a calm ring;
//   • turning off "Show temperature" ALSO kills all thermal ring colouring, so a
//     110°C GPU renders a calm accent ring;
//   • `active` is declared + bound by the host but never honoured, so a paused
//     (expanded / off-page) instance keeps sampling history.
Item {
    id: root
    width: 520; height: 640

    // A theme in scope so the directly-instantiated MetricGauge resolves `theme`.
    property alias theme: _theme
    App.Theme { id: _theme }

    App.WidgetConfigSchema { id: sc }

    WidgetHarness {
        id: h
        anchors.fill: parent
        widgetFile: "GpuWidget.qml"
        expanded: true
    }

    // Directly-instantiated shared gauge for the store/gauge shared-area tests.
    Wg.MetricGauge { id: gauge; width: 200; height: 200; visible: false }

    // ── Tree helpers ─────────────────────────────────────────────────────────
    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids)
            for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
    }
    // The one MetricGauge inside the widget (unique: it carries history+ok+big).
    function findGauge() {
        var found = null
        eachItem(h.item, function (n) {
            if (found) return
            if (n.hasOwnProperty("history") && n.hasOwnProperty("ok") && n.hasOwnProperty("big"))
                found = n
        })
        return found
    }
    function findRing(node) {
        var found = null
        eachItem(node, function (n) {
            if (found) return
            if (n.hasOwnProperty("thickness") && n.hasOwnProperty("progressColor"))
                found = n
        })
        return found
    }
    function findText(str) {
        var found = null
        eachItem(h.item, function (n) {
            if (found) return
            if (n.text !== undefined && typeof n.text === "string" && n.text === str)
                found = n
        })
        return found
    }
    // Feed the metrics JSON (omit an arg entirely to leave that key absent).
    // Derived properties (avail/v/temp/status/col) update synchronously on read.
    // The onMetricsChanged accumulator, however, lags exactly one feed: because
    // the harness wires item.metrics = Qt.binding(() => harness.metrics) (a binding
    // over a `var`), the sample for feed(X) is committed to `hist` on the FOLLOWING
    // feed. History tests therefore end with flush() to commit the last real sample.
    function feed(usage, temp) {
        var m = {}
        if (usage !== undefined) m.gpu_usage_percent = usage
        if (temp !== undefined) m.gpu_temp_celsius = temp
        h.metricsJson = JSON.stringify(m)
    }
    // Commit the last real sample. An unavailable feed triggers the (lagged)
    // accumulator for the previous available tick but adds nothing of its own.
    function flush() { h.metricsJson = "{}" }
    function fieldsOf(type) {
        var s = sc.schemaFor(type); var out = {}
        for (var j = 0; j < s.sections.length; j++)
            for (var k = 0; k < (s.sections[j].fields || []).length; k++) {
                var f = s.sections[j].fields[k]
                if (f.key) out[f.key] = f
            }
        return out
    }
    function reset() {
        var s = h.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        h.storeCtl._touchSettings()
        h.metricsJson = "{}"
        h.expanded = true
        h.active = true
        h.item.hist = []
    }

    // ── Config schema (shared area) ──────────────────────────────────────────
    TestCase {
        name: "GpuSchema"
        when: windowShown

        function test_gpu_schema_display_fields() {
            var f = fieldsOf("gpu")
            verify(f.showTemp !== undefined, "gpu exposes showTemp")
            compare(f.showTemp.type, "toggle")
            compare(f.showTemp.dflt, true, "showTemp defaults on")
            verify(f.showHistory !== undefined, "gpu exposes showHistory")
            compare(f.showHistory.dflt, true, "showHistory defaults on")
            verify(f.warnTemp !== undefined, "gpu exposes warnTemp")
            compare(f.warnTemp.type, "slider")
            compare(f.warnTemp.dflt, 90, "warnTemp default is 90")
            compare(f.warnTemp.min, 60)
            compare(f.warnTemp.max, 110, "GPU warn range goes to 110°C")
        }
        function test_gpu_schema_has_title_and_appearance() {
            var f = fieldsOf("gpu")
            verify(f.title !== undefined, "custom title field present")
            verify(f.accent !== undefined, "per-widget accent present")
            verify(f.cardBackdrop !== undefined, "per-widget backdrop present")
        }
    }

    // ── Shared MetricGauge (store/gauge shared area) ─────────────────────────
    TestCase {
        name: "GpuGaugeShared"
        when: windowShown

        function test_ring_clamps_value_to_unit_interval() {
            gauge.ok = true
            gauge.value = 1.5
            var ring = findRing(gauge)
            verify(ring !== null, "found the RingProgress")
            compare(ring.value, 1, "ring clamps an over-100% value to 1.0")
            gauge.value = -0.4
            compare(ring.value, 0, "ring clamps a negative value to 0")
        }
        function test_not_ok_dims_ring_to_zero() {
            var ring = findRing(gauge)
            gauge.value = 0.8
            gauge.ok = false
            compare(ring.value, 0, "an unavailable gauge draws an empty (0) ring")
            gauge.ok = true
        }
    }

    // ── Availability / N/A ───────────────────────────────────────────────────
    TestCase {
        name: "GpuAvailability"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); reset() }

        function test_na_when_key_absent() {
            var w = h.item
            feed()                              // no gpu keys at all
            compare(w.avail, false, "no usage key → unavailable")
            var g = findGauge()
            compare(g.ok, false, "gauge dimmed")
            compare(g.big, "N/A", "gauge reads N/A")
        }
        function test_na_when_null() {
            var w = h.item
            feed(null)
            compare(w.avail, false, "null usage → unavailable")
        }
        function test_na_when_negative() {
            var w = h.item
            feed(-1)
            compare(w.avail, false, "negative usage → unavailable")
            compare(findGauge().big, "N/A")
        }
        function test_available_shows_percent() {
            var w = h.item
            feed(42)
            compare(w.avail, true, "0..100 usage → available")
            compare(w.v, 42, "reads gpu_usage_percent")
            var g = findGauge()
            compare(g.ok, true, "gauge live")
            compare(g.big, "42%", "gauge shows the percent")
            compare(g.value, 0.42, "ring fills proportionally")
        }
        function test_zero_is_available() {
            var w = h.item
            feed(0)
            compare(w.avail, true, "0% is a valid reading, not N/A")
            compare(findGauge().big, "0%")
        }
        function test_ring_clamps_over_100() {
            var w = h.item
            feed(150)
            compare(w.avail, true)
            compare(findGauge().value, 1, "ring value clamps to 1.0 above 100%")
            compare(findGauge().big, "150%", "the number itself is not clamped")
        }
    }

    // ── Temperature header status ────────────────────────────────────────────
    TestCase {
        name: "GpuTemperatureStatus"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); reset() }

        function test_status_shows_temp_when_enabled() {
            var w = h.item
            feed(30, 65)
            compare(w.showTemp, true, "showTemp defaults on")
            compare(w.status, "65°C", "header shows the temperature")
        }
        function test_status_hidden_when_showTemp_off() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "showTemp", false)
            feed(30, 65)
            compare(w.status, "", "showTemp off hides the header temperature")
        }
        function test_status_hidden_when_temp_zero() {
            var w = h.item
            feed(30, 0)
            // temp stays 0 (only <0 is normalised to -1), but status gates on temp>0.
            compare(w.temp, 0, "0°C passes through as 0")
            compare(w.status, "", "no temperature shown at/below 0")
        }
        function test_status_hidden_when_temp_negative() {
            var w = h.item
            feed(30, -5)
            compare(w.status, "", "negative temperature hidden")
        }
        function test_status_hidden_when_temp_null() {
            var w = h.item
            feed(30, null)
            compare(w.temp, -1)
            compare(w.status, "", "null temperature hidden")
        }
        function test_status_colour_thresholds() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "warnTemp", 90)
            feed(30, 95)
            compare(String(w.statusColor), String(root.theme.error), "above warnTemp → red")
            feed(30, 80)   // 80 > 90-17=73 → amber
            compare(String(w.statusColor), String(root.theme.warning), "above warnTemp-17 → amber")
            feed(30, 60)   // 60 < 73 → calm
            compare(String(w.statusColor), String(root.theme.textSecondary), "well below → calm")
        }
    }

    // ── Ring colour escalation ───────────────────────────────────────────────
    TestCase {
        name: "GpuRingColour"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); reset() }

        // Load path (no/low temperature so the thermal branch is inert).
        function test_load_calm_below_75() {
            var w = h.item
            feed(50)                       // no temp key
            compare(String(w.col(w.v)), String(w.effAccent), "comfortable load → accent ring")
        }
        function test_load_amber_above_75() {
            var w = h.item
            feed(80)
            compare(String(w.col(w.v)), String(root.theme.warning), "load > 75% → amber ring")
        }
        function test_load_red_above_92() {
            var w = h.item
            feed(95)
            compare(String(w.col(w.v)), String(root.theme.error), "load > 92% → red ring")
        }

        // Thermal path (showTemp on) escalates the whole ring.
        function test_temp_red_above_warnTemp() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "warnTemp", 90)
            feed(20, 95)
            compare(String(w.col(w.v)), String(root.theme.error), "temp > warnTemp → red ring")
        }
        function test_temp_amber_above_warnTemp_minus_12() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "warnTemp", 90)
            feed(20, 79)                   // 79 > 90-12=78
            compare(String(w.col(w.v)), String(root.theme.warning), "temp > warnTemp-12 → amber ring")
        }
        function test_temp_calm_below_bands() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "warnTemp", 90)
            feed(20, 70)                   // 70 < 78 and load 20 < 75
            compare(String(w.col(w.v)), String(w.effAccent), "cool + light load → accent ring")
        }
        function test_gauge_colour_matches_col() {
            var w = h.item
            feed(95)
            compare(String(findGauge().color), String(w.col(w.v)), "gauge paints with col(v)")
        }
    }

    // ── Config defaults + reactivity ─────────────────────────────────────────
    TestCase {
        name: "GpuConfig"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); reset() }

        function test_defaults_when_settings_empty() {
            var w = h.item
            compare(w.showTemp, true, "showTemp defaults true")
            compare(w.showHistory, true, "showHistory defaults true")
            compare(w.warnTemp, 90, "warnTemp defaults 90")
        }
        function test_defaults_when_store_null() {
            var w = h.item
            var saved = w.store
            w.store = null
            compare(w.showTemp, true, "null store → showTemp default")
            compare(w.showHistory, true, "null store → showHistory default")
            compare(w.warnTemp, 90, "null store → warnTemp default")
            w.store = saved                 // restore harness wiring
        }
        function test_showTemp_reactive() {
            var w = h.item
            feed(30, 65)
            verify(w.status.indexOf("65") >= 0, "temp shown when on")
            h.storeCtl.setSetting("test-instance", "showTemp", false)
            compare(w.status, "", "toggling showTemp off updates live")
            h.storeCtl.setSetting("test-instance", "showTemp", true)
            verify(w.status.indexOf("65") >= 0, "and back on live")
        }
        function test_warnTemp_reactive() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "warnTemp", 100)
            feed(20, 95)                    // 95 < 100 → not red
            verify(String(w.col(w.v)) !== String(root.theme.error), "below new threshold: not red")
            h.storeCtl.setSetting("test-instance", "warnTemp", 90)  // 95 > 90 → red, live
            compare(String(w.col(w.v)), String(root.theme.error), "revision bump re-reads warnTemp")
        }
        function test_showHistory_reactive() {
            var w = h.item
            compare(w.showHistory, true)
            h.storeCtl.patchSettings("test-instance", { showHistory: false })
            compare(w.showHistory, false, "patchSettings bump re-reads showHistory")
        }
    }

    // ── History accumulation ─────────────────────────────────────────────────
    TestCase {
        name: "GpuHistory"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); reset() }

        function test_history_accumulates() {
            var w = h.item
            feed(10); feed(20); feed(30); flush()
            compare(w.hist.length, 3, "one sample per available tick")
            compare(w.hist[0], 0.10, "samples stored as 0..1 fractions")
            compare(w.hist[2], 0.30)
        }
        function test_history_caps_at_48() {
            var w = h.item
            for (var i = 1; i <= 60; i++) feed(i)
            flush()
            compare(w.hist.length, 48, "history buffer caps at 48 samples")
            // 60 samples pushed; oldest 12 dropped; window is 13..60.
            compare(w.hist[0], 0.13, "oldest retained sample is the 13th push")
            compare(w.hist[w.hist.length - 1], 0.60, "newest is the last push")
        }
        function test_no_sample_when_unavailable() {
            var w = h.item
            feed(40); flush()
            compare(w.hist.length, 1, "one available tick → one sample")
            feed(null); flush()             // GPU drops out — no sample
            compare(w.hist.length, 1, "no history pushed on an unavailable tick")
            feed(); flush()                 // key absent — still nothing
            compare(w.hist.length, 1)
        }
        function test_showHistory_off_still_accumulates() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "showHistory", false)
            feed(10); feed(20); flush()
            compare(w.hist.length, 2, "samples keep accumulating even when hidden")
            compare(findGauge().history.length, 0, "but the sparkline is fed an empty history")
        }

        // BUG (audit, low): `active` is declared and bound by the host to pause
        // sampling while expanded / off-page, but onMetricsChanged never checks it.
        // Intended: an inactive instance stops accumulating.
        function test_inactive_instance_pauses_sampling() {
            var w = h.item
            h.active = false
            feed(33); feed(44); flush()
            compare(w.hist.length, 0,
                    "an inactive (expanded/off-page) instance should not sample history")
        }
    }

    // ── Universal appearance keys ────────────────────────────────────────────
    TestCase {
        name: "GpuAppearance"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); reset() }

        function test_default_accent_is_gaming_category() {
            var w = h.item
            verify(Qt.colorEqual(w.effAccent, root.theme.catGaming),
                   "with no override, effAccent is the Gaming category colour")
        }
        function test_default_header_is_gpu() {
            var w = h.item
            compare(w.titleOverride, "", "no override by default")
            verify(findText("GPU") !== null, "header renders the default GPU title")
        }
        function test_accent_recolours_effAccent_and_ring() {
            var w = h.item
            // Wire the per-instance accent exactly as Dashboard.injectWidget does.
            w.accentName = Qt.binding(function () {
                h.storeCtl.revision; var s = h.storeCtl.settingsFor("test-instance")
                return (s && s.accent) ? s.accent : ""
            })
            h.storeCtl.setSetting("test-instance", "accent", "red")
            verify(Qt.colorEqual(w.effAccent, root.theme.accentPresets["red"].a),
                   "accent preset recolours effAccent")
            feed(50)   // comfortable load → ring uses effAccent
            compare(String(w.col(w.v)), String(w.effAccent),
                    "comfortable-load ring follows the per-widget accent")
        }
        function test_title_override_honored_in_header() {
            var w = h.item
            w.titleOverride = Qt.binding(function () {
                h.storeCtl.revision; var s = h.storeCtl.settingsFor("test-instance")
                return (s && s.title) ? s.title : ""
            })
            h.storeCtl.setSetting("test-instance", "title", "RTX 4090")
            compare(w.titleOverride, "RTX 4090", "custom title flows from the 'title' key")
            verify(findText("RTX 4090") !== null, "header renders the custom title")
        }
    }

    // ── Deliberate bug pins (intended behaviour that current code violates) ──
    TestCase {
        name: "GpuBugs"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); reset() }

        // BUG (audit, low): header amber threshold is warnTemp-17 but the ring's
        // is warnTemp-12 — a 5°C band where the number is amber inside a calm ring.
        function test_header_and_ring_amber_thresholds_agree() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "warnTemp", 90)
            feed(20, 75)   // 75 > 73 (header amber) but 75 < 78 (ring still calm)
            compare(String(w.statusColor), String(root.theme.warning),
                    "header text is amber at 75°C")
            compare(String(w.col(w.v)), String(root.theme.warning),
                    "the ring must agree with the header's amber threshold")
        }

        // BUG (audit, low): showTemp=false disables ALL thermal ring colouring, so
        // an overheating GPU renders a calm accent ring with no red anywhere.
        function test_thermal_warning_survives_showTemp_off() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { showTemp: false, warnTemp: 90 })
            feed(20, 110)  // dangerously hot, but light load
            compare(String(w.col(w.v)), String(root.theme.error),
                    "a 110°C GPU must still show a red ring even with the temp text hidden")
        }
    }
}
