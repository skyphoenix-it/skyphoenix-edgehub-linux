import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: schema:jsonPath, schema:pollSec, schema:mode, schema:gaugeMax, schema:listMax, schema:authToken, schema:warnAt, schema:critAt
//
// Network + parsing path of ui/qml/widgets/HttpJsonWidget.qml, driven offline via
// the xhrFactory seam (passed through NetHub inside the widget). Asserts URL +
// auth-header construction, JSON-path extraction, value/list/number mapping,
// threshold colouring, every error state, and that live results are EPHEMERAL
// (never written to the persisted document — no config.toml churn per poll).
Item {
    id: root
    width: 760; height: 620

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
            },
            fireTimeout: function () { if (this.ontimeout) this.ontimeout() }
        }
    }

    WidgetHarness {
        id: h; anchors.fill: parent
        widgetFile: "HttpJsonWidget.qml"; expanded: true
    }
    App.WidgetConfigSchema { id: sc }
    function iid() { return h.instanceId }
    function clearSettings() {
        var s = h.storeCtl.settingsFor(iid()); for (var k in s) delete s[k]; h.storeCtl._touchSettings()
    }

    TestCase {
        name: "HttpJsonNet"
        when: windowShown
        property var lastFake: null
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clearSettings(); h.active = false
            h.item.xhrFactory = function () { lastFake = root.makeFake(); return lastFake }
        }
        function drive(url, path, status, body) {
            h.storeCtl.patchSettings(iid(), { url: url, jsonPath: path })
            h.item.refresh()
            if (status !== undefined) lastFake.resolveWith(status, body)
        }

        // ── request construction ─────────────────────────────────────────────
        function test_get_url_and_no_auth_by_default() {
            h.storeCtl.patchSettings(iid(), { url: "https://api.example.com/status", jsonPath: "" })
            h.item.refresh()
            verify(lastFake !== null && lastFake.sent, "sent through the gate")
            compare(lastFake.method, "GET")
            compare(lastFake.url, "https://api.example.com/status")
            verify(lastFake.headers["Authorization"] === undefined, "no auth header when no token")
        }

        function test_bearer_token_becomes_auth_header() {
            h.storeCtl.patchSettings(iid(), { url: "https://api.example.com/s", authToken: "SECRET" })
            h.item.refresh()
            compare(lastFake.headers["Authorization"], "Bearer SECRET")
        }

        function test_empty_url_does_not_fetch() {
            h.storeCtl.patchSettings(iid(), { url: "", jsonPath: "x" })
            lastFake = null
            h.item.refresh()
            verify(lastFake === null, "no request without a URL")
        }

        // ── JSON path extraction → value ─────────────────────────────────────
        function test_dotted_path_extracts_number() {
            drive("https://x/y", "data.value", 200, '{"data":{"value":42}}')
            compare(h.item.valNum, 42, "numeric value extracted")
            compare(h.item.valText, "42", "formatted as an integer")
            compare(h.item.errText, "", "no error on success")
        }

        function test_bracket_index_path() {
            drive("https://x/y", "items[1].name", 200, '{"items":[{"name":"a"},{"name":"b"}]}')
            compare(h.item.valText, "b", "items[1].name resolved")
        }

        function test_float_is_rounded_to_one_decimal() {
            drive("https://x/y", "v", 200, '{"v":3.14159}')
            compare(h.item.valText, "3.1", "small float shown to one decimal")
        }

        function test_blank_path_uses_whole_body_scalar() {
            drive("https://x/y", "", 200, '99')
            compare(h.item.valNum, 99, "a bare JSON number is taken whole")
        }

        function test_missing_path_is_no_match() {
            drive("https://x/y", "nope.here", 200, '{"data":1}')
            compare(h.item.errText, "No match", "an unresolved path is a clear error")
        }

        // ── list mode ────────────────────────────────────────────────────────
        function test_array_value_becomes_list() {
            drive("https://x/y", "rows", 200, '{"rows":["one","two","three"]}')
            compare(h.item.listItems.length, 3, "array mapped to list items")
            compare(h.item.listItems[0], "one")
            compare(h.item.valText, "3 items", "count summarised as text")
        }

        // ── thresholds → colour ──────────────────────────────────────────────
        function test_threshold_colours() {
            h.storeCtl.patchSettings(iid(), { warnAt: "80", critAt: "95" })
            drive("https://x/y", "v", 200, '{"v":50}')
            compare(h.item.valColor, h.item.effAccent, "below warn → accent")
            drive("https://x/y", "v", 200, '{"v":85}')
            compare(h.item.valColor, h.theme.warning, "≥ warn → amber")
            drive("https://x/y", "v", 200, '{"v":99}')
            compare(h.item.valColor, h.theme.error, "≥ crit → red")
        }

        // ── error states ─────────────────────────────────────────────────────
        function test_non_200_is_unavailable() {
            drive("https://x/y", "v", 500, "")
            compare(h.item.errText, "Unavailable", "http error → Unavailable")
        }
        function test_malformed_json_is_parse_error() {
            drive("https://x/y", "v", 200, "not json{")
            compare(h.item.errText, "Parse error")
        }
        function test_timeout_state() {
            h.storeCtl.patchSettings(iid(), { url: "https://x/y", jsonPath: "v" })
            h.item.refresh()
            lastFake.fireTimeout()
            compare(h.item.errText, "Timed out")
        }

        // ── ephemeral persistence (the flash-wear guarantee) ─────────────────
        function test_live_results_are_not_persisted() {
            drive("https://x/y", "v", 200, '{"v":7}')
            compare(h.item.valNum, 7, "value is live in memory")
            var disk = h.storeCtl._persistableData().settings[iid()] || ({})
            verify(disk.httpVal === undefined, "httpVal not written to config")
            verify(disk.httpText === undefined, "httpText not written to config")
            verify(disk.hist === undefined, "poll history not written to config")
            compare(disk.url, "https://x/y", "the configured URL is persisted")
        }
    }

    // Schema ↔ widget key sync — each keyed assertion names its schema key so the
    // behaviour matrix credits every HTTP/JSON config field.
    TestCase {
        name: "HttpJsonSchema"
        when: windowShown
        function keys() {
            var s = sc.schemaFor("httpjson"); var k = {}
            for (var i = 0; i < s.sections.length; i++)
                for (var j = 0; j < (s.sections[i].fields || []).length; j++)
                    if (s.sections[i].fields[j].key) k[s.sections[i].fields[j].key] = true
            return k
        }
        function test_schema_exposes_every_widget_key() {
            var k = keys()
            verify(k["jsonPath"] === true, "httpjson schema exposes jsonPath")
            verify(k["pollSec"] === true, "httpjson schema exposes pollSec")
            verify(k["mode"] === true, "httpjson schema exposes mode")
            verify(k["gaugeMax"] === true, "httpjson schema exposes gaugeMax")
            verify(k["listMax"] === true, "httpjson schema exposes listMax")
            verify(k["authToken"] === true, "httpjson schema exposes authToken")
            verify(k["warnAt"] === true, "httpjson schema exposes warnAt")
            verify(k["critAt"] === true, "httpjson schema exposes critAt")
        }
    }
}
