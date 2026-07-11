import QtQuick
import QtQuick.Layouts

// Break reminder — a repeating interval timer that nudges you to take a break
// (ADHD time-blindness aid). Interval is persisted; the countdown runs while
// the tile is active (single-driver via `active`).
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Break Reminder"; icon: "☕"; accentColor: theme.success
    big: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    property int intervalMin: cfg.intervalMin || 30
    property int remaining: intervalMin * 60
    property bool running: true
    property bool due: false

    function reset() { remaining = intervalMin * 60; due = false }
    function setInterval(m) {
        var v = Math.max(5, Math.min(120, m))
        if (store) store.setSetting(instanceId, "intervalMin", v)
        remaining = v * 60; due = false
    }
    function fmt(s) {
        var mm = Math.floor(s / 60), ss = s % 60
        return (mm < 10 ? "0" : "") + mm + ":" + (ss < 10 ? "0" : "") + ss
    }
    onIntervalMinChanged: if (!due) remaining = intervalMin * 60

    Timer {
        interval: 1000; repeat: true; running: w.active && w.running
        onTriggered: {
            if (w.remaining > 0) w.remaining--
            else { w.due = true; flash.restart() }
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
            text: w.due ? "Take a break!" : w.fmt(w.remaining)
            font.pixelSize: w.due ? (w.expanded ? 44 : 22)
                                  : (w.expanded ? 88 : Math.max(26, Math.min(w.width * 0.28, 52)))
            font.bold: true; font.family: w.due ? theme.fontDisplay : theme.fontMono
            color: w.due ? theme.success : theme.textPrimary
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: !w.due
            text: "until next break"; font.pixelSize: w.expanded ? 15 : 10; color: theme.textSecondary
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded; spacing: theme.spacingSm
            PillButton { label: w.running ? "Pause" : "Resume"; glyph: w.running ? "⏸" : "▶"
                onClicked: w.running = !w.running }
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
