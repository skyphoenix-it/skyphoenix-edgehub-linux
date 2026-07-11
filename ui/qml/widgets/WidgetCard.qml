import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Premium widget card with tap-to-expand.
// Uses the shared design-system tokens exposed via `theme` (see main.qml).
Rectangle {
    id: card
    radius: theme.radiusLg
    color: theme.cardBackground
    border.width: 1
    border.color: tapArea.containsMouse ? theme.accent : theme.cardBorder
    Behavior on border.color { ColorAnimation { duration: theme.motionFast } }

    property string title: ""
    property string icon: ""
    property bool expandable: true
    signal tapped()

    default property alias inlineContent: contentHost.data

    // Subtle glass gradient overlay
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.04) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.06) }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.spacingLg
        spacing: theme.spacingSm

        // Header row
        RowLayout {
            visible: title !== "" || icon !== ""
            Layout.fillWidth: true
            spacing: theme.spacingSm
            Layout.preferredHeight: 24

            Text {
                visible: icon !== ""
                text: icon
                font.pixelSize: 20
            }

            Text {
                text: title
                font.pixelSize: theme.fontTitle
                font.weight: Font.Medium
                color: theme.textSecondary
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                visible: expandable
                text: "↗"
                font.pixelSize: 16
                color: theme.accent
                opacity: tapArea.containsMouse ? 0.9 : 0.4
                Behavior on opacity { NumberAnimation { duration: theme.motionFast } }
            }
        }

        // Content area — fills remaining space
        Item {
            id: contentHost
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
        }
    }

    // Press / hover feedback
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Qt.rgba(1, 1, 1, 0.05)
        opacity: tapArea.pressed || tapArea.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: theme.motionFast } }
    }

    scale: tapArea.pressed && expandable ? 0.98 : 1.0
    Behavior on scale { NumberAnimation { duration: theme.motionFast; easing.type: Easing.OutCubic } }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: expandable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (expandable) card.tapped()
        }
    }
}
