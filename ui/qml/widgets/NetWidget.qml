import QtQuick
import QtQuick.Layouts

// Network throughput — real up/down byte-rates from the Rust core, with a
// live sparkline of recent activity (history kept in-widget).
//
// Sizing (W1 wave 2a): layout keys off the injected `sizeClass`.
//   • 0.5x0.5 (micro) — headerless; the two rates, big and centred. No graph.
//   • 1x1 (baseline)  — rates row above the sparkline (the classic tile).
//   • wide            — rates (+ session peaks) beside a full-width sparkline.
//   • tall            — rates + session peaks above a sparkline that earns the
//                       height (peaks are genuinely more information).
//   • full (overlay)  — rates left, peaks right, big sparkline below.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Network"; iconName: "net"; accentColor: theme.catServices
    showHeader: !micro

    // Live per-instance config (see WidgetConfigSchema "net").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property bool showHistory: cfg.showHistory !== undefined ? cfg.showHistory : true
    readonly property string unit: cfg.unit !== undefined ? cfg.unit : "bytes"

    property real rx: metrics.net_rx_bytes_per_sec || 0
    property real tx: metrics.net_tx_bytes_per_sec || 0
    property real peakRx: 0
    property real peakTx: 0
    property var hist: []
    function fmt(bps) {
        if (w.unit === "bits") {
            var mb = bps * 8 / 1e6
            // Step down to Kbps for small values so it doesn't read "0.0 Mbps".
            return mb < 1 ? (bps * 8 / 1e3).toFixed(0) + " Kbps" : mb.toFixed(1) + " Mbps"
        }
        // Round to whole bytes FIRST, then pick the unit — otherwise a value like
        // 1023.7 takes the B/s branch and rounds up to a nonsensical "1024 B/s".
        var b = Math.round(bps)
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB/s"
        if (b >= 1024) return (b / 1024).toFixed(0) + " KB/s"
        return b + " B/s"
    }

    // Session peaks + sparkline history live in the shared store (keyed by
    // instanceId) so a tile and its expanded overlay — separate instances — share
    // the same accumulated state instead of resetting to 0/empty on every open (S5).
    function _persist() {
        if (!store || !instanceId) return
        store.patchSettings(instanceId, { hist: w.hist, peakRx: w.peakRx, peakTx: w.peakTx })
    }
    function _restoreState() {
        if (!store || !instanceId) return
        var s = store.settingsFor(instanceId)
        if (s.hist !== undefined) w.hist = JSON.parse(JSON.stringify(s.hist))
        if (s.peakRx !== undefined) w.peakRx = s.peakRx
        if (s.peakTx !== undefined) w.peakTx = s.peakTx
        spark.requestPaint()
    }
    onStoreChanged: _restoreState()

    onMetricsChanged: {
        // Honour `active`: an off-page/hidden instance must not keep accumulating
        // (S3). Read the freshly-changed `metrics` directly — the derived rx/tx
        // bindings lag one frame behind this handler.
        if (!w.active) return
        var m = w.metrics || ({})
        var r = m.net_rx_bytes_per_sec
        var t = m.net_tx_bytes_per_sec
        // Skip frames with no net data so history isn't poisoned with fake 0s (S4).
        if (r === undefined && t === undefined) return
        r = r || 0; t = t || 0
        hist.push({ r: r, t: t })
        if (hist.length > 60) hist.shift()
        if (r > peakRx) peakRx = r
        if (t > peakTx) peakTx = t
        _persist()
        spark.requestPaint()
    }
    onEffAccentChanged: spark.requestPaint()

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    readonly property bool horiz: sizeClass === "wide"
    // Session peaks earn a place wherever there is room beyond the baseline:
    // the overlay (as before), and now also tall/wide tiles.
    readonly property bool showPeaks: !micro && (expanded || big || horiz)
    // Rate text scales with the box: the micro tile IS the two numbers.
    readonly property real rateFont: expanded ? 30
        : micro ? Math.max(20, Math.min(width * 0.115, 38))
        : (big || horiz) ? Math.max(16, Math.min(width * 0.05, 26))
        : Math.max(15, Math.min(width * 0.032, 22))

    GridLayout {
        id: lay
        anchors.fill: parent
        anchors.margins: theme.spacingSm
        columns: w.horiz ? 2 : 1
        rowSpacing: w.expanded ? 10 : 4
        columnSpacing: theme.spacingLg

        // Rates block (+ peaks beside in the overlay, beneath on tall/wide).
        GridLayout {
            columns: w.expanded ? 2 : 1
            rowSpacing: 2; columnSpacing: theme.spacingLg
            Layout.fillWidth: !w.horiz
            // micro (no graph): the rates are the tile — centre them in it.
            Layout.fillHeight: w.micro || !w.showHistory
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: w.horiz ? Math.round(lay.width * 0.36) : -1

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: w.micro ? 2 : 0
                Text { text: "↓ " + w.fmt(w.rx); color: theme.success; font.bold: true
                    font.family: theme.fontMono; font.pixelSize: w.rateFont
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10
                    Layout.fillWidth: true; elide: Text.ElideRight
                    horizontalAlignment: w.micro ? Text.AlignHCenter : Text.AlignLeft }
                Text { text: "↑ " + w.fmt(w.tx); color: w.effAccent; font.bold: true
                    font.family: theme.fontMono; font.pixelSize: w.rateFont
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10
                    Layout.fillWidth: true; elide: Text.ElideRight
                    horizontalAlignment: w.micro ? Text.AlignHCenter : Text.AlignLeft }
            }
            // Session peaks — "best so far". Right-aligned beside the rates in
            // the overlay; a quiet line under them on tall/wide tiles.
            ColumnLayout {
                visible: w.showPeaks; spacing: 0
                Layout.alignment: w.expanded ? (Qt.AlignRight | Qt.AlignVCenter) : Qt.AlignLeft
                Text { text: "peak ↓ " + w.fmt(w.peakRx); color: theme.textTertiary
                    font.family: theme.fontMono
                    font.pixelSize: w.expanded ? 14 : Math.max(11, Math.min(w.width * 0.03, 14))
                    horizontalAlignment: w.expanded ? Text.AlignRight : Text.AlignLeft
                    Layout.alignment: w.expanded ? Qt.AlignRight : Qt.AlignLeft }
                Text { text: "peak ↑ " + w.fmt(w.peakTx); color: theme.textTertiary
                    font.family: theme.fontMono
                    font.pixelSize: w.expanded ? 14 : Math.max(11, Math.min(w.width * 0.03, 14))
                    horizontalAlignment: w.expanded ? Text.AlignRight : Text.AlignLeft
                    Layout.alignment: w.expanded ? Qt.AlignRight : Qt.AlignLeft }
            }
        }

        Canvas {
            id: spark
            visible: w.showHistory && !w.micro
            Layout.fillWidth: true; Layout.fillHeight: true
            onPaint: {
                var ctx = getContext('2d'); ctx.clearRect(0, 0, width, height)
                if (w.hist.length < 2 || width <= 0 || height <= 0) return
                var max = 1
                for (var i = 0; i < w.hist.length; i++)
                    max = Math.max(max, w.hist[i].r, w.hist[i].t)
                function line(key, color) {
                    ctx.beginPath()
                    for (var j = 0; j < w.hist.length; j++) {
                        var x = j * width / (w.hist.length - 1)
                        var y = height - (w.hist[j][key] / max) * height * 0.92 - 2
                        j === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
                    }
                    ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.stroke()
                }
                line("r", theme.success)
                line("t", w.effAccent)
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }
}
