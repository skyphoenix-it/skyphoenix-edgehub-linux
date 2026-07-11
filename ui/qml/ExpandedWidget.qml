import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Full-screen overlay for expanded widget interaction.
// Animation is driven by the `shown` state (bound by the parent) so the
// overlay can be opened and closed repeatedly — not just once.
Rectangle {
    id: overlay
    anchors.fill: parent
    color: theme.backgroundColor
    z: 100

    property string widgetTitle: ""
    property string widgetIcon: ""
    property color accentColor: theme.accent
    property var widgetContent: null
    // Parent binds this to "is a widget currently expanded?".
    property bool shown: false
    signal closeRequested()

    visible: shown || opacity > 0.01

    // State-driven entrance/exit animation (re-runs every open/close).
    scale: shown ? 1.0 : 0.96
    opacity: shown ? 1.0 : 0.0
    Behavior on scale { NumberAnimation { duration: theme.motionPage; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: theme.motionFast } }

    // Backdrop gradient tinted by the widget's category accent.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: theme.backgroundColor }
            GradientStop { position: 1.0; color: theme.backgroundColor2 }
        }
    }
    Rectangle {
        anchors.fill: parent
        opacity: 0.10
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: overlay.accentColor }
            GradientStop { position: 0.5; color: "transparent" }
        }
    }

    // Back button
    Rectangle {
        id: backBtn
        anchors.left: parent.left; anchors.top: parent.top
        anchors.margins: theme.spacingLg
        width: theme.touchSecondary; height: theme.touchSecondary; radius: theme.radiusMd
        color: theme.cardBackground
        border.width: 1; border.color: theme.cardBorder
        z: 10

        Text {
            anchors.centerIn: parent
            text: "←"
            font.pixelSize: 24
            color: theme.textPrimary
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: overlay.closeRequested()
        }
    }

    // Title with icon + accent underline
    Column {
        anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: theme.spacingLg
        spacing: 6
        z: 10
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: theme.spacingSm
            Text { text: overlay.widgetIcon; font.pixelSize: theme.fontTitle + 6 }
            Text {
                text: overlay.widgetTitle
                font.pixelSize: theme.fontTitle + 6; font.bold: true
                font.family: theme.fontDisplay
                color: theme.textPrimary
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 48; height: 3; radius: 2; color: overlay.accentColor
        }
    }

    // Content area
    Item {
        anchors.top: backBtn.bottom; anchors.left: parent.left
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.margins: theme.spacingLg; anchors.topMargin: theme.spacingLg
        clip: true

        // Dynamically-loaded widget content. Unload while hidden to free
        // resources and guarantee a fresh instance on the next open.
        Loader {
            anchors.fill: parent
            active: overlay.shown
            sourceComponent: overlay.shown ? overlay.widgetContent : null
        }
    }
}
