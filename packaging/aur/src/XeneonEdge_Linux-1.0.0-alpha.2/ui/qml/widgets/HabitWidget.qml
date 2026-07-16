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
    // Parse a "yyyy-MM-dd" key into a local-noon Date (mirrors CountdownWidget's
    // component-wise construction — never `new Date(str)`, which is UTC).
    function parseKey(k) { var p = String(k).split("-"); return new Date(+p[0], (+p[1]) - 1, +p[2], 12, 0, 0, 0) }
    // Calendar day immediately before a key, DST-safe.
    function prevDayKey(k) { return key(prevDay(parseKey(k))) }
    property string todayKey: (w.tick, key(new Date()))
    property bool doneToday: checkins.indexOf(todayKey) >= 0

    // Streak from an arbitrary check-in list — used ONLY to (a) derive an initial
    // streak from a legacy config that predates the stored number, and (b)
    // recompute after un-checking today. The live streak itself is a persisted
    // NUMBER (see `streak` / `streakState`), so it is NOT capped by the pruned
    // heatmap window the way `streakOf(checkins)` alone would be.
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
    // The maintained streak state, from storage when present, else derived once
    // from the (possibly pruned) check-in array for BACKWARD COMPAT with old
    // configs that only ever stored `checkins`. Returns { n, last }.
    function streakState() {
        if (cfg.streak !== undefined && cfg.lastCheckinDay !== undefined)
            return { n: cfg.streak, last: cfg.lastCheckinDay }
        var arr = checkins
        if (!arr.length) return { n: 0, last: "" }
        var sorted = arr.slice().sort()
        return { n: streakOf(arr), last: sorted[sorted.length - 1] }
    }
    // Live current streak: the stored number, valid while its last check-in is
    // today or yesterday (grace day); a wider gap means the run has lapsed → 0.
    // Falls back to array-derivation for legacy configs (no stored number).
    property int streak: {
        w.tick
        if (cfg.streak !== undefined && cfg.lastCheckinDay !== undefined) {
            var last = cfg.lastCheckinDay
            if (last === todayKey) return cfg.streak
            if (last === prevDayKey(todayKey)) return cfg.streak   // grace day
            return 0                                               // lapsed
        }
        return streakOf(checkins)                                  // legacy derive
    }
    // Best streak ever — persisted, but never less than the current run.
    readonly property int bestStreak: Math.max(cfg.bestStreak || 0, streak)
    status: w.expanded ? "" : w.streak + "🔥"

    readonly property var milestones: [7, 14, 30, 60, 100, 200, 365]
    function milestoneMsg(n) {
        if (milestones.indexOf(n) >= 0) return "🏆 " + n + "-day milestone!"
        return "🔥 " + n + (n === 1 ? " day!" : " days!")
    }

    // Only the most recent HEATMAP_DAYS check-ins are ever shown, so the stored
    // `checkins` array is pruned to that window (prevents unbounded growth of the
    // config over years of use). The STREAK is stored independently as a number,
    // so it is not capped by this pruning — a 40-day run reports 40, not 28.
    readonly property int heatmapDays: 28
    function toggleToday() {
        if (!store) return
        var a = checkins.slice()
        var i = a.indexOf(todayKey)
        var checking = i < 0
        var prevBest = w.bestStreak
        if (checking) {
            a.push(todayKey)
            var st = streakState()
            var ns
            if (st.last === todayKey) ns = st.n                       // idempotent: already counted today
            else if (st.last === prevDayKey(todayKey)) ns = st.n + 1  // consecutive → continue the run
            else ns = 1                                               // gap or first-ever → fresh streak
            var newBest = Math.max(prevBest, ns)
            // Announce a milestone only when it's a genuinely NEW best; a plain
            // re-check of an already-reached day shows the flame message instead.
            celebrateNow(ns > prevBest ? milestoneMsg(ns)
                                       : "🔥 " + ns + (ns === 1 ? " day!" : " days!"))
            // Prune the heatmap array (keys sort chronologically as strings), but
            // persist the full streak NUMBER + the last check-in day.
            a.sort()
            if (a.length > heatmapDays) a = a.slice(a.length - heatmapDays)
            store.patchSettings(instanceId, { checkins: a, streak: ns,
                                lastCheckinDay: todayKey, bestStreak: newBest })
        } else {
            // Un-check today: recompute the maintained number from the shorter
            // array (best-effort, walks back from today/yesterday); never lower
            // the best-ever.
            a.splice(i, 1)
            var recomputed = streakOf(a)
            var sorted = a.slice().sort()
            var newLast = sorted.length ? sorted[sorted.length - 1] : ""
            a.sort()
            if (a.length > heatmapDays) a = a.slice(a.length - heatmapDays)
            store.patchSettings(instanceId, { checkins: a, streak: recomputed,
                                lastCheckinDay: newLast, bestStreak: prevBest })
        }
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
