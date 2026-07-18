import QtQuick

// Sparkline — a lightweight area+line history chart (values normalized 0..1).
// Reused by the metric tiles so a tall tile shows live history instead of empty
// space. Cheap Canvas draw; no per-frame blur.
Item {
    id: s
    property var values: []        // array of numbers in 0..1
    property color color: theme.accent
    property bool fill: true

    // Cheap signature of the current samples so a producer that mutates the
    // bound array IN PLACE (history.push(...) — no NOTIFY fires) still repaints.
    property string _sig: ""
    function _signature() {
        var v = s.values
        if (!v || typeof v.length !== "number") return "0"
        var acc = v.length + ":"
        for (var i = 0; i < v.length; i++) {
            var x = v[i]
            acc += ((typeof x === "number" && isFinite(x)) ? x : "x") + ","
        }
        return acc
    }

    Canvas {
        id: cv
        anchors.fill: parent
        onPaint: {
            var ctx = getContext('2d')
            ctx.clearRect(0, 0, width, height)
            // Only a real array is renderable; null / non-array objects are
            // degenerate input and must draw nothing (not a stray baseline).
            var vals = (s.values && typeof s.values.length === "number") ? s.values : null
            var n = vals ? vals.length : 0
            if (n < 2 || width <= 0 || height <= 0)
                return
            function X(i) { return i * width / (n - 1) }
            function Y(v) { return height - Math.max(0, Math.min(1, v)) * (height - 4) - 2 }

            // Skip NaN/undefined/non-finite samples so one bad value cannot poison
            // the whole polyline+fill (lineTo(x, NaN) breaks the entire path).
            // Indices are preserved on the x axis so time order is unaffected.
            var pts = []
            for (var i = 0; i < n; i++) {
                var v = vals[i]
                if (typeof v === "number" && isFinite(v))
                    pts.push({ x: X(i), y: Y(v) })
            }
            if (pts.length < 2)
                return

            if (s.fill) {
                ctx.beginPath()
                ctx.moveTo(pts[0].x, height)
                for (var i2 = 0; i2 < pts.length; i2++) ctx.lineTo(pts[i2].x, pts[i2].y)
                ctx.lineTo(pts[pts.length - 1].x, height)
                ctx.closePath()
                var grad = ctx.createLinearGradient(0, 0, 0, height)
                grad.addColorStop(0, Qt.rgba(s.color.r, s.color.g, s.color.b, 0.38))
                grad.addColorStop(1, Qt.rgba(s.color.r, s.color.g, s.color.b, 0.0))
                ctx.fillStyle = grad
                ctx.fill()
            }

            ctx.beginPath()
            for (var j = 0; j < pts.length; j++) {
                j === 0 ? ctx.moveTo(pts[j].x, pts[j].y) : ctx.lineTo(pts[j].x, pts[j].y)
            }
            ctx.strokeStyle = s.color
            ctx.lineWidth = 2.5
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.stroke()
        }
    }

    // Poll for in-place mutation of the bound array (no reassignment ⇒ no
    // onValuesChanged). Repaint only when the sample signature actually changes,
    // so an idle sparkline stays quiet on the fanless panel.
    // running: s.visible — a sparkline that isn't on screen must not poll. The
    // Manager keeps preview widgets INSTANTIATED across tab switches (Loaders don't
    // unload when a tab hides), so an ungated 100ms timer here kept firing on EVERY
    // Manager section, burning frames and making all scrolling stutter. Gating on
    // visibility stops every off-screen sparkline; a visible one polls as before.
    Timer {
        interval: 100; running: s.visible; repeat: true
        onTriggered: {
            var sig = s._signature()
            if (sig !== s._sig) { s._sig = sig; cv.requestPaint() }
        }
    }

    onValuesChanged: { s._sig = s._signature(); cv.requestPaint() }
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()
    onColorChanged: cv.requestPaint()
    Component.onCompleted: { s._sig = s._signature(); cv.requestPaint() }
}
