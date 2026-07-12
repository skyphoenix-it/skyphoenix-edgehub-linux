import QtQuick
import QtQuick.Layouts

// Root-filesystem usage — real data (statvfs via the Rust core).
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Disk"; iconName: "disk"; accentColor: theme.catInfo
    big: expanded

    // Live per-instance config (see WidgetConfigSchema "disk").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property real warnPercent: cfg.warnPercent !== undefined ? cfg.warnPercent : 90

    property real v: metrics.disk_usage_percent || 0
    // Amber over the warn line, red when critically full (a nearly-full disk
    // shouldn't look the same as one just over the threshold).
    function col(p) {
        if (p >= 97) return theme.error
        if (p > w.warnPercent) return theme.warning
        return w.effAccent
    }
    function human(b) {
        if (b >= 1099511627776) return (b / 1099511627776).toFixed(2) + " TB"
        return (b / 1073741824).toFixed(0) + " GB"
    }
    readonly property real freeBytes: Math.max(0, (metrics.disk_total_bytes || 0) - (metrics.disk_used_bytes || 0))

    // Disk usage barely changes; the gauge carries it, no sparkline needed.
    MetricGauge {
        anchors.fill: parent
        value: Math.min(w.v / 100, 1)
        big: w.v.toFixed(0) + "%"
        sub: w.expanded
             ? (w.human(metrics.disk_used_bytes || 0) + " / " + w.human(metrics.disk_total_bytes || 0)
                + "  ·  " + w.human(w.freeBytes) + " free")
             : (w.human(metrics.disk_used_bytes || 0) + " / " + w.human(metrics.disk_total_bytes || 0))
        color: w.col(w.v)
        expanded: w.expanded
    }
}
