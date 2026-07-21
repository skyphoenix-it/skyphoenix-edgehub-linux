import QtQuick
import QtQuick.Layouts

// GPU utilization + temperature - real data (amdgpu sysfs via the Rust core).
// Shows "N/A" gracefully when no discrete GPU is discoverable.
//
// Sizing (W1 wave 2a): layout keys off the injected `sizeClass` (see CpuWidget
// for the pattern). micro = headerless bare ring + the one number; baseline =
// the classic ring + sparkline strip; wide = ring beside a full-width
// sparkline; tall = squared ring + full-height sparkline + an avg/peak caption
// inside the ring; full = the expanded gauge.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "GPU"; iconName: "gpu"; accentColor: theme.catGaming
    showHeader: !micro

    // Live per-instance config (see WidgetConfigSchema "gpu").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
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
    // Temperature escalates the whole gauge; otherwise reflect load in the accent.
    // Thermal escalation is a safety signal - it must survive even when the temp
    // text is hidden (showTemp only governs the header status, not the ring). The
    // amber band matches the header's (warnTemp-17) so number and ring never disagree.
    function col(p) {
        if (w.temp > 0) {
            if (w.temp > w.warnTemp) return theme.error
            if (w.temp > w.warnTemp - 17) return theme.warning
        }
        return p > 92 ? theme.error : p > 75 ? theme.warning : w.effAccent
    }

    // Rolling history. Mirrored into the shared store (keyed by instanceId) so a
    // tile and its expanded overlay - two separate instances - draw one graph
    // instead of the overlay opening blank (S5). `hist` is an EPHEMERAL store key,
    // so the per-sample write bumps reactivity but never touches disk.
    property var hist: []
    function _seedHist() {
        if (w.store && w.instanceId && (!w.hist || w.hist.length === 0)) {
            var s = w.store.settingsFor(w.instanceId)
            if (s.hist && s.hist.length) w.hist = s.hist.slice()
        }
    }
    onStoreChanged: _seedHist()
    onInstanceIdChanged: _seedHist()
    onMetricsChanged: {
        if (!w.active) return           // paused (expanded / off-page) → stop sampling
        if (!w.avail) return
        var h = w.hist.slice(); h.push(w.v / 100)
        if (h.length > 48) h.shift()
        w.hist = h
        if (w.store && w.instanceId) w.store.setSetting(w.instanceId, "hist", h)
    }

    // avg/peak over the retained history - the extra line a tall tile earns.
    readonly property string histStats: {
        if (!w.showHistory || !w.hist || w.hist.length < 2) return ""
        var sum = 0, peak = 0
        for (var i = 0; i < w.hist.length; i++) {
            sum += w.hist[i]
            if (w.hist[i] > peak) peak = w.hist[i]
        }
        return "avg " + Math.round(sum / w.hist.length * 100) + "% · peak "
               + Math.round(peak * 100) + "%"
    }

    MetricGauge {
        anchors.fill: parent
        ok: w.avail
        value: Math.min(w.v / 100, 1)
        big: w.avail ? w.v.toFixed(0) + "%" : "N/A"
        // Temp shows in the header - don't repeat it in the sub-line. Tall
        // tiles use the line for avg/peak (genuinely more information).
        sub: (!w.expanded && w.avail && w.big) ? w.histStats : ""
        color: w.col(w.v)
        history: w.showHistory && !w.micro ? w.hist : []
        expanded: w.expanded
        // Per-size layout (sizeClass injected by Dashboard; micro derived by chrome).
        showSpark: w.showHistory && !w.micro
        horizontal: w.sizeClass === "wide"
        sparkFills: (w.sizeClass === "tall" || w.sizeClass === "large") && !w.expanded
        bigMax: w.micro ? 72 : 60
    }
}
