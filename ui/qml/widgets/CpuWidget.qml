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
    // Temperature is the real warning signal — escalate the WHOLE gauge (ring +
    // number) on it, not just the tiny header text. Otherwise reflect load, in the
    // widget's own accent while comfortable.
    function col(p) {
        if (w.showTemp && w.temp > 0) {
            if (w.temp > w.warnTemp) return theme.error
            if (w.temp > w.warnTemp - 12) return theme.warning
        }
        return p > 90 ? theme.error : p > 70 ? theme.warning : w.effAccent
    }

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
        // Temp lives in the header (top-right) — the sub-line only adds core count
        // in expanded, so the reading isn't printed twice.
        sub: w.expanded ? ((metrics.cpu_core_count || 0) + " cores") : ""
        color: w.col(w.v)
        history: w.showHistory ? w.hist : []
        expanded: w.expanded
    }
}
