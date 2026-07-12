import QtQuick
import QtQuick.Layouts

// Break reminder — a repeating interval timer that nudges you to take a break
// (ADHD time-blindness aid). Interval is persisted; the countdown runs while
// the tile is active (single-driver via `active`).
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Break Reminder"; iconName: "break"; accentColor: theme.success
    big: expanded

    // All state lives in the store (absolute end-epoch, running, paused-remaining,
    // due), so the tile and the expanded view are the SAME timer and it survives
    // a restart. Derived from cfg exactly like FocusWidget.
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    property int intervalMin: cfg.intervalMin || 30
    property bool running: cfg.running !== undefined ? cfg.running : true
    property bool due: cfg.due || false
    // Custom reminder text shown when a break is due; empty → default wording.
    readonly property string message: cfg.message !== undefined ? cfg.message : ""

    property int pulse: 0
    property int remaining: {
        pulse
        if (due) return 0
        if (running && cfg.endEpoch)
            return Math.max(0, Math.round((cfg.endEpoch - Date.now()) / 1000))
        return cfg.pausedRemaining !== undefined ? cfg.pausedRemaining : intervalMin * 60
    }

    function save(o) { if (store) store.patchSettings(instanceId, o) }
    function reset() {
        save({ due: false, running: true, pausedRemaining: intervalMin * 60,
               endEpoch: Date.now() + intervalMin * 60 * 1000 })
    }
    function toggleRun() {
        if (running) save({ running: false, pausedRemaining: remaining })
        else save({ running: true, endEpoch: Date.now() + remaining * 1000 })
    }
    function setInterval(m) {
        var v = Math.max(5, Math.min(120, m))
        save({ intervalMin: v, due: false, running: true, pausedRemaining: v * 60,
               endEpoch: Date.now() + v * 60 * 1000 })
    }
    function fmt(s) {
        var mm = Math.floor(s / 60), ss = s % 60
        return (mm < 10 ? "0" : "") + mm + ":" + (ss < 10 ? "0" : "") + ss
    }

    // Seed an end time on first run so a fresh (auto-running) reminder actually
    // counts down. Only the active instance seeds, to avoid a double write.
    Component.onCompleted: {
        if (w.active && running && !due && !cfg.endEpoch)
            save({ endEpoch: Date.now() + remaining * 1000 })
    }

    Timer {
        interval: 1000; repeat: true; running: w.active && w.running && !w.due
        onTriggered: {
            w.pulse++
            if (w.remaining <= 0) { w.save({ due: true }); flash.restart() }
        }
    }
    Rectangle {
        anchors.fill: parent; radius: theme.radiusLg; color: theme.success; opacity: 0; z: 5
        SequentialAnimation on opacity {
            id: flash; running: false; loops: 3
            NumberAnimation { to: 0.30; duration: 250 }
            NumberAnimation { to: 0.0; duration: 400 }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent; spacing: w.expanded ? 14 : 4
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: w.due ? (w.message.length ? w.message : "Take a break!") : w.fmt(w.remaining)
            font.pixelSize: w.due ? (w.expanded ? 44 : 22)
                                  : (w.expanded ? 88 : Math.max(26, Math.min(w.width * 0.28, 52)))
            font.bold: true; font.family: w.due ? theme.fontDisplay : theme.fontMono
            color: w.due ? theme.success : theme.textPrimary
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: !w.due
            text: "until next break"; font.pixelSize: w.expanded ? 15 : 12; color: theme.textSecondary
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded; spacing: theme.spacingSm
            PillButton { label: w.running ? "Pause" : "Resume"; glyph: w.running ? "⏸" : "▶"
                onClicked: w.toggleRun() }
            PillButton { label: "Reset"; glyph: "⟲"; primary: true; tint: theme.success; onClicked: w.reset() }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded; spacing: theme.spacingSm
            PillButton { label: "−5m"; onClicked: w.setInterval(w.intervalMin - 5) }
            Text { text: "every " + w.intervalMin + "m"; color: theme.textSecondary; font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter }
            PillButton { label: "+5m"; onClicked: w.setInterval(w.intervalMin + 5) }
        }
        // Quick reset from the compact tile.
        PillButton { Layout.alignment: Qt.AlignHCenter; visible: !w.expanded && w.due
            label: "Done"; primary: true; tint: theme.success; onClicked: w.reset() }
    }
}
