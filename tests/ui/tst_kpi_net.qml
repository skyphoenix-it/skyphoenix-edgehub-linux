import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: schema:source, schema:filePath, schema:invert
//
// ui/qml/widgets/KpiWidget.qml network + file path, offline via xhrFactory. Covers
// the HTTP source, the LOCAL FILE source (file:// endpoint, works offline), JSON
// vs bare-number bodies, the inverted "lower is worse" thresholds, and no-match.
Item {
    id: root
    width: 640; height: 520

    function makeFake() {
        return {
            method: "", url: "", sent: false, aborted: false,
            readyState: 0, status: 0, responseText: "", headers: ({}),
            timeout: 0, ontimeout: null, onreadystatechange: null,
            open: function (m, u) { this.method = m; this.url = u; this.readyState = 1 },
            setRequestHeader: function (k, v) { this.headers[k] = v },
            send: function () { this.sent = true },
            abort: function () { this.aborted = true },
            resolveWith: function (status, body) {
                this.status = status; this.responseText = body; this.readyState = 4
                if (this.onreadystatechange) this.onreadystatechange()
            }
        }
    }

    WidgetHarness {
        id: h; anchors.fill: parent
        widgetFile: "KpiWidget.qml"; expanded: true
    }
    App.WidgetConfigSchema { id: sc }
    function iid() { return h.instanceId }
    function clearSettings() {
        var s = h.storeCtl.settingsFor(iid()); for (var k in s) delete s[k]; h.storeCtl._touchSettings()
    }

    TestCase {
        name: "KpiNet"
        when: windowShown
        property var lastFake: null
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clearSettings(); h.active = false
            h.item.xhrFactory = function () { lastFake = root.makeFake(); return lastFake }
        }

        // ── HTTP source ──────────────────────────────────────────────────────
        function test_http_json_path_number() {
            h.storeCtl.patchSettings(iid(), { source: "http", url: "https://api/x", jsonPath: "stats.count" })
            h.item.refresh()
            compare(lastFake.url, "https://api/x")
            lastFake.resolveWith(200, '{"stats":{"count":128}}')
            compare(h.item.valNum, 128)
            compare(h.item.valText, "128")
        }

        function test_http_bare_number_body() {
            h.storeCtl.patchSettings(iid(), { source: "http", url: "https://api/x", jsonPath: "" })
            h.item.refresh()
            lastFake.resolveWith(200, "42")
            compare(h.item.valNum, 42, "a bare numeric body is taken as the value")
        }

        // ── local FILE source ────────────────────────────────────────────────
        function test_file_source_builds_file_url() {
            h.storeCtl.patchSettings(iid(), { source: "file", filePath: "/run/metrics/depth", jsonPath: "" })
            h.item.refresh()
            compare(lastFake.url, "file:///run/metrics/depth", "a bare path becomes a file:// URL")
        }

        function test_file_already_prefixed_is_left_alone() {
            h.storeCtl.patchSettings(iid(), { source: "file", filePath: "file:///tmp/x", jsonPath: "" })
            h.item.refresh()
            compare(lastFake.url, "file:///tmp/x")
        }

        function test_file_status_zero_is_success() {
            // A local file read reports status 0 (no HTTP layer) - must still succeed.
            h.storeCtl.patchSettings(iid(), { source: "file", filePath: "/x", jsonPath: "" })
            h.item.refresh()
            lastFake.resolveWith(0, "7")
            compare(h.item.valNum, 7, "status 0 with a body is a valid local read")
            compare(h.item.errText, "")
        }

        function test_non_numeric_file_shows_as_text() {
            h.storeCtl.patchSettings(iid(), { source: "file", filePath: "/x", jsonPath: "" })
            h.item.refresh()
            lastFake.resolveWith(0, "degraded")
            compare(h.item.valText, "degraded")
        }

        // ── thresholds ───────────────────────────────────────────────────────
        function test_normal_thresholds() {
            h.storeCtl.patchSettings(iid(), { source: "http", url: "https://a/x", jsonPath: "", warnAt: "80", critAt: "95" })
            h.item.refresh(); lastFake.resolveWith(200, "50")
            compare(h.item.valColor, h.item.effAccent, "below warn → accent")
            h.item.refresh(); lastFake.resolveWith(200, "97")
            compare(h.item.valColor, h.theme.error, "≥ crit → red")
        }

        function test_inverted_thresholds_lower_is_worse() {
            h.storeCtl.patchSettings(iid(), { source: "http", url: "https://a/x", jsonPath: "",
                invert: true, warnAt: "90", critAt: "50" })
            h.item.refresh(); lastFake.resolveWith(200, "99")
            compare(h.item.valColor, h.item.effAccent, "well above → accent")
            h.item.refresh(); lastFake.resolveWith(200, "80")
            compare(h.item.valColor, h.theme.warning, "≤ warn → amber (lower is worse)")
            h.item.refresh(); lastFake.resolveWith(200, "40")
            compare(h.item.valColor, h.theme.error, "≤ crit → red")
        }

        function test_unconfigured_does_not_fetch() {
            clearSettings()
            h.storeCtl.patchSettings(iid(), { source: "http", url: "" })
            lastFake = null
            h.item.refresh()
            verify(lastFake === null, "no request without an endpoint")
        }
    }

    // Schema ↔ widget key sync - the KPI-specific keys (the shared jsonPath/warnAt/
    // etc. are credited by tst_httpjson_net).
    TestCase {
        name: "KpiSchema"
        when: windowShown
        function keys() {
            var s = sc.schemaFor("kpi"); var k = {}
            for (var i = 0; i < s.sections.length; i++)
                for (var j = 0; j < (s.sections[i].fields || []).length; j++)
                    if (s.sections[i].fields[j].key) k[s.sections[i].fields[j].key] = true
            return k
        }
        function test_schema_exposes_kpi_keys() {
            var k = keys()
            verify(k["source"] === true, "kpi schema exposes source")
            verify(k["filePath"] === true, "kpi schema exposes filePath")
            verify(k["invert"] === true, "kpi schema exposes invert")
        }
    }

    // ── Per-sizeClass structure (W1 wave 2b) ────────────────────────────────
    // Fixed-size hosts at the real projected cell footprints (the panel's short
    // axis is 720, so a half-cell is ~348x409 portrait / ~423x306 landscape and
    // the baseline third is ~696x819 / ~846x612).
    Item { width: 348; height: 409
        WidgetHarness { id: kMicro; anchors.fill: parent; widgetFile: "KpiWidget.qml"; expanded: false } }
    Item { width: 696; height: 819
        WidgetHarness { id: kBase; anchors.fill: parent; widgetFile: "KpiWidget.qml"; expanded: false } }
    Item { id: kWideWrap; width: 1269; height: 612
        WidgetHarness { id: kWide; anchors.fill: parent; widgetFile: "KpiWidget.qml"; expanded: false } }
    // 1x3 portrait - the whole panel.
    Item { width: 696; height: 2459
        WidgetHarness { id: kBoard; anchors.fill: parent; widgetFile: "KpiWidget.qml"; expanded: false } }

    TestCase {
        name: "KpiSizes"
        when: windowShown

        function configure(host) {
            host.active = false
            host.storeCtl.patchSettings(host.instanceId,
                { source: "http", url: "http://x/y", label: "Error budget", unit: "%" })
        }
        // Feed a real series so the trend + stats have something to show.
        function feed(host) {
            configure(host)
            host.item.xhrFactory = function () { return root.makeFake() }
            var vals = [40, 55, 42, 61, 58]
            for (var i = 0; i < vals.length; i++) host.item._apply(vals[i])
        }

        // 0.5x0.5 - a READOUT: the number, and nothing that needs a finger.
        function test_micro_is_the_number_alone() {
            tryVerify(function () { return kMicro.ready }, 3000)
            var k = kMicro.item
            k.sizeClass = "compact"
            feed(kMicro)
            compare(k.micro, true, "a 348x409 compact box is the micro tile")
            compare(k.showHeader, false, "micro drops the chrome header")
            compare(k.showLabel, false, "micro drops the label - the number IS the tile")
            compare(k.showSpark, false, "…and the trend")
            compare(k.showStats, false, "…and the stats strip")
            verify(k.valuePx >= 100, "the number still fills the box (" + k.valuePx.toFixed(0) + "px)")
        }

        // The number is sized off the BOX, not off `expanded` - the wave-2b bug.
        function test_number_scales_with_the_tile() {
            tryVerify(function () { return kBase.ready }, 3000)
            tryVerify(function () { return kMicro.ready }, 3000)
            kMicro.item.sizeClass = "compact"; feed(kMicro)
            var k = kBase.item
            k.sizeClass = "compact"
            feed(kBase)
            compare(k.micro, false, "a 696x819 baseline tile is not micro")
            compare(k.showLabel, true, "the baseline earns the label")
            compare(k.showSpark, true, "…and the trend")
            verify(k.valuePx > kMicro.item.valuePx,
                   "the baseline number is bigger than the micro one ("
                   + k.valuePx.toFixed(0) + " vs " + kMicro.item.valuePx.toFixed(0) + ")")
            verify(k.valuePx > 40, "…and far past the old flat 40px (" + k.valuePx.toFixed(0) + ")")
        }

        // A genuinely wide box puts the trend BESIDE the number.
        function test_wide_splits_number_and_trend() {
            tryVerify(function () { return kWide.ready }, 3000)
            var k = kWide.item
            k.sizeClass = "wide"
            feed(kWide)
            compare(k.split, true, "1269x612 (1x1.5 landscape) splits into two columns")
            compare(lay_of(kWide).columns, 2, "…which is the GridLayout flipping columns")
            // Portrait 1x1.5 is 696x1229 - the same size, the other shape.
            kWideWrap.width = 696; kWideWrap.height = 1229
            k.sizeClass = "tall"
            compare(k.split, false, "the portrait projection of the same size stacks")
            compare(lay_of(kWide).columns, 1, "…back to a single column")
            kWideWrap.width = 1269; kWideWrap.height = 612
        }

        // 1x3 - the whole panel. A billboard: the stats strip is real extra
        // content, and the trend takes the slack instead of leaving air.
        function test_fullscreen_is_a_billboard() {
            tryVerify(function () { return kBoard.ready }, 3000)
            tryVerify(function () { return kBase.ready }, 3000)
            var k = kBoard.item
            k.sizeClass = "large"
            feed(kBoard)
            kBase.item.sizeClass = "compact"; feed(kBase)
            compare(k.roomy, true, "1x2/1x3 are the roomy class")
            compare(k.showStats, true, "the billboard earns a min/avg/max strip")
            compare(kBase.item.showStats, false, "…which the baseline tile does not")
            verify(k.valuePx >= kBase.item.valuePx,
                   "the number is at least as big as the baseline's")
            verify(k.labelPx > kBase.item.labelPx, "the label grows with the box")
            // The stats are values on STABLE cells, not a rebuilt model.
            var minCell = findText(k, "min")
            verify(minCell !== null, "the min cell exists")
            k.sizeClass = "full"
            verify(findText(k, "min") === minCell, "the same cell survives a class flip")
        }

        // Helper: the content GridLayout (the value Text's grandparent).
        function lay_of(host) {
            var t = findValueText(host.item)
            return t ? t.parent.parent.parent : null   // Text → RowLayout → ColumnLayout → Grid
        }
        function findValueText(node) {
            return findFirst(node, function (n) {
                return n.hasOwnProperty("font") && n.hasOwnProperty("text")
                       && String(n.text) === "58" })
        }
        function findText(node, s) {
            return findFirst(node, function (n) {
                return n.hasOwnProperty("text") && String(n.text) === s })
        }
        // NOTE: no guard for the value-text `preferredWidth` pairing (added to
        // KpiWidget alongside MetricGauge's). It is deliberately absent, not
        // forgotten. `valuePx` is pre-computed from the character count, so the
        // reading already fits under a MONOSPACE font no matter what the Layout
        // does; the pairing only matters when `theme.fontMono` falls back to a
        // proportional face (missing/wider mono). The headless suite ships
        // DejaVu Sans Mono, so a guard here passes with OR without the fix - it
        // would be inert. Writing an inert guard is the exact anti-pattern this
        // codebase has been purging; the fix is verified manually under a
        // no-mono fontconfig and the blind spot is recorded in BACKLOG.md.
        function findFirst(node, pred) {
            if (!node) return null
            if (pred(node)) return node
            var kids = node.children
            for (var i = 0; kids && i < kids.length; i++) {
                var r = findFirst(kids[i], pred)
                if (r) return r
            }
            return null
        }
    }
}
