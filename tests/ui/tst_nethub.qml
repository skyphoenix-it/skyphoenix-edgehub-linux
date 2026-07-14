import QtQuick
import QtTest
import "../../ui/qml/widgets" as W

// The egress gate (ui/qml/widgets/NetHub.qml). Driven entirely offline through a
// fake XHR: no real sockets. Asserts the gate's ordering (offline → allowlist →
// local-file bypass), the attestation counters, header pass-through, and the
// onDone/onError contract for success, non-200, timeout and open-failure.
Item {
    id: root
    width: 50; height: 50

    // A fake XHR that records what NetHub did to it and resolves on demand.
    function makeFake() {
        return {
            method: "", url: "", sent: false, aborted: false,
            readyState: 0, status: 0, responseText: "",
            timeout: 0, ontimeout: null, onreadystatechange: null,
            headers: ({}),
            open: function (m, u) { this.method = m; this.url = u; this.readyState = 1 },
            setRequestHeader: function (k, v) { this.headers[k] = v },
            send: function (b) { this.sent = true; this.body = b },
            abort: function () { this.aborted = true },
            resolveWith: function (status, body) {
                this.status = status; this.responseText = body; this.readyState = 4
                if (this.onreadystatechange) this.onreadystatechange()
            },
            fireTimeout: function () { if (this.ontimeout) this.ontimeout() }
        }
    }

    W.NetHub { id: hub }

    TestCase {
        name: "NetHub"
        when: windowShown

        property var lastFake: null
        function init() {
            hub.offline = false
            hub.allowHosts = []
            hub.requests = 0
            hub.blocked = 0
            hub.byHost = ({})
            var tc = this
            hub.xhrFactory = function () { tc.lastFake = root.makeFake(); return tc.lastFake }
        }

        // ── host parsing ─────────────────────────────────────────────────────
        function test_hostOf_extracts_authority() {
            compare(hub.hostOf("https://api.example.com/v1/x?y=1"), "api.example.com")
            compare(hub.hostOf("http://10.0.0.5:9090/metrics"), "10.0.0.5:9090")
            compare(hub.hostOf("/local/path"), "", "a local path has no host")
        }

        // ── success path ─────────────────────────────────────────────────────
        function test_request_success_calls_onDone_and_counts() {
            var got = null
            hub.request({ url: "https://api.example.com/s",
                onDone: function (st, body) { got = { st: st, body: body } },
                onError: function () { fail("should not error") } })
            verify(lastFake !== null && lastFake.sent, "request was actually sent")
            compare(hub.requests, 1, "one request counted")
            compare(hub.byHost["api.example.com"], 1, "per-host counter bumped")
            lastFake.resolveWith(200, '{"ok":true}')
            verify(got !== null, "onDone fired")
            compare(got.st, 200); compare(got.body, '{"ok":true}')
        }

        function test_non_200_is_error() {
            var err = null
            hub.request({ url: "https://api.example.com/s",
                onDone: function () { fail("should not succeed") },
                onError: function (r) { err = r } })
            lastFake.resolveWith(503, "")
            compare(err, "http 503", "a server error surfaces as http <status>")
        }

        // ── offline kill switch ──────────────────────────────────────────────
        function test_offline_blocks_remote_before_send() {
            hub.offline = true
            var err = null
            var xhr = hub.request({ url: "https://api.example.com/s",
                onError: function (r) { err = r } })
            compare(xhr, null, "no XHR created when offline")
            compare(err, "offline")
            compare(hub.blocked, 1, "blocked counter bumped")
            compare(hub.requests, 0, "nothing sent")
        }

        function test_offline_still_allows_local_file() {
            hub.offline = true
            hub.request({ url: "file:///run/metric",
                onDone: function () {}, onError: function () { fail("local read must not be gated") } })
            verify(lastFake !== null && lastFake.sent, "a local file reads even offline (not egress)")
            compare(hub.byHost["(local)"], 1, "counted as a local read")
        }

        // ── host allowlist ───────────────────────────────────────────────────
        function test_allowlist_blocks_disallowed_host() {
            hub.allowHosts = ["allowed.example.com"]
            var err = null
            hub.request({ url: "https://evil.example.com/x", onError: function (r) { err = r } })
            compare(err, "blocked")
            compare(hub.blocked, 1)
            // an allowed host passes
            hub.request({ url: "https://allowed.example.com/x", onDone: function () {} })
            compare(hub.requests, 1, "the allowed host went through")
        }

        function test_per_request_allow_overrides_global() {
            hub.allowHosts = []   // global allows all
            var err = null
            hub.request({ url: "https://other.example.com/x", allow: ["only.example.com"],
                onError: function (r) { err = r } })
            compare(err, "blocked", "a per-request allowlist narrows the global one")
        }

        // ── headers, timeout, open failure ───────────────────────────────────
        function test_headers_are_applied() {
            hub.request({ url: "https://api.example.com/s",
                headers: { "Authorization": "Bearer T", "X-Test": "1" }, onDone: function () {} })
            compare(lastFake.headers["Authorization"], "Bearer T", "auth header set")
            compare(lastFake.headers["X-Test"], "1", "extra header set")
        }

        function test_timeout_surfaces() {
            var err = null
            hub.request({ url: "https://api.example.com/s", onError: function (r) { err = r } })
            lastFake.fireTimeout()
            compare(err, "timeout")
        }

        function test_open_failure_is_reported() {
            var err = null
            hub.xhrFactory = function () {
                return { timeout: 0, open: function () { throw new Error("boom") },
                         setRequestHeader: function () {}, send: function () {} }
            }
            var xhr = hub.request({ url: "https://api.example.com/s", onError: function (r) { err = r } })
            compare(err, "open-failed")
        }

        // ── isAllowed (non-sending predicate) ────────────────────────────────
        function test_isAllowed_predicate() {
            hub.offline = false; hub.allowHosts = ["ok.example.com"]
            verify(hub.isAllowed("https://ok.example.com/x"), "listed host allowed")
            verify(!hub.isAllowed("https://no.example.com/x"), "unlisted host not allowed")
            verify(hub.isAllowed("file:///x"), "local always allowed")
            hub.offline = true
            verify(!hub.isAllowed("https://ok.example.com/x"), "offline blocks even listed hosts")
            verify(hub.isAllowed("file:///x"), "offline still allows local files")
        }
    }
}
