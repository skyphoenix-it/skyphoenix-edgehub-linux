import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ─────────────────────────────────────────────────────────────────────────
// WidgetChrome — the shared, uniform frame for EVERY widget.
//
// This is the "common thread" of the design language: a glass card with a
// subtle gradient, an accent glow, and a consistent header (icon + title +
// optional trailing status). Individual widgets place their content inside
// via the default `content` alias and only need to worry about their data.
//
//   WidgetChrome {
//       title: "Focus"; icon: "🎯"; accentColor: theme.catProductivity
//       big: height > 240
//       // ...your content here...
//   }
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: chrome

    // --- Public API ---
    property string title: ""
    property string icon: ""
    property color accentColor: theme.accent
    property string status: ""          // small trailing status text (top-right)
    property color statusColor: theme.textSecondary
    property bool big: height > 240      // "expanded" mode (richer content)
    property bool showHeader: true
    property bool interactive: false     // draw an accent ring on hover
    // When hosted inside the expanded overlay (which supplies its own card),
    // drop this widget's own card surface + padding to avoid a card-in-a-card.
    property bool chromeless: false
    property real contentMargins: chromeless ? 0 : (big ? theme.spacingLg : theme.spacingSm)
    property alias headerRightItem: headerRight.data

    default property alias content: body.data

    // Convenience: header height scales with size.
    readonly property int headerHeight: big ? 30 : 20

    // --- Card surface ---
    Rectangle {
        id: surface
        visible: !chrome.chromeless
        anchors.fill: parent
        radius: theme.radiusLg
        color: theme.cardFill()
        border.width: 1
        border.color: chrome.interactive && hoverArea.containsMouse
                      ? chrome.accentColor : theme.cardBorder
        Behavior on border.color { ColorAnimation { duration: theme.motionFast } }

        // Diagonal glass gradient
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.05) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.10) }
            }
        }

        // Accent wash in the top-left corner — ties each widget to its category.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            opacity: 0.10
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: chrome.accentColor }
                GradientStop { position: 0.55; color: "transparent" }
            }
        }

        // Top accent hairline (glow)
        Rectangle {
            visible: theme.glow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: parent.radius
            anchors.rightMargin: parent.radius
            height: 2
            radius: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: chrome.accentColor }
                GradientStop { position: 1.0; color: "transparent" }
            }
            opacity: 0.7
        }
    }

    // --- Content column: header + body ---
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: chrome.contentMargins
        spacing: chrome.big ? theme.spacingSm : theme.spacingXs

        // Header
        RowLayout {
            visible: chrome.showHeader && (chrome.title !== "" || chrome.icon !== "")
            Layout.fillWidth: true
            Layout.preferredHeight: chrome.headerHeight
            spacing: theme.spacingSm

            Text {
                visible: chrome.icon !== ""
                text: chrome.icon
                font.pixelSize: chrome.big ? 18 : 13
            }
            Text {
                text: chrome.title
                font.pixelSize: chrome.big ? theme.fontTitle : 11
                font.weight: Font.DemiBold
                font.family: theme.fontDisplay
                color: theme.textSecondary
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            // Optional custom trailing items (buttons etc.)
            RowLayout {
                id: headerRight
                spacing: theme.spacingXs
                Layout.alignment: Qt.AlignVCenter
            }
            Text {
                visible: chrome.status !== ""
                text: chrome.status
                font.pixelSize: chrome.big ? 12 : 9
                font.family: theme.fontMono
                color: chrome.statusColor
            }
        }

        // Body — the widget's own content lives here.
        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
        }
    }

    // Hover ring for interactive widgets
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: chrome.interactive
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
    }
}

