import QtQuick
import QtTest

// COVERS: schema:unit

// Comprehensive coverage for the Network widget (ui/qml/widgets/NetWidget.qml).
//
// Exercises: rate reading from the Rust metrics JSON, byte/bit formatting and
// unit boundaries, config reactivity (unit / showHistory), defaults, session
// peaks + history accumulation, the history cap, the (dead) `active` gate, the
// universal appearance keys (accent / title / backdrop) on the shared
// WidgetChrome, and robustness against empty/missing metrics.
//
// Assertions that encode the *intended* behaviour but fail against the current
// code are deliberate — they pin real bugs called out in the audit:
//   • fmt(1023.7) rounds up to "1024 B/s" instead of rolling into KB/s.
//   • peaks + history live on the widget instance, not the shared store, so a
//     tile and its expanded overlay do NOT share them.
//   • `active` is declared but never honoured (hidden instances keep churning).
Item {
    id: root
    width: 520; height: 420

    WidgetHarness {
        id: h
        anchors.fill: parent
        widgetFile: "NetWidget.qml"
        expanded: true
    }

    // Recurse the widget's visual tree so we can inspect the rendered Text nodes
    // (colours + formatted strings) that the widget builds internally.
    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids)
            for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
    }
    function findText(prefix) {
        var found = null
        eachItem(h.item, function (n) {
            if (found) return
            if (n.text !== undefined && typeof n.text === "string" && n.text.indexOf(prefix) === 0)
                found = n
        })
        return found
    }
    function feed(rx, tx) {
        h.metricsJson = JSON.stringify({ net_rx_bytes_per_sec: rx, net_tx_bytes_per_sec: tx })
    }

    TestCase {
        name: "Net"
        when: windowShown

        function init() {
            tryVerify(function () { return h.ready }, 3000)
            // Clear per-instance settings and reset the metrics feed + in-widget
            // accumulators so each test starts from a known state.
            var s = h.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            h.storeCtl._touchSettings()
            h.metricsJson = "{}"
            h.expanded = true
            h.active = true
            var w = h.item
            w.hist = []
            w.peakRx = 0
            w.peakTx = 0
        }

        // ── Metrics reading ──────────────────────────────────────────────────
        function test_reads_rx_tx_from_metrics() {
            var w = h.item
            feed(2048, 512)
            compare(w.rx, 2048, "rx read from net_rx_bytes_per_sec")
            compare(w.tx, 512, "tx read from net_tx_bytes_per_sec")
        }

        function test_down_uses_success_up_uses_accent() {
            var w = h.item
            feed(1000, 2000)
            var down = findText("↓")
            var up = findText("↑")
            verify(down !== null && up !== null, "found the down/up readouts")
            verify(Qt.colorEqual(down.color, h.theme.success), "download line uses theme.success")
            verify(Qt.colorEqual(up.color, w.effAccent), "upload line uses effAccent")
            // The two must be distinguishable so direction is readable.
            verify(!Qt.colorEqual(h.theme.success, w.effAccent), "down/up colours differ")
        }

        function test_missing_metrics_default_to_zero() {
            var w = h.item
            h.metricsJson = "{}"                       // no net keys at all
            compare(w.rx, 0, "rx defaults to 0")
            compare(w.tx, 0, "tx defaults to 0")
            compare(w.fmt(w.rx), "0 B/s", "zero renders as 0 B/s, no crash")
            h.metricsJson = '{"cpu_load": 12}'        // present but no net keys
            compare(w.rx, 0, "still 0 with unrelated metrics")
        }

        // ── Byte formatting ──────────────────────────────────────────────────
        function test_fmt_bytes_units() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "unit", "bytes")
            compare(w.unit, "bytes")
            compare(w.fmt(1048576), "1.0 MB/s", "1 MiB → MB/s")
            compare(w.fmt(1024), "1 KB/s", "1 KiB → KB/s")
            compare(w.fmt(500), "500 B/s", "sub-KiB → B/s")
            compare(w.fmt(0), "0 B/s", "zero")
        }

        // BUG (audit): the < 1024 test happens before Math.round, so 1023.7 takes
        // the B/s branch and rounds up to "1024 B/s" instead of rolling into KB/s.
        function test_fmt_byte_boundary_does_not_show_1024() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "unit", "bytes")
            verify(w.fmt(1023.7) !== "1024 B/s",
                   "1023.7 B/s must roll up, not render '1024 B/s' (got '" + w.fmt(1023.7) + "')")
        }

        // ── Bit formatting ───────────────────────────────────────────────────
        function test_fmt_bits_units() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "unit", "bits")
            compare(w.unit, "bits")
            // 1 MB/s * 8 = 8 Mbps.
            compare(w.fmt(1000000), "8.0 Mbps", "≥1 Mbps shows Mbps")
            // 100 KB/s * 8 = 800 Kbps (< 1 Mbps → Kbps).
            compare(w.fmt(100000), "800 Kbps", "<1 Mbps steps down to Kbps")
        }

        function test_unit_switch_rerenders_readouts() {
            var w = h.item
            feed(2000000, 3000000)
            h.storeCtl.setSetting("test-instance", "unit", "bytes")
            var downBytes = findText("↓")
            verify(downBytes.text.indexOf("MB/s") >= 0, "bytes mode shows MB/s (got '" + downBytes.text + "')")
            h.storeCtl.setSetting("test-instance", "unit", "bits")
            var downBits = findText("↓")
            verify(downBits.text.indexOf("Mbps") >= 0, "switching to bits re-renders as Mbps (got '" + downBits.text + "')")
        }

        // ── Config defaults + reactivity ─────────────────────────────────────
        function test_defaults_when_settings_empty() {
            var w = h.item
            // init() cleared settings — nothing set.
            compare(w.showHistory, true, "showHistory defaults true")
            compare(w.unit, "bytes", "unit defaults to bytes")
        }

        function test_showHistory_toggle_is_reactive() {
            var w = h.item
            compare(w.showHistory, true)
            h.storeCtl.setSetting("test-instance", "showHistory", false)
            compare(w.showHistory, false, "config edit hides the graph live")
            h.storeCtl.setSetting("test-instance", "showHistory", true)
            compare(w.showHistory, true, "and shows it again live")
        }

        function test_cfg_rereads_on_revision_bump() {
            var w = h.item
            compare(w.unit, "bytes")
            // patchSettings bumps store.revision → cfg re-reads.
            h.storeCtl.patchSettings("test-instance", { unit: "bits", showHistory: false })
            compare(w.unit, "bits", "unit follows a revision bump")
            compare(w.showHistory, false, "showHistory follows a revision bump")
        }

        // ── Session peaks + history accumulation ─────────────────────────────
        function test_peaks_track_session_maximum() {
            var w = h.item
            feed(1000, 500)
            feed(5000, 200)      // new rx peak
            feed(800, 9000)      // new tx peak
            feed(100, 100)       // smaller — peaks must hold
            compare(w.peakRx, 5000, "peakRx holds the session max down-rate")
            compare(w.peakTx, 9000, "peakTx holds the session max up-rate")
        }

        function test_history_accumulates_and_caps_at_60() {
            var w = h.item
            w.hist = []
            // Feed a long contiguous ramp; only the last 60 samples must survive.
            // (The handler records the previous tick's rate, so we assert on the
            // shape of the window — contiguous, length 60 — not absolute values.)
            for (var i = 1; i <= 80; i++) feed(i, i * 2)
            compare(w.hist.length, 60, "history buffer caps at 60 samples (push/shift)")
            var n = w.hist.length
            compare(w.hist[n - 1].r - w.hist[0].r, 59,
                    "the retained window spans exactly 60 consecutive samples (oldest dropped)")
            for (var j = 1; j < n; j++)
                compare(w.hist[j].r - w.hist[j - 1].r, 1, "samples stay in FIFO order")
            compare(w.hist[n - 1].t, w.hist[n - 1].r * 2, "tx recorded alongside rx")
        }

        // BUG (audit, medium): peaks + history are plain instance properties, not
        // stored in the shared DashboardStore. A tile and its expanded overlay are
        // SEPARATE instances, so the overlay resets peaks to 0 / an empty graph on
        // every open — contradicting the store's documented shared-state design.
        // The intended behaviour: session state lives in the store so both share it.
        function test_peaks_persisted_to_shared_store() {
            var w = h.item
            feed(4000, 7000)
            var s = h.storeCtl.settingsFor("test-instance")
            verify(s.peakRx !== undefined && s.peakTx !== undefined,
                   "peaks should live in the shared store so tile+overlay share them")
        }

        function test_history_persisted_to_shared_store() {
            var w = h.item
            feed(1000, 2000)
            feed(1500, 2500)
            var s = h.storeCtl.settingsFor("test-instance")
            verify(s.hist !== undefined && s.hist.length >= 2,
                   "sparkline history should live in the shared store, not per-instance")
        }

        // ── The dead `active` gate ───────────────────────────────────────────
        // BUG (audit, low): `active` is declared but never read; hidden/off-page
        // instances keep pushing history + updating peaks every tick. Intended:
        // an inactive instance pauses accumulation.
        function test_inactive_instance_pauses_accumulation() {
            var w = h.item
            w.hist = []
            h.active = false
            feed(1234, 5678)
            feed(2345, 6789)
            compare(w.hist.length, 0,
                    "an inactive (off-page) instance should not accumulate history")
        }

        // ── Universal appearance keys on WidgetChrome ────────────────────────
        function test_default_accent_is_category_colour() {
            var w = h.item
            verify(Qt.colorEqual(w.effAccent, h.theme.catServices),
                   "with no accent override, effAccent is the Services category colour")
        }

        function test_universal_appearance_keys_apply() {
            var w = h.item
            // Wire the universal per-instance bindings exactly as Dashboard.injectWidget does.
            w.titleOverride = Qt.binding(function () {
                h.storeCtl.revision; var s = h.storeCtl.settingsFor("test-instance")
                return (s && s.title) ? s.title : ""
            })
            w.accentName = Qt.binding(function () {
                h.storeCtl.revision; var s = h.storeCtl.settingsFor("test-instance")
                return (s && s.accent) ? s.accent : ""
            })
            w.cardBackdrop = Qt.binding(function () {
                h.storeCtl.revision; var s = h.storeCtl.settingsFor("test-instance")
                return (s && s.cardBackdrop) ? s.cardBackdrop : "none"
            })

            h.storeCtl.patchSettings("test-instance",
                { title: "Uplink", accent: "red", cardBackdrop: "mesh" })

            compare(w.titleOverride, "Uplink", "custom title flows from config")
            compare(w.cardBackdrop, "mesh", "card backdrop flows from config")
            verify(Qt.colorEqual(w.effAccent, h.theme.accentPresets["red"].a),
                   "accent preset recolours effAccent")
        }
    }
}
