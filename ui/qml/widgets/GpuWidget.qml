import QtQuick
import QtQuick.Layouts

// GPU utilization + temperature — real data (amdgpu sysfs via the Rust core).
// Shows "N/A" gracefully when no discrete GPU is discoverable.
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "GPU"; icon: "🎮"; accentColor: theme.catGaming
    big: expanded

    property bool avail: metrics.gpu_usage_percent !== undefined
                         && metrics.gpu_usage_percent !== null
                         && metrics.gpu_usage_percent >= 0
    property real v: avail ? metrics.gpu_usage_percent : 0
    property real temp: (metrics.gpu_temp_celsius === undefined || metrics.gpu_temp_celsius === null || metrics.gpu_temp_celsius < 0)
                        ? -1 : metrics.gpu_temp_celsius
    status: temp > 0 ? temp.toFixed(0) + "°C" : ""
    statusColor: temp > 85 ? theme.error : temp > 70 ? theme.warning : theme.textSecondary
    function col(p) { return p > 90 ? theme.error : p > 65 ? theme.warning : theme.catGaming }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.86
        spacing: w.expanded ? 16 : 6
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: w.avail ? w.v.toFixed(0) + "%" : "N/A"
            font.pixelSize: w.expanded ? 128 : Math.max(28, Math.min(w.width * 0.3, 64))
            font.bold: true; font.family: theme.fontMono
            color: w.avail ? w.col(w.v) : theme.textTertiary
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: w.expanded ? 16 : 8
            radius: height / 2; color: theme.cardBorder; visible: w.avail
            Rectangle {
                height: parent.height; radius: height / 2
                width: parent.width * Math.min(w.v / 100, 1); color: w.col(w.v)
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded && w.temp > 0
            text: "Edge temperature " + w.temp.toFixed(0) + "°C"
            font.pixelSize: 16; color: theme.textSecondary
        }
    }
}
