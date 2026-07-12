import QtQuick

// GridBackground — a subtle synthwave perspective grid. A Canvas draws horizontal
// lines that bunch up toward a horizon (in the lower third) plus vertical lines
// converging to a central vanishing point, in a translucent theme.accent colour.
// Animated by a single `phase` property that scrolls the horizontal lines slowly
// downward (perspective scroll). The Canvas repaints from a Timer capped at
// ~20fps; when `active` is false the Timer stops but the last frame stays painted
// — matching the static behaviour of the waves/stars backdrops.
Item {
    id: root
    property bool active: true
    property color tint: theme.accent
    clip: true

    // Scroll phase (0..1) — one unit == one row of forward motion; loops seamlessly.
    property real phase: 0.0

    Timer {
        running: root.active
        repeat: true
        interval: 50   // ~20fps, deliberately capped
        onTriggered: {
            root.phase = (root.phase + 0.006) % 1.0
            grid.requestPaint()
        }
    }

    Canvas {
        id: grid
        anchors.fill: parent
        onPaint: {
            var ctx = getContext('2d')
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0) return

            var vx = width / 2                 // vanishing point x (centre)
            var vy = height * 0.66             // horizon in the lower third
            var groundH = height - vy
            var rows = 16
            var cols = 12

            ctx.strokeStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.18)
            ctx.lineWidth = 1

            // Vertical lines converging up to the vanishing point.
            for (var c = 0; c <= cols; c++) {
                var f = c / cols                       // 0..1 across the screen
                var xBottom = f * width * 2.0 - width * 0.5   // spread wider than the screen
                ctx.beginPath()
                ctx.moveTo(xBottom, height)
                ctx.lineTo(vx, vy)
                ctx.stroke()
            }

            // Horizontal lines that bunch toward the horizon; scrolled by `phase`.
            ctx.strokeStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.22)
            for (var r = 0; r <= rows; r++) {
                var t = (r + root.phase) / rows        // 0..1 depth (0 == horizon)
                if (t > 1.0) continue
                var y = vy + groundH * Math.pow(t, 2.2)   // squared => bunch near horizon
                // Fade lines out as they approach the horizon.
                var a = 0.06 + t * 0.22
                ctx.strokeStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, a)
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.lineTo(width, y)
                ctx.stroke()
            }

            // A faint horizon line.
            ctx.strokeStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.28)
            ctx.beginPath()
            ctx.moveTo(0, vy)
            ctx.lineTo(width, vy)
            ctx.stroke()
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }
}
