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
            { lbl: "CPU", val: num(metrics.cpu_usage_percent), max: 100, unit: "%", col: lc(theme.catSystem), show: w.showCpu && num(metrics.cpu_usage_percent) >= 0 },
            { lbl: "GPU", val: num(metrics.gpu_usage_percent), max: 100, unit: "%", col: lc(theme.catGaming), show: w.showGpu && num(metrics.gpu_usage_percent) >= 0 },
            { lbl: "RAM", val: num(metrics.ram_usage_percent), max: 100, unit: "%", col: lc(theme.catProductivity), show: w.showRam && num(metrics.ram_usage_percent) >= 0 },
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
            // STABLE DELEGATES (owner-reported clunk). The model is a literal list
            // of row labels, so it is evaluated ONCE and the six delegates live for
            // the widget's whole life. Binding the Repeater to `w.rows` instead —
            // a fresh JS array every metrics tick — destroyed and recreated every
            // delegate ~2s, so nothing survived long enough to animate and the
            // whole widget flickered through reconstruction. Now a tick only moves
            // the bound VALUES below; the bar glides and the colour cross-fades.
            model: ["CPU", "GPU", "RAM", "DISK", "CPU °", "GPU °"]
            delegate: RowLayout {
                id: sensorRow
                required property string modelData
                // Live lookup into the derived rows (re-evaluates on every metrics/
                // config/accent change); null while this row is hidden.
                readonly property var row: {
                    var rs = w.rows
                    for (var i = 0; i < rs.length; i++) if (rs[i].lbl === sensorRow.modelData) return rs[i]
                    return null
                }
                visible: row !== null
                // Compact tiles are height-starved (a 120px tile leaves ~64px of
                // body): let every row share that height so all six stay fully
                // visible instead of overflowing the clipped body (S12). Expanded
                // tiles keep their natural, top-aligned rows.
                Layout.fillWidth: true; Layout.fillHeight: !w.expanded
                spacing: theme.spacingSm
                Text { text: sensorRow.modelData; font.family: theme.fontMono; color: theme.textSecondary
                    font.pixelSize: w.expanded ? 16 : 12; Layout.preferredWidth: w.expanded ? 62 : 46
                    Layout.fillHeight: !w.expanded; verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight; fontSizeMode: Text.VerticalFit; minimumPixelSize: 6 }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: w.expanded ? 12 : 6
                    radius: height / 2; color: theme.cardBorder
                    Rectangle {
                        height: parent.height; radius: height / 2
                        color: sensorRow.row ? sensorRow.row.col : "transparent"
                        width: sensorRow.row
                               ? parent.width * Math.min(sensorRow.row.val / sensorRow.row.max, 1) : 0
                        // A 1° temperature rise moves ONLY this bar, smoothly — the
                        // token collapses both eases to an instant jump under
                        // reduce-motion. Threshold colour (cool→warn→hot) cross-fades
                        // instead of hard-cutting for the same reason.
                        Behavior on width { NumberAnimation { duration: theme.motionValue; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: theme.motionValue } }
                    }
                }
                Text { text: sensorRow.row ? sensorRow.row.val.toFixed(0) + sensorRow.row.unit : ""
                    font.family: theme.fontMono
                    color: theme.textPrimary; font.pixelSize: w.expanded ? 16 : 12
                    horizontalAlignment: Text.AlignRight; Layout.preferredWidth: w.expanded ? 64 : 50
                    Layout.fillHeight: !w.expanded; verticalAlignment: Text.AlignVCenter
                    fontSizeMode: Text.VerticalFit; minimumPixelSize: 6 }
            }
        }
    }

    // Every row disabled → an explicit placeholder instead of a blank card.
    Text {
        anchors.centerIn: parent
        visible: w.rows.length === 0
        width: parent.width - 2 * theme.spacingSm
        text: "No sensors enabled"
        color: theme.textSecondary
        font.family: theme.fontDisplay
        font.pixelSize: w.expanded ? 16 : 13
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
    }
}
