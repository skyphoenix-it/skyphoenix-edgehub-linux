import QtQuick
import QtQuick.Layouts

// CPU utilization + temperature — real data from the Rust core (metricsJson).
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "CPU"; iconName: "cpu"; accentColor: theme.catSystem
    big: expanded

    // Live per-instance config (see WidgetConfigSchema "cpu").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property bool showTemp: cfg.showTemp !== undefined ? cfg.showTemp : true
    readonly property bool showHistory: cfg.showHistory !== undefined ? cfg.showHistory : true
    readonly property real warnTemp: cfg.warnTemp !== undefined ? cfg.warnTemp : 85

    property real v: metrics.cpu_usage_percent || 0
    property real temp: (metrics.cpu_temp_celsius === undefined || metrics.cpu_temp_celsius === null) ? -1 : metrics.cpu_temp_celsius
    status: (w.showTemp && temp > 0) ? temp.toFixed(0) + "°C" : ""
    statusColor: temp > w.warnTemp ? theme.error : temp > w.warnTemp - 17 ? theme.warning : theme.textSecondary
    function col(p) { return p > 85 ? theme.error : p > 60 ? theme.warning : theme.catSystem }

    property var hist: []
    onMetricsChanged: {
        var h = w.hist.slice(); h.push(w.v / 100)
        if (h.length > 48) h.shift()
        w.hist = h
    }

    MetricGauge {
        anchors.fill: parent
        value: Math.min(w.v / 100, 1)
        big: w.v.toFixed(0) + "%"
        sub: w.expanded ? ((metrics.cpu_core_count || 0) + " cores"
                           + (w.showTemp && w.temp > 0 ? "  ·  " + w.temp.toFixed(0) + "°C" : ""))
                        : (w.showTemp && w.temp > 0 ? w.temp.toFixed(0) + "°C" : "")
        color: w.col(w.v)
        history: w.showHistory ? w.hist : []
        expanded: w.expanded
    }
}
