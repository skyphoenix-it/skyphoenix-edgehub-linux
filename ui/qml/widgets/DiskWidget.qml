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
    function col(p) { return p > w.warnPercent ? theme.warning : theme.catInfo }
    function human(b) {
        if (b >= 1099511627776) return (b / 1099511627776).toFixed(2) + " TB"
        return (b / 1073741824).toFixed(0) + " GB"
    }

    // Disk usage barely changes; the gauge carries it, no sparkline needed.
    MetricGauge {
        anchors.fill: parent
        value: Math.min(w.v / 100, 1)
        big: w.v.toFixed(0) + "%"
        sub: w.human(metrics.disk_used_bytes || 0) + " / " + w.human(metrics.disk_total_bytes || 0)
        color: w.col(w.v)
        expanded: w.expanded
    }
}
