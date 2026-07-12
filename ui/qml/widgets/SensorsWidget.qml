import QtQuick
import QtQuick.Layouts

// Sensor cluster — CPU / GPU / RAM utilization + temperatures in one glance.
// All values are real (from the Rust core); rows without data are hidden.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Sensors"; iconName: "sensors"; accentColor: theme.catSystem
    big: expanded

    // Live per-instance config (see WidgetConfigSchema "sensors").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property bool showCpu: cfg.showCpu !== undefined ? cfg.showCpu : true
    readonly property bool showGpu: cfg.showGpu !== undefined ? cfg.showGpu : true
    readonly property bool showRam: cfg.showRam !== undefined ? cfg.showRam : true

    function num(x) { return (x === undefined || x === null) ? -1 : x }
    property var rows: {
        var r = [
            { lbl: "CPU", val: metrics.cpu_usage_percent || 0, max: 100, unit: "%", col: theme.catSystem, show: w.showCpu },
            { lbl: "GPU", val: num(metrics.gpu_usage_percent), max: 100, unit: "%", col: theme.catGaming, show: w.showGpu && num(metrics.gpu_usage_percent) >= 0 },
            { lbl: "RAM", val: metrics.ram_usage_percent || 0, max: 100, unit: "%", col: theme.catProductivity, show: w.showRam },
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
                    font.pixelSize: w.expanded ? 16 : 12; Layout.preferredWidth: w.expanded ? 62 : 46 }
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
                    color: theme.textPrimary; font.pixelSize: w.expanded ? 16 : 12
                    horizontalAlignment: Text.AlignRight; Layout.preferredWidth: w.expanded ? 64 : 50 }
            }
        }
    }
}
