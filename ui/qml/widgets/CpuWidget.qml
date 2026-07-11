import QtQuick
import QtQuick.Layouts

// CPU utilization + temperature — real data from the Rust core (metricsJson).
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "CPU"; icon: "🖥"; accentColor: theme.catSystem
    big: expanded

    property real v: metrics.cpu_usage_percent || 0
    property real temp: (metrics.cpu_temp_celsius === undefined || metrics.cpu_temp_celsius === null) ? -1 : metrics.cpu_temp_celsius
    status: temp > 0 ? temp.toFixed(0) + "°C" : ""
    statusColor: temp > 85 ? theme.error : temp > 68 ? theme.warning : theme.textSecondary
    function col(p) { return p > 85 ? theme.error : p > 60 ? theme.warning : theme.catSystem }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.86
        spacing: w.expanded ? 16 : 6
        Text {
            Layout.alignment: Qt.AlignHCenter; text: w.v.toFixed(0) + "%"
            font.pixelSize: w.expanded ? 128 : Math.max(28, Math.min(w.width * 0.3, 64))
            font.bold: true; font.family: theme.fontMono; color: w.col(w.v)
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: w.expanded ? 16 : 8
            radius: height / 2; color: theme.cardBorder
            Rectangle {
                height: parent.height; radius: height / 2
                width: parent.width * Math.min(w.v / 100, 1); color: w.col(w.v)
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded
            text: (metrics.cpu_core_count || 0) + " logical cores"
                  + (w.temp > 0 ? "  ·  " + w.temp.toFixed(0) + "°C" : "")
            font.pixelSize: 16; color: theme.textSecondary
        }
    }
}
