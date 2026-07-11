import QtQuick
import QtQuick.Layouts

// Focus / Pomodoro — ADHD-friendly, feature-complete, fully persistent.
//
// All timer state lives in the store (phase, running, an absolute end-epoch,
// paused-remaining, sessions-done-today), so the tile and the expanded view are
// the SAME timer, a running session survives expand/collapse, and it resumes
// after a restart. Uses an absolute end time (not a decrementing counter) so it
// stays correct across backgrounding.
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Focus Timer"; icon: "🎯"; accentColor: theme.catProductivity
    big: expanded; showHeader: expanded

    readonly property var presets: ({
        "classic": { work: 25, short: 5, long: 15, every: 4, label: "Classic" },
        "deep":    { work: 50, short: 10, long: 20, every: 3, label: "Deep" },
        "sprint":  { work: 15, short: 3, long: 10, every: 4, label: "Sprint" }
    })
    readonly property var nudges: [
        "One small step at a time.", "You've got this — stay with it.",
        "Progress over perfection.", "Just focus on this one thing.",
        "Breathe. Reset. Continue.", "Future you says thanks."
    ]

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    property string presetName: cfg.preset || "classic"
    property var p: presets[presetName] || presets["classic"]
    property string phase: cfg.phase || "work"     // work | short | long
    property bool running: cfg.running || false
    property int completedWork: cfg.day === today() ? (cfg.doneToday || 0) : 0

    // A local pulse ticks each second (when this instance drives) to refresh
    // `remaining`, which is derived from the persisted absolute end time.
    property int pulse: 0
    property int phaseTotal: phaseSeconds(phase)
    property int remaining: {
        pulse
        if (running && cfg.endEpoch)
            return Math.max(0, Math.round((cfg.endEpoch - Date.now()) / 1000))
        return cfg.pausedRemaining !== undefined ? cfg.pausedRemaining : phaseTotal
    }

    function today() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }
    function phaseSeconds(ph) { return (ph === "work" ? p.work : ph === "short" ? p.short : p.long) * 60 }
    function phaseColor() { return phase === "work" ? theme.catProductivity : phase === "short" ? theme.success : theme.accent }
    function phaseLabel() { return phase === "work" ? "Focus" : phase === "short" ? "Short Break" : "Long Break" }
    function fmt(s) { var m = Math.floor(s / 60), sec = s % 60; return String(m).padStart(2, '0') + ":" + String(sec).padStart(2, '0') }

    function save(obj) { if (store) store.patchSettings(instanceId, obj) }

    function start() { save({ running: true, endEpoch: Date.now() + remaining * 1000 }) }
    function pause() { save({ running: false, pausedRemaining: remaining }) }
    function toggle() { running ? pause() : start() }
    function addFive() {
        if (running) save({ endEpoch: cfg.endEpoch + 300000 })
        else save({ pausedRemaining: remaining + 300 })
    }
    function loadPhase(ph, run) {
        var secs = phaseSeconds(ph)
        save({ phase: ph, pausedRemaining: secs, running: run, endEpoch: run ? Date.now() + secs * 1000 : 0 })
    }
    function reset() { save({ completedWork: 0, day: today() }); loadPhase("work", false) }
    function applyPreset(name) { save({ preset: name, completedWork: 0, day: today() }); loadPhase("work", false) }
    function advance(natural) {
        var cw = completedWork
        var nextPhase, done = cw
        if (phase === "work") {
            done = cw + 1
            nextPhase = (done % p.every === 0) ? "long" : "short"
        } else {
            nextPhase = "work"
        }
        var secs = phaseSeconds(nextPhase)
        // Auto-continue into the next phase (classic Pomodoro flow).
        save({ phase: nextPhase, doneToday: done, day: today(),
               running: true, endEpoch: Date.now() + secs * 1000, pausedRemaining: secs })
        flash.restart()
    }
    function skip() { advance(false) }

    // Only the active (visible) instance drives completion, so phases never
    // double-advance. `remaining` itself is derived from endEpoch everywhere.
    Timer {
        interval: 1000; repeat: true; running: w.active
        onTriggered: {
            w.pulse++
            if (w.running && w.remaining <= 0) w.advance(true)
        }
    }

    Rectangle {
        anchors.fill: parent; radius: theme.radiusLg; color: w.phaseColor(); opacity: 0; z: 5
        SequentialAnimation on opacity {
            id: flash; running: false
            NumberAnimation { to: 0.35; duration: 120 }
            NumberAnimation { to: 0.0; duration: 500 }
        }
    }

    // ── Compact ──
    Item {
        anchors.fill: parent; visible: !w.expanded
        RingProgress {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.9; height: width
            value: 1 - w.remaining / Math.max(1, w.phaseTotal)
            progressColor: w.phaseColor(); progressColor2: w.phaseColor()
        }
        ColumnLayout {
            anchors.centerIn: parent; spacing: 0
            Text { Layout.alignment: Qt.AlignHCenter; text: w.fmt(w.remaining)
                font.pixelSize: Math.max(20, Math.min(parent.width * 0.26, 34))
                font.family: theme.fontMono; font.bold: true
                color: w.running ? w.phaseColor() : theme.textPrimary }
            Text { Layout.alignment: Qt.AlignHCenter; text: w.phaseLabel()
                font.pixelSize: 10; color: theme.textSecondary }
        }
    }

    // ── Expanded ──
    ColumnLayout {
        anchors.fill: parent; visible: w.expanded; spacing: theme.spacingMd

        SegmentedControl {
            Layout.fillWidth: true; Layout.preferredHeight: theme.touchTertiary
            tint: w.phaseColor()
            options: [ { label: "Classic", value: "classic" }, { label: "Deep", value: "deep" }, { label: "Sprint", value: "sprint" } ]
            currentValue: w.presetName
            onSelected: function (v) { w.applyPreset(v) }
        }
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            RingProgress {
                id: bigRing; anchors.centerIn: parent
                width: Math.min(parent.width, parent.height); height: width
                value: 1 - w.remaining / Math.max(1, w.phaseTotal)
                progressColor: w.phaseColor(); progressColor2: w.phaseColor()
            }
            ColumnLayout {
                anchors.centerIn: parent; spacing: 2
                Text { Layout.alignment: Qt.AlignHCenter; text: w.phaseLabel().toUpperCase()
                    font.pixelSize: 14; font.letterSpacing: 2; color: w.phaseColor() }
                Text { Layout.alignment: Qt.AlignHCenter; text: w.fmt(w.remaining)
                    font.pixelSize: Math.min(bigRing.width * 0.30, 92); font.family: theme.fontMono
                    font.bold: true; color: theme.textPrimary }
                Text { Layout.alignment: Qt.AlignHCenter
                    text: w.completedWork + " done today"; font.pixelSize: 12; color: theme.textSecondary }
            }
        }
        Text {
            Layout.fillWidth: true; visible: w.phase === "work"
            horizontalAlignment: Text.AlignHCenter
            text: w.nudges[w.completedWork % w.nudges.length]
            font.pixelSize: 13; font.italic: true; color: theme.textTertiary; elide: Text.ElideRight
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingSm
            PillButton { label: "Reset"; glyph: "⟲"; tint: theme.textSecondary; onClicked: w.reset() }
            PillButton { label: w.running ? "Pause" : "Start"; glyph: w.running ? "⏸" : "▶"
                primary: true; tint: w.phaseColor(); implicitWidth: 150; onClicked: w.toggle() }
            PillButton { label: "+5"; glyph: "＋"; tint: w.phaseColor(); onClicked: w.addFive() }
            PillButton { label: "Skip"; glyph: "⏭"; tint: theme.textSecondary; onClicked: w.skip() }
        }
    }
}
