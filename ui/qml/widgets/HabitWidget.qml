import QtQuick
import QtQuick.Layouts

// Habit streak — daily check-ins with a real streak count + heatmap.
// Persisted; streak is computed from consecutive days ending today/yesterday.
//
// Sizing (W1 wave 2b): the heatmap used to be expanded-only, on the reasoning
// (still in WidgetCatalog) that "a tile shows a streak number + one button,
// whatever room it is given". That outlived its truth: the 28-day grid is 7x4
// cells, which fits a 696x819 baseline tile with room to spare — so a tile with
// the space now earns the history rather than showing a lone number in a big box.
//   • 0.5x0.5 (micro) — headerless: the streak number + Check in. The heatmap is
//                       genuinely too small to read at 348x409, so it stays off.
//   • 1x1 (baseline)  — streak + the 28-day heatmap + Check in.
//   • wide            — the streak/button column BESIDE the heatmap.
//   • tall            — streak, heatmap, button stacked.
//   • full (overlay)  — unchanged: streak + best + heatmap + button.
// The check-in button is a PillButton (theme.touchSecondary) at every size — it is
// the whole interaction, so it is never shrunk to make a layout fit.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: w.name.length ? w.name : "Habit"; iconName: "habit"; accentColor: theme.catProductivity
    showHeader: !micro

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

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    readonly property bool horiz: sizeClass === "wide"
    // The heatmap is 7 wide x 4 down; a micro tile cannot show 28 legible cells.
    readonly property bool showHeatmap: w.expanded || !w.micro
    readonly property real streakPx: w.expanded ? 40
        : w.micro ? Math.max(18, Math.min(width * 0.22, height * 0.20, 64))
        : Math.max(16, Math.min((w.horiz ? width * 0.5 : width) * 0.10,
                                height * 0.10, 44))
    // Cell size follows the box. `horiz` measures against its own column, and
    // gives the 4 rows a real height budget (the shared 0.06 term starved a
    // 846x306 wide box where the map sits beside the number, not under it).
    readonly property real heatCell: w.expanded ? 24
        : Math.max(8, Math.min((w.horiz ? width * 0.5 : width) / 9,
                               height * (w.horiz ? 0.14 : 0.06), 34))

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

    // `columns` flips for a wide box; that only RESHAPES — no delegate is rebuilt
    // (the heatmap's model is the literal 28, so its cells live for the widget's
    // whole life and a check-in only moves their bound values).
    GridLayout {
        anchors.centerIn: parent
        width: parent.width
        columns: w.horiz ? 2 : 1
        rowSpacing: w.expanded ? 14 : 6
        columnSpacing: theme.spacingLg

        // 28-day heatmap. Was expanded-only "because the grid can't fit"; at
        // 7x4 cells it fits every size but the 1/12 tile, so it is now earned by
        // room rather than by mode.
        GridLayout {
            Layout.alignment: Qt.AlignCenter
            columns: 7
            visible: w.showHeatmap
            rowSpacing: Math.max(2, w.heatCell * 0.18)
            columnSpacing: Math.max(2, w.heatCell * 0.18)
            Repeater {
                model: 28
                delegate: Rectangle {
                    required property int index
                    // Layout.preferred*, not width/height: a GridLayout sizes its
                    // children from their implicit/preferred hints and IGNORES a
                    // plain width, which collapsed every cell to a ~11px speck.
                    Layout.preferredWidth: Math.round(w.heatCell)
                    Layout.preferredHeight: Math.round(w.heatCell)
                    radius: Math.max(2, Math.round(w.heatCell) * 0.17)
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

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignCenter
            spacing: w.expanded ? 14 : 4

            Text {
                Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
                text: w.streak + (w.streak === 1 ? " day 🔥" : " days 🔥")
                font.pixelSize: Math.round(w.streakPx); font.bold: true; color: w.effAccent
                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            }
            // Best streak — a record to beat (expanded).
            Text {
                Layout.alignment: Qt.AlignHCenter; visible: w.expanded && w.bestStreak > 0
                text: "Best: " + w.bestStreak + (w.bestStreak === 1 ? " day" : " days")
                      + (w.streak >= w.bestStreak && w.streak > 0 ? "  ·  personal best! 🏆" : "")
                font.pixelSize: 14; color: theme.textSecondary
            }
            // Check in from every size — a PillButton is theme.touchSecondary (60),
            // above the 52 minimum, and this is the widget's whole interaction.
            PillButton {
                Layout.alignment: Qt.AlignHCenter
                label: w.doneToday ? (w.expanded ? "Done today ✓" : "✓ today") : "Check in"
                glyph: w.doneToday ? "" : "🔥"
                primary: !w.doneToday; tint: w.effAccent
                onClicked: w.toggleToday()
            }
        }
    }
}
