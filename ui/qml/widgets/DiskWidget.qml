import QtQuick
import QtQuick.Layouts

// Root-filesystem usage — real data (statvfs via the Rust core).
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Disk"; icon: "💽"; accentColor: theme.catInfo
    big: expanded

    property real v: metrics.disk_usage_percent || 0
    function col(p) { return p > 92 ? theme.error : p > 80 ? theme.warning : theme.catInfo }
    function human(b) {
        if (b >= 1099511627776) return (b / 1099511627776).toFixed(2) + " TB"
        return (b / 1073741824).toFixed(0) + " GB"
    }

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
            Layout.alignment: Qt.AlignHCenter
            text: w.human(metrics.disk_used_bytes || 0) + " / " + w.human(metrics.disk_total_bytes || 0) + "  ·  /"
            font.pixelSize: w.expanded ? 18 : 11; color: theme.textSecondary
        }
    }
}
