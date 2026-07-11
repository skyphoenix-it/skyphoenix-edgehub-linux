import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ─────────────────────────────────────────────────────────────────────────
// FocusTimer — full-featured, ADHD-friendly focus / Pomodoro widget.
//
// Features:
//   • Work / Short break / Long break phases with automatic cycling
//   • Configurable durations via presets (Classic 25·5·15, Deep 50·10·20,
//     Sprint 15·3·10, and a custom mode)
//   • Session counter (e.g. "Session 2 / 4") and long-break-after-N logic
//   • Big circular progress ring (glanceable at any tile size)
//   • Start / Pause / Reset, +5 min, Skip phase
//   • Optional "keep me on task" nudge label that rotates encouragements
//   • Gentle flash + chime hook on phase completion
//   • Compact tile mode (small) auto-collapses to just the ring + time
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: focus
    property bool big: height > 240

    // Phase model
    // phase: "work" | "short" | "long"
    property string phase: "work"
    property bool running: false

    // Presets: [workMin, shortMin, longMin, longEvery]
    property var presets: ({
        "classic": { work: 25, short: 5, long: 15, every: 4, label: "Classic" },
        "deep":    { work: 50, short: 10, long: 20, every: 3, label: "Deep" },
        "sprint":  { work: 15, short: 3, long: 10, every: 4, label: "Sprint" },
        "custom":  { work: 30, short: 6, long: 18, every: 4, label: "Custom" }
    })
    property string presetName: "classic"
    property var p: presets[presetName]

    property int completedWork: 0            // how many work sessions done
    property int remaining: 25 * 60          // seconds left in current phase (set in onCompleted)
    property int phaseTotal: 25 * 60         // seconds in current phase (set in onCompleted)

    // ADHD-friendly rotating nudges
    property var nudges: [
        "One small step at a time.",
        "You've got this — stay with it.",
        "Progress over perfection.",
        "Just focus on this one thing.",
        "Breathe. Reset. Continue.",
        "Future you says thanks."
    ]
    property int nudgeIdx: 0

    signal phaseCompleted(string finishedPhase)

    function phaseColor() {
        return phase === "work" ? theme.catProductivity
             : phase === "short" ? theme.success : theme.accent
    }
    function phaseLabel() {
        return phase === "work" ? "Focus" : phase === "short" ? "Short Break" : "Long Break"
    }
    function phaseSeconds(ph) {
        return (ph === "work" ? p.work : ph === "short" ? p.short : p.long) * 60
    }
    function loadPhase(ph) {
        phase = ph
        phaseTotal = phaseSeconds(ph)
        remaining = phaseTotal
    }
    function applyPreset(name) {
        presetName = name
        p = presets[name]
        running = false
        completedWork = 0
        loadPhase("work")
    }
    function reset() {
        running = false
        completedWork = 0
        loadPhase("work")
    }
    function skip() { advancePhase(false) }

    function advancePhase(natural) {
        if (natural) focus.phaseCompleted(phase)
        if (phase === "work") {
            completedWork++
            nudgeIdx = (nudgeIdx + 1) % nudges.length
            if (completedWork % p.every === 0) loadPhase("long")
            else loadPhase("short")
        } else {
            loadPhase("work")
        }
        flash.restart()
    }

    Timer {
        interval: 1000; repeat: true; running: focus.running
        onTriggered: {
            if (focus.remaining > 0) focus.remaining--
            else focus.advancePhase(true)
        }
    }

    // Completion flash overlay
    Rectangle {
        anchors.fill: parent
        radius: theme.radiusLg
        color: focus.phaseColor()
        opacity: 0
        z: 5
        SequentialAnimation on opacity {
            id: flash; running: false
            NumberAnimation { to: 0.35; duration: 120 }
            NumberAnimation { to: 0.0; duration: 500 }
        }
    }

    // ── Compact layout (small tile) ──
    Item {
        anchors.fill: parent
        visible: !focus.big
        RingProgress {
            id: miniRing
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.9
            height: width
            value: 1 - focus.remaining / Math.max(1, focus.phaseTotal)
            progressColor: focus.phaseColor()
            progressColor2: focus.phaseColor()
        }
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: fmt(focus.remaining)
                font.pixelSize: Math.min(parent.width * 0.28, 34)
                font.family: theme.fontMono; font.bold: true
                color: focus.running ? focus.phaseColor() : theme.textPrimary
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: focus.phaseLabel()
                font.pixelSize: 10; color: theme.textSecondary
            }
        }
    }

    // ── Expanded layout ──
    ColumnLayout {
        anchors.fill: parent
        visible: focus.big
        spacing: theme.spacingMd

        // Preset selector
        SegmentedControl {
            Layout.fillWidth: true
            Layout.preferredHeight: theme.touchTertiary
            tint: focus.phaseColor()
            options: [
                { label: "Classic", value: "classic" },
                { label: "Deep",    value: "deep" },
                { label: "Sprint",  value: "sprint" },
                { label: "Custom",  value: "custom" }
            ]
            currentValue: focus.presetName
            onSelected: function(v) { focus.applyPreset(v) }
        }

        // Big ring + time
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            RingProgress {
                id: bigRing
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height)
                height: width
                value: 1 - focus.remaining / Math.max(1, focus.phaseTotal)
                progressColor: focus.phaseColor()
                progressColor2: focus.phaseColor()
            }
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 2
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: focus.phaseLabel().toUpperCase()
                    font.pixelSize: 14; font.letterSpacing: 2
                    color: focus.phaseColor()
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: fmt(focus.remaining)
                    font.pixelSize: Math.min(bigRing.width * 0.30, 92)
                    font.family: theme.fontMono; font.bold: true
                    color: theme.textPrimary
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Session " + (focus.completedWork + (focus.phase === "work" ? 1 : 0)) + " · " +
                          focus.completedWork + " done today"
                    font.pixelSize: 12; color: theme.textSecondary
                }
            }
        }

        // Nudge
        Text {
            Layout.fillWidth: true
            visible: focus.phase === "work"
            horizontalAlignment: Text.AlignHCenter
            text: focus.nudges[focus.nudgeIdx]
            font.pixelSize: 13; font.italic: true
            color: theme.textTertiary
            elide: Text.ElideRight
        }

        // Controls
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: theme.spacingSm
            PillButton {
                label: "Reset"; glyph: "⟲"; tint: theme.textSecondary
                onClicked: focus.reset()
            }
            PillButton {
                label: focus.running ? "Pause" : "Start"
                glyph: focus.running ? "⏸" : "▶"
                primary: true; tint: focus.phaseColor()
                implicitWidth: 150
                onClicked: focus.running = !focus.running
            }
            PillButton {
                label: "+5"; glyph: "＋"; tint: focus.phaseColor()
                onClicked: { focus.remaining += 300; focus.phaseTotal += 300 }
            }
            PillButton {
                label: "Skip"; glyph: "⏭"; tint: theme.textSecondary
                onClicked: focus.skip()
            }
        }
    }

    function fmt(s) {
        var m = Math.floor(s / 60), sec = s % 60
        return String(m).padStart(2, '0') + ":" + String(sec).padStart(2, '0')
    }

    Component.onCompleted: loadPhase("work")
}
