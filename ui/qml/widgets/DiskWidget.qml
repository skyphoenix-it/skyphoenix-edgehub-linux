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
    // Clamp to the schema slider range (50..99). The Manager control socket or a
    // hand-edited config can inject anything, and an out-of-range warn line breaks
    // the colour bands (e.g. warnPercent 0 paints every disk amber).
    readonly property real warnPercent: {
        var p = cfg.warnPercent !== undefined ? cfg.warnPercent : 90
        return Math.max(50, Math.min(99, p))
    }

    // statvfs('/') failure — and the pre-first-sample frame — report no real disk
    // (total absent or 0). Don't fabricate a confident "0%"; flag the tile
    // unavailable so the gauge dims instead of showing a full empty track.
    property bool avail: metrics.disk_total_bytes !== undefined
                         && metrics.disk_total_bytes !== null
                         && metrics.disk_total_bytes > 0

    // The df-correct fill (accounts for root-reserved blocks). Clamp to 0..100 so a
    // transient used>total sample can't overdrive the ring.
    property real v: avail ? Math.max(0, Math.min(100, metrics.disk_usage_percent || 0)) : 0

    // Critical (red) must always sit above the warn line so the amber band stays
    // reachable, and never below the hardware-sensible 97%. Ordering the checks
    // warn→critical stops a high warnPercent turning the ring red below the user's
    // own warn line.
    readonly property real critPercent: Math.max(97, w.warnPercent + 1)
    function col(p) {
        if (p > w.critPercent) return theme.error
        if (p > w.warnPercent) return theme.warning
        return w.effAccent
    }
    function human(b) {
        // Sizes are computed in powers of two, so label them with binary units.
        if (b >= 1099511627776) return (b / 1099511627776).toFixed(2) + " TiB"
        return (b / 1073741824).toFixed(0) + " GiB"
    }
    // Used/free derive from the ring's percent (the same accounting as the gauge)
    // so a 100%-full ring never simultaneously advertises root-reserved "free"
    // space, and the sub-line's implied fill always matches the ring.
    readonly property real usedBytes: (metrics.disk_total_bytes || 0) * w.v / 100
    readonly property real freeBytes: avail ? Math.max(0, (metrics.disk_total_bytes || 0) - usedBytes) : 0

    // Disk usage barely changes; the gauge carries it, no sparkline needed.
    MetricGauge {
        anchors.fill: parent
        ok: w.avail
        value: Math.min(w.v / 100, 1)
        big: w.avail ? w.v.toFixed(0) + "%" : "N/A"
        sub: !w.avail ? ""
             : w.expanded
             ? (w.human(w.usedBytes) + " / " + w.human(metrics.disk_total_bytes || 0)
                + "  ·  " + w.human(w.freeBytes) + " free")
             : (w.human(w.usedBytes) + " / " + w.human(metrics.disk_total_bytes || 0))
        color: w.col(w.v)
        expanded: w.expanded
    }
}
