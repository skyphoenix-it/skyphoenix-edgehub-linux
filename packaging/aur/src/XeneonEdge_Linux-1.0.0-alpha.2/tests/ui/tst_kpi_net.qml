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
            // A local file read reports status 0 (no HTTP layer) — must still succeed.
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

    // Schema ↔ widget key sync — the KPI-specific keys (the shared jsonPath/warnAt/
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
}
