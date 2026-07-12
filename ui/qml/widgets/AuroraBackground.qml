import QtQuick

// AuroraBackground — northern-lights curtains: a few tall, soft vertical bands
// (transparent at both ends, coloured in the middle) in green/teal/purple theme
// colours that slide horizontally on slow sinusoidal loops with gently animated
// opacity. Uses plain Rectangle vertical gradients (reliable everywhere) rather
// than Shapes. When `active` is false the curtains stay painted but stop moving.
Item {
    id: root
    property bool active: true
    clip: true

    // A single soft vertical curtain.
    component Curtain: Rectangle {
        property color tint: "#ffffff"
        property real strength: 0.3
        height: root.height
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(tint.r, tint.g, tint.b, 0.0) }
            GradientStop { position: 0.35; color: Qt.rgba(tint.r, tint.g, tint.b, strength) }
            GradientStop { position: 0.65; color: Qt.rgba(tint.r, tint.g, tint.b, strength) }
            GradientStop { position: 1.0; color: Qt.rgba(tint.r, tint.g, tint.b, 0.0) }
        }
    }

    Curtain {
        id: c1
        width: root.width * 0.55; tint: theme.catServices; strength: 0.4
        SequentialAnimation on x {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: -c1.width * 0.4; duration: 17000; easing.type: Easing.InOutSine }
            NumberAnimation { to: root.width - c1.width * 0.7; duration: 21000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on opacity {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: 0.55; duration: 9000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 11000; easing.type: Easing.InOutSine }
        }
    }
    Curtain {
        id: c2
        width: root.width * 0.5; tint: theme.catEntertainment; strength: 0.36
        x: root.width * 0.3
        SequentialAnimation on x {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: root.width - c2.width * 0.6; duration: 23000; easing.type: Easing.InOutSine }
            NumberAnimation { to: -c2.width * 0.3; duration: 19000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on opacity {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: 0.5; duration: 12000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.95; duration: 8000; easing.type: Easing.InOutSine }
        }
    }
    Curtain {
        id: c3
        width: root.width * 0.6; tint: theme.accent2; strength: 0.34
        x: root.width * 0.55
        SequentialAnimation on x {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: root.width * 0.05; duration: 20000; easing.type: Easing.InOutSine }
            NumberAnimation { to: root.width - c3.width * 0.5; duration: 25000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on opacity {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: 0.6; duration: 10000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 13000; easing.type: Easing.InOutSine }
        }
    }
    Curtain {
        id: c4
        width: root.width * 0.45; tint: theme.catInfo; strength: 0.3
        x: root.width * 0.1
        SequentialAnimation on x {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: root.width - c4.width * 0.8; duration: 27000; easing.type: Easing.InOutSine }
            NumberAnimation { to: -c4.width * 0.2; duration: 22000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on opacity {
            running: root.active; loops: Animation.Infinite
            NumberAnimation { to: 0.45; duration: 11000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.9; duration: 9000; easing.type: Easing.InOutSine }
        }
    }
}
