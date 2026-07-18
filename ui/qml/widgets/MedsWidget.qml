import QtQuick
import QtQuick.Layouts

// ─────────────────────────────────────────────────────────────────────────
// Meds — scheduled doses with a taken / due / earlier state, and a taken-today
// record that survives a restart.
//
// TONE IS A HARD REQUIREMENT, NOT A PREFERENCE. A dose whose time has passed
// un-marked renders in `textTertiary` and reads "not marked" — never red, never
// "MISSED", never a count of failures. Three reasons, in descending order of
// how much they bind us:
//   • Safety. This widget cannot know whether a dose was taken; it only knows
//     whether it was TAPPED. Colouring an un-tapped dose as an alarm asserts a
//     fact we do not have, and the plausible correction ("take it now") is the
//     dangerous one — double-dosing. Muted-and-neutral is the only honest state.
//   • Evidence. The "calm UI" canon is largely unevidenced (a 2019 review found
//     none of the autism software-a11y guidelines were empirically based), but
//     the part that IS clinical is the flash threshold: the Epilepsy Foundation's
//     advisory board recommends staying under 2 Hz, stricter than WCAG 2.3.1's
//     3/s. So nothing here blinks, pulses or animates on a timer AT ALL — the due
//     state is a colour and a word, held still.
//   • It is a reminder, not a scoreboard. Guilt is not an adherence mechanism.
//
// Persistence: `takenDay` + `taken` (dose keys). Anything not from today is
// ignored rather than migrated, so the rollover is a read-time decision and the
// widget never writes on a timer — only a tap writes. Nothing here belongs in
// DashboardStore._ephemeralKeys because nothing here is per-tick state.
//
// Sizing (W1 wave 2b): the day's schedule used to be `expanded`-only, so a 1x2
// tile (696x1639 — room for two dozen doses) showed ONE dose and a button, and
// the actual schedule was locked behind the overlay. The split is now by SHAPE:
//   • wide  — the focused dose + Mark taken BESIDE the schedule. The focus block
//             is this widget's summary/control, so the wide box spends its width
//             on it rather than stacking three cramped bands.
//   • every other shape (compact / tall / large / full) — the day's schedule,
//             headed by the taken count. Each row IS the touch target
//             (theme.touchSecondary = 60, above the 52 minimum), so the one-tap
//             logging survives without a separate button.
// A list earns MORE ROWS, not bigger ones: the row height is fixed at every size
// and only the number of visible rows changes.
// ─────────────────────────────────────────────────────────────────────────
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Meds"; iconName: "meds"; accentColor: theme.catServices

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    // One dose per line: "HH:MM Name". Free text rather than a structured editor
    // because the whole adjustment surface is meant to stay small — the evidence
    // supports "make it adjustable, keep the surface small", not a form builder.
    readonly property string schedule: cfg.schedule !== undefined ? cfg.schedule : ""
    // How long after its time a dose still reads "Due now" rather than settling
    // into the neutral "not marked" state. The one knob that genuinely changes
    // behaviour, so it is the only one offered.
    readonly property int dueWindowMin: cfg.dueWindowMin !== undefined ? cfg.dueWindowMin : 60

    function todayKey() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }
    property string dayKey: (w.tick, todayKey())
    // Taken-today only. A stored day that is not today means the list is stale, so
    // it reads as empty — the rollover needs no timer and cannot half-apply.
    readonly property var takenToday: (cfg.takenDay === dayKey && cfg.taken) ? cfg.taken : []

    // ── Schedule parsing ────────────────────────────────────────────────────
    // Lenient on purpose: "8:00 Ritalin", "08:00  Ritalin 10mg" and "20:30" all
    // parse. A line with no readable time is kept as an UNTIMED dose rather than
    // dropped — silently discarding a medication line is the worst failure mode
    // here, so it degrades to "no set time" and is still tappable.
    readonly property var doses: {
        var out = []
        var lines = String(w.schedule).split("\n")
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line.length) continue
            var m = /^(\d{1,2}):(\d{2})\s*(.*)$/.exec(line)
            var h = -1, mi = 0, name = line
            if (m) {
                var hh = +m[1], mm = +m[2]
                if (hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59) {
                    h = hh; mi = mm; name = m[3].trim()
                    if (!name.length) name = "Dose"
                }
            }
            // The stable identity of a dose across a re-read: its own line text.
            // Index would re-point every taken mark when a line is inserted above.
            out.push({ key: line, name: name, hour: h, minute: mi,
                       mins: h < 0 ? -1 : h * 60 + mi })
        }
        // Timed doses in clock order; untimed ones last, in written order.
        out.sort(function (a, b) {
            if (a.mins < 0 && b.mins < 0) return 0
            if (a.mins < 0) return 1
            if (b.mins < 0) return -1
            return a.mins - b.mins
        })
        return out
    }

    function isTaken(key) { return w.takenToday.indexOf(key) >= 0 }
    // The ONE place the wall clock enters this widget. `stateOf`/`focusDoseAt`
    // already accept an explicit `nowM` so they can be pure functions of
    // (dose, clock); this extends that same seam to the RENDERED tile, which
    // otherwise always reads the real clock and so can only be tested at the
    // mercy of when the suite happens to run.
    //
    // -1 (the default) = use the wall clock. Nothing in the config schema or the
    // Manager can set this; it is a seam, not a setting.
    //
    // Tests MUST pin it. A schedule is a bare "HH:mm" with no date, so a dose
    // written as "ten minutes ago" silently becomes a dose due in 23h50m when
    // the suite runs at 00:07 — which is exactly how tst_meds failed every
    // night in the first ten minutes after midnight.
    property int nowMinsOverride: -1
    function nowMins() {
        if (w.nowMinsOverride >= 0) return w.nowMinsOverride
        var d = new Date(); return d.getHours() * 60 + d.getMinutes()
    }

    // "taken" | "due" | "later" | "open"
    //   due   — its time has arrived and is still inside the window
    //   open  — its time has passed un-marked. NOT "missed": see the header.
    //   later — still ahead of us today
    // An untimed dose is never "due"; it just sits "open" until tapped.
    //
    // `nowM` (minutes since midnight) is optional and defaults to the wall clock.
    // Passing it makes this a pure function of (dose, clock) — which is what lets
    // the state matrix be tested at a FIXED time of day instead of depending on
    // when the suite happens to run (a schedule built as "now + 2 h" is a
    // different scenario at 22:00 than at 09:00, and would flake nightly).
    function stateOf(dose, nowM) {
        if (isTaken(dose.key)) return "taken"
        if (dose.mins < 0) return "open"
        var n = (nowM !== undefined && nowM !== null) ? nowM : (w.tick, nowMins())
        if (n < dose.mins) return "later"
        if (n < dose.mins + w.dueWindowMin) return "due"
        return "open"
    }
    function colorOf(st) {
        if (st === "taken") return theme.success
        if (st === "due") return w.effAccent
        return theme.textTertiary        // "open" and "later" are both quiet
    }
    function labelOf(st) {
        if (st === "taken") return "Taken"
        if (st === "due") return "Due now"
        if (st === "later") return "Later"
        return "Not marked"
    }
    function timeOf(dose) {
        if (dose.mins < 0) return "-"
        return (dose.hour < 10 ? "0" : "") + dose.hour + ":" + (dose.minute < 10 ? "0" : "") + dose.minute
    }

    // The dose the tile leads with: the one that is due, else the next one later
    // today, else the first un-marked, else the first. Never null while doses
    // exist, so the compact tile always has something to say.
    // Split into a function taking the clock, for the same reason as stateOf().
    function focusDoseAt(nowM) {
        var d = w.doses, i
        for (i = 0; i < d.length; i++) if (w.stateOf(d[i], nowM) === "due") return d[i]
        for (i = 0; i < d.length; i++) if (w.stateOf(d[i], nowM) === "later") return d[i]
        for (i = 0; i < d.length; i++) if (w.stateOf(d[i], nowM) === "open") return d[i]
        return d.length ? d[0] : null
    }
    readonly property var focusDose: { var _ = w.tick; return w.focusDoseAt(undefined) }
    readonly property int takenCount: {
        var n = 0
        for (var i = 0; i < w.doses.length; i++) if (w.isTaken(w.doses[i].key)) n++
        return n
    }
    status: w.expanded || !w.doses.length ? "" : w.takenCount + "/" + w.doses.length

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    readonly property bool horiz: sizeClass === "wide"
    // The wide shape leads with the focused dose + its button; every other shape
    // leads with the schedule (whose rows are themselves the tap target).
    readonly property bool showFocus: w.horiz
    readonly property bool showSchedule: !w.horiz || w.width > 560
    // A dose row is a full touch target at EVERY size — never thinned for density.
    readonly property real rowH: theme.touchSecondary
    readonly property real rowFont: w.expanded ? 16
        : Math.max(13, Math.min((w.horiz ? width * 0.55 : width) * 0.028, 16))
    readonly property real timeFont: w.expanded ? 18
        : Math.max(14, Math.min((w.horiz ? width * 0.55 : width) * 0.032, 18))

    // Toggle, not a one-way "confirm": a mis-tap must be undoable, and an undo is
    // strictly safer than leaving a false "taken" on the record.
    function toggleTaken(key) {
        if (!store) return
        var a = w.takenToday.slice()
        var i = a.indexOf(key)
        if (i >= 0) a.splice(i, 1)
        else a.push(key)
        store.patchSettings(instanceId, { takenDay: w.dayKey, taken: a })
    }

    // ── Empty state ─────────────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        width: parent.width - 2 * theme.spacingSm
        visible: w.doses.length === 0
        text: w.expanded ? "Add your doses in settings - one per line, like “08:00 Vitamin D”."
                         : "Add doses\nin settings"
        color: theme.textTertiary; font.pixelSize: w.expanded ? 15 : 12
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
    }

    // `columns` flips for a wide box: the focus block sits BESIDE the schedule
    // instead of replacing it. Only a reshape — the ListView is not rebuilt.
    GridLayout {
        anchors.fill: parent
        visible: w.doses.length > 0
        columns: (w.showFocus && w.showSchedule) ? 2 : 1
        rowSpacing: theme.spacingSm
        columnSpacing: theme.spacingLg

        // ── The one dose that matters + a tap target. The wide shape's
        // summary/control column.
        ColumnLayout {
            visible: w.showFocus && w.focusDose !== null
            Layout.fillWidth: true
            Layout.maximumWidth: w.showSchedule ? w.width * 0.42 : Number.POSITIVE_INFINITY
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            Text {
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: w.focusDose ? w.timeOf(w.focusDose) : ""
                font.pixelSize: Math.round(w.timeFont * 1.4); font.bold: true
                font.family: theme.fontMono
                color: w.focusDose ? w.colorOf(w.stateOf(w.focusDose)) : theme.textTertiary
            }
            Text {
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: w.focusDose ? w.focusDose.name : ""
                font.pixelSize: Math.round(w.rowFont); color: theme.textPrimary
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: w.focusDose ? w.labelOf(w.stateOf(w.focusDose)) : ""
                font.pixelSize: Math.max(11, Math.round(w.rowFont * 0.8))
                color: theme.textSecondary; elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                visible: !w.showSchedule
                text: w.takenCount + " of " + w.doses.length + " marked taken today"
                font.pixelSize: Math.max(10, Math.round(w.rowFont * 0.75))
                color: theme.textTertiary; elide: Text.ElideRight
            }
            // Logging from the tile itself — the whole point is that it takes one
            // tap. A PillButton is theme.touchSecondary (60), above the minimum.
            PillButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: theme.spacingXs
                visible: w.focusDose !== null
                label: w.focusDose && w.isTaken(w.focusDose.key) ? "Taken ✓" : "Mark taken"
                primary: !!(w.focusDose && !w.isTaken(w.focusDose.key))
                tint: w.focusDose && w.isTaken(w.focusDose.key) ? theme.success : w.effAccent
                onClicked: if (w.focusDose) w.toggleTaken(w.focusDose.key)
            }
        }

        // ── The day's schedule. Was expanded-only; a 1x2 tile has room for two
        // dozen doses, so it is earned by ROOM rather than by mode.
        ColumnLayout {
            visible: w.showSchedule
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: theme.spacingSm

            Text {
                Layout.fillWidth: true
                visible: !w.showFocus
                text: w.takenCount + " of " + w.doses.length + " marked taken today"
                color: theme.textSecondary
                font.pixelSize: Math.round(w.rowFont * 0.95)
                elide: Text.ElideRight
            }

            // The viewport is snapped to a WHOLE number of rows: filling the
            // height outright slices the last dose in half at the card edge.
            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                ListView {
                    id: doseList
                    readonly property real rowPitch: w.rowH + spacing
                    width: parent.width
                    height: Math.max(w.rowH,
                                     Math.floor(parent.height / rowPitch) * rowPitch - spacing)
                    anchors.top: parent.top
                    clip: true; spacing: theme.spacingSm
                    interactive: w.expanded
                    model: w.doses
                    delegate: Rectangle {
                        id: doseRow
                        required property var modelData
                        readonly property string st: w.stateOf(modelData)
                        width: ListView.view ? ListView.view.width : 0
                        // A full-width row IS the touch target — above
                        // touchTertiary (52), so a shaky tap still lands on the
                        // right dose. Fixed across sizes: room buys rows, not bulk.
                        height: w.rowH
                        radius: theme.radiusSm
                        color: doseRow.st === "due" ? Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b, 0.12)
                                                    : "transparent"
                        border.width: 1
                        border.color: doseRow.st === "taken" ? theme.success
                                      : doseRow.st === "due" ? w.effAccent : theme.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: theme.spacingMd; anchors.rightMargin: theme.spacingMd
                            spacing: theme.spacingMd

                            Text {
                                text: w.timeOf(doseRow.modelData)
                                font.pixelSize: Math.round(w.timeFont); font.family: theme.fontMono
                                color: w.colorOf(doseRow.st)
                                Layout.preferredWidth: Math.round(w.timeFont * 3.6)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                Text {
                                    text: doseRow.modelData.name; color: theme.textPrimary
                                    font.pixelSize: Math.round(w.rowFont)
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                }
                                Text {
                                    text: w.labelOf(doseRow.st)
                                    color: theme.textSecondary
                                    font.pixelSize: Math.max(10, Math.round(w.rowFont * 0.75))
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                }
                            }
                            // A check that is filled when taken; the row's
                            // MouseArea does the work, so this stays purely a
                            // state read-out.
                            Rectangle {
                                Layout.preferredWidth: 32; Layout.preferredHeight: 32
                                radius: 16
                                color: doseRow.st === "taken" ? theme.success : "transparent"
                                border.width: 2
                                border.color: doseRow.st === "taken" ? theme.success : theme.cardBorder
                                Text {
                                    anchors.centerIn: parent
                                    visible: doseRow.st === "taken"
                                    text: "✓"; color: "#0D1117"; font.bold: true; font.pixelSize: 18
                                }
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: w.toggleTaken(doseRow.modelData.key) }
                    }
                }
            }
        }
    }
}
