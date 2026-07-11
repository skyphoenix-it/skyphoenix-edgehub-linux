import QtQuick

// RingProgress — a circular progress ring used by timers and gauges.
Item {
    id: ring
    property real value: 0.0          // 0..1
    property real thickness: Math.max(6, Math.min(width, height) * 0.08)
    property color trackColor: theme.cardBorder
    property color progressColor: theme.accent
    property color progressColor2: theme.accent2
    property bool glow: theme.glow

    Canvas {
        id: cv
        anchors.fill: parent
        onPaint: {
            var ctx = getContext('2d')
            var cx = width / 2, cy = height / 2
            var r = Math.min(cx, cy) - ring.thickness / 2 - 2
            ctx.clearRect(0, 0, width, height)
            // Guard against zero/negative radius before the item has been laid
            // out (Canvas.arc throws "Incorrect argument radius" for r <= 0).
            if (r <= 0)
                return

            // Track
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
            ctx.strokeStyle = ring.trackColor
            ctx.lineWidth = ring.thickness
            ctx.lineCap = "round"
            ctx.stroke()

            // Progress arc with gradient
            var start = -Math.PI / 2
            var end = start + Math.max(0.0001, Math.min(1, ring.value)) * 2 * Math.PI
            var grad = ctx.createLinearGradient(0, 0, width, height)
            grad.addColorStop(0, ring.progressColor)
            grad.addColorStop(1, ring.progressColor2)
            if (ring.glow) {
                ctx.shadowBlur = ring.thickness * 1.2
                ctx.shadowColor = ring.progressColor
            }
            ctx.beginPath()
            ctx.arc(cx, cy, r, start, end)
            ctx.strokeStyle = grad
            ctx.lineWidth = ring.thickness
            ctx.lineCap = "round"
            ctx.stroke()
        }
    }

    onValueChanged: cv.requestPaint()
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()
    onThicknessChanged: cv.requestPaint()
    onTrackColorChanged: cv.requestPaint()
    onProgressColorChanged: cv.requestPaint()
    onProgressColor2Changed: cv.requestPaint()
    onGlowChanged: cv.requestPaint()
    Component.onCompleted: cv.requestPaint()
}

