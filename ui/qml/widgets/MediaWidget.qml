import QtQuick
import QtQuick.Layouts

// Now Playing — real MPRIS control via the `media` bridge (Spotify, YouTube
// Music in a browser, any MPRIS player). Shows a genuine "nothing playing"
// state rather than fabricated data.
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Now Playing"; icon: "🎵"; accentColor: theme.catEntertainment
    big: expanded

    property bool avail: (typeof media !== "undefined") && media && media.available
    status: avail ? media.playerName : ""

    // Nothing-playing placeholder (accurate state, not fake content)
    ColumnLayout {
        anchors.centerIn: parent; visible: !w.avail; spacing: 6
        Text { Layout.alignment: Qt.AlignHCenter; text: "🎧"; opacity: 0.5
            font.pixelSize: w.expanded ? 64 : 34 }
        Text { Layout.alignment: Qt.AlignHCenter; text: "Nothing playing"
            color: theme.textSecondary; font.pixelSize: w.expanded ? 18 : 12 }
    }

    // Compact
    RowLayout {
        anchors.fill: parent; anchors.margins: theme.spacingSm
        visible: w.avail && !w.expanded; spacing: theme.spacingSm
        Rectangle {
            Layout.preferredWidth: 46; Layout.preferredHeight: 46; radius: theme.radiusSm; clip: true
            gradient: Gradient { GradientStop { position: 0; color: theme.catEntertainment } GradientStop { position: 1; color: theme.accent } }
            Image { id: artC; anchors.fill: parent; source: w.avail && media.artUrl ? media.artUrl : ""
                fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
                visible: status === Image.Ready }
            Text { anchors.centerIn: parent; text: "♪"; color: "#fff"; font.pixelSize: 22
                visible: artC.status !== Image.Ready }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 0
            Text { text: w.avail ? media.title : ""; color: theme.textPrimary; font.pixelSize: 13
                font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { text: w.avail ? media.artist : ""; color: theme.textSecondary; font.pixelSize: 11
                elide: Text.ElideRight; Layout.fillWidth: true }
        }
        Text { text: (w.avail && media.playing) ? "⏸" : "▶"; font.pixelSize: 24; color: theme.catEntertainment
            MouseArea { anchors.fill: parent; onClicked: if (w.avail) media.playPause() } }
    }

    // Expanded
    ColumnLayout {
        anchors.fill: parent; anchors.margins: theme.spacingLg
        visible: w.avail && w.expanded; spacing: theme.spacingMd
        Item { Layout.fillHeight: true }
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(w.width * 0.5, 260); Layout.preferredHeight: Layout.preferredWidth
            radius: theme.radiusLg; clip: true
            gradient: Gradient { GradientStop { position: 0; color: theme.catEntertainment } GradientStop { position: 1; color: theme.accent } }
            Image { id: artE; anchors.fill: parent; source: w.avail && media.artUrl ? media.artUrl : ""
                fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
                visible: status === Image.Ready }
            Text { anchors.centerIn: parent; text: "♪"; color: "#fff"; font.pixelSize: 80
                visible: artE.status !== Image.Ready }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: w.avail ? media.title : ""; font.pixelSize: 26; font.bold: true
                color: theme.textPrimary; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: w.avail ? (media.artist + (media.album ? "  ·  " + media.album : "")) : ""
                font.pixelSize: 15; color: theme.textSecondary; elide: Text.ElideRight }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 6; radius: 3; color: theme.cardBorder
            Rectangle { height: parent.height; radius: 3; color: theme.catEntertainment
                width: parent.width * Math.max(0, Math.min(1, w.avail ? media.position : 0))
                Behavior on width { NumberAnimation { duration: 400 } } }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingXl
            Text { text: "⏮"; font.pixelSize: 36; color: theme.textPrimary
                MouseArea { anchors.fill: parent; onClicked: if (w.avail) media.previous() } }
            Rectangle {
                Layout.preferredWidth: theme.touchPrimary; Layout.preferredHeight: theme.touchPrimary
                radius: width / 2; color: theme.catEntertainment
                Text { anchors.centerIn: parent; text: (w.avail && media.playing) ? "⏸" : "▶"
                    font.pixelSize: 32; color: "#0D1117" }
                MouseArea { anchors.fill: parent; onClicked: if (w.avail) media.playPause() }
            }
            Text { text: "⏭"; font.pixelSize: 36; color: theme.textPrimary
                MouseArea { anchors.fill: parent; onClicked: if (w.avail) media.next() } }
        }
        Item { Layout.fillHeight: true }
    }
}
