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
    // Per-minute tick injected by the Dashboard (S6): keeps todayKey/breaksToday
    // rolling over at midnight on a 24/7 device instead of freezing at boot-day.
    property int tick: 0

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
    readonly property bool showSuggestion: cfg.showSuggestion !== undefined ? cfg.showSuggestion : true
    // Breaks acknowledged today (momentum), auto-resets across midnight.
    property string todayKey: (w.tick, Qt.formatDate(new Date(), "yyyy-MM-dd"))
    property int breaksToday: cfg.day === todayKey ? (cfg.breaksToday || 0) : 0
    readonly property var breakIdeas: [
        "Stand up & stretch", "Drink some water", "Look 20ft away for 20s",
        "Roll your shoulders", "Take 5 slow breaths", "Quick walk around"
    ]

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
    // Acknowledge a due break: count it toward today's total, then restart the timer.
    function takeBreak() {
        save({ due: false, running: true, breaksToday: breaksToday + 1, day: todayKey,
               pausedRemaining: intervalMin * 60, endEpoch: Date.now() + intervalMin * 60 * 1000 })
    }
    // A config-side interval change reseeds the countdown to the new length (so the
    // slider isn't half-honored), preserving the running/paused state. Only the
    // active instance writes, and it's deferred to avoid a write during binding eval.
    onIntervalMinChanged: Qt.callLater(_applyInterval)
    function _applyInterval() {
        if (!w.active || cfg.intervalMin === undefined) return
        var secs = w.intervalMin * 60
        if (w.running) save({ due: false, pausedRemaining: secs, endEpoch: Date.now() + secs * 1000 })
        else save({ due: false, pausedRemaining: secs, endEpoch: 0 })
    }
    function toggleRun() {
        if (running) {
            // While due, `remaining` is forced to 0 — snapshotting it would
            // persist pausedRemaining:0 and corrupt the timer. Fall back to the
            // last stored remaining (or a full interval) instead.
            var snap = w.due ? (cfg.pausedRemaining !== undefined ? cfg.pausedRemaining : intervalMin * 60)
                             : remaining
            save({ running: false, pausedRemaining: snap })
        } else save({ running: true, endEpoch: Date.now() + remaining * 1000 })
    }
    function setInterval(m) {
        var v = Math.max(5, Math.min(120, m))
        // Preserve the running/paused state: tapping ±5m while paused must not
        // silently resume the countdown.
        var run = w.running
        save({ intervalMin: v, due: false, running: run, pausedRemaining: v * 60,
               endEpoch: run ? Date.now() + v * 60 * 1000 : 0 })
    }
    function fmt(s) {
        var mm = Math.floor(s / 60), ss = s % 60
        return (mm < 10 ? "0" : "") + mm + ":" + (ss < 10 ? "0" : "") + ss
    }

    // Seed an end time so a fresh (auto-running) reminder actually counts down.
    // Component.onCompleted runs BEFORE the store/instanceId are injected, so the
    // original seed here was a no-op and the timer stayed frozen. Instead, run the
    // seed reactively once the store is wired up (and again if the endEpoch key is
    // cleared). Only the active instance seeds, to avoid a double write, and only
    // when endEpoch is genuinely absent (undefined) — an explicit endEpoch:0 means
    // "no live end time, use the fallback" and must be left alone.
    function _seedIfNeeded() {
        if (!w.active || !store || !instanceId) return
        if (w.running && !w.due && cfg.endEpoch === undefined)
            save({ endEpoch: Date.now() + remaining * 1000 })
    }
    Component.onCompleted: _seedIfNeeded()
    onStoreChanged: _seedIfNeeded()
    onInstanceIdChanged: _seedIfNeeded()
    Connections {
        target: w.store
        function onRevisionChanged() { w._seedIfNeeded() }
    }

    Timer {
        interval: 1000; repeat: true; running: w.active && w.running && !w.due
        onTriggered: {
            w.pulse++
            if (w.remaining <= 0) { w.save({ due: true }); flash.restart() }
        }
    }
    Rectangle {
        anchors.fill: parent; radius: theme.radiusLg; color: w.effAccent; opacity: 0; z: 5
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
            // Custom due-messages are user text and can be long — cap the width and
            // wrap/elide so they never overflow the tile (S12).
            Layout.maximumWidth: w.width * 0.92
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap; maximumLineCount: w.expanded ? 3 : 2; elide: Text.ElideRight
            text: w.due ? (w.message.length ? w.message : "Take a break!") : w.fmt(w.remaining)
            font.pixelSize: w.due ? (w.expanded ? 44 : 22)
                                  : (w.expanded ? 88 : Math.max(26, Math.min(w.width * 0.28, 52)))
            font.bold: true; font.family: w.due ? theme.fontDisplay : theme.fontMono
            color: w.due ? w.effAccent : theme.textPrimary
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: !w.due
            text: "until next break"; font.pixelSize: w.expanded ? 15 : 12; color: theme.textSecondary
        }
        // Break-activity suggestion when a break is due (ADHD "what do I do now?").
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: w.due && w.showSuggestion
            Layout.maximumWidth: w.width * 0.9; horizontalAlignment: Text.AlignHCenter
            text: "Try: " + w.breakIdeas[w.breaksToday % w.breakIdeas.length]
            font.pixelSize: w.expanded ? 16 : 12; font.italic: true; color: theme.textTertiary
            elide: Text.ElideRight
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded; spacing: theme.spacingSm
            PillButton { label: w.running ? "Pause" : "Resume"; glyph: w.running ? "⏸" : "▶"
                onClicked: w.toggleRun() }
            PillButton { label: w.due ? "Took it" : "Reset"; glyph: w.due ? "✓" : "⟲"; primary: true
                tint: w.effAccent; onClicked: w.due ? w.takeBreak() : w.reset() }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded; spacing: theme.spacingSm
            PillButton { label: "−5m"; onClicked: w.setInterval(w.intervalMin - 5) }
            Text { text: "every " + w.intervalMin + "m"; color: theme.textSecondary; font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter }
            PillButton { label: "+5m"; onClicked: w.setInterval(w.intervalMin + 5) }
        }
        // Momentum: how many breaks acknowledged today.
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded && w.breaksToday > 0
            text: "✓ " + w.breaksToday + (w.breaksToday === 1 ? " break today" : " breaks today")
            font.pixelSize: 14; color: theme.textSecondary
        }
        // Compact controls — pause/resume and reset straight from the tile.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: theme.spacingXs
            visible: !w.expanded && !w.due; spacing: theme.spacingSm
            PillButton { implicitHeight: 36
                label: w.running ? "Pause" : "Resume"; glyph: w.running ? "⏸" : "▶"
                onClicked: w.toggleRun() }
            PillButton { implicitHeight: 36
                label: "Reset"; glyph: "⟲"; tint: w.effAccent; onClicked: w.reset() }
        }
        // Quick acknowledge from the compact tile.
        PillButton { Layout.alignment: Qt.AlignHCenter; visible: !w.expanded && w.due
            label: "Done"; primary: true; tint: w.effAccent; onClicked: w.takeBreak() }
    }
}
