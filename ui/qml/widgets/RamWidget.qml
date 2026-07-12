import QtQuick
import QtQuick.Layouts

// Memory usage — real data from the Rust core.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Memory"; iconName: "ram"; accentColor: theme.catProductivity
    big: expanded

    // Live per-instance config (see WidgetConfigSchema "ram").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string unit: cfg.unit !== undefined ? cfg.unit : "percent"
    readonly property bool showHistory: cfg.showHistory !== undefined ? cfg.showHistory : true

    property real v: metrics.ram_usage_percent || 0
    function col(p) { return p > 90 ? theme.error : p > 75 ? theme.warning : theme.catProductivity }
    function gb(b) { return (b / 1073741824).toFixed(1) }

    property var hist: []
    onMetricsChanged: {
        var h = w.hist.slice(); h.push(w.v / 100)
        if (h.length > 48) h.shift()
        w.hist = h
    }

    MetricGauge {
        anchors.fill: parent
        value: Math.min(w.v / 100, 1)
        big: w.unit === "gb" ? ((metrics.ram_used_bytes || 0) / 1073741824).toFixed(1) + " GB"
                             : w.v.toFixed(0) + "%"
        sub: w.gb(metrics.ram_used_bytes || 0) + " / " + w.gb(metrics.ram_total_bytes || 0) + " GB"
        color: w.col(w.v)
        history: w.showHistory ? w.hist : []
        expanded: w.expanded
    }
}
