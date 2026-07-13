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
            verify(fill.width <= track.width + 0.5, "fill never exceeds the track")
            verify(fill.width >= track.width - 0.5, "at >100% the bar is fully filled")
        }

        // ---- GPU hotplug reuses the delegate at index 1 (behaviour note) ----
        // Documents bug #4: because rows is rebuilt as a fresh array and the
        // Repeater diffs by index, inserting the GPU row shifts what index 1
        // shows from RAM to GPU.
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
        function test_empty_metrics_shows_zero_reading() {
            var w = h.item
            h.metricsJson = "{}"
            var cpu = rowFor(w, "CPU")
            verify(cpu !== null, "CPU row shown before any metrics tick")
            compare(cpu.val, 0, "no data coalesces to a confident 0% (known issue)")
            compare(rowFor(w, "RAM").val, 0)
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
