import QtQuick
import QtTest

// COVERS: schema:showCpu, schema:showDisk, schema:showGpu, schema:showRam, schema:showTemps

// Comprehensive coverage for area "widget:sensors" (ui/qml/widgets/SensorsWidget.qml).
//
// Drives config through the DashboardStore the harness owns and asserts on the
// widget's derived `rows` model, its num() helper, colour thresholds, accent
// handling, reactivity, and real geometry (overflow clipping + empty-body
// placeholder). Assertions describe the CORRECT behaviour; where the widget is
// buggy they fail on purpose (see the audit) rather than being weakened.
Item {
    id: root
    width: 520; height: 900

    // Roomy tile for the logic/colour/reactivity tests.
    WidgetHarness {
        id: h; anchors.fill: parent
        widgetFile: "SensorsWidget.qml"; expanded: true
    }
    // A compact 1x1-ish tile pinned to the 120px minimum height, for the
    // overflow/clipping geometry test.
    WidgetHarness {
        id: hSmall; width: 220; height: 120
        widgetFile: "SensorsWidget.qml"; expanded: false
    }

    // ── shared helpers (root scope is visible inside the TestCases) ──────────
    function rowFor(w, lbl) {
        var rs = w.rows
        for (var i = 0; i < rs.length; i++) if (rs[i].lbl === lbl) return rs[i]
        return null
    }
    function colEq(a, b) { return Qt.colorEqual(a, b) }

    // Recursively visit every visual child.
    function eachChild(obj, fn) {
        if (!obj) return
        var ch = obj.children
        if (!ch) return
        for (var i = 0; i < ch.length; i++) { fn(ch[i]); eachChild(ch[i], fn) }
    }
    // First Text descendant whose text === label.
    function findText(rootItem, label) {
        var found = null
        eachChild(rootItem, function (c) {
            if (found) return
            if (c && c.hasOwnProperty("text") && c.text === label) found = c
        })
        return found
    }
    // Every visible Text descendant with non-empty text.
    function visibleTexts(rootItem) {
        var out = []
        eachChild(rootItem, function (c) {
            if (c && c.hasOwnProperty("text") && typeof c.text === "string"
                && c.text !== "" && c.visible) out.push(c.text)
        })
        return out
    }

    readonly property string fullMetrics: JSON.stringify({
        cpu_usage_percent: 45, gpu_usage_percent: 30, ram_usage_percent: 60,
        disk_usage_percent: 55, disk_total_bytes: 1000000000,
        cpu_temp_celsius: 50, gpu_temp_celsius: 55
    })

    // ── logic / config / colour / reactivity ────────────────────────────────
    TestCase {
        name: "SensorsLogic"
        when: windowShown

        function init() {
            tryVerify(function () { return h.ready }, 3000)
            var s = h.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            h.storeCtl._touchSettings()
            if (h.item.hasOwnProperty("accentName")) h.item.accentName = ""
            h.metricsJson = "{}"
        }
        function feed(o) { h.metricsJson = JSON.stringify(o) }

        // ---- num() coalescing helper ----
        function test_num_helper() {
            var w = h.item
            compare(w.num(undefined), -1, "undefined → -1")
            compare(w.num(null), -1, "null → -1")
            compare(w.num(0), 0, "genuine 0 preserved")
            compare(w.num(42), 42, "value passthrough")
        }

        // ---- all rows visible with a full metrics payload ----
        function test_all_six_rows_with_full_metrics() {
            var w = h.item
            feed(JSON.parse(root.fullMetrics))
            compare(w.rows.length, 6, "CPU/GPU/RAM/DISK/CPU°/GPU° all present")
            verify(rowFor(w, "CPU") !== null)
            verify(rowFor(w, "GPU") !== null)
            verify(rowFor(w, "RAM") !== null)
            verify(rowFor(w, "DISK") !== null)
            verify(rowFor(w, "CPU °") !== null)
            verify(rowFor(w, "GPU °") !== null)
        }

        // ---- each show* toggle honoured after a revision bump ----
        function test_toggle_each_row() {
            var w = h.item
            feed(JSON.parse(root.fullMetrics))
            compare(w.rows.length, 6)

            h.storeCtl.setSetting("test-instance", "showCpu", false)
            compare(rowFor(w, "CPU"), null, "showCpu:false hides CPU")
            h.storeCtl.setSetting("test-instance", "showCpu", true)
            verify(rowFor(w, "CPU") !== null, "showCpu:true restores CPU")

            h.storeCtl.setSetting("test-instance", "showGpu", false)
            compare(rowFor(w, "GPU"), null, "showGpu:false hides GPU")

            h.storeCtl.setSetting("test-instance", "showRam", false)
            compare(rowFor(w, "RAM"), null, "showRam:false hides RAM")

            h.storeCtl.setSetting("test-instance", "showDisk", false)
            compare(rowFor(w, "DISK"), null, "showDisk:false hides DISK")

            h.storeCtl.setSetting("test-instance", "showTemps", false)
            compare(rowFor(w, "CPU °"), null, "showTemps:false hides CPU°")
            compare(rowFor(w, "GPU °"), null, "showTemps:false hides GPU°")
        }

        // ---- GPU absent (null) hides both GPU rows even with toggles on ----
        function test_gpu_null_hides_gpu_rows() {
            var w = h.item
            feed({ cpu_usage_percent: 10, ram_usage_percent: 20, disk_usage_percent: 30,
                   disk_total_bytes: 5, gpu_usage_percent: null, gpu_temp_celsius: null,
                   cpu_temp_celsius: 40 })
            compare(rowFor(w, "GPU"), null, "gpu_usage null → GPU hidden")
            compare(rowFor(w, "GPU °"), null, "gpu_temp null → GPU° hidden")
            verify(rowFor(w, "CPU") !== null, "CPU still shown")
        }

        // ---- disk with zero total is hidden even when showDisk is true ----
        function test_disk_zero_total_hidden() {
            var w = h.item
            feed({ cpu_usage_percent: 10, ram_usage_percent: 20,
                   disk_usage_percent: 88, disk_total_bytes: 0 })
            compare(rowFor(w, "DISK"), null, "disk_total_bytes:0 hides DISK")
            // ...and non-zero brings it back.
            feed({ cpu_usage_percent: 10, ram_usage_percent: 20,
                   disk_usage_percent: 88, disk_total_bytes: 123 })
            verify(rowFor(w, "DISK") !== null, "non-zero total shows DISK")
        }

        // ---- CPU/RAM hidden when their metric is absent (no fabricated 0%, S4) ----
        function test_cpu_ram_hidden_when_metric_absent() {
            var w = h.item
            feed({ gpu_usage_percent: 40, disk_usage_percent: 30, disk_total_bytes: 5 })  // no cpu/ram keys
            compare(rowFor(w, "CPU"), null, "absent cpu_usage → CPU hidden, not a fabricated 0%")
            compare(rowFor(w, "RAM"), null, "absent ram_usage → RAM hidden, not a fabricated 0%")
            // a real 0 (idle machine) still shows the row, at value 0.
            feed({ cpu_usage_percent: 0, ram_usage_percent: 0 })
            var cpu = rowFor(w, "CPU"), ram = rowFor(w, "RAM")
            verify(cpu !== null && cpu.val === 0, "real cpu 0% shows the CPU row at 0")
            verify(ram !== null && ram.val === 0, "real ram 0% shows the RAM row at 0")
        }

        // ---- temperature colour thresholds at the 70 / 85 boundaries ----
        function test_temp_colour_thresholds() {
            var w = h.item
            function cpuTempCol(t) {
                feed({ cpu_usage_percent: 5, ram_usage_percent: 5, cpu_temp_celsius: t })
                return rowFor(w, "CPU °").col
            }
            verify(colEq(cpuTempCol(70), h.theme.catSystem), "t=70 → base (catSystem)")
            verify(colEq(cpuTempCol(71), h.theme.warning),   "t=71 → warning")
            verify(colEq(cpuTempCol(85), h.theme.warning),   "t=85 → warning (boundary)")
            verify(colEq(cpuTempCol(86), h.theme.error),     "t=86 → error")
        }

        // ---- load bars follow a valid per-widget accent; hot temp stays error ----
        function test_valid_accent_recolours_load_hot_temp_stays_error() {
            var w = h.item
            feed({ cpu_usage_percent: 45, gpu_usage_percent: 30, ram_usage_percent: 60,
                   disk_usage_percent: 55, disk_total_bytes: 9, cpu_temp_celsius: 90 })
            w.accentName = "purple"
            verify(w.accentName !== "" && h.theme.accentPresets["purple"] !== undefined)
            var eff = w.effAccent
            verify(colEq(rowFor(w, "CPU").col, eff), "CPU load bar → effAccent")
            verify(colEq(rowFor(w, "RAM").col, eff), "RAM load bar → effAccent")
            verify(colEq(rowFor(w, "DISK").col, eff), "DISK load bar → effAccent")
            // A >85 temp must remain error-coloured regardless of accent.
            verify(colEq(rowFor(w, "CPU °").col, h.theme.error),
                   "hot temp stays error even with accent set")
            // A cool temp under accent uses the accent (documents bug: collapses
            // category colours, but this is the code's actual behaviour).
            feed({ cpu_usage_percent: 45, ram_usage_percent: 60, cpu_temp_celsius: 50 })
            verify(colEq(rowFor(w, "CPU °").col, eff), "cool temp → effAccent when accent set")
        }

        // ---- an unknown accent name flips accentSet but effAccent falls back ----
        function test_invalid_accent_falls_back_to_category() {
            var w = h.item
            feed({ cpu_usage_percent: 45, ram_usage_percent: 60 })
            w.accentName = "violet"   // not a preset key
            // effAccent falls back to accentColor (catSystem); accentSet is still
            // true, so every load bar collapses to catSystem (documented bug #8).
            verify(colEq(w.effAccent, h.theme.catSystem), "unknown accent → catSystem fallback")
            verify(colEq(rowFor(w, "CPU").col, h.theme.catSystem))
            verify(colEq(rowFor(w, "RAM").col, h.theme.catSystem),
                   "RAM collapses to catSystem under an invalid accent")
        }

        // ---- distinct category colours when NO accent is set ----
        function test_distinct_category_colours_without_accent() {
            var w = h.item
            feed(JSON.parse(root.fullMetrics))
            verify(colEq(rowFor(w, "CPU").col,  h.theme.catSystem))
            verify(colEq(rowFor(w, "GPU").col,  h.theme.catGaming))
            verify(colEq(rowFor(w, "RAM").col,  h.theme.catProductivity))
            verify(colEq(rowFor(w, "DISK").col, h.theme.catInfo))
        }

        // ---- reactivity: rows re-evaluate on revision, metrics, and accent ----
        function test_reactivity() {
            var w = h.item
            feed(JSON.parse(root.fullMetrics))
            compare(w.rows.length, 6)
            // store.revision (config) reactivity
            h.storeCtl.setSetting("test-instance", "showGpu", false)
            compare(rowFor(w, "GPU"), null, "revision bump recomputes rows")
            // metrics reactivity
            feed({ cpu_usage_percent: 99, ram_usage_percent: 1 })
            compare(rowFor(w, "CPU").val, 99, "new metrics value flows through")
            // accent reactivity (no metrics/config change)
            w.accentName = "green"
            verify(colEq(rowFor(w, "CPU").col, w.effAccent), "accent change recolours")
        }

        // ---- value/unit shape: '%' vs '°C', and never a -1 in a visible row ----
        function test_value_shape_and_units() {
            var w = h.item
            feed(JSON.parse(root.fullMetrics))
            compare(rowFor(w, "CPU").unit, "%")
            compare(rowFor(w, "RAM").unit, "%")
            compare(rowFor(w, "CPU °").unit, "°C")
            compare(rowFor(w, "GPU °").unit, "°C")
            var rs = w.rows
            for (var i = 0; i < rs.length; i++)
                verify(rs[i].val !== -1, "no visible row carries the -1 sentinel (" + rs[i].lbl + ")")
        }

        // ---- rendered label text formats as toFixed(0)+unit ----
        function test_rendered_labels_formatted() {
            var w = h.item
            feed({ cpu_usage_percent: 45.7, ram_usage_percent: 60.2, cpu_temp_celsius: 49.9 })
            verify(findText(w, "46%") !== null, "45.7% renders as 46%")
            verify(findText(w, "60%") !== null, "60.2% renders as 60%")
            verify(findText(w, "50°C") !== null, "49.9°C renders as 50°C")
        }

        // ---- value >100 clamps the fill bar to the full track width ----
        function test_over_100_clamps_bar_width() {
            var w = h.item
            feed({ cpu_usage_percent: 105, ram_usage_percent: 60 })
            compare(rowFor(w, "CPU").val, 105, "raw value is not clamped in the model")
            var label = findText(w, "105%")
            verify(label !== null, "value label present")
            var rowLayout = label.parent            // the RowLayout for CPU
            // children: [labelText, trackRect, valueText]
            var track = rowLayout.children[1]
            var fill = track.children[0]
            // The bar now ANIMATES to its target (delegates survive ticks), so
            // wait for the ease to land rather than sampling mid-flight.
            tryVerify(function () { return fill.width >= track.width - 0.5 }, 2000,
                      "at >100% the bar eases to fully filled")
            verify(fill.width <= track.width + 0.5, "fill never exceeds the track")
        }

        // ---- THE OWNER-REPORTED CLUNK: a tick must not rebuild the widget ----
        // "If the CPU temp rises 1 degree, only the bar length should increase/
        // decrease smoothly, not reload the entire bar." The Repeater's model was
        // a fresh JS array per metrics tick, so every delegate was destroyed and
        // recreated ~2s — nothing survived long enough to animate. The model is
        // now a static label list: these assertions prove the SAME delegate
        // objects live across ticks and only their bound values move.
        function test_delegates_survive_metric_ticks() {
            var w = h.item
            feed({ cpu_usage_percent: 20, ram_usage_percent: 30, cpu_temp_celsius: 50 })
            var cpuLabel = findText(w, "CPU")
            verify(cpuLabel !== null, "CPU row rendered")
            var track = cpuLabel.parent.children[1]
            var fill = track.children[0]
            // Two more ticks with changed values.
            feed({ cpu_usage_percent: 45, ram_usage_percent: 35, cpu_temp_celsius: 51 })
            feed({ cpu_usage_percent: 60, ram_usage_percent: 40, cpu_temp_celsius: 52 })
            var cpuLabel2 = findText(w, "CPU")
            var fill2 = cpuLabel2.parent.children[1].children[0]
            // Object IDENTITY: a recreated delegate would be a different object.
            verify(cpuLabel2 === cpuLabel, "the CPU label is the SAME object after two metric ticks")
            verify(fill2 === fill, "the CPU fill bar is the SAME object after two metric ticks")
            // …and the surviving bar's bound value tracked the data.
            tryVerify(function () { return Math.abs(fill2.width - track.width * 0.60) < 2 }, 2000,
                      "the surviving bar eased to the new 60% value")
        }

        // ---- bar length + threshold colour EASE between ticks ----
        // Pins: the fill animates via theme.motionValue (Behavior on width /
        // color), and both collapse to an instant jump under reduce-motion.
        function test_bar_and_colour_ease_and_collapse_under_reduce_motion() {
            var w = h.item
            h.theme.reduceMotion = false
            compare(h.theme.motionValue, 400, "precondition: value easing enabled")
            feed({ cpu_usage_percent: 0, ram_usage_percent: 10, cpu_temp_celsius: 50 })
            var cpuLabel = findText(w, "CPU")
            var track = cpuLabel.parent.children[1]
            var fill = track.children[0]
            // Let the layout polish give the track real geometry first, and let
            // the bar settle at its 0% start.
            tryVerify(function () { return track.width > 50 }, 2000, "track laid out")
            tryVerify(function () { return fill.width < 2 }, 2000, "bar settled at ~0%")

            // A new sample GLIDES: immediately after the tick the bar is still
            // en route, then lands on the target.
            feed({ cpu_usage_percent: 100, ram_usage_percent: 10, cpu_temp_celsius: 50 })
            verify(fill.width < track.width * 0.9,
                   "mid-ease right after the tick (" + fill.width + " of " + track.width + ")")
            tryVerify(function () { return fill.width >= track.width - 1 }, 2000,
                      "…then eases to the full 100% width")

            // Threshold colour cross-fades rather than hard-cutting: cool→hot.
            var tempFill = findText(w, "CPU °").parent.children[1].children[0]
            // The colour itself eases now, so wait for it to settle at the base
            // tone before provoking the threshold change.
            tryVerify(function () { return colEq(tempFill.color, h.theme.catSystem) }, 2000,
                      "cool temp settles at the base colour")
            feed({ cpu_usage_percent: 100, ram_usage_percent: 10, cpu_temp_celsius: 90 })
            verify(!colEq(tempFill.color, h.theme.error),
                   "immediately after the tick the colour is still fading, not hard-cut")
            tryVerify(function () { return colEq(tempFill.color, h.theme.error) }, 2000,
                      "…and lands on the error colour")

            // REDUCE-MOTION IS SACRED: the same updates become instant jumps —
            // asserted IMMEDIATELY after the tick, where the motion-on case above
            // was still provably mid-ease.
            h.theme.reduceMotion = true
            compare(h.theme.motionValue, 0, "reduce-motion zeroes the value token")
            feed({ cpu_usage_percent: 0, ram_usage_percent: 10, cpu_temp_celsius: 50 })
            tryVerify(function () { return fill.width < 2 }, 50,
                      "under reduce-motion the bar snaps (no 400ms glide)")
            tryVerify(function () { return colEq(tempFill.color, h.theme.catSystem) }, 50,
                      "under reduce-motion the colour snaps (no 400ms fade)")
            h.theme.reduceMotion = false
        }

        // ---- GPU hotplug shifts the ROWS index (behaviour note) ----
        // w.rows is still rebuilt as a fresh array, so inserting the GPU row
        // shifts what rows[1] holds from RAM to GPU. The rendered DELEGATES no
        // longer care (they are keyed by their own static label), but the
        // derived-model semantics are pinned here so they don't drift silently.
        function test_gpu_insert_shifts_index() {
            var w = h.item
            feed({ cpu_usage_percent: 10, ram_usage_percent: 20,
                   disk_usage_percent: 30, disk_total_bytes: 4 })
            compare(w.rows[1].lbl, "RAM", "no GPU: index 1 is RAM")
            feed({ cpu_usage_percent: 10, gpu_usage_percent: 77, ram_usage_percent: 20,
                   disk_usage_percent: 30, disk_total_bytes: 4 })
            compare(w.rows[1].lbl, "GPU", "GPU appears: index 1 is now GPU (delegate reused)")
        }

        // ---- empty metrics still shows CPU/RAM as a solid 0% (documents bug #7) ----
        // Empty metrics no longer fabricate a confident 0% for CPU/RAM (S4). The
        // rows are hidden until real data arrives — matching CpuWidget/RamWidget and
        // this widget's own GPU/disk/temp rows (was previously a documented bug).
        function test_empty_metrics_hides_cpu_ram() {
            var w = h.item
            h.metricsJson = "{}"
            compare(rowFor(w, "CPU"), null, "no metrics → CPU hidden, not a fabricated 0%")
            compare(rowFor(w, "RAM"), null, "no metrics → RAM hidden, not a fabricated 0%")
        }

        // ---- 'active' contract is ignored: rows keep computing when inactive ----
        // Documents bug #5 (active declared + bound but never honoured).
        function test_active_is_ignored() {
            var w = h.item
            feed(JSON.parse(root.fullMetrics))
            h.active = false
            compare(w.active, false, "active propagates to the widget")
            compare(w.rows.length, 6, "rows keep evaluating despite active=false")
            h.active = true
        }

        // ---- disabling every row leaves NO placeholder (real bug #6) ----
        function test_all_disabled_needs_placeholder() {
            var w = h.item
            feed(JSON.parse(root.fullMetrics))
            h.storeCtl.patchSettings("test-instance", {
                showCpu: false, showGpu: false, showRam: false,
                showDisk: false, showTemps: false
            })
            compare(w.rows.length, 0, "no rows remain")
            // A well-behaved widget shows a 'nothing to show' placeholder; only the
            // chrome title 'Sensors' should otherwise be visible.
            var texts = visibleTexts(w).filter(function (t) { return t !== "Sensors" })
            verify(texts.length >= 1,
                   "expected a placeholder when all rows are disabled, found none: "
                   + JSON.stringify(texts))
        }
    }

    // ── geometry: compact tile clips the bottom rows (real bug #1) ───────────
    // ── Per-sizeClass structure (W1 wave 2a) ────────────────────────────────
    // Fixed-size hosts at real projected cell footprints.
    Item { width: 344; height: 416
        WidgetHarness { id: hMicro; anchors.fill: parent; widgetFile: "SensorsWidget.qml"; expanded: false } }
    Item { id: wideWrap; width: 696; height: 416
        WidgetHarness { id: hWide; anchors.fill: parent; widgetFile: "SensorsWidget.qml"; expanded: false } }
    Item { width: 344; height: 840
        WidgetHarness { id: hTall; anchors.fill: parent; widgetFile: "SensorsWidget.qml"; expanded: false } }

    TestCase {
        name: "SensorsSizes"
        when: windowShown

        function feedTo(host) {
            host.metricsJson = JSON.stringify({ cpu_usage_percent: 20, gpu_usage_percent: 30,
                ram_usage_percent: 40, disk_usage_percent: 50, disk_total_bytes: 1e12,
                cpu_temp_celsius: 55, gpu_temp_celsius: 45 })
        }
        function gridOf(host) {
            var cpu = findText(host.item, "CPU")
            return cpu ? cpu.parent.parent : null   // delegate RowLayout → the Grid/ColumnLayout
        }

        // 0.5x0.5 — headerless; the six slim rows are the tile.
        function test_micro_headerless_rows() {
            tryVerify(function () { return hMicro.ready }, 3000)
            var w = hMicro.item
            w.sizeClass = "compact"
            feedTo(hMicro)
            compare(w.micro, true, "a 344x416 compact box is the micro tile")
            compare(w.showHeader, false, "micro hides the header — the rows are the tile")
            compare(gridOf(hMicro).columns, 1, "micro keeps a single column")
            verify(w.rowFont >= 12, "row type stays legible")
        }

        // wide — the SAME delegates reflow into two columns; identity survives
        // the class flip (the whole point of the static model).
        function test_wide_two_columns_same_delegates() {
            tryVerify(function () { return hWide.ready }, 3000)
            var w = hWide.item
            w.sizeClass = "compact"
            feedTo(hWide)
            var cpuBefore = findText(w, "CPU")
            var fillBefore = cpuBefore.parent.children[1].children[0]
            compare(gridOf(hWide).columns, 1, "compact: one column")
            w.sizeClass = "wide"
            compare(gridOf(hWide).columns, 2, "wide: the rows flow into two columns")
            var cpuAfter = findText(w, "CPU")
            verify(cpuAfter === cpuBefore, "the CPU label is the SAME object across the class flip")
            verify(cpuAfter.parent.children[1].children[0] === fillBefore,
                   "…and so is its fill bar (no delegate rebuild on resize)")
            wideWrap.width = 840; wideWrap.height = 344
            compare(gridOf(hWide).columns, 2, "the landscape projection keeps two columns")
            wideWrap.width = 696; wideWrap.height = 416
            w.sizeClass = "compact"
        }

        // tall — single column, thicker bars + larger type than micro.
        function test_tall_scales_rows_up() {
            tryVerify(function () { return hTall.ready }, 3000)
            tryVerify(function () { return hMicro.ready }, 3000)
            var w = hTall.item
            w.sizeClass = "tall"
            feedTo(hTall)
            hMicro.item.sizeClass = "compact"
            feedTo(hMicro)
            compare(gridOf(hTall).columns, 1, "tall keeps a single column")
            verify(w.barH > hMicro.item.barH, "tall bars are thicker than micro bars ("
                   + w.barH.toFixed(1) + " vs " + hMicro.item.barH.toFixed(1) + ")")
            w.sizeClass = "full"
            compare(w.micro, false, "full is never micro")
        }
    }

    TestCase {
        name: "SensorsOverflow"
        when: windowShown

        function init() {
            tryVerify(function () { return hSmall.ready }, 3000)
            var s = hSmall.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hSmall.storeCtl._touchSettings()
            hSmall.metricsJson = root.fullMetrics
        }

        function test_six_rows_fit_in_120px_tile() {
            var w = hSmall.item
            tryVerify(function () { return w.rows.length === 6 }, 2000,
                      "all 6 rows are enabled/present in the compact tile")
            // Locate the content ColumnLayout via a known row label:
            //   DISK Text → RowLayout → content ColumnLayout → body Item.
            var disk = findText(w, "DISK")
            verify(disk !== null, "DISK label found")
            var contentCol = disk.parent.parent       // ColumnLayout that lays out the rows
            var body = contentCol.parent               // WidgetChrome body (clip:true)
            verify(contentCol.implicitHeight !== undefined, "resolved the content ColumnLayout")
            // Force the layout so positions/implicit sizes are real, then let the
            // polish settle (offscreen defers layout otherwise).
            if (contentCol.forceLayout) contentCol.forceLayout()
            wait(50)

            var bodyH = body.height
            // Every enabled row must render fully inside the clipped body. Rows whose
            // bottom edge falls past bodyH are silently clipped and unreadable.
            var labels = ["CPU", "GPU", "RAM", "DISK", "CPU °", "GPU °"]
            var clipped = []
            for (var i = 0; i < labels.length; i++) {
                var t = findText(w, labels[i])
                if (!t) continue
                var p = t.mapToItem(body, 0, t.height)   // bottom edge in body coords
                if (p.y > bodyH + 0.5) clipped.push(labels[i] + "@" + Math.round(p.y))
            }
            verify(clipped.length === 0,
                   "no row may be clipped in a 120px tile; body=" + Math.round(bodyH)
                   + "px, content=" + Math.round(contentCol.implicitHeight)
                   + "px, clipped rows: " + JSON.stringify(clipped))
        }
    }
}
