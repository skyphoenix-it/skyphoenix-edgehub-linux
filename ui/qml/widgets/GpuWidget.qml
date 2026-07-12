import QtQuick
import QtQuick.Layouts

// GPU utilization + temperature — real data (amdgpu sysfs via the Rust core).
// Shows "N/A" gracefully when no discrete GPU is discoverable.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "GPU"; iconName: "gpu"; accentColor: theme.catGaming
    big: expanded

    // Live per-instance config (see WidgetConfigSchema "gpu").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? store.settingsFor(instanceId) : ({})
    }
    readonly property bool showTemp: cfg.showTemp !== undefined ? cfg.showTemp : true
    readonly property bool showHistory: cfg.showHistory !== undefined ? cfg.showHistory : true
    readonly property real warnTemp: cfg.warnTemp !== undefined ? cfg.warnTemp : 90

    property bool avail: metrics.gpu_usage_percent !== undefined
                         && metrics.gpu_usage_percent !== null
                         && metrics.gpu_usage_percent >= 0
    property real v: avail ? metrics.gpu_usage_percent : 0
    property real temp: (metrics.gpu_temp_celsius === undefined || metrics.gpu_temp_celsius === null || metrics.gpu_temp_celsius < 0)
                        ? -1 : metrics.gpu_temp_celsius
    status: (w.showTemp && temp > 0) ? temp.toFixed(0) + "°C" : ""
    statusColor: temp > w.warnTemp ? theme.error : temp > w.warnTemp - 17 ? theme.warning : theme.textSecondary
    function col(p) { return p > 90 ? theme.error : p > 65 ? theme.warning : theme.catGaming }

    property var hist: []
    onMetricsChanged: {
        if (!w.avail) return
        var h = w.hist.slice(); h.push(w.v / 100)
        if (h.length > 48) h.shift()
        w.hist = h
    }

    MetricGauge {
        anchors.fill: parent
        ok: w.avail
        value: Math.min(w.v / 100, 1)
        big: w.avail ? w.v.toFixed(0) + "%" : "N/A"
        sub: w.avail && w.showTemp && w.temp > 0 ? w.temp.toFixed(0) + "°C" : ""
        color: w.col(w.v)
        history: w.showHistory ? w.hist : []
        expanded: w.expanded
    }
}
