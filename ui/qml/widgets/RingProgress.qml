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
    // Opt-in smoothing for DATA-driven rings (metric gauges): a new sample eases
    // the sweep instead of hard-cutting it. Deliberately OFF by default so
    // second-hand timer rings (focus/break/countdown) keep their honest 1Hz step
    // — and don't pay ~24 extra Canvas repaints per second. The token already
    // collapses to 0 under reduce-motion.
    property bool animateValue: false
    Behavior on value {
        enabled: ring.animateValue
        // motionFast, NOT motionValue: any running animation holds the render
        // loop awake, and a Canvas ring is the most expensive thing on screen to
        // re-render. 150ms reads as a crisp settle on a ~2s sample cadence;
        // the 400ms glide measured over 3x the CPU on the real panel. Still 0
        // (instant) under reduce-motion.
        NumberAnimation { duration: theme.motionFast; easing.type: Easing.OutCubic }
    }

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

    // Repaint coalescing for the EASED path only. A Canvas repaint is a full
    // CPU re-rasterization of the ring; letting the 400ms glide repaint at the
    // display's 60Hz measured ~1.8% CPU per gauge on the real panel — most of
    // the whole app's budget. ~22fps during the glide is visually
    // indistinguishable for a sweep this slow and costs a third as much. The
    // timer only ever runs while a glide is delivering value changes, so an
    // idle ring stays completely quiet; the final frame is never dropped
    // (a pending repaint is always flushed on the next trigger). Timer/stepped
    // consumers (animateValue: false) keep the direct 1:1 repaint.
    property bool _repaintPending: false
    Timer {
        id: paintThrottle
        interval: 45
        onTriggered: if (ring._repaintPending) { ring._repaintPending = false; cv.requestPaint(); restart() }
    }
    onValueChanged: {
        if (!animateValue) { cv.requestPaint(); return }
        if (paintThrottle.running) { ring._repaintPending = true; return }
        cv.requestPaint()
        paintThrottle.start()
    }
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()
    onThicknessChanged: cv.requestPaint()
    onTrackColorChanged: cv.requestPaint()
    onProgressColorChanged: cv.requestPaint()
    onProgressColor2Changed: cv.requestPaint()
    onGlowChanged: cv.requestPaint()
    Component.onCompleted: cv.requestPaint()
}

