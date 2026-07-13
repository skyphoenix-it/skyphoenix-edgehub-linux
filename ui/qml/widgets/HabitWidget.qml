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
    // DST-safe previous-calendar-day step (S6): anchor at local noon and use
    // setDate() so a fixed-24h jump can never skip/duplicate a date across a
    // spring-forward / fall-back boundary near midnight.
    function prevDay(d) { var n = new Date(d); n.setHours(12, 0, 0, 0); n.setDate(n.getDate() - 1); return n }
    property string todayKey: (w.tick, key(new Date()))
    property bool doneToday: checkins.indexOf(todayKey) >= 0

    // Streak from an arbitrary check-in list (reused for the live value + the
    // post-check-in value used to drive milestones/best-streak).
    function streakOf(arr) {
        if (!arr.length) return 0
        var set = {}
        for (var i = 0; i < arr.length; i++) set[arr[i]] = true
        var d = new Date(); d.setHours(12, 0, 0, 0)
        var n = 0
        if (!set[key(d)]) d = prevDay(d)
        while (set[key(d)]) { n++; d = prevDay(d) }
        return n
    }
    property int streak: (w.tick, streakOf(checkins))
    // Best streak ever — persisted, but never less than the current run.
    readonly property int bestStreak: Math.max(cfg.bestStreak || 0, streak)
    status: w.expanded ? "" : w.streak + "🔥"

    readonly property var milestones: [7, 14, 30, 60, 100, 200, 365]
    function milestoneMsg(n) {
        if (milestones.indexOf(n) >= 0) return "🏆 " + n + "-day milestone!"
        return "🔥 " + n + (n === 1 ? " day!" : " days!")
    }

    // Only the most recent HEATMAP_DAYS check-ins are ever shown, and the streak
    // only walks backwards from today — so persisted storage is bounded to that
    // window (prevents unbounded growth of the config document over years of use).
    readonly property int heatmapDays: 28
    function toggleToday() {
        if (!store) return
        var a = checkins.slice()
        var i = a.indexOf(todayKey)
        var checking = i < 0
        if (i >= 0) a.splice(i, 1); else a.push(todayKey)
        // Best-ever and milestone are computed from the FULL run before pruning.
        var ns = streakOf(a)
        var prevBest = w.bestStreak
        if (checking) {
            // Announce a milestone only when it's a genuinely NEW best; a plain
            // re-check of an already-reached day shows the flame message instead.
            celebrateNow(ns > prevBest ? milestoneMsg(ns)
                                       : "🔥 " + ns + (ns === 1 ? " day!" : " days!"))
        }
        // Prune to the displayable window (keys sort chronologically as strings).
        a.sort()
        if (a.length > heatmapDays) a = a.slice(a.length - heatmapDays)
        store.patchSettings(instanceId, { checkins: a, bestStreak: Math.max(prevBest, ns) })
    }

    // Celebration pop (mirrors FocusWidget) — the check-in dopamine hit.
    property string celebrateMsg: ""
    function celebrateNow(msg) { celebrateMsg = msg; celebrateAnim.restart(); flash.restart() }
    Rectangle {
        anchors.fill: parent; radius: theme.radiusLg; color: w.effAccent; opacity: 0; z: 5
        SequentialAnimation on opacity {
            id: flash; running: false
            NumberAnimation { to: 0.32; duration: 130 }
            NumberAnimation { to: 0.0; duration: 520 }
        }
    }
    Text {
        id: celebrateLabel; anchors.centerIn: parent; z: 20
        width: parent.width - 2 * theme.spacingLg
        text: w.celebrateMsg; opacity: 0
        font.pixelSize: w.expanded ? 34 : 17; font.bold: true; font.family: theme.fontDisplay
        color: w.effAccent; horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
        SequentialAnimation {
            id: celebrateAnim; running: false
            PropertyAction { target: celebrateLabel; property: "scale"; value: 0.6 }
            ParallelAnimation {
                NumberAnimation { target: celebrateLabel; property: "opacity"; from: 0; to: 1; duration: 180 }
                NumberAnimation { target: celebrateLabel; property: "scale"; to: 1.12
                    duration: 260; easing.type: theme.reduceMotion ? Easing.Linear : Easing.OutBack }
            }
            PauseAnimation { duration: 900 }
            NumberAnimation { target: celebrateLabel; property: "opacity"; to: 0; duration: 500 }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent; spacing: w.expanded ? 14 : 4
        Text {
            Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
            text: w.streak + (w.streak === 1 ? " day 🔥" : " days 🔥")
            font.pixelSize: w.expanded ? 40 : 22; font.bold: true; color: w.effAccent
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        }
        // Best streak — a record to beat (expanded).
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded && w.bestStreak > 0
            text: "Best: " + w.bestStreak + (w.bestStreak === 1 ? " day" : " days")
                  + (w.streak >= w.bestStreak && w.streak > 0 ? "  ·  personal best! 🏆" : "")
            font.pixelSize: 14; color: theme.textSecondary
        }
        // 28-day heatmap. Hidden on compact tiles so the streak + check-in
        // button stay fully within a 1x1 tile (the grid can't fit at that size).
        GridLayout {
            Layout.alignment: Qt.AlignHCenter; columns: 7
            visible: w.expanded
            rowSpacing: w.expanded ? 6 : 3; columnSpacing: w.expanded ? 6 : 3
            Repeater {
                model: 28
                delegate: Rectangle {
                    required property int index
                    property int cell: w.expanded ? 24 : 12
                    width: cell; height: cell; radius: 4
                    // index 27 = today, going back. Calendar-date stepping (S6)
                    // so cells never collide across a DST boundary.
                    property string dk: {
                        w.tick
                        var d = new Date(); d.setHours(12, 0, 0, 0)
                        d.setDate(d.getDate() - (27 - index))
                        return w.key(d)
                    }
                    property bool on: w.checkins.indexOf(dk) >= 0
                    color: on ? w.effAccent : theme.cardBorder
                    opacity: on ? 1 : 0.5
                    border.width: dk === w.todayKey ? 2 : 0; border.color: theme.textPrimary
                }
            }
        }
        // Check in from either mode — a bounded target so a compact tap elsewhere
        // still expands the tile (matches Hydration's "+1" pattern).
        PillButton {
            Layout.alignment: Qt.AlignHCenter
            label: w.doneToday ? (w.expanded ? "Done today ✓" : "✓ today") : "Check in"
            glyph: w.doneToday ? "" : "🔥"
            primary: !w.doneToday; tint: w.effAccent
            onClicked: w.toggleToday()
        }
    }
}
