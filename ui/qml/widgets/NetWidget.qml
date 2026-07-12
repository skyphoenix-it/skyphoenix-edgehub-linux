import QtQuick
import QtQuick.Layouts

// Network throughput — real up/down byte-rates from the Rust core, with a
// live sparkline of recent activity (history kept in-widget).
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Network"; iconName: "net"; accentColor: theme.catServices
    big: expanded

    // Live per-instance config (see WidgetConfigSchema "net").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? store.settingsFor(instanceId) : ({})
    }
    readonly property bool showHistory: cfg.showHistory !== undefined ? cfg.showHistory : true
    readonly property string unit: cfg.unit !== undefined ? cfg.unit : "bytes"

    property real rx: metrics.net_rx_bytes_per_sec || 0
    property real tx: metrics.net_tx_bytes_per_sec || 0
    property var hist: []
    function fmt(bps) {
        if (w.unit === "bits") return (bps * 8 / 1e6).toFixed(1) + " Mbps"
        if (bps >= 1048576) return (bps / 1048576).toFixed(1) + " MB/s"
        if (bps >= 1024) return (bps / 1024).toFixed(0) + " KB/s"
        return Math.round(bps) + " B/s"
    }

    onMetricsChanged: {
        hist.push({ r: rx, t: tx })
        if (hist.length > 60) hist.shift()
        spark.requestPaint()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.spacingSm
        spacing: w.expanded ? 10 : 4

        RowLayout {
            Layout.fillWidth: true; spacing: theme.spacingLg
            ColumnLayout {
                spacing: 0
                Text { text: "↓ " + w.fmt(w.rx); color: theme.success; font.bold: true
                    font.family: theme.fontMono; font.pixelSize: w.expanded ? 30 : 15 }
                Text { text: "↑ " + w.fmt(w.tx); color: theme.accent; font.bold: true
                    font.family: theme.fontMono; font.pixelSize: w.expanded ? 30 : 15 }
            }
            Item { Layout.fillWidth: true }
        }

        Canvas {
            id: spark
            visible: w.showHistory
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
                line("t", theme.accent)
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }
}
