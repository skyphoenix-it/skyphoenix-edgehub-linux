import QtQuick
import QtQuick.Layouts

// Habit streak — daily check-ins with a real streak count + heatmap.
// Persisted; streak is computed from consecutive days ending today/yesterday.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: w.name.length ? w.name : "Habit"; iconName: "habit"; accentColor: theme.catProductivity
    big: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property var checkins: cfg.checkins || []
    // Optional habit name; empty → default "Habit" header.
    readonly property string name: cfg.name !== undefined ? cfg.name : ""
    function key(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
    property string todayKey: (w.tick, key(new Date()))
    property bool doneToday: checkins.indexOf(todayKey) >= 0

    property int streak: {
        w.tick
        if (!checkins.length) return 0
        var set = {}
        for (var i = 0; i < checkins.length; i++) set[checkins[i]] = true
        var d = new Date(); var n = 0
        // Allow the streak to count from yesterday if today isn't checked yet.
        if (!set[key(d)]) d = new Date(d.getTime() - 86400000)
        while (set[key(d)]) { n++; d = new Date(d.getTime() - 86400000) }
        return n
    }
    status: w.expanded ? "" : w.streak + "🔥"

    function toggleToday() {
        var a = checkins.slice()
        var i = a.indexOf(todayKey)
        if (i >= 0) a.splice(i, 1); else a.push(todayKey)
        if (store) store.setSetting(instanceId, "checkins", a)
    }

    ColumnLayout {
        anchors.centerIn: parent; spacing: w.expanded ? 14 : 4
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: w.streak + (w.streak === 1 ? " day 🔥" : " days 🔥")
            font.pixelSize: w.expanded ? 40 : 22; font.bold: true; color: theme.catProductivity
        }
        // 28-day heatmap
        GridLayout {
            Layout.alignment: Qt.AlignHCenter; columns: 7
            rowSpacing: w.expanded ? 6 : 3; columnSpacing: w.expanded ? 6 : 3
            Repeater {
                model: 28
                delegate: Rectangle {
                    required property int index
                    property int cell: w.expanded ? 24 : 12
                    width: cell; height: cell; radius: 4
                    // index 27 = today, going back
                    property string dk: {
                        w.tick
                        var d = new Date(new Date().getTime() - (27 - index) * 86400000)
                        return w.key(d)
                    }
                    property bool on: w.checkins.indexOf(dk) >= 0
                    color: on ? theme.catProductivity : theme.cardBorder
                    opacity: on ? 1 : 0.5
                    border.width: dk === w.todayKey ? 2 : 0; border.color: theme.textPrimary
                }
            }
        }
        PillButton {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded
            label: w.doneToday ? "Done today ✓" : "Check in"
            glyph: w.doneToday ? "" : "🔥"
            primary: !w.doneToday; tint: theme.catProductivity
            onClicked: w.toggleToday()
        }
    }
}
