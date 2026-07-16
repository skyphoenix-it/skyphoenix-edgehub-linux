import QtQuick

// GridBackground — a subtle synthwave perspective grid: horizontal lines that
// bunch toward a horizon (lower third) plus vertical lines converging to a central
// vanishing point, in a translucent theme.accent colour. Only the horizontal lines
// scroll, so the STATIC verticals + horizon are painted ONCE into their own Canvas
// (a cached GPU texture) and only the scrolling lines repaint on the ~20fps timer —
// roughly halving per-frame raster work vs redrawing the whole grid each tick. When
// `active` is false the timer stops and the last frame stays painted.
Item {
    id: root
    property bool active: true
    // Primary tint (S7). Defaults to theme.accent; overridable via BackdropLayer.
    property color accent: theme.accent
    property color tint: accent
    clip: true

    // Scroll phase (0..1) — one unit == one row of forward motion; loops seamlessly.
    property real phase: 0.0

    readonly property real vx: width / 2                 // vanishing point x (centre)
    readonly property real vy: height * 0.66             // horizon in the lower third

    Timer {
        running: root.active
        repeat: true
        interval: 50   // ~20fps, deliberately capped
        onTriggered: {
            root.phase = (root.phase + 0.006) % 1.0
            dynamicGrid.requestPaint()
        }
    }

    // Static layer: vertical lines + horizon (never changes except on resize).
    Canvas {
        id: staticGrid
        anchors.fill: parent
        onPaint: {
            var ctx = getContext('2d')
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0) return
            var cols = 12
            ctx.lineWidth = 1
            ctx.strokeStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.18)
            for (var c = 0; c <= cols; c++) {
                var f = c / cols
                var xBottom = f * width * 2.0 - width * 0.5   // spread wider than the screen
                ctx.beginPath(); ctx.moveTo(xBottom, height); ctx.lineTo(root.vx, root.vy); ctx.stroke()
            }
            // Horizon line.
            ctx.strokeStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.28)
            ctx.beginPath(); ctx.moveTo(0, root.vy); ctx.lineTo(width, root.vy); ctx.stroke()
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
        // `tint` lives on root, not the Canvas — repaint the statics when it changes.
        Connections { target: root; function onTintChanged() { staticGrid.requestPaint() } }
    }

    // Dynamic layer: only the scrolling horizontal lines repaint each tick.
    Canvas {
        id: dynamicGrid
        anchors.fill: parent
        onPaint: {
            var ctx = getContext('2d')
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0) return
            var vy = root.vy, groundH = height - vy, rows = 16
            ctx.lineWidth = 1
            for (var r = 0; r <= rows; r++) {
                var t = (r + root.phase) / rows        // 0..1 depth (0 == horizon)
                if (t > 1.0) continue
                var y = vy + groundH * Math.pow(t, 2.2)   // squared => bunch near horizon
                var a = 0.06 + t * 0.22                    // fade out toward the horizon
                ctx.strokeStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, a)
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
            }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
        // When motion is off the timer is stopped, so nothing else repaints this
        // layer — react to tint changes explicitly so a theme/accent switch takes.
        Connections { target: root; function onTintChanged() { dynamicGrid.requestPaint() } }
    }
}
