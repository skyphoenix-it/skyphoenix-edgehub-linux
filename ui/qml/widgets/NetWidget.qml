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
//   • full (overlay)  — rates left, peaks right, big sparkline below; SIZED by the
//                       pane it is actually given (see rateFont), not by literals.
//                       "full" is NOT a full screen: Dashboard hosts the overlay's
//                       live preview in a pane beside the config form — ~941x456 in
//                       landscape, ~656x980 stacked in portrait — so it is a class
//                       like any other and reads its own box.
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

    // Does this instance have half-screen room? The same predicate HabitWidget
    // derives, for the same reason: Dashboard injects a sizeClass, never a size
    // NAME, so the question has to be answered from the room itself. Among the
    // sizes this widget declares, 1x1.5 is the only one that is BOTH off-square and
    // full-short-axis (696x1229 portrait / 1269x612 landscape, short side >= 612),
    // where 0.5x1 and 1x0.5 stop at 423 — so WidgetChrome's own 480 half-cell
    // threshold separates them here too, with no size-name special case. `large`
    // and `full` are roomier still; this widget declares no `large` tile, but it
    // must not read as cramped if it ever does.
    readonly property bool roomy: sizeClass === "large" || sizeClass === "full"
        || ((sizeClass === "tall" || sizeClass === "wide")
            && Math.min(width, height) >= 480)

    // Session peaks earn a place wherever there is room beyond the baseline:
    // the overlay (as before), and now also tall/wide tiles.
    // The `expanded ||` this used to lead with was already DEAD — the overlay is
    // injected as sizeClass "full", which `big` already covers — but it said the
    // decision was partly the overlay's, which is the habit being removed.
    readonly property bool showPeaks: !micro && (big || horiz)

    // Rate text scales with the box: the micro tile IS the two numbers.
    //
    // This used to open with `expanded ? 30`, a literal frozen twice over: it
    // ignored the box it was actually in, and it never noticed when W5 shrank the
    // overlay's live-preview pane to 38% of the width in landscape. Worse, 30 beat
    // the 26 a 1x1.5 tile got — a tile with FAR more room than that pane.
    //
    // The height term is new and binds nowhere on a shipped tile (the 26 cap
    // already did): it exists so the overlay's short 456px landscape pane cannot
    // let width alone overreach. Only `roomy` boxes are allowed past 26.
    readonly property real rateFont: micro
        ? Math.max(20, Math.min(width * 0.115, 38))
        : (big || horiz)
        ? Math.max(16, Math.min(width * 0.05, height * 0.09, w.roomy ? 40 : 26))
        : Math.max(15, Math.min(width * 0.032, 22))

    GridLayout {
        id: lay
        anchors.fill: parent
        anchors.margins: theme.spacingSm
        columns: w.horiz ? 2 : 1
        // Air is room, not mode. 10 was "the overlay" and 4 "not the overlay";
        // what earns the wider gap is having the space for it, which is the same
        // `roomy` predicate rateFont's cap uses — so a 1x1.5 tile, whose rates are
        // now ~35px, gets the breathing room its own contents ask for instead of
        // the baseline third's tighter 4. Compact/micro tiles are unchanged.
        rowSpacing: w.roomy ? 10 : 4
        columnSpacing: theme.spacingLg

        // Rates block (+ peaks beside in the overlay, beneath on tall/wide).
        GridLayout {
            // DELIBERATELY still keyed off the mode, with `alignment` below — and
            // the second of the two legitimate cases in this file (see `status` on
            // WidgetChrome). This is COMPOSITION — which side the peaks sit on —
            // not a dimension. No box measurement makes one arrangement correct:
            // a 696-wide 1x1.5 tile and the 656-wide portrait overlay pane have
            // effectively the same width and genuinely want different compositions,
            // because one is a thing you glance at and the other is the thing you
            // opened. `expanded` is the honest question there. Sizes are not
            // allowed to ask it; what-goes-where is.
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
                    font.family: theme.fontMono; font.pixelSize: Math.round(w.rateFont)
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10
                    Layout.fillWidth: true; elide: Text.ElideRight
                    horizontalAlignment: w.micro ? Text.AlignHCenter : Text.AlignLeft }
                Text { text: "↑ " + w.fmt(w.tx); color: w.effAccent; font.bold: true
                    font.family: theme.fontMono; font.pixelSize: Math.round(w.rateFont)
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10
                    Layout.fillWidth: true; elide: Text.ElideRight
                    horizontalAlignment: w.micro ? Text.AlignHCenter : Text.AlignLeft }
            }
            // Session peaks — "best so far". Right-aligned beside the rates in
            // the overlay; a quiet line under them on tall/wide tiles.
            // The peaks are a SECONDARY readout of the rates, so they are sized
            // from the rates rather than re-deriving the box: `expanded ? 14`
            // cost nothing to drop on its own (both overlay panes drive the old
            // width term straight into its own 14 cap), but it left the peaks
            // pinned at 14 next to a rate number that had grown to 40. Tied to
            // rateFont they stay legible against it at every box. The `alignment`
            // ternaries below are composition, not size — see `columns` above.
            ColumnLayout {
                visible: w.showPeaks; spacing: 0
                Layout.alignment: w.expanded ? (Qt.AlignRight | Qt.AlignVCenter) : Qt.AlignLeft
                Text { text: "peak ↓ " + w.fmt(w.peakRx); color: theme.textTertiary
                    font.family: theme.fontMono
                    font.pixelSize: Math.round(Math.max(11, Math.min(w.rateFont * 0.52, 20)))
                    horizontalAlignment: w.expanded ? Text.AlignRight : Text.AlignLeft
                    Layout.alignment: w.expanded ? Qt.AlignRight : Qt.AlignLeft }
                Text { text: "peak ↑ " + w.fmt(w.peakTx); color: theme.textTertiary
                    font.family: theme.fontMono
                    font.pixelSize: Math.round(Math.max(11, Math.min(w.rateFont * 0.52, 20)))
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
