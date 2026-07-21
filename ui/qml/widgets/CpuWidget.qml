import QtQuick
import QtQuick.Layouts

// CPU utilization + temperature - real data from the Rust core (metricsJson).
//
// Sizing (W1 wave 2a): layout keys off the injected `sizeClass`, never off
// `expanded`. The shared MetricGauge carries the ring; each size earns its box:
//   • 0.5x0.5 (micro) - headerless bare ring + the one number. No sparkline.
//   • 1x1 (baseline)  - header + ring + the classic sparkline strip.
//   • wide            - ring beside the sparkline, which finally gets real width.
//   • tall            - bigger sparkline share + an avg/peak line inside the
//                       ring: genuinely more information, not a stretched void.
//   • full (overlay)  - the expanded gauge (core count sub-line).
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "CPU"; iconName: "cpu"; accentColor: theme.catSystem
    showHeader: !micro

    // Live per-instance config (see WidgetConfigSchema "cpu").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property bool showTemp: cfg.showTemp !== undefined ? cfg.showTemp : true
    readonly property bool showHistory: cfg.showHistory !== undefined ? cfg.showHistory : true
    readonly property real warnTemp: cfg.warnTemp !== undefined ? cfg.warnTemp : 85

    // Availability: a frame with no usable usage reading must dim the gauge
    // ("N/A") rather than render a confident 0% (mirror GpuWidget).
    property bool avail: metrics.cpu_usage_percent !== undefined
                         && metrics.cpu_usage_percent !== null
                         && metrics.cpu_usage_percent >= 0
    property real v: avail ? metrics.cpu_usage_percent : 0
    // A genuine 0 °C reading is real data - only undefined/null is "missing".
    property real temp: (metrics.cpu_temp_celsius === undefined || metrics.cpu_temp_celsius === null)
                        ? -1 : metrics.cpu_temp_celsius
    status: (w.showTemp && temp >= 0) ? temp.toFixed(0) + "°C" : ""
    // Header temperature colour tracks the ring exactly, so both signals switch
    // at the same threshold (no 5 °C band where they disagree).
    statusColor: w.col(w.v)
    // Temperature is the real warning signal - escalate the WHOLE gauge (ring +
    // number) on it, not just the tiny header text. Otherwise reflect load, in the
    // widget's own accent while comfortable.
    function col(p) {
        if (w.showTemp && w.temp >= 0) {
            if (w.temp > w.warnTemp) return theme.error
            if (w.temp > w.warnTemp - 12) return theme.warning
        }
        return p > 90 ? theme.error : p > 70 ? theme.warning : w.effAccent
    }

    // Rolling history. Mirrored into the shared store (keyed by instanceId) so a
    // tile and its expanded overlay - two separate instances - share one graph.
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
        // Honour `active` (hidden/off-page tiles must not churn) and only record
        // a sample when the frame actually carried a reading - never a fake 0%.
        // Availability/value are computed from `metrics` directly here: the bound
        // `avail`/`v` properties re-evaluate lazily and would read one frame stale
        // inside this handler.
        var u = metrics.cpu_usage_percent
        if (!w.active || u === undefined || u === null || u < 0) return
        var h = w.hist.slice()
        h.push(Math.max(0, Math.min(1, u / 100)))   // clamp out-of-range usage
        if (h.length > 48) h.shift()
        w.hist = h
        if (w.store && w.instanceId) w.store.setSetting(w.instanceId, "hist", h)
    }

    // avg/peak over the retained history - the extra line a tall tile earns.
    // Needs ≥2 samples (one reading has no "average" story to tell).
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
        // Temp lives in the header (top-right) - the sub-line only adds core count
        // in the overlay, so the reading isn't printed twice. Hide it when the
        // count is absent/0 rather than printing a misleading "0 cores". Tall
        // tiles (room, but not the overlay) use the line for avg/peak instead.
        sub: w.expanded
             ? ((metrics.cpu_core_count || 0) > 0 ? (metrics.cpu_core_count + " cores") : "")
             : (w.avail && w.big ? w.histStats : "")
        color: w.col(w.v)
        history: w.showHistory && !w.micro ? w.hist : []
        expanded: w.expanded
        // Per-size layout (sizeClass injected by Dashboard; micro derived by chrome).
        showSpark: w.showHistory && !w.micro
        horizontal: w.sizeClass === "wide"
        // Tall TILES hand the sparkline all the height below a squared ring;
        // the overlay keeps the classic expanded gauge.
        sparkFills: (w.sizeClass === "tall" || w.sizeClass === "large") && !w.expanded
        bigMax: w.micro ? 72 : 60
    }
}
