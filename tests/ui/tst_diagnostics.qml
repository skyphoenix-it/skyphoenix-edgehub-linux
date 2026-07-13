import QtQuick
import QtTest
import "../../ui/qml" as App

// Diagnostics (ui/qml/Diagnostics.qml) — the on-device diagnostics screen. It
// resolves `theme`, `stackView`, `_configDir` (and optionally `_buildType`) by
// name, so we provide them at the file root. Assert: metric rows render from the
// injected metricsJson, empty/malformed frames degrade to N/A (no blank grid),
// tab switching, screen rows, and the Back action firing through stackView.pop().
Item {
    id: root
    width: 700; height: 900

    property alias theme: _theme
    App.Theme { id: _theme }

    // Globals Diagnostics reads unqualified.
    property string _configDir: "/home/test/.config/xeneon"
    property int popCount: 0
    QtObject { id: stackViewObj; function pop() { root.popCount++ } }
    property var stackView: stackViewObj

    App.Diagnostics { id: diag }

    // ── tree helpers ─────────────────────────────────────────────────────────
    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids) for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
    }
    function findPred(node, pred) {
        var f = null
        eachItem(node, function (n) { if (!f && pred(n)) f = n })
        return f
    }
    function findText(node, str) {
        return findPred(node, function (n) {
            return n.text !== undefined && typeof n.text === "string" && n.text === str
        })
    }
    function findButton(str) {
        return findPred(diag, function (n) {
            return n.text === str && n.checkable !== undefined   // a Button
        })
    }

    TestCase {
        name: "Diagnostics"
        when: windowShown

        function init() {
            diag.currentPage = 0
            diag.metricsJson = ""
            diag.configJson = ""
            diag.screensData = ""
            root.popCount = 0
        }

        // ── Metric rows render from metricsJson ──────────────────────────────
        function test_metric_values_render() {
            diag.metricsJson = JSON.stringify({ cpu_usage_percent: 42, cpu_temp_celsius: 58 })
            verify(findText(diag, "42.0%") !== null, "CPU usage row renders the injected value")
            verify(findText(diag, "58.0°C") !== null, "CPU temp row renders the injected value")
        }

        function test_bytes_formatted_to_gb() {
            diag.metricsJson = JSON.stringify({ ram_total_bytes: 16 * 1024 * 1024 * 1024 })
            verify(findText(diag, "16.0 GB") !== null, "byte metric is formatted to GB")
        }

        function test_missing_metric_is_na() {
            diag.metricsJson = JSON.stringify({ cpu_usage_percent: 10 })   // no RAM keys
            verify(findText(diag, "N/A") !== null, "a missing metric renders N/A, not a fake value")
        }

        // ── Empty / malformed frames degrade gracefully ─────────────────────
        function test_empty_frame_parses_to_empty_object() {
            diag.metricsJson = ""
            compare(JSON.stringify(diag.parsedMetrics), "{}", "an empty frame parses to {}")
            verify(findText(diag, "N/A") !== null, "empty frame → cards show N/A (grid not blanked)")
        }

        function test_malformed_frame_is_guarded() {
            var threw = false
            try { diag.metricsJson = "{not: valid json" } catch (e) { threw = true }
            verify(!threw, "a malformed frame does not throw")
            compare(JSON.stringify(diag.parsedMetrics), "{}", "malformed frame parses to {} (guarded)")
        }

        // ── Tab switching ────────────────────────────────────────────────────
        function test_tabs_switch_pages() {
            var screensTab = findButton("Screens")
            verify(screensTab !== null, "Screens tab present")
            mouseClick(screensTab)
            compare(diag.currentPage, 2, "clicking a tab switches the current page")
            var logTab = findButton("Log")
            mouseClick(logTab)
            compare(diag.currentPage, 3, "clicking the Log tab selects it")
        }

        // ── Screen rows render from screensData ──────────────────────────────
        function test_screen_rows_render() {
            diag.screensData = JSON.stringify([
                { model: "XENEON EDGE", name: "DP-3", likelyXeneonEdge: true, isPrimary: false,
                  geometry: { width: 720, height: 2560 }, refreshRate: 60, orientation: "portrait",
                  logicalDpi: 96, physicalDpi: 96, edidHash: "abc123" } ])
            diag.currentPage = 2
            verify(findText(diag, "XENEON EDGE") !== null, "the screen model row renders")
            verify(findText(diag, "Connector: DP-3") !== null, "the connector line renders")
        }

        function test_malformed_screensData_guarded() {
            var threw = false
            try { diag.screensData = "[not json"; diag.currentPage = 2 } catch (e) { threw = true }
            verify(!threw, "malformed screensData does not throw (guarded to [])")
        }

        // ── Config JSON page ─────────────────────────────────────────────────
        function test_config_json_rendered() {
            diag.configJson = '{"version":1}'
            diag.currentPage = 1
            verify(findText(diag, '{"version":1}') !== null, "the config page shows the raw config JSON")
        }

        // ── Back action fires through stackView.pop() ───────────────────────
        function test_back_action_fires() {
            var back = findButton("← Back")
            verify(back !== null, "Back button present")
            mouseClick(back)
            compare(root.popCount, 1, "the Back action pops the stack view")
        }
    }
}
