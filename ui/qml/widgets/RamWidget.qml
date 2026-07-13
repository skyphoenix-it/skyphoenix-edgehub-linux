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

    // Availability: a real usage reading has actually arrived (mirror GpuWidget).
    // Before the first frame — or on a partial frame missing the percent — the
    // tile must show a placeholder, not a confident fabricated 0%.
    property bool avail: metrics.ram_usage_percent !== undefined
                         && metrics.ram_usage_percent !== null
                         && metrics.ram_usage_percent >= 0
    property real v: avail ? metrics.ram_usage_percent : 0
    property real usedBytes: metrics.ram_used_bytes || 0
    property real totalBytes: metrics.ram_total_bytes || 0
    property bool haveBytes: totalBytes > 0
    function col(p) { return p > 90 ? theme.error : p > 75 ? theme.warning : w.effAccent }
    function gb(b) { return (b / 1073741824).toFixed(1) }

    property var hist: []
    onMetricsChanged: {
        // Honor the single-driver `active` gate, and read availability straight
        // from the incoming frame (the `avail`/`v` bindings settle a tick later)
        // so a frame without a usage reading never seeds a spurious 0.
        if (!w.active) return
        var p = metrics.ram_usage_percent
        if (p === undefined || p === null || p < 0) return
        var h = w.hist.slice(); h.push(Math.max(0, Math.min(1, p / 100)))
        if (h.length > 48) h.shift()
        w.hist = h
    }

    MetricGauge {
        anchors.fill: parent
        ok: w.avail
        value: Math.min(w.v / 100, 1)
        big: !w.avail ? "N/A"
           : w.unit === "gb" ? (w.haveBytes ? w.gb(w.usedBytes) + " GB" : "N/A")
                             : w.v.toFixed(0) + "%"
        // gb mode already shows the used figure in the centre, so the sub-line
        // reports the percent instead of repeating it. No bytes yet → placeholder.
        sub: !w.haveBytes ? "—"
           : w.unit === "gb" ? w.v.toFixed(0) + "%"
                             : w.gb(w.usedBytes) + " / " + w.gb(w.totalBytes) + " GB"
        color: w.col(w.v)
        history: w.showHistory ? w.hist : []
        expanded: w.expanded
    }
}
