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
//
// Sizing (W1 wave 2b): this is THE number-first widget — its whole point is one
// figure read from across a room — so the number is sized off the BOX at every
// size, not off `expanded`. It used to be a flat 40px in every tile and 88px in
// the overlay, which left a 40px digit floating in a 696x819 baseline tile and
// made `1x3` (the whole 720x2560 panel) a scaled-up tile rather than a billboard.
//   • 0.5x0.5 (micro) — the number alone. No label, no trend, no refresh button:
//                       a 1/12 tile is a READOUT, and a control that cannot hold
//                       52px does not belong on it (it lives in the overlay).
//   • 1x1 (baseline)  — number + unit + label + trend.
//   • wide / tall     — the same content; a genuinely wide box (0.5x1 landscape,
//                       1x0.5 portrait, 1x1.5 landscape) puts the trend BESIDE
//                       the number instead of under it.
//   • large (1x2/1x3) — the billboard: the number at its width cap, the trend
//                       absorbing the slack height, plus a min/avg/max strip —
//                       real extra information, not a stretched card.
//   • full (overlay)  — the billboard plus the stats strip.
//
// A NOTE ON THE PORTRAIT CAP. The number is WIDTH-limited: the panel's short axis
// is 720px, so `1x1` and `1x3` are the same width and the digits genuinely cannot
// grow much between them. What `1x3` earns is vertical — a far taller trend, a
// bigger label and the stats strip. In LANDSCAPE the same size is 2540x612, and
// there the split billboard lets the number run to the height cap. That asymmetry
// is the honest consequence of a rotating panel, not a layout bug.
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
    // Micro drops the header: 36px of chrome out of a 409px-tall tile buys a title
    // the number does not need (it has no label at that size either — see below).
    showHeader: !micro

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
        var self = this
        w._xhr = w._hub().request({
            url: w.endpoint,
            // Stored value (may be a ${env:}/file: ref); NetHub resolves it. Only
            // the http source authenticates — the local-file source reads a path
            // and must never send a credential anywhere.
            authToken: w.source === "http" ? w.authToken : "",
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

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    // `large` (1x2 / 1x3) is large in BOTH orientations, and `wide` projects to
    // two very different boxes, so the SHAPE has to be read off the geometry —
    // the class alone cannot tell 696x2459 from 2540x612. (`micro` is chrome's.)
    readonly property bool roomy: sizeClass === "large"
    readonly property bool split: (roomy || sizeClass === "wide") && width > height * 1.4
    // How many characters the number is. A KPI's legibility is digit-count
    // dependent — "7" and "1284.5" cannot take the same pixelSize in the same box.
    readonly property int _valChars: Math.max(1, w.errText.length ? 1 : (w.valText.length || 1))
    // Estimated advance width of the display font's digits, as a fraction of
    // pixelSize, plus the unit's share (it is a sibling Text, ~30% of the value's
    // size and 1-2 glyphs). Sizing the number TO FIT beats leaning on
    // fontSizeMode: HorizontalFit shrinks the glyphs but NOT the Text's line box,
    // so the unit — which aligns to that box — floats away from the baseline, and
    // the oversized implicit width collapsed the trend column to a sliver in every
    // split layout. HorizontalFit stays below purely as a backstop.
    readonly property real _digitRatio: 0.62
    readonly property real _unitTerm: (w.unit.length > 0 && !w.errText.length) ? 0.42 : 0
    // The number's width budget: the whole body, or half of it when split.
    readonly property real _boxW: Math.max(40, (w.split ? lay.width * 0.5 : lay.width) - 8)
    readonly property real _fitPx: w._boxW / (w._valChars * w._digitRatio + w._unitTerm)
    // The number scales to its box, clamped per shape so it reads as a figure
    // rather than a wall.
    readonly property real valuePx: expanded ? 150
        : Math.max(18, Math.min(w._fitPx,
            w.micro ? w.height * 0.45 : w.split ? w.height * 0.55 : w.height * 0.30,
            w.micro ? 200 : w.split ? 340 : 300))
    readonly property real unitPx: Math.max(10, w.valuePx * 0.30)
    readonly property real labelPx: expanded ? 18 : Math.max(11, Math.min(w.valuePx * 0.16, 44))
    // Micro is a readout: the number is the whole tile.
    readonly property bool showLabel: !w.micro
    readonly property bool showSpark: !w.micro && w.histNorm.length > 1 && !w.errText.length
    // min / avg / max over the trend window — genuinely MORE information, so it
    // is earned by the sizes with room instead of being overlay-only.
    readonly property bool showStats: (w.expanded || w.roomy) && w.hist.length > 1
    readonly property var stats: {
        var a = w.hist
        if (!a.length) return null
        var lo = Infinity, hi = -Infinity, sum = 0
        for (var i = 0; i < a.length; i++) { if (a[i] < lo) lo = a[i]; if (a[i] > hi) hi = a[i]; sum += a[i] }
        return { min: lo, max: hi, avg: sum / a.length }
    }
    function fmt(v) {
        if (typeof v !== "number" || !isFinite(v)) return "—"
        return Number.isInteger(v) ? "" + v : (Math.abs(v) >= 100 ? "" + Math.round(v) : v.toFixed(1))
    }

    property string cfgKey: source + "|" + url + "|" + filePath + "|" + jsonPath + "|" + authToken
    onCfgKeyChanged: if (w.active) fetchDebounce.restart()
    onActiveChanged: if (w.active) fetchDebounce.restart()
    Component.onCompleted: if (w.active) fetchDebounce.restart()
    Timer { id: fetchDebounce; interval: 300; onTriggered: w.refresh() }
    Timer { interval: Math.max(2, w.pollSec) * 1000; repeat: true
            running: w.active && w.configured; onTriggered: w.refresh() }

    Text {
        anchors.centerIn: parent
        visible: !w.configured
        width: parent.width - 2 * theme.spacingSm
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        text: w.micro ? "No source" : "Connect a URL or file\nin settings"
        color: theme.textTertiary; font.pixelSize: w.expanded ? 16 : 12
    }

    // The number, the trend, and (where earned) the stats. `columns` flips for a
    // genuinely wide box, which only RESHAPES — the same items, never rebuilt.
    GridLayout {
        id: lay
        anchors.fill: parent
        anchors.margins: w.expanded ? 10 : (w.micro ? 6 : 4)
        // Reserve the refresh button's corner instead of letting content slide
        // under it (at 1x3 the stats strip did exactly that, and the button ate
        // the `max` value).
        anchors.bottomMargin: refreshBtn.visible
            ? theme.touchTertiary + 2 * theme.spacingXs : anchors.margins
        visible: w.configured
        columns: w.split ? 2 : 1
        rowSpacing: w.expanded ? 8 : 2
        columnSpacing: theme.spacingLg

        // ── The number + its label ──
        ColumnLayout {
            Layout.fillWidth: true
            // Takes ALL the slack a stacked box has left over, so the trend sits
            // at the bottom and the number owns the rest. (No Layout.alignment
            // here: setting it cancels fillHeight, which left a dead band under
            // the 1x3 stats strip.) The spacers do the centring instead.
            Layout.fillHeight: !w.split
            // Hold the split at an even two columns: the value Text's implicit
            // width is enormous and would otherwise starve the trend beside it.
            Layout.maximumWidth: w.split ? lay.width * 0.5 : Number.POSITIVE_INFINITY
            spacing: 0

            Item { Layout.fillHeight: true; visible: !w.split }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 4
                Text {
                    id: valueText
                    text: w.errText.length ? "—" : (w.valText.length ? w.valText : "…")
                    font.pixelSize: Math.round(w.valuePx); font.bold: true; color: w.valColor
                    font.family: theme.fontDisplay
                    // valuePx (char-count based) is the real fit; HorizontalFit +
                    // maximumWidth are the backstop. NOT preferredWidth: this value
                    // sits in a [value][unit] row, and forcing the value to the full
                    // box width shoved the unit out and left-aligned the number
                    // off-centre. maximumWidth alone caps without forcing a wide box,
                    // so the row stays centred and a stray-long value still can't
                    // overrun the tile.
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: 14; elide: Text.ElideRight
                    Layout.maximumWidth: w._boxW
                }
                Text {
                    id: unitText
                    visible: w.unit.length > 0 && !w.errText.length
                    text: w.unit; font.pixelSize: Math.round(w.unitPx); color: theme.textSecondary
                    Layout.alignment: Qt.AlignBottom
                    bottomPadding: Math.round(w.valuePx * 0.16)
                }
            }

            // Label / error line — dropped on micro, where the number IS the tile.
            Text {
                visible: w.showLabel
                Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                text: w.errText.length ? w.errText : (w.label.length ? w.label : w.title)
                color: w.errText.length ? theme.warning : theme.textSecondary
                font.pixelSize: Math.round(w.labelPx)
            }

            Item { Layout.fillHeight: true; visible: !w.split }
        }

        // ── The trend, and the stats it explains ──
        ColumnLayout {
            visible: w.showSpark || w.showStats
            Layout.fillWidth: true
            // Only a SPLIT box hands its slack to the trend column (there the two
            // columns are side by side and the trend has the full height to use).
            // A stacked box gives the slack to the NUMBER — see the Sparkline.
            Layout.fillHeight: w.split
            spacing: theme.spacingXs

            Sparkline {
                visible: w.showSpark
                Layout.fillWidth: true
                Layout.fillHeight: w.split
                // The trend SUPPORTS the number; it does not replace it. On
                // fillHeight it took ~60% of a 1x3 panel and the widget stopped
                // being a KPI — so it takes a FRACTION of the box (a bigger one
                // once there is room) and the value block absorbs the rest.
                Layout.preferredHeight: w.expanded ? 70
                    : Math.max(20, Math.min(w.height * (w.roomy ? 0.26 : 0.16),
                                            w.roomy ? 640 : 120))
                values: w.histNorm; color: w.valColor
            }
            // min / avg / max over the window — the large sizes' extra content.
            RowLayout {
                visible: w.showStats
                Layout.fillWidth: true
                spacing: theme.spacingMd
                Repeater {
                    // A STATIC label model: the three cells live for the widget's
                    // whole life and only their bound values move. Binding this to
                    // a derived array would rebuild all three on every poll.
                    model: ["min", "avg", "max"]
                    delegate: ColumnLayout {
                        id: statCell
                        required property string modelData
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                            text: statCell.modelData
                            color: theme.textTertiary; font.pixelSize: Math.round(w.labelPx * 0.7)
                            font.letterSpacing: 1
                        }
                        Text {
                            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                            text: w.stats ? w.fmt(w.stats[statCell.modelData]) : "—"
                            color: theme.textSecondary; font.family: theme.fontMono
                            font.pixelSize: Math.round(w.labelPx); elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // Manual refresh. A real ≥52px target (it was 34px — under theme.touchTertiary),
    // and it is NOT shown on micro: a 1/12 tile cannot host a control at that size,
    // so it stays a readout and the button lives in the overlay instead — which is
    // also why the overlay now has one at all.
    Rectangle {
        id: refreshBtn
        visible: w.configured && !w.micro
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.rightMargin: theme.spacingXs; anchors.bottomMargin: theme.spacingXs
        width: theme.touchTertiary; height: theme.touchTertiary; radius: width / 2
        color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b,
                       rMA.pressed ? 0.32 : (rMA.containsMouse ? 0.22 : 0.14))
        Text { anchors.centerIn: parent; text: "⟳"; font.pixelSize: 24; color: w.effAccent }
        MouseArea { id: rMA; anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor; onClicked: w.refresh() }
    }
}
