import QtQuick
import QtQuick.Layouts

// ─────────────────────────────────────────────────────────────────────────
// Routine — a daily checklist that resets each day, with nothing to lose.
//
// THE NO-SHAMING RULE IS STRUCTURAL, NOT COSMETIC. It is not "we chose calm
// colours"; it is that the widget stores NO CROSS-DAY STATE AT ALL. There is no
// streak, no completion history, no "you did 3/5 yesterday" — so there is
// literally nothing for a bad day to break, and no number a missed day can make
// go down. That is why this is a separate widget from `habit` (which is a streak,
// on purpose, for people who want one) rather than a flag on it: you cannot bolt
// "no consequences" onto a design whose consequence IS the feature.
//
// Consequently: an unchecked step is `textPrimary` (a normal thing you might do),
// never red, never a warning. A new day silently unchecks everything. Nothing
// blinks or animates on a timer — the only clinically-grounded number in the
// whole a11y literature here is the Epilepsy Foundation's <2 Hz flash advice, and
// the cheapest way to honour it is to have no timed animation whatsoever.
//
// Persistence: `day` + `done` (step keys). Reading ignores a `day` that isn't
// today, so the reset is a read-time decision — no timer, no write at midnight,
// and it cannot half-apply if the device was asleep.
// ─────────────────────────────────────────────────────────────────────────
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Routine"; iconName: "routine"; accentColor: theme.catProductivity

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    // One step per line. Same reasoning as Meds' schedule: a small adjustment
    // surface beats a structured editor.
    readonly property string steps: cfg.steps !== undefined ? cfg.steps : ""

    function todayKey() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }
    property string dayKey: (w.tick, todayKey())
    // Today's ticks only. A stored day that is not today reads as empty — that IS
    // the daily reset.
    readonly property var doneToday: (cfg.day === dayKey && cfg.done) ? cfg.done : []

    // A step's identity is its own text, not its index: inserting a line above
    // must not silently re-point the ticks below it onto different steps.
    // Duplicate lines therefore share one tick — acceptable, and better than
    // index drift, which corrupts state invisibly.
    readonly property var stepList: {
        var out = []
        var lines = String(w.steps).split("\n")
        for (var i = 0; i < lines.length; i++) {
            var t = lines[i].trim()
            if (t.length) out.push(t)
        }
        return out
    }

    function isDone(step) { return w.doneToday.indexOf(step) >= 0 }
    readonly property int doneCount: {
        var n = 0
        for (var i = 0; i < w.stepList.length; i++) if (w.isDone(w.stepList[i])) n++
        return n
    }
    readonly property bool allDone: w.stepList.length > 0 && w.doneCount === w.stepList.length
    status: w.expanded || !w.stepList.length ? "" : w.doneCount + "/" + w.stepList.length

    function toggle(step) {
        if (!store) return
        var a = w.doneToday.slice()
        var i = a.indexOf(step)
        if (i >= 0) a.splice(i, 1)
        else a.push(step)
        store.patchSettings(instanceId, { day: w.dayKey, done: a })
    }

    // ── Empty state ─────────────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        width: parent.width - 2 * theme.spacingSm
        visible: w.stepList.length === 0
        text: w.expanded ? "Add your steps in settings — one per line."
                         : "Add steps\nin settings"
        color: theme.textTertiary; font.pixelSize: w.expanded ? 15 : 12
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
    }

    ColumnLayout {
        anchors.fill: parent
        visible: w.stepList.length > 0
        spacing: theme.spacingSm

        // Progress, stated as a fact and nothing more. No "x% — keep going!",
        // no target, no comparison to yesterday (there is no yesterday here).
        RowLayout {
            Layout.fillWidth: true
            visible: w.expanded
            spacing: theme.spacingSm
            Text {
                text: w.allDone ? "All done for today ✓"
                                : w.doneCount + " of " + w.stepList.length + " done"
                color: w.allDone ? theme.success : theme.textSecondary
                font.pixelSize: 15
            }
            Item { Layout.fillWidth: true }
        }
        // A neutral fill bar: it shows what IS done and simply stays short when
        // little is. The remainder is cardBorder, not a red "gap to close".
        Rectangle {
            visible: w.expanded
            Layout.fillWidth: true; Layout.preferredHeight: 6
            radius: 3; color: theme.cardBorder
            Rectangle {
                height: parent.height; radius: 3
                width: parent.width * (w.stepList.length ? w.doneCount / w.stepList.length : 0)
                color: w.allDone ? theme.success : w.effAccent
                // A width tween on an explicit tap is the one motion here: it is
                // interaction-triggered (WCAG 2.3.3 territory, AAA) and single-shot,
                // so it is nowhere near a flash — and it still respects reduceMotion.
                Behavior on width { NumberAnimation { duration: theme.motionValue; easing.type: Easing.OutCubic } }
            }
        }

        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: w.expanded ? theme.spacingSm : 2
            interactive: w.expanded
            model: w.stepList
            delegate: Item {
                id: stepRow
                required property var modelData
                readonly property bool done: w.isDone(stepRow.modelData)
                width: ListView.view ? ListView.view.width : 0
                // Expanded rows are a full touch target; the compact tile packs
                // more rows in and relies on the tile's own tap-to-expand for
                // anything finer.
                height: w.expanded ? theme.touchTertiary : 22

                RowLayout {
                    anchors.fill: parent
                    spacing: theme.spacingSm
                    Rectangle {
                        Layout.preferredWidth: w.expanded ? 28 : 14
                        Layout.preferredHeight: w.expanded ? 28 : 14
                        Layout.alignment: Qt.AlignVCenter
                        radius: width / 2
                        color: stepRow.done ? w.effAccent : "transparent"
                        border.width: 2
                        border.color: stepRow.done ? w.effAccent : theme.cardBorder
                        Text {
                            anchors.centerIn: parent; visible: stepRow.done
                            text: "✓"; color: "#0D1117"; font.bold: true
                            font.pixelSize: w.expanded ? 16 : 9
                        }
                    }
                    Text {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        text: stepRow.modelData
                        // A done step is de-emphasised; an undone one is just
                        // normal text. Neither is an error.
                        color: stepRow.done ? theme.textTertiary : theme.textPrimary
                        font.pixelSize: w.expanded ? 17 : 12
                        font.strikeout: stepRow.done
                        elide: Text.ElideRight
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: w.toggle(stepRow.modelData) }
            }
        }

        // Compact footer: the count, so a glance answers "where am I" without
        // expanding. Deliberately not a percentage.
        Text {
            visible: !w.expanded
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
            text: w.allDone ? "All done ✓" : w.doneCount + " of " + w.stepList.length
            color: w.allDone ? theme.success : theme.textSecondary
            font.pixelSize: 11; elide: Text.ElideRight
        }
    }
}
