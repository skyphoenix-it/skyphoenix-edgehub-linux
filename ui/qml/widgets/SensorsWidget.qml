import QtQuick
import QtQuick.Layouts

// Sensor cluster — CPU / GPU / RAM utilization + temperatures in one glance.
// All values are real (from the Rust core); rows without data are hidden.
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Sensors"; icon: "📊"; accentColor: theme.catSystem
    big: expanded

    function num(x) { return (x === undefined || x === null) ? -1 : x }
    property var rows: {
        var r = [
            { lbl: "CPU", val: metrics.cpu_usage_percent || 0, max: 100, unit: "%", col: theme.catSystem, show: true },
            { lbl: "GPU", val: num(metrics.gpu_usage_percent), max: 100, unit: "%", col: theme.catGaming, show: num(metrics.gpu_usage_percent) >= 0 },
            { lbl: "RAM", val: metrics.ram_usage_percent || 0, max: 100, unit: "%", col: theme.catProductivity, show: true },
            { lbl: "DISK", val: metrics.disk_usage_percent || 0, max: 100, unit: "%", col: theme.catInfo, show: (metrics.disk_total_bytes || 0) > 0 },
            { lbl: "CPU °", val: num(metrics.cpu_temp_celsius), max: 100, unit: "°C", col: theme.warning, show: num(metrics.cpu_temp_celsius) >= 0 },
            { lbl: "GPU °", val: num(metrics.gpu_temp_celsius), max: 100, unit: "°C", col: theme.error, show: num(metrics.gpu_temp_celsius) >= 0 }
        ]
        var out = []
        for (var i = 0; i < r.length; i++) if (r[i].show) out.push(r[i])
        return out
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: w.expanded ? 12 : 5
        Repeater {
            model: w.rows
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: theme.spacingSm
                Text { text: modelData.lbl; font.family: theme.fontMono; color: theme.textSecondary
                    font.pixelSize: w.expanded ? 16 : 10; Layout.preferredWidth: w.expanded ? 62 : 42 }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: w.expanded ? 12 : 6
                    radius: height / 2; color: theme.cardBorder
                    Rectangle {
                        height: parent.height; radius: height / 2; color: modelData.col
                        width: parent.width * Math.min(modelData.val / modelData.max, 1)
                        Behavior on width { NumberAnimation { duration: 400 } }
                    }
                }
                Text { text: modelData.val.toFixed(0) + modelData.unit; font.family: theme.fontMono
                    color: theme.textPrimary; font.pixelSize: w.expanded ? 16 : 10
                    horizontalAlignment: Text.AlignRight; Layout.preferredWidth: w.expanded ? 64 : 46 }
            }
        }
    }
}
