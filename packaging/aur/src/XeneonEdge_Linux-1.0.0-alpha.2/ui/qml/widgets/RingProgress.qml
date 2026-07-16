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

            // Progress arc. An idle metric (value <= 0) must paint nothing — a
            // round-cap stroke over a zero-length arc would leave a spurious dot
            // at 12 o'clock, so guard the sweep instead of flooring it.
            var frac = Math.max(0, Math.min(1, ring.value))
            if (frac <= 0)
                return
            var start = -Math.PI / 2
            var end = start + frac * 2 * Math.PI
            var c0 = ring.progressColor, c1 = ring.progressColor2
            // (Canvas shadowBlur glow removed — it is a CPU-side blur that is
            // recomputed on every repaint and caused noticeable jank when the
            // ring animates each second. The gradient stroke reads well on its own.)
            if (Qt.colorEqual(c0, c1)) {
                // Single colour: one cheap stroke (the common timer/gauge case).
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, end)
                ctx.strokeStyle = c0
                ctx.lineWidth = ring.thickness
                ctx.lineCap = "round"
                ctx.stroke()
            } else {
                // Two-colour ramp that follows the arc (a bounding-box linear
                // gradient does not track angular position). Draw short segments
                // with a per-segment interpolated colour; round caps blend them.
                var segs = Math.max(2, Math.round(frac * 48))
                for (var k = 0; k < segs; k++) {
                    var a0 = start + (end - start) * (k / segs)
                    var a1 = start + (end - start) * ((k + 1) / segs)
                    var t = (k + 0.5) / segs
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, a0, a1)
                    ctx.strokeStyle = Qt.rgba(c0.r + (c1.r - c0.r) * t,
                                              c0.g + (c1.g - c0.g) * t,
                                              c0.b + (c1.b - c0.b) * t,
                                              c0.a + (c1.a - c0.a) * t)
                    ctx.lineWidth = ring.thickness
                    ctx.lineCap = "round"
                    ctx.stroke()
                }
            }
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

