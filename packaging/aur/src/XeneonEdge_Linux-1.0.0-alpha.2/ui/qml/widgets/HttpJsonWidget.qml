import QtQuick
import QtQuick.Layouts

// HTTP / JSON — the generic data-connected primitive. Polls a URL, pulls a value
// out of the JSON response by a dot/bracket path, and shows it as a number, a
// gauge, or a short list. All egress goes through NetHub (never a raw XHR), so
// "no telemetry / local-only" stays provable and a global offline switch / host
// allowlist governs it centrally.
//
// Live results (value/text/error/history) are mirrored into the SHARED per-instance
// store settings and registered as EPHEMERAL keys, so: (a) the compact tile and its
// expanded overlay show the same reading without polling twice, and (b) a poll every
// N seconds never rewrites config.toml (the flash-wear win already used by metrics).
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    // The egress gate. Injected by Dashboard (one app-global instance); a local
    // fallback keeps the widget self-contained in tests / standalone use.
    property var netHub: null
    NetHub { id: _fallbackHub }
    function _hub() { return netHub ? netHub : _fallbackHub }
    // Test seam (mirrors Weather): a per-request XHR factory passed through the gate.
    property var xhrFactory: null

    title: "HTTP / JSON"; iconName: "net"; accentColor: theme.catInfo

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string url: cfg.url || ""
    readonly property string jsonPath: cfg.jsonPath || ""
    readonly property int pollSec: cfg.pollSec !== undefined ? Math.max(2, cfg.pollSec) : 60
    readonly property string mode: cfg.mode || "value"          // value | gauge | list
    readonly property string unit: cfg.unit || ""
    readonly property real gaugeMax: cfg.gaugeMax !== undefined ? cfg.gaugeMax : 100
    readonly property int listMax: cfg.listMax !== undefined ? cfg.listMax : 5
    readonly property string authToken: cfg.authToken || ""
    // Thresholds: value ≥ warnAt → amber, ≥ critAt → red. Blank/NaN disables.
    readonly property real warnAt: cfg.warnAt !== undefined && cfg.warnAt !== "" ? Number(cfg.warnAt) : NaN
    readonly property real critAt: cfg.critAt !== undefined && cfg.critAt !== "" ? Number(cfg.critAt) : NaN

    // ── Live (ephemeral, store-shared) state ────────────────────────────────
    readonly property string valText: cfg.httpText !== undefined ? cfg.httpText : ""
    readonly property var valNum: cfg.httpVal   // number or undefined
    readonly property string errText: cfg.httpErr || ""
    readonly property var listItems: cfg.httpList || []
    property var hist: []

    function _seedHist() {
        if (w.store && w.instanceId && (!w.hist || w.hist.length === 0)) {
            var s = w.store.settingsFor(w.instanceId)
            if (s.hist && s.hist.length) w.hist = s.hist.slice()
        }
    }
    onStoreChanged: _seedHist()
    onInstanceIdChanged: _seedHist()

    // ── JSON path resolver (dot + [index], e.g. "data.items[0].value") ──────
    function resolvePath(obj, path) {
        if (!path || !path.length) return obj
        var parts = ("" + path).replace(/\[(\w+)\]/g, ".$1").replace(/^\./, "").split(".")
        var cur = obj
        for (var i = 0; i < parts.length; i++) {
            if (cur === null || cur === undefined) return undefined
            cur = cur[parts[i]]
        }
        return cur
    }

    function threshColor(v) {
        if (typeof v === "number") {
            if (!isNaN(w.critAt) && v >= w.critAt) return theme.error
            if (!isNaN(w.warnAt) && v >= w.warnAt) return theme.warning
        }
        return w.effAccent
    }
    // The reading's colour — surfaced in the header and the value.
    status: w.errText.length ? "!" : ""
    statusColor: theme.warning
    readonly property color valColor: w.errText.length ? theme.warning
        : (typeof w.valNum === "number" ? threshColor(w.valNum) : theme.textPrimary)

    // ── Fetch ───────────────────────────────────────────────────────────────
    property var _xhr: null
    Component.onDestruction: { if (_xhr) _xhr.abort() }

    function _put(obj) {
        // Persist live results into the shared settings (all ephemeral keys → no
        // disk write, but the expanded overlay + compact tile stay in sync).
        if (w.store && w.instanceId) w.store.patchSettings(w.instanceId, obj)
    }

    function refresh() {
        if (!w.url.length) { _put({ httpErr: "", httpText: "", httpVal: undefined, httpList: [] }); return }
        if (w._xhr) w._xhr.abort()
        var self = this
        w._xhr = w._hub().request({
            url: w.url,
            // The STORED value (may be a ${env:}/file: ref). NetHub resolves it
            // and builds the header — the widget must never hold the plaintext
            // secret, or it would ride cfgKey/settings into config.toml.
            authToken: w.authToken,
            timeout: 8000,
            xhrFactory: w.xhrFactory,
            onDone: function (status, body) {
                w._xhr = null
                var doc
                try { doc = JSON.parse(body) } catch (e) { _put({ httpErr: "Parse error" }); return }
                var v = self.resolvePath(doc, w.jsonPath)
                if (v === undefined) { _put({ httpErr: "No match", httpText: "—" }); return }
                self._apply(v)
            },
            onError: function (reason) {
                w._xhr = null
                _put({ httpErr: reason === "offline" ? "Offline"
                              : reason === "blocked" ? "Blocked"
                              : reason === "timeout" ? "Timed out" : "Unavailable" })
            }
        })
    }

    // Map a resolved JSON value → display state (text / number / list).
    function _apply(v) {
        var patch = { httpErr: "", httpAt: 0 }
        if (Array.isArray(v)) {
            var items = []
            for (var i = 0; i < v.length && i < 24; i++) {
                var e = v[i]
                items.push((e !== null && typeof e === "object") ? JSON.stringify(e) : ("" + e))
            }
            patch.httpList = items
            patch.httpText = items.length + " item" + (items.length === 1 ? "" : "s")
            patch.httpVal = undefined
        } else if (typeof v === "number") {
            patch.httpVal = v
            patch.httpText = "" + (Math.abs(v) >= 100 || Number.isInteger(v) ? Math.round(v) : v.toFixed(1))
            patch.httpList = []
            // Sparkline history (normalised against the gauge max) — shared + ephemeral.
            var h = w.hist.slice()
            var norm = w.gaugeMax > 0 ? Math.max(0, Math.min(1, v / w.gaugeMax)) : 0
            h.push(norm); if (h.length > 48) h.shift()
            w.hist = h
            patch.hist = h
        } else if (typeof v === "boolean") {
            patch.httpVal = undefined; patch.httpList = []
            patch.httpText = v ? "true" : "false"
        } else if (v === null || v === undefined) {
            patch.httpVal = undefined; patch.httpList = []; patch.httpText = "—"
        } else {
            patch.httpVal = undefined; patch.httpList = []
            patch.httpText = ("" + v).slice(0, 64)
        }
        _put(patch)
    }

    // Debounce config changes into one fetch; only the ACTIVE instance polls (the
    // inactive overlay/tile just renders the shared last reading).
    property string cfgKey: url + "|" + jsonPath + "|" + mode + "|" + authToken
    onCfgKeyChanged: if (w.active) fetchDebounce.restart()
    onActiveChanged: if (w.active) fetchDebounce.restart()
    Component.onCompleted: { _seedHist(); if (w.active) fetchDebounce.restart() }
    Timer { id: fetchDebounce; interval: 300; onTriggered: w.refresh() }
    Timer { interval: Math.max(2, w.pollSec) * 1000; repeat: true; running: w.active && w.url.length > 0
            onTriggered: w.refresh() }

    // ── Presentation ─────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: w.expanded ? 8 : 2
        spacing: w.expanded ? 10 : 4

        // Empty / unconfigured hint.
        Text {
            visible: !w.url.length
            Layout.fillWidth: true; Layout.fillHeight: true
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            text: "Add a URL in settings\nto connect a data source"
            color: theme.textTertiary; font.pixelSize: w.expanded ? 16 : 12
        }

        // VALUE / GAUGE — a single reading.
        Loader {
            visible: w.url.length > 0 && w.mode !== "list"
            active: visible
            Layout.fillWidth: true; Layout.fillHeight: true
            sourceComponent: w.mode === "gauge" ? gaugeView : valueView
        }

        // LIST — array of items.
        ColumnLayout {
            visible: w.url.length > 0 && w.mode === "list"
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: 2
            Repeater {
                model: w.listItems.slice(0, w.expanded ? Math.max(w.listMax, 12) : w.listMax)
                delegate: Text {
                    required property var modelData
                    Layout.fillWidth: true
                    text: "• " + modelData
                    elide: Text.ElideRight; maximumLineCount: 1
                    color: theme.textPrimary; font.pixelSize: w.expanded ? 15 : 12
                }
            }
            Item { Layout.fillHeight: true }
            Text {
                visible: w.errText.length > 0
                text: w.errText; color: theme.warning; font.pixelSize: 12
            }
        }
    }

    Component {
        id: valueView
        ColumnLayout {
            anchors.fill: parent
            RowLayout {
                Layout.alignment: Qt.AlignCenter; spacing: 4
                Text {
                    text: w.errText.length ? "—" : (w.valText.length ? w.valText : "…")
                    font.pixelSize: w.expanded ? 72 : 32; font.bold: true
                    color: w.valColor
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: 14; elide: Text.ElideRight
                    Layout.maximumWidth: w.width - 24
                }
                Text {
                    visible: w.unit.length > 0 && !w.errText.length
                    text: w.unit; font.pixelSize: w.expanded ? 22 : 14; color: theme.textSecondary
                    Layout.alignment: Qt.AlignBottom; bottomPadding: w.expanded ? 12 : 4
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                visible: w.errText.length > 0 || (w.expanded && w.jsonPath.length > 0)
                text: w.errText.length ? w.errText : w.jsonPath
                color: w.errText.length ? theme.warning : theme.textTertiary
                font.pixelSize: 12
            }
            // Tiny trend line under the number (numeric readings only).
            Sparkline {
                visible: w.hist.length > 1 && !w.errText.length
                Layout.fillWidth: true; Layout.preferredHeight: w.expanded ? 60 : 22
                values: w.hist; color: w.valColor
            }
        }
    }

    Component {
        id: gaugeView
        MetricGauge {
            anchors.fill: parent
            ok: !w.errText.length && typeof w.valNum === "number"
            value: (typeof w.valNum === "number" && w.gaugeMax > 0)
                   ? Math.max(0, Math.min(1, w.valNum / w.gaugeMax)) : 0
            big: w.errText.length ? "—" : (w.valText.length ? w.valText + (w.unit.length ? w.unit : "") : "…")
            sub: w.expanded ? (w.errText.length ? w.errText : w.jsonPath) : ""
            color: w.valColor
            history: w.hist
            expanded: w.expanded
        }
    }

    // Compact manual refresh (bottom-right), clear of the top-right config affordance.
    Rectangle {
        visible: !w.expanded && w.url.length > 0
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.rightMargin: theme.spacingXs; anchors.bottomMargin: theme.spacingXs
        width: 34; height: 34; radius: width / 2
        color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b,
                       rMA.pressed ? 0.32 : (rMA.containsMouse ? 0.22 : 0.14))
        Text { anchors.centerIn: parent; text: "⟳"; font.pixelSize: 18; color: w.effAccent }
        MouseArea { id: rMA; anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor; onClicked: w.refresh() }
    }
}
