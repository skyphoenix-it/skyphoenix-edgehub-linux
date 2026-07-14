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

    // ── Attestation counters (read-only surface for Diagnostics / enterprise) ──
    property int requests: 0     // requests actually sent
    property int blocked: 0      // requests refused by the gate
    property var byHost: ({})    // { host: count } of sent requests

    function _isLocal(url) {
        return url.indexOf("http://") !== 0 && url.indexOf("https://") !== 0
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

    function _bump(host) {
        var m = hub.byHost
        m[host] = (m[host] || 0) + 1
        hub.byHost = m   // reassign so bindings on byHost update
    }

    // request(opts): the single egress entry point.
    //   opts.url        (required) http(s):// for remote, anything else = local file
    //   opts.method     default "GET"
    //   opts.headers    { name: value } (applied when the XHR supports it)
    //   opts.body       request body (string)
    //   opts.timeout    ms, default 8000
    //   opts.allow      per-request host allowlist (augments the global one)
    //   opts.xhrFactory per-request XHR factory (test seam; wins over hub.xhrFactory)
    //   opts.onDone(status, responseText)
    //   opts.onError(reason)  reason ∈ offline | blocked | timeout | "http <n>" | open-failed
    // Returns the XHR object (so the caller can track / abort it), or null if
    // the gate refused the request before any socket was opened.
    function request(opts) {
        opts = opts || {}
        var url = opts.url || ""
        var local = _isLocal(url)

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

        hub.requests++
        _bump(local ? "(local)" : hostOf(url))

        var mk = opts.xhrFactory ? opts.xhrFactory : (hub.xhrFactory ? hub.xhrFactory : null)
        var xhr = mk ? mk() : new XMLHttpRequest()
        xhr.timeout = opts.timeout || 8000
        xhr.ontimeout = function () { if (opts.onError) opts.onError("timeout") }
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var st = xhr.status
            // A local file read succeeds with status 0 (no HTTP layer); a remote
            // request must be a real 200.
            var ok = (st === 200) || (local && (st === 0 || st === 200) && !!xhr.responseText)
            if (ok) { if (opts.onDone) opts.onDone(st, xhr.responseText) }
            else { if (opts.onError) opts.onError("http " + st) }
        }
        try {
            xhr.open(opts.method || "GET", url)
            if (opts.headers && xhr.setRequestHeader)
                for (var k in opts.headers) xhr.setRequestHeader(k, opts.headers[k])
            xhr.send(opts.body !== undefined ? opts.body : undefined)
        } catch (e) {
            if (opts.onError) opts.onError("open-failed")
            return xhr
        }
        return xhr
    }
}
