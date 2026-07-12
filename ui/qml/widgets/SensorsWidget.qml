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
    readonly property bool showDisk: cfg.showDisk !== undefined ? cfg.showDisk : true
    readonly property bool showTemps: cfg.showTemps !== undefined ? cfg.showTemps : true

    function num(x) { return (x === undefined || x === null) ? -1 : x }
    property var rows: {
        // Load bars follow the per-widget accent when one is set, else keep their
        // distinct category colours (which help tell the rows apart at a glance).
        var accentSet = w.accentName !== ""
        function lc(base) { return accentSet ? w.effAccent : base }
        // Temperature bars threshold by the ACTUAL value — a cool GPU must not show
        // a red bar (the old constant amber/red misread as "hot").
        function tc(t) { return t > 85 ? theme.error : t > 70 ? theme.warning : (accentSet ? w.effAccent : theme.catSystem) }
        var ct = num(metrics.cpu_temp_celsius), gt = num(metrics.gpu_temp_celsius)
        var r = [
            { lbl: "CPU", val: metrics.cpu_usage_percent || 0, max: 100, unit: "%", col: lc(theme.catSystem), show: w.showCpu },
            { lbl: "GPU", val: num(metrics.gpu_usage_percent), max: 100, unit: "%", col: lc(theme.catGaming), show: w.showGpu && num(metrics.gpu_usage_percent) >= 0 },
            { lbl: "RAM", val: metrics.ram_usage_percent || 0, max: 100, unit: "%", col: lc(theme.catProductivity), show: w.showRam },
            { lbl: "DISK", val: metrics.disk_usage_percent || 0, max: 100, unit: "%", col: lc(theme.catInfo), show: w.showDisk && (metrics.disk_total_bytes || 0) > 0 },
            { lbl: "CPU °", val: ct, max: 100, unit: "°C", col: tc(ct), show: w.showTemps && ct >= 0 },
            { lbl: "GPU °", val: gt, max: 100, unit: "°C", col: tc(gt), show: w.showTemps && gt >= 0 }
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
