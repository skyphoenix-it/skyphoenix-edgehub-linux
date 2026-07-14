import QtQuick
import QtQuick.Layouts

// KPI — a single headline number, from an HTTP/JSON endpoint or a local file,
// with a label, a unit, colour-coded thresholds and a tiny trend line. Built for
// dashboards where one number matters: error budget, queue depth, revenue, uptime.
//
// Egress (HTTP source) goes through NetHub, exactly like HttpJsonWidget. A "file"
// source reads a local path (JSON or a bare number) and works fully offline — a
// local file is not egress, so the gate lets it through even in offline mode.
// Live results are shared + ephemeral (no config.toml churn on each poll).
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property var netHub: null
    NetHub { id: _fallbackHub }
    function _hub() { return netHub ? netHub : _fallbackHub }
    property var xhrFactory: null

    title: "KPI"; iconName: "sensors"; accentColor: theme.catInfo
    big: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string source: cfg.source || "http"       // http | file
    readonly property string url: cfg.url || ""
    readonly property string filePath: cfg.filePath || ""
    readonly property string jsonPath: cfg.jsonPath || ""
    readonly property string label: cfg.label || ""
    readonly property string unit: cfg.unit || ""
    readonly property int pollSec: cfg.pollSec !== undefined ? Math.max(2, cfg.pollSec) : 60
    readonly property string authToken: cfg.authToken || ""
    readonly property bool invert: cfg.invert === true          // true → lower is worse
    readonly property real warnAt: cfg.warnAt !== undefined && cfg.warnAt !== "" ? Number(cfg.warnAt) : NaN
    readonly property real critAt: cfg.critAt !== undefined && cfg.critAt !== "" ? Number(cfg.critAt) : NaN

    // Resolved endpoint: http(s) URL, or a local file:// path.
    readonly property string endpoint: {
        if (w.source === "file") {
            if (!w.filePath.length) return ""
            return w.filePath.indexOf("file:") === 0 ? w.filePath : ("file://" + w.filePath)
        }
        return w.url
    }
    readonly property bool configured: w.endpoint.length > 0

    readonly property string valText: cfg.httpText !== undefined ? cfg.httpText : ""
    readonly property var valNum: cfg.httpVal
    readonly property string errText: cfg.httpErr || ""
    // Raw numeric series (in-memory, this instance) used to auto-range the trend
    // line; the NORMALISED copy is persisted to the shared `hist` key so the
    // compact tile and expanded overlay draw the same sparkline.
    property var hist: []

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
    // Threshold colour, honouring the "lower is worse" (invert) direction.
    function threshColor(v) {
        if (typeof v === "number") {
            if (w.invert) {
                if (!isNaN(w.critAt) && v <= w.critAt) return theme.error
                if (!isNaN(w.warnAt) && v <= w.warnAt) return theme.warning
            } else {
                if (!isNaN(w.critAt) && v >= w.critAt) return theme.error
                if (!isNaN(w.warnAt) && v >= w.warnAt) return theme.warning
            }
        }
        return w.effAccent
    }
    readonly property color valColor: w.errText.length ? theme.warning
        : (typeof w.valNum === "number" ? threshColor(w.valNum) : theme.textPrimary)
    status: w.errText.length ? "!" : ""
    statusColor: theme.warning

    property var _xhr: null
    Component.onDestruction: { if (_xhr) _xhr.abort() }
    function _put(obj) { if (w.store && w.instanceId) w.store.patchSettings(w.instanceId, obj) }

    function refresh() {
        if (!w.configured) { _put({ httpErr: "", httpText: "", httpVal: undefined }); return }
        if (w._xhr) w._xhr.abort()
        var headers = (w.source === "http" && w.authToken.length) ? ({ "Authorization": "Bearer " + w.authToken }) : undefined
        var self = this
        w._xhr = w._hub().request({
            url: w.endpoint,
            headers: headers,
            timeout: 8000,
            xhrFactory: w.xhrFactory,
            onDone: function (status, body) {
                w._xhr = null
                self._applyBody(body)
            },
            onError: function (reason) {
                w._xhr = null
                _put({ httpErr: reason === "offline" ? "Offline"
                              : reason === "blocked" ? "Blocked"
                              : reason === "timeout" ? "Timed out" : "Unavailable" })
            }
        })
    }

    // A body may be JSON (extract via jsonPath) or a bare number/string (a plain
    // file, e.g. `echo 42 > /run/metric`). Try JSON first, then fall back to raw.
    function _applyBody(body) {
        var v
        var parsed = null, isJson = false
        try { parsed = JSON.parse(body); isJson = true } catch (e) { isJson = false }
        if (isJson) {
            v = w.jsonPath.length ? resolvePath(parsed, w.jsonPath) : parsed
        } else {
            var t = ("" + body).trim()
            var n = Number(t)
            v = (t.length && !isNaN(n)) ? n : t
        }
        if (v === undefined) { _put({ httpErr: "No match", httpText: "—" }); return }
        _apply(v)
    }

    function _apply(v) {
        var patch = { httpErr: "" }
        if (typeof v === "number") {
            patch.httpVal = v
            patch.httpText = "" + (Number.isInteger(v) ? v : (Math.abs(v) >= 100 ? Math.round(v) : v.toFixed(1)))
            var h = w.hist.slice(); h.push(v); if (h.length > 48) h.shift()
            // Normalise the sparkline against the observed range so a flat-ish KPI
            // still reads as a line (store raw in hist; Sparkline maps 0..1, so we
            // pre-normalise here against a rolling min/max).
            w.hist = h
            patch.hist = _normalise(h)
        } else if (v === null || v === undefined) {
            patch.httpVal = undefined; patch.httpText = "—"
        } else {
            patch.httpVal = undefined; patch.httpText = ("" + v).slice(0, 32)
        }
        _put(patch)
    }
    // Map a raw numeric series to 0..1 against its own min/max (a KPI has no fixed
    // scale like a percentage, so auto-range it for the trend line).
    function _normalise(arr) {
        var lo = Infinity, hi = -Infinity
        for (var i = 0; i < arr.length; i++) { if (arr[i] < lo) lo = arr[i]; if (arr[i] > hi) hi = arr[i] }
        var span = hi - lo
        var out = []
        for (var j = 0; j < arr.length; j++) out.push(span > 0 ? (arr[j] - lo) / span : 0.5)
        return out
    }
    // hist holds RAW values for range tracking; the sparkline reads the normalised
    // copy persisted alongside. Keep a normalised view for the chart.
    readonly property var histNorm: cfg.hist || []

    property string cfgKey: source + "|" + url + "|" + filePath + "|" + jsonPath + "|" + authToken
    onCfgKeyChanged: if (w.active) fetchDebounce.restart()
    onActiveChanged: if (w.active) fetchDebounce.restart()
    Component.onCompleted: if (w.active) fetchDebounce.restart()
    Timer { id: fetchDebounce; interval: 300; onTriggered: w.refresh() }
    Timer { interval: Math.max(2, w.pollSec) * 1000; repeat: true
            running: w.active && w.configured; onTriggered: w.refresh() }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: w.expanded ? 10 : 4
        spacing: w.expanded ? 8 : 2

        Text {
            visible: !w.configured
            Layout.fillWidth: true; Layout.fillHeight: true
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            text: "Connect a URL or file\nin settings"
            color: theme.textTertiary; font.pixelSize: w.expanded ? 16 : 12
        }

        Item { Layout.fillHeight: true; visible: w.configured }

        // The big number.
        RowLayout {
            visible: w.configured
            Layout.alignment: Qt.AlignHCenter; spacing: 4
            Text {
                text: w.errText.length ? "—" : (w.valText.length ? w.valText : "…")
                font.pixelSize: w.expanded ? 88 : 40; font.bold: true; color: w.valColor
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: 16; elide: Text.ElideRight
                Layout.maximumWidth: w.width - 20
            }
            Text {
                visible: w.unit.length > 0 && !w.errText.length
                text: w.unit; font.pixelSize: w.expanded ? 26 : 15; color: theme.textSecondary
                Layout.alignment: Qt.AlignBottom; bottomPadding: w.expanded ? 16 : 6
            }
        }

        // Label / error line.
        Text {
            visible: w.configured
            Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            text: w.errText.length ? w.errText : (w.label.length ? w.label : w.title)
            color: w.errText.length ? theme.warning : theme.textSecondary
            font.pixelSize: w.expanded ? 18 : 13
        }

        Sparkline {
            visible: w.configured && w.histNorm.length > 1 && !w.errText.length
            Layout.fillWidth: true; Layout.preferredHeight: w.expanded ? 70 : 26
            values: w.histNorm; color: w.valColor
        }

        Item { Layout.fillHeight: true; visible: w.configured }
    }

    Rectangle {
        visible: !w.expanded && w.configured
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
