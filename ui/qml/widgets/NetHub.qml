import QtQuick

// ─────────────────────────────────────────────────────────────────────────
// NetHub — the single egress gate. EVERY outbound request from a widget goes
// through NetHub.request(); it is the ONLY place in the QML tree that may
// construct an XMLHttpRequest. This makes "no telemetry / local-only" provable
// by construction: there is exactly one choke point to audit, gate, and count.
//
// In production Dashboard.qml creates ONE NetHub and injects it into every net
// widget (so `offline`, the host allowlist and the attestation counters are
// app-global). A widget instantiated standalone (tests) falls back to its own
// NetHub, so the same code path is exercised offline through the xhrFactory seam.
//
// The gate enforces, in order:
//   1. global offline  — a hard kill switch (blocks all remote egress)
//   2. host allowlist   — when non-empty, only these hosts may be reached
//   3. local files pass — file:/relative URLs are not egress, so they are only
//                         subject to nothing (a local KPI file works offline)
// then counts the request (for the attestation surface) and performs it.
// ─────────────────────────────────────────────────────────────────────────
QtObject {
    id: hub

    // Global kill switch. When true, NO remote request is made (local file:
    // reads still work — they are not egress).
    property bool offline: false

    // Host allowlist. Empty = allow any host. Non-empty = only these hosts.
    // (Populated by managed/enterprise config in a later epic; empty by default.)
    property var allowHosts: []

    // Test seam: when set, called instead of `new XMLHttpRequest()`. A caller
    // may also pass a per-request `xhrFactory` in opts (used by widgets that
    // already own the seam, e.g. Weather), which takes precedence.
    property var xhrFactory: null

    // Resolves credential references (E7). Anything with a
    // resolveSecret(raw) -> { ok, value, error, plaintext } method; in the hub
    // that is ConfigBridge (Dashboard injects it). Null in tests/standalone,
    // where _resolveToken falls back — see there for why a ref then FAILS rather
    // than being sent verbatim.
    property var secretResolver: null

    // ── Attestation counters (read-only surface for Diagnostics / enterprise) ──
    property int requests: 0     // requests actually sent
    property int blocked: 0      // requests refused by the gate
    property var byHost: ({})    // { host: count } of sent requests

    // Is this a LOCAL read (not egress)? This must be an allowlist of local forms,
    // never "anything that isn't http(s)": the old shape treated EVERY unknown
    // scheme as local, so `webcal://…` — a real Apple/iCloud calendar URL — skipped
    // both the offline kill switch and the host allowlist and went straight out.
    // Any scheme we do not positively recognise is therefore NOT local; it is
    // refused by request() rather than waved through as a file read.
    function _isLocal(url) {
        var u = ("" + (url || "")).trim()
        if (!u.length) return false
        if (/^file:/i.test(u)) return true          // explicit local file
        if (/^qrc:/i.test(u)) return true           // bundled resource
        return !_hasScheme(u)                       // a bare/relative path
    }
    // "scheme:" per RFC 3986, plus protocol-relative "//host" (which inherits
    // http(s) and is therefore egress, not a path).
    function _hasScheme(url) {
        return /^[a-z][a-z0-9+.-]*:/i.test(url) || url.indexOf("//") === 0
    }
    // Egress we recognise and are willing to send.
    function _isRemote(url) {
        return /^https?:\/\//i.test(("" + (url || "")).trim())
    }
    function hostOf(url) {
        var m = /^https?:\/\/([^\/?#]+)/i.exec(url || "")
        return m ? m[1].toLowerCase() : ""
    }
    // Whether a URL would be permitted right now (does not send). Useful for UI.
    function isAllowed(url) {
        if (_isLocal(url)) return true
        if (offline) return false
        if (allowHosts && allowHosts.length && allowHosts.indexOf(hostOf(url)) < 0) return false
        return true
    }

    // Returns the host's new tally (so callers/tests can assert the count without
    // reaching into byHost).
    function _bump(host) {
        var m = hub.byHost
        m[host] = (m[host] || 0) + 1
        hub.byHost = m   // reassign so bindings on byHost update
        return m[host]
    }

    // ── Secrets (E7 Phase A) ────────────────────────────────────────────────
    // A stored token is a REFERENCE, not a value. Widgets hand the raw stored
    // string to request({authToken}) and NEVER resolve it themselves: the
    // resolved secret then exists only inside one request() call, so it cannot
    // reach a widget property, the store, or config.toml.
    function _looksLikeRef(s) {
        var t = (s || "").trim()
        return t.indexOf("${env:") === 0 || t.indexOf("file:") === 0 || t.indexOf("secret://") === 0
    }

    // Hosts already warned about a plaintext credential — the warning is about a
    // stored value, not an event, so it must not repeat on every poll.
    property var _plaintextWarned: ({})

    // → { ok, value, error }
    function _resolveToken(raw) {
        if (!raw || !("" + raw).length) return { ok: true, value: "" }
        var r = hub.secretResolver
        if (r && r.resolveSecret) {
            var res = r.resolveSecret("" + raw)
            // Keep working, but say so once: E1 shipped this field, so a user may
            // already have a real token sitting in config.toml.
            if (res.plaintext === true && !hub._plaintextWarned[raw]) {
                hub._plaintextWarned[raw] = true
                console.warn("NetHub: this widget's Bearer token is stored in plain text in " +
                             "config.toml. Use ${env:VAR} or file:/path instead - it is then read " +
                             "only when the request is made and never written to disk.")
            }
            return { ok: !!res.ok, value: res.value || "", error: res.error || "" }
        }
        // No resolver (standalone widget / test harness). A plaintext literal is
        // still usable, but a REF must NOT be sent verbatim: shipping
        // "${env:CI_TOKEN}" to a remote host as a Bearer token both fails
        // confusingly AND discloses the reference. Fail closed instead.
        if (_looksLikeRef(raw))
            return { ok: false, value: "", error: "no secret resolver available to read " + ("" + raw).trim() }
        return { ok: true, value: "" + raw }
    }

    // request(opts): the single egress entry point.
    //   opts.url        (required) http(s):// for remote, anything else = local file
    //   opts.method     default "GET"
    //   opts.headers    { name: value } (applied when the XHR supports it)
    //   opts.authToken  the STORED credential (a "${env:}"/"file:" ref or a legacy
    //                   literal) — resolved here and sent as "Authorization:
    //                   Bearer <value>". Pass the stored string, never a resolved
    //                   secret: that is what keeps it out of ui_state.
    //   opts.body       request body (string)
    //   opts.timeout    ms, default 8000
    //   opts.allow      per-request host allowlist (augments the global one)
    //   opts.xhrFactory per-request XHR factory (test seam; wins over hub.xhrFactory)
    //   opts.onDone(status, responseText)
    //   opts.onError(reason)  reason ∈ offline | blocked | timeout | "http <n>" |
    //                         open-failed | "secret: <why>"
    // Returns the XHR object (so the caller can track / abort it), or null if
    // the gate refused the request before any socket was opened.
    function request(opts) {
        opts = opts || {}
        var url = opts.url || ""
        var local = _isLocal(url)

        // Neither a local read nor http(s): a scheme the gate cannot reason about
        // (webcal:, ftp:, //host, …). Refuse it. Treating it as "local" would skip
        // the kill switch and the allowlist, and guessing it is remote would mean
        // enforcing an allowlist against a host we did not parse. A caller that
        // wants webcal: must map it to https: itself (CalendarWidget does).
        if (!local && !_isRemote(url)) {
            hub.blocked++
            if (opts.onError) opts.onError("unsupported-scheme")
            return null
        }

        if (!local && hub.offline) {
            hub.blocked++
            if (opts.onError) opts.onError("offline")
            return null
        }
        var effAllow = (opts.allow && opts.allow.length) ? opts.allow : hub.allowHosts
        if (!local && effAllow && effAllow.length && effAllow.indexOf(hostOf(url)) < 0) {
            hub.blocked++
            if (opts.onError) opts.onError("blocked")
            return null
        }

        // Resolve the credential BEFORE any socket is opened: an unresolvable
        // secret must never become a request (a missing env var would otherwise
        // send an unauthenticated call, which reads as an auth failure from the
        // far end and hides the real cause).
        var headers = opts.headers
        if (opts.authToken !== undefined && opts.authToken !== null) {
            var sec = _resolveToken(opts.authToken)
            if (!sec.ok) {
                hub.blocked++
                if (opts.onError) opts.onError("secret: " + sec.error)
                return null
            }
            if (sec.value.length) {
                // Copy: never mutate the caller's object — headers may be a
                // widget property, which would park the secret in the QML tree.
                headers = {}
                for (var hk in opts.headers) headers[hk] = opts.headers[hk]
                headers["Authorization"] = "Bearer " + sec.value
            }
        }

        hub.requests++
        _bump(local ? "(local)" : hostOf(url))

        var mk = opts.xhrFactory ? opts.xhrFactory : (hub.xhrFactory ? hub.xhrFactory : null)
        var xhr = mk ? mk() : new XMLHttpRequest()
        xhr.timeout = opts.timeout || 8000
        xhr.ontimeout = function () { if (opts.onError) opts.onError("timeout") }
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var st = xhr.status
            // A local file read succeeds with status 0 (no HTTP layer). A remote
            // request succeeds on ANY 2xx, not just 200: a transforming proxy
            // legitimately answers 203, and CalendarWidget accepted 203/206 before
            // it moved onto the gate — narrowing that here would have silently
            // broken an ICS feed behind a corporate proxy. A 2xx with an empty body
            // (204) still fails the caller's own parse, which is the right layer
            // for that.
            var ok = (st >= 200 && st < 300) || (local && (st === 0 || st === 200) && !!xhr.responseText)
            if (ok) { if (opts.onDone) opts.onDone(st, xhr.responseText) }
            else { if (opts.onError) opts.onError("http " + st) }
        }
        try {
            xhr.open(opts.method || "GET", url)
            if (headers && xhr.setRequestHeader)
                for (var k in headers) xhr.setRequestHeader(k, headers[k])
            xhr.send(opts.body !== undefined ? opts.body : undefined)
        } catch (e) {
            if (opts.onError) opts.onError("open-failed")
            return xhr
        }
        return xhr
    }
}
