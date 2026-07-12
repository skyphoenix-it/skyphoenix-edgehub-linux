import QtQuick
import QtQuick.Shapes

// AuroraBackground — northern-lights curtains: a few tall, soft vertical bands
// (LinearGradient top→bottom, transparent at both ends and coloured in the
// middle) in green/teal/purple theme colours. Each band slides horizontally on a
// slow sinusoidal loop with a gently animated opacity, so they read as drifting
// curtains. GPU-rendered (QtQuick.Shapes); the bands overlap at low opacity for
// an additive, screen-blend feel. When `active` is false the curtains stay
// painted but stop moving — matching the waves/stars backdrops.
Item {
    id: root
    property bool active: true
    clip: true

    // A single soft vertical curtain: a rectangle filled with a top→bottom
    // gradient that is transparent at both ends and coloured in the middle.
    component Curtain: Shape {
        id: curtain
        property color tint: "#ffffff"
        property real band: 180
        property real strength: 0.3
        width: band; height: root.height
        antialiasing: true
        ShapePath {
            strokeWidth: 0
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: root.height
                GradientStop { position: 0.0; color: Qt.rgba(curtain.tint.r, curtain.tint.g, curtain.tint.b, 0.0) }
                GradientStop { position: 0.35; color: Qt.rgba(curtain.tint.r, curtain.tint.g, curtain.tint.b, curtain.strength) }
                GradientStop { position: 0.65; color: Qt.rgba(curtain.tint.r, curtain.tint.g, curtain.tint.b, curtain.strength) }
                GradientStop { position: 1.0; color: Qt.rgba(curtain.tint.r, curtain.tint.g, curtain.tint.b, 0.0) }
            }
            startX: 0; startY: 0
            PathLine { x: curtain.band; y: 0 }
            PathLine { x: curtain.band; y: root.height }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: 0 }
        }
    }

    Curtain {
        id: c1
        tint: theme.catServices; band: root.width * 0.55; strength: 0.32
        SequentialAnimation on x {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: -c1.band * 0.4; duration: 17000; easing.type: Easing.InOutSine }
            NumberAnimation { to: root.width - c1.band * 0.7; duration: 21000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on opacity {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: 0.55; duration: 9000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 11000; easing.type: Easing.InOutSine }
        }
    }

    Curtain {
        id: c2
        tint: theme.catEntertainment; band: root.width * 0.5; strength: 0.3
        x: root.width * 0.3
        SequentialAnimation on x {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: root.width - c2.band * 0.6; duration: 23000; easing.type: Easing.InOutSine }
            NumberAnimation { to: -c2.band * 0.3; duration: 19000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on opacity {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: 0.5; duration: 12000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.95; duration: 8000; easing.type: Easing.InOutSine }
        }
    }

    Curtain {
        id: c3
        tint: theme.accent2; band: root.width * 0.6; strength: 0.28
        x: root.width * 0.55
        SequentialAnimation on x {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: root.width * 0.05; duration: 20000; easing.type: Easing.InOutSine }
            NumberAnimation { to: root.width - c3.band * 0.5; duration: 25000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on opacity {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: 0.6; duration: 10000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 13000; easing.type: Easing.InOutSine }
        }
    }

    Curtain {
        id: c4
        tint: theme.catInfo; band: root.width * 0.45; strength: 0.26
        x: root.width * 0.1
        SequentialAnimation on x {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: root.width - c4.band * 0.8; duration: 27000; easing.type: Easing.InOutSine }
            NumberAnimation { to: -c4.band * 0.2; duration: 22000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on opacity {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: 0.45; duration: 11000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.9; duration: 9000; easing.type: Easing.InOutSine }
        }
    }
}
