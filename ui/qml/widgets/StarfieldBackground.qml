import QtQuick

// StarfieldBackground — a calm, deep-space field: two static star layers (drawn
// once) for depth, plus a handful of gently twinkling accent stars. Cheap: no
// per-frame canvas repaint; only a few opacity animations.
Item {
    id: root
    property bool active: true
    property color tint: "#CFE3FF"
    clip: true

    component StarLayer: Canvas {
        id: cv
        property int count: 60
        property real maxR: 1.8
        property color color: "#FFFFFF"
        anchors.fill: parent
        onPaint: {
            var ctx = getContext('2d')
            ctx.clearRect(0, 0, width, height)
            if (width <= 0 || height <= 0) return
            // Deterministic pseudo-random placement (stable across repaints).
            for (var i = 0; i < count; i++) {
                var sx = (((i * 977 + 131) % 1000) / 1000) * width
                var sy = (((i * 571 + 293) % 1000) / 1000) * height
                var r = 0.5 + (((i * 313) % 100) / 100) * maxR
                ctx.beginPath()
                ctx.arc(sx, sy, r, 0, 2 * Math.PI)
                ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.35 + ((i * 41) % 55) / 100)
                ctx.fill()
            }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }

    StarLayer { count: 140; maxR: 1.6; color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 1); opacity: 0.8 }
    StarLayer { count: 70; maxR: 2.8; color: "#FFFFFF"; opacity: 1.0 }

    // A few brighter twinkling stars on top for life.
    Repeater {
        model: 20
        delegate: Rectangle {
            required property int index
            width: 4; height: 4; radius: 2
            color: theme.accent
            x: (((index * 733 + 91) % 1000) / 1000) * root.width
            y: (((index * 421 + 197) % 1000) / 1000) * root.height
            SequentialAnimation on opacity {
                running: root.active; loops: Animation.Infinite
                NumberAnimation { to: 0.15; duration: 1200 + (index % 5) * 400; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.95; duration: 1400 + (index % 4) * 500; easing.type: Easing.InOutSine }
            }
        }
    }
}
