import QtQuick

// Sparkline — a lightweight area+line history chart (values normalized 0..1).
// Reused by the metric tiles so a tall tile shows live history instead of empty
// space. Cheap Canvas draw; no per-frame blur.
Item {
    id: s
    property var values: []        // array of numbers in 0..1
    property color color: theme.accent
    property bool fill: true

    Canvas {
        id: cv
        anchors.fill: parent
        onPaint: {
            var ctx = getContext('2d')
            ctx.clearRect(0, 0, width, height)
            var n = s.values ? s.values.length : 0
            if (n < 2 || width <= 0 || height <= 0)
                return
            function X(i) { return i * width / (n - 1) }
            function Y(v) { return height - Math.max(0, Math.min(1, v)) * (height - 4) - 2 }

            if (s.fill) {
                ctx.beginPath()
                ctx.moveTo(0, height)
                for (var i = 0; i < n; i++) ctx.lineTo(X(i), Y(s.values[i]))
                ctx.lineTo(width, height)
                ctx.closePath()
                var grad = ctx.createLinearGradient(0, 0, 0, height)
                grad.addColorStop(0, Qt.rgba(s.color.r, s.color.g, s.color.b, 0.38))
                grad.addColorStop(1, Qt.rgba(s.color.r, s.color.g, s.color.b, 0.0))
                ctx.fillStyle = grad
                ctx.fill()
            }

            ctx.beginPath()
            for (var j = 0; j < n; j++) {
                var x = X(j), y = Y(s.values[j])
                j === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
            }
            ctx.strokeStyle = s.color
            ctx.lineWidth = 2.5
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.stroke()
        }
    }

    onValuesChanged: cv.requestPaint()
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()
    onColorChanged: cv.requestPaint()
    Component.onCompleted: cv.requestPaint()
}
