import QtQuick

// Analog clock face on a Canvas — repainted each second by the shared tick.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Analog"; iconName: "analog"; accentColor: theme.catSystem
    big: expanded; showHeader: expanded

    // Live per-instance config (see WidgetConfigSchema "analogClock").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property bool showSeconds: cfg.showSeconds !== undefined ? cfg.showSeconds : true
    readonly property bool showNumerals: cfg.showNumerals !== undefined ? cfg.showNumerals : false

    onShowSecondsChanged: cv.requestPaint()
    onShowNumeralsChanged: cv.requestPaint()

    Canvas {
        id: cv
        anchors.fill: parent
        anchors.margins: theme.spacingSm
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
                ctx.strokeStyle = theme.accent; ctx.lineWidth = Math.max(1, rad * 0.02)
                ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(sa) * rad * 0.82, cy + Math.sin(sa) * rad * 0.82); ctx.stroke()
            }
            ctx.fillStyle = theme.accent; ctx.beginPath(); ctx.arc(cx, cy, Math.max(2, rad * 0.05), 0, 2 * Math.PI); ctx.fill()
        }
        Connections { target: w; function onTickChanged() { cv.requestPaint() } }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }
}
