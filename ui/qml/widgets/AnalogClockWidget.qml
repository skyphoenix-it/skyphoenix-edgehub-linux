import QtQuick

// Analog clock face on a Canvas - repainted each second by the shared tick.
//
// Sizing (W1): layout keys off `sizeClass` (injected by Dashboard), never off
// `expanded`. What the leftover space earns:
//   • 0.5x0.5 (micro) - the face IS the widget; nothing competes with it.
//   • 1x1 (compact)   - face + today's date beneath it.
//   • wide            - face on the left, digital time + date beside it.
//   • tall / full     - face on top, digital time + date beneath it.
// The same class has a different aspect per orientation (0.5x1 is tall-narrow in
// portrait, wide-short in landscape) - the face/info split derives from the box,
// so both projections of a class lay out honestly.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Analog"; iconName: "analog"; accentColor: theme.catSystem
    showHeader: expanded

    // Live per-instance config (see WidgetConfigSchema "analogClock").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property bool showSeconds: cfg.showSeconds !== undefined ? cfg.showSeconds : true
    readonly property bool showNumerals: cfg.showNumerals !== undefined ? cfg.showNumerals : false

    // ── Per-size layout flags ────────────────────────────────────────────────
    // 0.5x0.5 and 1x1 are both "compact" (shape, not footprint); the micro
    // half-cell is told apart by the box (~344-416px short side vs ~690px+).
    readonly property bool micro: sizeClass === "compact" && Math.min(width, height) < 480
    readonly property bool horiz: sizeClass === "wide"
    readonly property bool showDate: !micro
    readonly property bool showDigital: !micro && sizeClass !== "compact"

    onShowSecondsChanged: cv.requestPaint()
    onShowNumeralsChanged: cv.requestPaint()
    onEffAccentChanged: cv.requestPaint()
    // Reactivated tile (edit-mode/off-page → live) refreshes with current time+palette.
    onActiveChanged: if (active) cv.requestPaint()

    Item {
        id: box
        anchors.fill: parent
        anchors.margins: theme.spacingSm

        // Space carved out for the info block: a side column in wide, a bottom
        // band otherwise - all derived from the box, no one-class pixel values.
        readonly property real infoW: w.horiz ? Math.max(150, width * 0.40) : 0
        readonly property real infoH: !w.horiz && w.showDate
                                      ? Math.max(36, Math.min(height * 0.20, w.showDigital ? 120 : 56))
                                      : 0
        readonly property real faceRegionW: Math.max(0, width - infoW - (infoW > 0 ? theme.spacingMd : 0))
        readonly property real faceRegionH: Math.max(0, height - infoH - (infoH > 0 ? theme.spacingSm : 0))

        // In vertical modes the face + info stack is centered as ONE group, so a
        // narrow tall tile doesn't strand the face high above a bottom band.
        readonly property real groupH: Math.min(faceRegionW, faceRegionH)
                                       + (infoH > 0 ? infoH + theme.spacingSm : 0)
        readonly property real groupY: Math.max(0, (height - groupH) / 2)

        Canvas {
            id: cv
            width: Math.max(0, Math.min(box.faceRegionW, box.faceRegionH))
            height: width
            x: (box.faceRegionW - width) / 2
            y: w.horiz ? (box.faceRegionH - height) / 2 : box.groupY
            onPaint: {
                var ctx = getContext('2d')
                var cx = width / 2, cy = height / 2, rad = Math.min(cx, cy) - 6
                ctx.clearRect(0, 0, width, height)
                if (rad <= 0) return

                ctx.strokeStyle = theme.cardBorder; ctx.lineWidth = Math.max(3, rad * 0.04)
                ctx.beginPath(); ctx.arc(cx, cy, rad, 0, 2 * Math.PI); ctx.stroke()
                for (var t = 0; t < 12; t++) {
                    var ta = t * Math.PI / 6
                    ctx.strokeStyle = theme.textTertiary; ctx.lineWidth = 2
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(ta) * rad * 0.88, cy + Math.sin(ta) * rad * 0.88)
                    ctx.lineTo(cx + Math.cos(ta) * rad * 0.96, cy + Math.sin(ta) * rad * 0.96)
                    ctx.stroke()
                }
                if (w.showNumerals) {
                    ctx.fillStyle = theme.textSecondary
                    ctx.font = Math.max(9, rad * 0.16) + "px sans-serif"
                    ctx.textAlign = "center"; ctx.textBaseline = "middle"
                    for (var n = 1; n <= 12; n++) {
                        var na = n * Math.PI / 6 - Math.PI / 2
                        ctx.fillText(n, cx + Math.cos(na) * rad * 0.72, cy + Math.sin(na) * rad * 0.72)
                    }
                }
                var now = new Date(), h = now.getHours() % 12, m = now.getMinutes(), s = now.getSeconds()
                var ha = (h + m / 60) * Math.PI / 6 - Math.PI / 2
                var ma = (m + s / 60) * Math.PI / 30 - Math.PI / 2
                var sa = s * Math.PI / 30 - Math.PI / 2
                ctx.lineCap = "round"
                ctx.strokeStyle = theme.textPrimary; ctx.lineWidth = Math.max(3, rad * 0.045)
                ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(ha) * rad * 0.5, cy + Math.sin(ha) * rad * 0.5); ctx.stroke()
                ctx.lineWidth = Math.max(2, rad * 0.03)
                ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(ma) * rad * 0.72, cy + Math.sin(ma) * rad * 0.72); ctx.stroke()
                if (w.showSeconds) {
                    ctx.strokeStyle = w.effAccent; ctx.lineWidth = Math.max(1, rad * 0.02)
                    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(sa) * rad * 0.82, cy + Math.sin(sa) * rad * 0.82); ctx.stroke()
                }
                ctx.fillStyle = w.effAccent; ctx.beginPath(); ctx.arc(cx, cy, Math.max(2, rad * 0.05), 0, 2 * Math.PI); ctx.fill()
            }
            // Single-driver rule (S3): only the active tile repaints on the shared tick.
            // Off-screen / expanded / edit-mode clocks are set active=false and stay idle.
            Connections { target: w; function onTickChanged() { if (w.active) cv.requestPaint() } }
            // Theme role colors (ring/ticks/numerals/hands) are read at paint time; repaint
            // when the palette changes so a theme switch doesn't leave a stale face.
            Connections {
                target: theme
                function onCardBorderChanged() { if (w.active) cv.requestPaint() }
                function onTextPrimaryChanged() { if (w.active) cv.requestPaint() }
                function onTextSecondaryChanged() { if (w.active) cv.requestPaint() }
                function onTextTertiaryChanged() { if (w.active) cv.requestPaint() }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
        }

        // Digital time + date - beside the face in wide, beneath it otherwise.
        Column {
            id: info
            visible: w.showDate
            spacing: Math.round(theme.spacingXs / 2)
            x: w.horiz ? box.width - box.infoW : 0
            y: w.horiz ? Math.round((box.height - height) / 2)
                       : Math.round(cv.y + cv.height + theme.spacingSm + Math.max(0, (box.infoH - height) / 2))
            width: w.horiz ? box.infoW : box.width

            Text {
                visible: w.showDigital
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: {
                    w.tick
                    return Qt.formatTime(new Date(), w.showSeconds ? "hh:mm:ss" : "hh:mm")
                }
                font.pixelSize: w.horiz ? Math.max(18, Math.min(box.infoW * 0.20, 64))
                                        : Math.max(18, Math.min(box.infoH * 0.52, 64))
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: 12; elide: Text.ElideRight
                font.bold: true; font.family: theme.fontMono
                color: theme.textPrimary
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: {
                    w.tick
                    return Qt.formatDate(new Date(), "ddd, d MMMM")
                }
                font.pixelSize: Math.max(12, Math.min((w.horiz ? box.infoW : box.width) * 0.075, 20))
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10; elide: Text.ElideRight
                font.family: theme.fontDisplay
                color: theme.textSecondary
            }
        }
    }
}
