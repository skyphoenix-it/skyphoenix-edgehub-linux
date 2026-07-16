import QtQuick
import QtTest
import "../../ui/qml" as App

// Comprehensive coverage for the Memory (RAM) metric widget
// (ui/qml/widgets/RamWidget.qml) plus its shared config schema.
//
// Drives config through the DashboardStore the widget is wired to, and asserts
// on the widget's own derived state (v/unit/showHistory/hist/col()/gb()/effAccent)
// as well as the rendered MetricGauge (centre "big" text, "sub" line, ring).
//
// Some assertions target the audited bugs and are EXPECTED to fail against the
// current code — those are marked in the report as likely-real-bug.
Item {
    id: root
    width: 460; height: 640

    // Main harness — expanded tile; metrics are driven directly per-test.
    WidgetHarness { id: hRam;   width: 420; height: 520; widgetFile: "RamWidget.qml"; expanded: true }
    // Compact half-width portrait tile (non-expanded) for the gb-mode overflow test.
    WidgetHarness { id: hSmall; width: 340; height: 560; widgetFile: "RamWidget.qml"; expanded: false }
    // A harness that is NEVER fed metrics → the pre-first-tick state.
    WidgetHarness { id: hFresh; width: 340; height: 560; widgetFile: "RamWidget.qml"; expanded: false }

    // Shared config schema (instantiated directly like the store/schema tests).
    App.WidgetConfigSchema { id: schema }

    // ── generic object-tree helpers ────────────────────────────────────────
    function walk(node, pred, acc) {
        if (!node) return acc
        var kids = node.children
        if (kids) {
            for (var i = 0; i < kids.length; i++) {
                var c = kids[i]
                if (c && pred(c)) acc.push(c)
                walk(c, pred, acc)
            }
        }
        return acc
    }
    function findAll(rootObj, pred) { return walk(rootObj, pred, []) }
    function findOne(rootObj, pred) { var a = walk(rootObj, pred, []); return a.length ? a[0] : null }

    function isGauge(o) {
        return typeof o.big === "string" && typeof o.sub === "string" && typeof o.history === "object"
    }
    function isRing(o) {
        return typeof o.thickness === "number" && typeof o.value === "number"
               && o.progressColor !== undefined && o.trackColor !== undefined
    }
    function isText(o) { return typeof o.text === "string" && o.font !== undefined }
    function isMouseArea(o) {
        return typeof o.pressed === "boolean" && typeof o.acceptedButtons !== "undefined"
               && typeof o.hoverEnabled === "boolean"
    }

    function gaugeOf(w) { return findOne(w, isGauge) }

    function clearCfg(h) {
        var s = h.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        h.storeCtl._touchSettings()
    }

    // ── Config: schema shape ───────────────────────────────────────────────
    TestCase {
        name: "RamConfigSchema"
        when: windowShown

        function test_ram_schema_exposes_expected_fields() {
            var s = schema.schemaFor("ram")
            verify(s && s.sections && s.sections.length > 0, "ram has a schema")
            var keys = {}
            var types = {}
            for (var j = 0; j < s.sections.length; j++)
                for (var k = 0; k < (s.sections[j].fields || []).length; k++) {
                    var f = s.sections[j].fields[k]
                    keys[f.key] = true; types[f.key] = f.type
                }
            verify(keys["unit"], "exposes 'unit'")
            verify(keys["showHistory"], "exposes 'showHistory'")
            verify(keys["title"], "exposes custom title")
            verify(keys["accent"], "exposes per-widget accent")
            verify(keys["cardBackdrop"], "exposes per-widget backdrop")
            compare(types["unit"], "segmented", "unit is a segmented control")
            compare(types["showHistory"], "toggle", "showHistory is a toggle")
        }

        function test_unit_options_are_percent_and_gb() {
            var s = schema.schemaFor("ram")
            var unitField = null
            for (var j = 0; j < s.sections.length; j++)
                for (var k = 0; k < (s.sections[j].fields || []).length; k++)
                    if (s.sections[j].fields[k].key === "unit") unitField = s.sections[j].fields[k]
            verify(unitField, "found unit field")
            compare(unitField.dflt, "percent", "defaults to percent")
            var vals = unitField.options.map(function (o) { return o.value })
            compare(vals.sort(), ["gb", "percent"], "offers percent + gb")
        }
    }

    // ── Derived logic: col()/gb()/v/defaults ───────────────────────────────
    TestCase {
        name: "RamDerivedLogic"
        when: windowShown
        function init() { tryVerify(function () { return hRam.ready }, 3000); clearCfg(hRam) }

        function test_config_defaults() {
            var w = hRam.item
            compare(w.unit, "percent", "unit defaults to percent")
            compare(w.showHistory, true, "showHistory defaults to true")
        }

        function test_v_reads_ram_usage_percent() {
            var w = hRam.item
            w.metrics = { ram_usage_percent: 63 }
            compare(w.v, 63, "v mirrors ram_usage_percent")
            w.metrics = {}
            compare(w.v, 0, "missing percent → 0")
        }

        function test_col_thresholds() {
            var w = hRam.item
            var th = hRam.theme
            compare(String(w.col(50)), String(w.effAccent), "50% → accent")
            compare(String(w.col(75)), String(w.effAccent), "75% (boundary, not >75) → accent")
            compare(String(w.col(75.5)), String(th.warning), "just above 75% → warning")
            compare(String(w.col(90)), String(th.warning), "90% (boundary, not >90) → warning")
            compare(String(w.col(90.5)), String(th.error), "just above 90% → error")
            compare(String(w.col(99)), String(th.error), "99% → error")
        }

        function test_effAccent_recolours_ring_and_number() {
            var w = hRam.item
            var th = hRam.theme
            w.accentName = "green"
            verify(Qt.colorEqual(w.effAccent, th.accentPresets["green"].a),
                   "effAccent resolves the preset colour")
            compare(String(w.col(50)), String(w.effAccent),
                    "col() below thresholds returns effAccent (recolours ring/number)")
            w.accentName = ""
        }

        function test_gb_uses_gibibyte_divisor() {
            var w = hRam.item
            // 1 GiB exactly → "1.0"
            compare(w.gb(1073741824), "1.0", "1 GiB → 1.0")
        }

        function test_gb_labelled_gb_matches_decimal_hardware_size() {
            // Corrected: memory is measured in binary units — a "32 GB" module is
            // 32 GiB (34359738368 bytes, exactly what ram_total_bytes reports), so
            // the 2^30 divisor is right and a 32 GiB stick reads 32.0 GB. The old
            // 32e9-byte (decimal) premise contradicted test_gb_uses_gibibyte_divisor.
            var w = hRam.item
            compare(w.gb(34359738368), "32.0",
                    "a 32 GiB stick should read 32.0 GB")
        }
    }

    // ── MetricGauge rendering: centre reading honours unit, reacts live ─────
    TestCase {
        name: "RamGaugeReading"
        when: windowShown
        function init() { tryVerify(function () { return hRam.ready }, 3000); clearCfg(hRam) }

        function feed(w) {
            w.metrics = { ram_usage_percent: 63,
                          ram_used_bytes: 23200000000,
                          ram_total_bytes: 34359738368 }
        }

        function test_percent_mode_centre_is_percent() {
            var w = hRam.item; feed(w)
            var g = gaugeOf(w)
            verify(g, "found the gauge")
            hRam.storeCtl.setSetting("test-instance", "unit", "percent")
            compare(g.big, "63%", "percent mode shows NN% in the centre")
        }

        function test_gb_mode_centre_is_used_gb() {
            var w = hRam.item; feed(w)
            var g = gaugeOf(w)
            hRam.storeCtl.setSetting("test-instance", "unit", "gb")
            compare(g.big, w.gb(23200000000) + " GB", "gb mode shows used-GB in the centre")
        }

        function test_unit_toggles_live_on_revision_bump() {
            var w = hRam.item; feed(w)
            var g = gaugeOf(w)
            hRam.storeCtl.setSetting("test-instance", "unit", "percent")
            compare(g.big, "63%", "starts as percent")
            hRam.storeCtl.setSetting("test-instance", "unit", "gb")
            verify(g.big.indexOf("GB") >= 0, "flips to GB live (store.revision bump)")
            hRam.storeCtl.setSetting("test-instance", "unit", "percent")
            compare(g.big, "63%", "flips back to percent live")
        }

        function test_ring_value_clamps_above_100() {
            // AUDIT testCase: ram_usage_percent > 100 clamps the ring to full.
            var w = hRam.item
            w.metrics = { ram_usage_percent: 150 }
            var g = gaugeOf(w)
            compare(g.value, 1, "gauge ring value clamps to 1.0 (no overflow)")
            var ring = findOne(g, isRing)
            verify(ring, "found ring")
            verify(ring.value <= 1.0, "ring stays clamped to full")
        }

        function test_gb_mode_does_not_print_used_twice() {
            // AUDIT (low): in gb mode the used figure shows in BOTH the centre
            // ("21.6 GB") and the sub-line ("21.6 / 32.0 GB").
            var w = hRam.item; feed(w)
            var g = gaugeOf(w)
            hRam.storeCtl.setSetting("test-instance", "unit", "gb")
            var usedStr = w.gb(23200000000)               // e.g. "21.6"
            verify(g.big.indexOf(usedStr) >= 0, "centre prints the used figure")
            verify(g.sub.indexOf(usedStr) < 0,
                   "sub-line should NOT repeat the used figure already shown in the centre")
        }
    }

    // ── showHistory config toggles the sparkline data live ──────────────────
    TestCase {
        name: "RamHistoryToggle"
        when: windowShown
        function init() { tryVerify(function () { return hRam.ready }, 3000); clearCfg(hRam) }

        function test_showHistory_gates_the_sparkline() {
            var w = hRam.item
            w.hist = []
            // Seed a few real samples so the sparkline has data.
            for (var i = 1; i <= 4; i++) w.metrics = { ram_usage_percent: 40 + i }
            var g = gaugeOf(w)
            verify(w.hist.length > 1, "history accumulated (" + w.hist.length + ")")

            hRam.storeCtl.setSetting("test-instance", "showHistory", true)
            compare(g.history.length, w.hist.length, "showHistory=true → gauge gets the samples")

            hRam.storeCtl.setSetting("test-instance", "showHistory", false)
            compare(g.history.length, 0, "showHistory=false → gauge history emptied live")

            hRam.storeCtl.setSetting("test-instance", "showHistory", true)
            compare(g.history.length, w.hist.length, "back on live")
        }
    }

    // ── History buffer behaviour (append / FIFO cap / guards) ───────────────
    TestCase {
        name: "RamHistoryBuffer"
        when: windowShown
        function init() { tryVerify(function () { return hRam.ready }, 3000); clearCfg(hRam) }

        // NOTE: onMetricsChanged reads w.v (a binding on metrics) which settles one
        // tick after the handler fires, so history lags the feed by exactly one
        // sample. These tests feed a value twice (or assert order-only) to stay
        // robust to that ordering rather than depending on it.
        function test_appends_a_sample_per_tick() {
            var w = hRam.item
            w.hist = []
            w.metrics = { ram_usage_percent: 63 }   // records the settling of the prior v
            w.metrics = { ram_usage_percent: 63 }   // v has settled to 63 → records 0.63
            compare(w.hist.length, 2, "one sample appended per metrics tick")
            fuzzyCompare(w.hist[w.hist.length - 1], 0.63, 1e-9, "sample is percent/100")
        }

        function test_fifo_cap_at_48() {
            var w = hRam.item
            w.hist = []
            for (var i = 1; i <= 55; i++) w.metrics = { ram_usage_percent: i }
            compare(w.hist.length, 48, "buffer capped at 48 samples (FIFO)")
            verify(w.hist[0] < w.hist[47], "oldest samples were dropped, newest retained")
            for (var j = 0; j < w.hist.length; j++)
                verify(w.hist[j] >= 0 && w.hist[j] <= 1, "every sample is normalised 0..1")
        }

        function test_partial_frame_should_not_seed_a_false_zero() {
            // AUDIT (low): onMetricsChanged has no availability guard, so a metrics
            // frame lacking ram_usage_percent pushes (undefined||0)/100 = 0 and the
            // sparkline dips to the floor for a dip that never happened.
            var w = hRam.item
            w.hist = []
            w.metrics = { ram_usage_percent: 63, ram_used_bytes: 2e10, ram_total_bytes: 3e10 }
            w.metrics = { ram_usage_percent: 63, ram_used_bytes: 2e10, ram_total_bytes: 3e10 }
            fuzzyCompare(w.hist[w.hist.length - 1], 0.63, 1e-9, "real samples recorded")
            // Two partial frames (total present, usage_percent missing): a widget that
            // guarded on availability (as GpuWidget does) would append nothing.
            w.metrics = { ram_total_bytes: 3e10 }
            w.metrics = { ram_total_bytes: 3e10 }
            verify(w.hist[w.hist.length - 1] !== 0,
                   "a frame with no ram_usage_percent must not append a spurious 0")
        }
    }

    // ── No-data / pre-first-tick state ──────────────────────────────────────
    TestCase {
        name: "RamNoData"
        when: windowShown
        function init() { tryVerify(function () { return hFresh.ready }, 3000) }

        function test_pre_first_tick_shows_neutral_placeholder_not_zero() {
            // AUDIT (low): before the first real metrics frame (metrics == {}), the
            // tile confidently prints "0.0 / 0.0 GB" / "0%" instead of a placeholder.
            var w = hFresh.item
            var g = gaugeOf(w)
            verify(g, "found gauge")
            verify(g.sub !== "0.0 / 0.0 GB",
                   "with no metrics yet the sub-line should be a neutral placeholder, not 0.0 / 0.0 GB")
        }

        function test_zero_total_is_graceful() {
            // AUDIT (low): ram_total_bytes==0 (read failure) still renders "0.0 / 0.0 GB".
            var w = hFresh.item
            w.metrics = { ram_used_bytes: 0, ram_total_bytes: 0, ram_usage_percent: 0 }
            var g = gaugeOf(w)
            verify(g.sub !== "0.0 / 0.0 GB",
                   "a 0-byte total should read as no-data, not a real 0-byte machine")
        }
    }

    // ── gb-mode centre text must fit inside the ring on a compact tile ──────
    TestCase {
        name: "RamGbOverflow"
        when: windowShown
        function init() { tryVerify(function () { return hSmall.ready }, 3000); clearCfg(hSmall) }

        function test_gb_centre_text_fits_ring_interior() {
            // AUDIT (medium): the long "NN.N GB" centre string has no width/elide
            // constraint, so on a half-width portrait tile it overruns the ring.
            var w = hSmall.item
            hSmall.storeCtl.setSetting("test-instance", "unit", "gb")
            w.metrics = { ram_usage_percent: 68,
                          ram_used_bytes: 23200000000,   // → "21.6 GB"
                          ram_total_bytes: 34359738368 }
            var g = gaugeOf(w)
            var ring = findOne(g, isRing)
            verify(ring && ring.width > 0, "ring laid out (w=" + (ring ? ring.width : -1) + ")")
            tryVerify(function () { return ring.width > 0 }, 2000)

            var bigText = findOne(g, function (o) { return isText(o) && o.text === g.big })
            verify(bigText, "found the centre text \"" + g.big + "\"")

            var interior = ring.width - 2 * ring.thickness
            verify(bigText.width <= interior,
                   "centre text (" + bigText.width.toFixed(0) + "px) must fit inside the ring interior ("
                   + interior.toFixed(0) + "px)")
        }
    }

    // ── Per-sizeClass structure (W1 wave 2a) ────────────────────────────────
    // Fixed-size hosts at real projected cell footprints.
    Item { width: 344; height: 416
        WidgetHarness { id: hMicro; anchors.fill: parent; widgetFile: "RamWidget.qml"; expanded: false } }
    Item { id: wideWrap; width: 696; height: 416
        WidgetHarness { id: hWide; anchors.fill: parent; widgetFile: "RamWidget.qml"; expanded: false } }
    Item { width: 344; height: 840
        WidgetHarness { id: hTall; anchors.fill: parent; widgetFile: "RamWidget.qml"; expanded: false } }

    TestCase {
        name: "RamSizes"
        when: windowShown
        readonly property var m: ({ ram_usage_percent: 68,
                                    ram_used_bytes: 23218000000,
                                    ram_total_bytes: 34359738368 })

        // 0.5x0.5 — headerless bare ring: only the one number.
        function test_micro_is_bare_ring() {
            tryVerify(function () { return hMicro.ready }, 3000)
            var w = hMicro.item
            w.sizeClass = "compact"
            hMicro.metricsJson = JSON.stringify(m)
            compare(w.micro, true, "a 344x416 compact box is the micro tile")
            compare(w.showHeader, false, "micro hides the header")
            var g = gaugeOf(w)
            compare(g.showSpark, false, "micro reserves no sparkline slot")
            compare(g.sub, "", "micro drops the used/total line — the number IS the tile")
            verify(g.bigMax > 60, "the headerless number may fill its box")
        }

        // baseline 1x1 keeps the used/total sub-line and the sparkline strip
        // (asserted throughout the cases above); wide goes side-by-side.
        function test_wide_puts_spark_beside_ring_in_both_orientations() {
            tryVerify(function () { return hWide.ready }, 3000)
            var w = hWide.item
            w.sizeClass = "wide"
            hWide.metricsJson = JSON.stringify(m)
            var g = gaugeOf(w)
            compare(g.horizontal, true, "wide lays ring and sparkline side by side")
            compare(g.showSpark, true, "the sparkline is the point of going wide")
            verify(g.sub.length > 0, "wide keeps the used/total context inside the ring")
            wideWrap.width = 840; wideWrap.height = 344
            compare(g.horizontal, true, "the landscape projection stays side-by-side")
            wideWrap.width = 696; wideWrap.height = 416
        }

        // tall — sparkline earns the height below a squared ring.
        function test_tall_hands_spark_the_height() {
            tryVerify(function () { return hTall.ready }, 3000)
            var w = hTall.item
            w.sizeClass = "tall"
            hTall.metricsJson = JSON.stringify(m)
            var g = gaugeOf(w)
            compare(g.sparkFills, true, "tall hands the sparkline all the height below the ring")
            verify(g.sub.length > 0, "tall keeps the used/total context")
            w.sizeClass = "full"
            compare(g.sparkFills, false, "the overlay keeps the classic expanded gauge")
            compare(w.micro, false, "full is never micro")
        }
    }

    // ── The gauge must not swallow taps meant to expand the tile ────────────
    TestCase {
        name: "RamTapPassthrough"
        when: windowShown
        function init() { tryVerify(function () { return hRam.ready }, 3000) }

        function test_gauge_has_no_tap_swallowing_mousearea() {
            // AUDIT testCase: tapping anywhere on the tile should expand it; the
            // MetricGauge must not contain a MouseArea that eats the chrome tap.
            var g = gaugeOf(hRam.item)
            var eaters = findAll(g, function (o) {
                return isMouseArea(o) && (o.acceptedButtons & Qt.LeftButton) && o.enabled
            })
            compare(eaters.length, 0, "no left-button MouseArea inside the gauge")
        }
    }
}
