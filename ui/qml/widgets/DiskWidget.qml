import QtQuick
import QtQuick.Layouts

// Root-filesystem usage — real data (statvfs via the Rust core).
//
// Sizing (W1): layout keys off `sizeClass` (injected by Dashboard), never off
// `expanded`. Disk usage barely changes, so the ring carries the story and each
// size earns what it can hold:
//   • 0.5x0.5 (micro) — a bare ring + percent, headerless: nothing competes
//     with the one number in a twelfth of the screen.
//   • 1x1 (compact)   — header + ring with percent and used/total inside.
//   • wide            — ring beside a Used / Free / Total detail column.
//   • tall / full     — ring above the same detail column.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Disk"; iconName: "disk"; accentColor: theme.catInfo
    showHeader: !micro

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

    // ── Per-size layout (sizeClass is injected by Dashboard) ─────────────────
    // 0.5x0.5 and 1x1 are both "compact" (shape, not footprint); the micro
    // half-cell is told apart by the box (~344-416px short side vs ~690px+).
    readonly property bool micro: sizeClass === "compact" && Math.min(width, height) < 480
    readonly property bool horiz: sizeClass === "wide"
    // The detail column earns its place wherever there is room beyond the ring.
    readonly property bool showDetails: sizeClass === "wide" || sizeClass === "tall"
                                        || sizeClass === "large" || sizeClass === "full"
    // used/total inside the ring: only the baseline tile and the overlay — the
    // micro ring is too small and the detail column already carries it elsewhere.
    readonly property bool showInlineSub: avail && !micro && !showDetails
    readonly property real ringDia: {
        var boxW = width - 2 * contentMargins, boxH = height - 2 * contentMargins - (showHeader ? headerHeight : 0)
        if (micro) return Math.max(0, Math.min(boxW, boxH) * 0.92)
        if (horiz) return Math.max(0, Math.min(boxH * 0.88, boxW * 0.44))
        if (sizeClass === "compact") return Math.max(0, Math.min(boxW, boxH) * 0.80)
        return Math.max(0, Math.min(boxW * 0.72, boxH * 0.52))   // tall / full
    }

    GridLayout {
        id: diskLayout
        anchors.centerIn: parent
        width: parent.width
        columns: w.horiz ? 2 : 1
        columnSpacing: theme.spacingLg
        rowSpacing: w.micro ? 0 : theme.spacingMd

        Item {
            id: ringBox
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            Layout.preferredWidth: Math.round(w.ringDia)
            Layout.preferredHeight: Math.round(w.ringDia)
            RingProgress {
                id: ring
                anchors.fill: parent
                value: w.avail ? w.v / 100 : 0
                thickness: Math.max(9, width * 0.10)
                progressColor: w.col(w.v); progressColor2: w.col(w.v)
                trackColor: Qt.rgba(theme.cardBorder.r, theme.cardBorder.g, theme.cardBorder.b, 0.6)
            }
            Column {
                anchors.centerIn: parent
                width: Math.max(24, ringBox.width - 2 * ring.thickness - 8)
                spacing: 0
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: w.avail ? w.v.toFixed(0) + "%" : "N/A"
                    font.pixelSize: Math.max(18, Math.min(ringBox.width * 0.30, w.sizeClass === "full" ? 108 : 72))
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10; elide: Text.ElideRight
                    font.bold: true; font.family: theme.fontMono
                    color: w.avail ? w.col(w.v) : theme.textTertiary
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: w.showInlineSub
                    text: w.human(w.usedBytes) + " / " + w.human(metrics.disk_total_bytes || 0)
                    font.pixelSize: Math.max(11, Math.min(ringBox.width * 0.055, 16))
                    fontSizeMode: Text.HorizontalFit; minimumPixelSize: 9; elide: Text.ElideRight
                    color: theme.textSecondary
                }
            }
        }

        // Used / Free / Total — the numbers the percent is made of, where a size
        // has the room to spell them out.
        ColumnLayout {
            visible: w.showDetails
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.maximumWidth: w.horiz ? Math.round(diskLayout.width * 0.5)
                                         : Math.round(diskLayout.width * 0.86)
            spacing: theme.spacingXs

            Repeater {
                model: [
                    { k: "Used",  val: w.avail ? w.human(w.usedBytes) : "—", hot: true },
                    { k: "Free",  val: w.avail ? w.human(w.freeBytes) : "—", hot: false },
                    { k: "Total", val: w.avail ? w.human(metrics.disk_total_bytes || 0) : "—", hot: false }
                ]
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: theme.spacingMd
                    Text {
                        text: modelData.k
                        font.pixelSize: Math.max(13, Math.min(w.width * 0.032, 18))
                        color: theme.textSecondary
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: modelData.val
                        font.pixelSize: Math.max(13, Math.min(w.width * 0.036, 20))
                        font.family: theme.fontMono; font.bold: modelData.hot
                        color: modelData.hot && w.avail ? w.col(w.v) : theme.textPrimary
                    }
                }
            }
        }
    }
}
