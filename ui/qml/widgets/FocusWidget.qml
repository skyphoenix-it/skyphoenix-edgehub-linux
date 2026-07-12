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
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Focus Timer"; iconName: "focus"; accentColor: theme.catProductivity
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
    // Custom-preset durations (minutes); only used when presetName === "custom".
    readonly property int workMin: cfg.workMin !== undefined ? cfg.workMin : 25
    readonly property int breakMin: cfg.breakMin !== undefined ? cfg.breakMin : 5
    readonly property bool autoStartBreak: cfg.autoStartBreak !== undefined ? cfg.autoStartBreak : false

    // ADHD-friendly "momentum" options (all honoured below).
    readonly property int dailyGoal: cfg.dailyGoal !== undefined ? cfg.dailyGoal : 4
    readonly property bool celebrate: cfg.celebrate !== undefined ? cfg.celebrate : true
    readonly property bool rewardPoints: cfg.rewardPoints !== undefined ? cfg.rewardPoints : true
    readonly property bool showNudges: cfg.showNudges !== undefined ? cfg.showNudges : true
    readonly property bool breakSuggestions: cfg.breakSuggestions !== undefined ? cfg.breakSuggestions : true
    readonly property int points: cfg.points || 0
    readonly property var breakIdeas: [
        "Stand up & stretch", "Drink some water", "Look 20ft away for 20s",
        "Roll your shoulders", "Take 5 slow breaths", "Quick walk around"
    ]
    property var p: presetName === "custom"
        ? ({ work: workMin, short: breakMin, long: breakMin, every: 4, label: "Custom" })
        : (presets[presetName] || presets["classic"])
    property string phase: cfg.phase || "work"     // work | short | long
    property bool running: cfg.running || false
    property int completedWork: cfg.day === today() ? (cfg.doneToday || 0) : 0

    // A local pulse ticks each second (when this instance drives) to refresh
    // `remaining`, which is derived from the persisted absolute end time.
    property int pulse: 0
    property int phaseTotal: phaseSeconds(phase)
    // Ring fill fraction (elapsed). Denominator grows if "+5" pushes remaining
    // past a phase's nominal length, so the ring never underflows past 0.
    readonly property real ringValue: 1 - remaining / Math.max(1, phaseTotal, remaining)
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
    // `completedWork` is derived read-only from the persisted `doneToday`; reset
    // the real key, not the derived one (writing completedWork was a silent no-op
    // that left "N done today" stuck).
    function reset() { save({ doneToday: 0, day: today() }); loadPhase("work", false) }
    function applyPreset(name) { save({ preset: name, doneToday: 0, day: today() }); loadPhase("work", false) }
    function advance(natural) {
        var cw = completedWork
        var nextPhase, done = cw, run
        var pts = points
        if (phase === "work") {
            done = cw + 1
            nextPhase = (done % p.every === 0) ? "long" : "short"
            // Roll straight into the break only when the user opted in;
            // otherwise pause and wait for them to start it.
            run = autoStartBreak
            // Reward: points per session (+ a bonus for hitting the daily goal),
            // and a celebration — a small, honest dopamine hit.
            var hitGoal = (done === dailyGoal)
            if (rewardPoints) pts += 10 + (hitGoal ? 50 : 0)
            if (celebrate) celebrateNow(hitGoal ? "🎯 Goal reached!  +50" : "🎉 Nice! Session done")
        } else {
            nextPhase = "work"
            // Never auto-start a work phase after a break.
            run = false
        }
        var secs = phaseSeconds(nextPhase)
        save({ phase: nextPhase, doneToday: done, day: today(), points: pts,
               running: run, endEpoch: run ? Date.now() + secs * 1000 : 0, pausedRemaining: secs })
        flash.restart()
    }

    // Celebration pop (message scales/fades in over a colour flash).
    property string celebrateMsg: ""
    function celebrateNow(msg) { celebrateMsg = msg; celebrateAnim.restart(); flash.restart() }
    function skip() { advance(false) }

    // Keep the idle clock in sync with the chosen preset / custom lengths: when
    // the timer is NOT running, changing the preset (via the widget's segmented)
    // or the custom minutes (via the config panel) resets the shown time + ring to
    // the new phase length. Guarded so it's a no-op when already correct, and
    // deferred to avoid a binding loop with `p`.
    onPChanged: Qt.callLater(_syncIdleDuration)
    function _syncIdleDuration() {
        if (running) return
        var secs = phaseSeconds(phase)
        if (cfg.pausedRemaining !== secs || cfg.endEpoch)
            save({ pausedRemaining: secs, endEpoch: 0 })
    }

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
    // Celebration message — pops in on a completed session (dopamine kick).
    Text {
        id: celebrateLabel; anchors.centerIn: parent; z: 20
        text: w.celebrateMsg; opacity: 0
        font.pixelSize: w.expanded ? 34 : 18; font.bold: true; font.family: theme.fontDisplay
        color: w.phaseColor(); horizontalAlignment: Text.AlignHCenter
        SequentialAnimation {
            id: celebrateAnim; running: false
            PropertyAction { target: celebrateLabel; property: "scale"; value: 0.6 }
            ParallelAnimation {
                NumberAnimation { target: celebrateLabel; property: "opacity"; from: 0; to: 1; duration: 180 }
                NumberAnimation { target: celebrateLabel; property: "scale"; to: 1.12
                    duration: 260; easing.type: theme.reduceMotion ? Easing.Linear : Easing.OutBack }
            }
            PauseAnimation { duration: 950 }
            NumberAnimation { target: celebrateLabel; property: "opacity"; to: 0; duration: 500 }
        }
    }

    // ── Compact ──
    Item {
        anchors.fill: parent; visible: !w.expanded
        RingProgress {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.9; height: width
            value: w.ringValue
            progressColor: w.phaseColor(); progressColor2: w.phaseColor()
        }
        ColumnLayout {
            anchors.centerIn: parent; spacing: 0
            Text { Layout.alignment: Qt.AlignHCenter; text: w.fmt(w.remaining)
                font.pixelSize: Math.max(20, Math.min(parent.width * 0.26, 34))
                font.family: theme.fontMono; font.bold: true
                color: w.running ? w.phaseColor() : theme.textPrimary }
            Text { Layout.alignment: Qt.AlignHCenter; text: w.phaseLabel()
                font.pixelSize: 12; color: theme.textSecondary }
        }
    }

    // ── Expanded ──
    ColumnLayout {
        anchors.fill: parent; visible: w.expanded; spacing: theme.spacingMd

        SegmentedControl {
            Layout.fillWidth: true; Layout.preferredHeight: theme.touchTertiary
            tint: w.phaseColor()
            options: [ { label: "Classic", value: "classic" }, { label: "Deep", value: "deep" }, { label: "Sprint", value: "sprint" }, { label: "Custom", value: "custom" } ]
            currentValue: w.presetName
            onSelected: function (v) { w.applyPreset(v) }
        }
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            RingProgress {
                id: bigRing; anchors.centerIn: parent
                width: Math.min(parent.width, parent.height); height: width
                value: w.ringValue
                progressColor: w.phaseColor(); progressColor2: w.phaseColor()
            }
            ColumnLayout {
                anchors.centerIn: parent; spacing: 2
                Text { Layout.alignment: Qt.AlignHCenter; text: w.phaseLabel().toUpperCase()
                    font.pixelSize: 14; font.letterSpacing: 2; color: w.phaseColor() }
                Text { Layout.alignment: Qt.AlignHCenter; text: w.fmt(w.remaining)
                    font.pixelSize: Math.min(bigRing.width * 0.30, 92); font.family: theme.fontMono
                    font.bold: true; color: theme.textPrimary }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingSm
                    Text { text: w.completedWork + " / " + w.dailyGoal + " today"
                        font.pixelSize: 12; color: w.completedWork >= w.dailyGoal ? theme.success : theme.textSecondary
                        font.bold: w.completedWork >= w.dailyGoal }
                    Text { visible: w.rewardPoints; text: "·  ⭐ " + w.points + " pts"
                        font.pixelSize: 12; color: theme.textSecondary }
                }
                // Goal progress dots — a glanceable "streak" bar.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter; spacing: 4; Layout.topMargin: 2
                    Repeater {
                        model: Math.min(w.dailyGoal, 8)
                        delegate: Rectangle {
                            required property int index
                            width: 8; height: 8; radius: 4
                            color: index < w.completedWork ? theme.success : theme.cardBorder
                        }
                    }
                }
            }
        }
        // Encouraging nudge (focus) or a break-activity suggestion (break).
        Text {
            Layout.fillWidth: true
            visible: (w.phase === "work" && w.showNudges) || (w.phase !== "work" && w.breakSuggestions)
            horizontalAlignment: Text.AlignHCenter
            text: w.phase === "work"
                  ? w.nudges[w.completedWork % w.nudges.length]
                  : "Break idea: " + w.breakIdeas[w.completedWork % w.breakIdeas.length]
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
