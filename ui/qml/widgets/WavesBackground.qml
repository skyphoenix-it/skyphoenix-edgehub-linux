import QtQuick

// WavesBackground — layered, slowly-scrolling sine waves along the bottom.
// Each wave is drawn ONCE onto a Canvas (a GPU texture) and animated by simply
// translating the item horizontally, so there is no per-frame repaint cost.
Item {
    id: root
    property bool active: true
    property color c1: theme.accent
    property color c2: theme.accent2
    property color c3: theme.catEntertainment
    clip: true

    component Wave: Item {
        id: wv
        property color tint: "#ffffff"
        property real amp: 40
        property real wavelength: 600
        property real baseY: 0.7      // fraction of height where the wave sits
        property real speed: 30000
        property real op: 0.15
        anchors.fill: parent
        Canvas {
            id: cv
            height: parent.height
            width: wv.wavelength + parent.width + 4
            onPaint: {
                var ctx = getContext('2d')
                ctx.clearRect(0, 0, width, height)
                var by = height * wv.baseY
                ctx.beginPath()
                ctx.moveTo(0, height)
                ctx.lineTo(0, by)
                for (var x = 0; x <= width; x += 6)
                    ctx.lineTo(x, by + Math.sin((x / wv.wavelength) * 2 * Math.PI) * wv.amp)
                ctx.lineTo(width, height)
                ctx.closePath()
                var g = ctx.createLinearGradient(0, by - wv.amp, 0, height)
                g.addColorStop(0, Qt.rgba(wv.tint.r, wv.tint.g, wv.tint.b, wv.op))
                g.addColorStop(1, Qt.rgba(wv.tint.r, wv.tint.g, wv.tint.b, wv.op * 0.25))
                ctx.fillStyle = g
                ctx.fill()
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
            // Scroll by exactly one wavelength → seamless loop (sine is periodic).
            NumberAnimation on x {
                running: root.active; loops: Animation.Infinite
                from: 0; to: -wv.wavelength; duration: wv.speed; easing.type: Easing.Linear
            }
        }
    }

    Wave { tint: root.c1; baseY: 0.58; amp: 70; wavelength: 520; speed: 24000; op: 0.42 }
    Wave { tint: root.c2; baseY: 0.70; amp: 52; wavelength: 700; speed: 33000; op: 0.34 }
    Wave { tint: root.c3; baseY: 0.82; amp: 90; wavelength: 780; speed: 28000; op: 0.28 }
}
