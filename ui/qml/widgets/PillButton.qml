import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// PillButton — uniform, touch-friendly button used across all widgets.
Rectangle {
    id: btn
    property string label: ""
    property string glyph: ""
    property color tint: theme.accent
    property bool primary: false      // filled vs. outline
    property bool danger: false
    property bool enabledState: true
    signal clicked()

    implicitHeight: theme.touchSecondary
    implicitWidth: Math.max(theme.touchSecondary, contentRow.implicitWidth + theme.spacingXl)
    radius: height / 2
    opacity: enabledState ? 1.0 : 0.4

    property color _c: danger ? theme.error : tint
    color: primary ? _c : Qt.rgba(_c.r, _c.g, _c.b, ma.containsMouse ? 0.22 : 0.12)
    border.width: primary ? 0 : 1
    border.color: Qt.rgba(_c.r, _c.g, _c.b, 0.5)
    Behavior on color { ColorAnimation { duration: theme.motionFast } }
    scale: ma.pressed && enabledState ? 0.96 : 1.0
    Behavior on scale { NumberAnimation { duration: theme.motionFast; easing.type: Easing.OutCubic } }

    RowLayout {
        id: contentRow
        anchors.centerIn: parent
        spacing: theme.spacingXs
        Text {
            visible: btn.glyph !== ""
            text: btn.glyph
            font.pixelSize: 18
            color: btn.primary ? "#0D1117" : btn._c
        }
        Text {
            visible: btn.label !== ""
            text: btn.label
            font.pixelSize: theme.fontLabel
            font.weight: Font.DemiBold
            color: btn.primary ? "#0D1117" : theme.textPrimary
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: btn.enabledState
        onClicked: btn.clicked()
    }
}

