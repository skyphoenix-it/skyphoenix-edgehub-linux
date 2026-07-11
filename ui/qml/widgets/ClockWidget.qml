import QtQuick
import QtQuick.Layouts

// Digital clock — driven by the shared dashboard tick (no per-widget timer).
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Clock"; icon: "🕐"; accentColor: theme.catSystem
    big: expanded
    status: (w.tick, Qt.formatDate(new Date(), "ddd"))

    ColumnLayout {
        anchors.centerIn: parent
        spacing: w.expanded ? 8 : 2
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: (w.tick, Qt.formatTime(new Date(), "HH:mm"))
            font.pixelSize: w.expanded ? 168 : Math.max(30, Math.min(w.width * 0.24, 74))
            font.bold: true; font.family: theme.fontMono; color: theme.textPrimary
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded
            text: (w.tick, Qt.formatTime(new Date(), "ss")) + " sec"
            font.pixelSize: 24; font.family: theme.fontMono; color: theme.accent
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: (w.tick, Qt.formatDate(new Date(), w.expanded ? "dddd, MMMM d yyyy" : "MMM d"))
            font.pixelSize: w.expanded ? 26 : 13; color: theme.textSecondary
        }
    }
}
