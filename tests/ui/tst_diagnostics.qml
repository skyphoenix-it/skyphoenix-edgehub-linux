import QtQuick
import QtTest
import "../../ui/qml" as App

// Diagnostics (ui/qml/Diagnostics.qml) — the on-device diagnostics screen. It
// resolves `theme`, `stackView`, `_configDir` (and optionally `_buildType`) by
// name, so we provide them at the file root. Assert: metric rows render from the
// injected metricsJson, empty/malformed frames degrade to N/A (no blank grid),
// tab switching, screen rows, and the Back action firing through stackView.pop().
// The Network tab (W5 finding 6) renders the injected NetHub gate: kill-switch
// state, allowlist, sent/blocked totals and per-host counts — asserted against
// a mock hub carrying the same property surface, including live updates.
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

    // Stand-in for the injected NetHub: the exact attestation surface the
    // Network tab reads (offline / allowHosts / requests / blocked / byHost).
    QtObject {
        id: mockHub
        property bool offline: false
        property var allowHosts: []
        property int requests: 0
        property int blocked: 0
        property var byHost: ({})
    }

    // Anchored HERE, at the use site: the component no longer anchors itself
    // (it is a StackView page in the product, and self-anchoring conflicted
    // with StackView's own sizing). This root is a plain Item, so it must
    // give the item a size or every click lands on a 0x0 target.
    App.Diagnostics { id: diag; anchors.fill: parent }

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
            diag.netHub = null
            mockHub.offline = false
            mockHub.allowHosts = []
            mockHub.requests = 0
            mockHub.blocked = 0
            mockHub.byHost = ({})
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

        // ── Redacted config-summary page ─────────────────────────────────────
        function test_redacted_config_summary_rendered_and_labelled() {
            diag.configJson = '{"format":"xeneon-config-diagnostics-v1","redaction":{"sensitive_values_omitted":true}}'
            diag.currentPage = 1
            verify(findText(diag, "Redacted configuration summary") !== null,
                   "the page states that it is not raw config")
            verify(findText(diag, diag.configJson) !== null,
                   "the page renders the core-produced redacted summary")
        }

        // ── Network tab (W5 finding 6): the NetHub attestation surface ──────
        function test_network_tab_exists_and_switches() {
            var tab = findButton("Network")
            verify(tab !== null, "the Network tab is present")
            mouseClick(tab)
            compare(diag.currentPage, 4, "the Network tab selects page 4")
        }

        function test_network_without_gate_states_it_honestly() {
            diag.netHub = null
            diag.currentPage = 4
            verify(findText(diag, "The network gate is not available in this session (no dashboard is running).") !== null,
                   "no injected hub → an honest 'not available' line, never zeros posing as an attestation")
            var counter = findText(diag, "Requests sent: 0")
            verify(counter === null || !counter.visible,
                   "…and no counter rows are shown (hidden with the gate card)")
        }

        function test_network_renders_gate_state_and_counters() {
            mockHub.offline = false
            mockHub.requests = 3
            mockHub.blocked = 1
            mockHub.byHost = ({ "api.example.com": 2, "(local)": 1 })
            diag.netHub = mockHub
            diag.currentPage = 4
            verify(findText(diag, "Offline kill switch: Off") !== null, "kill-switch state renders (off)")
            verify(findText(diag, "Allowed hosts: any host (no allowlist active)") !== null,
                   "an empty allowlist reads as 'any host'")
            verify(findText(diag, "Requests sent: 3") !== null, "sent total renders")
            verify(findText(diag, "Blocked by the gate: 1") !== null, "blocked total renders")
            compare(diag.netHosts.length, 2, "per-host rows flattened from byHost")
            compare(diag.netHosts[0].host, "api.example.com", "sorted by count, busiest first")
            compare(diag.netHosts[0].n, 2, "…with its tally")
            verify(findText(diag, "api.example.com") !== null, "the host row renders")
            verify(findText(diag, "2 requests") !== null, "…with its count")
            verify(findText(diag, "1 request") !== null, "singular count for the (local) row")
        }

        function test_network_offline_and_allowlist_render() {
            mockHub.offline = true
            mockHub.allowHosts = ["ci.example.com", "api.corp.example"]
            diag.netHub = mockHub
            diag.currentPage = 4
            verify(findText(diag, "Offline kill switch: On - all remote requests are refused") !== null,
                   "the kill switch reads as ON with its consequence spelled out")
            verify(findText(diag, "Allowed hosts: ci.example.com, api.corp.example") !== null,
                   "a non-empty allowlist renders its hosts")
        }

        function test_network_counters_track_the_hub_live() {
            diag.netHub = mockHub
            diag.currentPage = 4
            verify(findText(diag, "Requests sent: 0") !== null, "starts at zero")
            verify(findText(diag, "No requests have been sent this session.") !== null,
                   "empty byHost → an explicit empty state")
            mockHub.requests = 5
            mockHub.blocked = 2
            mockHub.byHost = ({ "wttr.in": 5 })
            verify(findText(diag, "Requests sent: 5") !== null, "sent total tracks the hub live")
            verify(findText(diag, "Blocked by the gate: 2") !== null, "blocked total tracks live")
            compare(diag.netHosts.length, 1, "the host row appeared")
            compare(diag.netHosts[0].host, "wttr.in", "with the right host")
            verify(findText(diag, "5 requests") !== null, "and its live count")
        }

        // The integration seam the REAL NetHub satisfies: the same property
        // names the tab binds to exist on the genuine gate (guards against the
        // mock drifting from the product).
        function test_mock_matches_the_real_nethub_surface() {
            var real = Qt.createQmlObject('import "../../ui/qml/widgets" as W; W.NetHub {}', root, "hub")
            verify(real.offline !== undefined, "real NetHub has offline")
            verify(real.allowHosts !== undefined, "real NetHub has allowHosts")
            compare(typeof real.requests, "number", "real NetHub counts requests")
            compare(typeof real.blocked, "number", "real NetHub counts blocked")
            verify(real.byHost !== undefined, "real NetHub tallies byHost")
            diag.netHub = real
            diag.currentPage = 4
            verify(findText(diag, "Requests sent: 0") !== null, "the tab renders off the REAL gate too")
            diag.netHub = null
            real.destroy()
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
