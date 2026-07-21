import QtQuick
import QtQuick.Layouts

// Hydration - count glasses toward a daily goal. Persisted; auto-resets daily.
//
// Sizing (W1 wave 2b): the tile is a CONTROL surface - logging a glass has to be
// one tap - so the +1 target is never shrunk to make a layout fit. Every declared
// size can hold it at >= theme.touchTertiary, so every size keeps it; what changes
// is how much context surrounds it.
//   • 0.5x0.5 (micro) - headerless: the count as a big number, and +1. The glass
//                       grid is dropped (8 droplets at 16px in a 348x409 tile is
//                       mush, not a readout) along with the streak line.
//   • 1x1 (baseline)  - the glass grid + count + streak + −/+1, all scaled to the
//                       box instead of the old fixed 16px/12px in a 696x819 tile.
//   • wide            - the grid BESIDE the count/controls column (1x0.5 portrait
//                       is 696x409; stacked, that is three cramped bands).
//   • tall            - the grid above a comfortable count + controls.
//   • full (overlay)  - the big block with tappable glasses, sized by the pane
//                       it is actually given (see the ovl* derivation below).
//
// FIXED (was a KNOWN DEFECT): the expanded ColumnLayout at the bottom of this
// file used to be built from literals - a 110px count, 88px glass cells, a 42px
// droplet, spacingXl between ~6 rows - chosen for a "full screen" that does not
// exist. "full" is NOT a full screen: Dashboard hosts the overlay in a pane
// beside the config form, ~941x456 in landscape and ~656x980 stacked in portrait,
// and the real device is 2560x720 landscape. Summed at goal 8 those literals
// asked for ~612px (812 at goal 20) and overran the 456-tall landscape pane at
// both ends - the count clipped off the top and the goal controls off the bottom,
// unreachably, at any goal past ~12. The overlay's hero sizes are now DERIVED
// from the pane (ovlCountPx / ovlCell / ovlDropPx / ovlSpacing), like every tile
// class above: a short pane shrinks the count and glasses so the column fits
// without scrolling; a tall pane keeps the generous look (portrait still sums to
// the original ~612px at goal 8). The literals were mode-keyed by CONTAINMENT
// (`visible: w.expanded`) rather than by a ternary, which is why they read as
// innocent. Everything ABOVE this line was already sized by its box.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    // Water-teal accent, deliberately distinct from theme.success: the count text
    // recolours to `success` when the goal is reached, so the resting accent must
    // differ or that reward is invisible (catInfo happens to equal success).
    title: "Hydration"; iconName: "hydration"; accentColor: theme.catServices
    showHeader: !micro

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    property int goal: cfg.goal || 8
    readonly property int glassMl: cfg.glassMl !== undefined ? cfg.glassMl : 250
    property string todayKey: (w.tick, Qt.formatDate(new Date(), "yyyy-MM-dd"))
    property int count: cfg.day === todayKey ? (cfg.count || 0) : 0
    status: count + "/" + goal

    // Live goal streak: only counts if the last goal-day is today or yesterday,
    // otherwise the streak has lapsed (shown as 0 until you hit the goal again).
    function _yesterdayKey() { var d = new Date(); d.setDate(d.getDate() - 1); return Qt.formatDate(d, "yyyy-MM-dd") }
    readonly property int streakDisplay: {
        var lg = cfg.lastGoalDay
        return (lg === todayKey || lg === _yesterdayKey()) ? (cfg.streak || 0) : 0
    }

    // Total volume drunk today (count × per-glass size), shown as L when ≥ 1000 ml.
    function volumeText() {
        var ml = w.count * w.glassMl
        return ml >= 1000 ? (ml / 1000).toFixed(1) + " L" : ml + " ml"
    }

    // Overfilling past the goal is allowed (extra-credit dopamine); capped only to
    // keep the glass grid sane.
    // Credit today's goal attainment into `patch` (streak + lastGoalDay) and
    // celebrate - but only the FIRST time the goal is reached today. Re-crossing
    // the same day keeps the streak and does not replay the celebration.
    function _creditGoalReached(patch) {
        var firstToday = cfg.lastGoalDay !== todayKey
        var s
        if (cfg.lastGoalDay === todayKey) s = cfg.streak || 1
        else s = (cfg.lastGoalDay === _yesterdayKey()) ? (cfg.streak || 0) + 1 : 1
        patch.streak = s; patch.lastGoalDay = todayKey
        if (firstToday) celebrateNow("🎉 Goal reached!")
    }
    function set(n) {
        if (!store) return
        var v = Math.max(0, Math.min(50, n))
        var was = w.count
        var patch = { "day": todayKey, "count": v }
        // First crossing of the goal today → bump the streak + celebrate.
        if (was < goal && v >= goal) _creditGoalReached(patch)
        store.patchSettings(instanceId, patch)
    }
    function setGoal(g) {
        if (!store) return
        var ng = Math.max(1, Math.min(20, g))
        var patch = { "goal": ng }
        // Lowering the goal to at/below the current count meets it just like a
        // glass tap would - credit the streak (only if it wasn't already met).
        if (w.count < w.goal && w.count >= ng) _creditGoalReached(patch)
        store.patchSettings(instanceId, patch)
    }

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    readonly property bool horiz: sizeClass === "wide"
    // Micro leads with the number; every other size leads with the glass grid.
    readonly property bool showGrid: !w.micro
    readonly property bool showStreak: !w.micro && w.streakDisplay > 1
    // The count line is the readout micro is built around, so it scales to the
    // box there and stays a caption everywhere else. The caption measures against
    // its own COLUMN (wide puts it beside the grid, so the full width would
    // over-read) and only gently against height - keying it to height alone
    // collapsed it to 12px in a 846x306 wide box that had room to spare.
    readonly property real countPx: w.micro
        ? Math.max(20, Math.min(width * 0.30, height * 0.26, 76))
        : Math.max(13, Math.min((w.horiz ? width * 0.5 : width) * 0.055,
                                height * 0.075, 26))
    // Droplet size follows the box AND the goal - 20 glasses in a half tile are
    // not the same glyph as 6 in a baseline one.
    //
    // The `w.expanded ? 42` this used to open with was DEAD CODE, not merely
    // mode-keyed: glassPx feeds only glassCell/glassCols and the droplet delegate,
    // all of which live inside the tile GridLayout below - and that layout is
    // `visible: !w.expanded`. The overlay draws its own glasses from its own
    // literals (see the expanded ColumnLayout), so the 42 never rendered anywhere.
    // Its existence is what made this read like a mode decision.
    readonly property real glassPx:
        Math.max(11, Math.min((w.horiz ? width * 0.5 : width) * 0.9 / Math.max(4, Math.ceil(Math.sqrt(w.goal) * 1.6)),
                              height * 0.16, 56))
    // The grid is a real Grid (not a Flow): a Flow reports NO implicit width, so
    // Layout.alignment collapsed it to zero and the droplets spilled out of the
    // left edge in one unwrapped row. Columns are computed so they wrap honestly.
    readonly property real glassCell: w.glassPx * 1.25
    readonly property int glassCols: Math.max(1, Math.min(w.goal,
        Math.floor(((w.horiz ? width * 0.5 : width) - 16) / Math.max(1, w.glassCell))))

    // Celebration pop (mirrors FocusWidget).
    //
    // The banner spans the whole CARD, so the card is what sizes it - the same
    // shape HabitWidget uses. `expanded ? 40 : 20` asked the wrong question and
    // got both answers wrong: a 696x819 baseline tile has more room than the
    // overlay's live-preview pane and still popped at 20, while the overlay kept
    // its 40 after W5 shrank that pane to 38% of the width in landscape. Both axes
    // bind (the text wraps to at most 2 lines, so the overlay's wide-but-short
    // 456px landscape pane must not overreach on width alone) and 40 stays the
    // designed ceiling.
    readonly property real celebratePx: Math.max(12, Math.min(width * 0.06,
                                                              height * 0.08, 40))
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
        // Bounded to the card and allowed to wrap/elide. It had no width, no
        // wrapMode and no elide, so a centred banner wider than the card had
        // nowhere to go and simply spilled out of both edges - celebrateNow()
        // takes an arbitrary string, and the only thing keeping this honest was
        // that today's ("🎉 Goal reached!") happens to be short. The 40px ceiling
        // makes that a real risk, not a theoretical one: at 40px on the narrowest
        // box that reaches it, the string is already most of the card.
        width: parent.width - 2 * theme.spacingLg
        text: w.celebrateMsg; opacity: 0
        font.pixelSize: Math.round(w.celebratePx); font.bold: true; font.family: theme.fontDisplay
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

    // ── Tile (every non-overlay size) ──
    // `columns` flips for a wide box; that only RESHAPES - the glass delegates
    // are not rebuilt (their model is the goal COUNT, an int, so a tap moves the
    // bound values and nothing is recreated).
    GridLayout {
        // centerIn + an explicit width (the wave-2a MoonWidget shape): the group
        // reads as ONE centred block instead of a top-anchored grid with the
        // controls stranded in the middle.
        anchors.centerIn: parent
        width: parent.width
        visible: !w.expanded
        columns: w.horiz ? 2 : 1
        rowSpacing: 6
        columnSpacing: theme.spacingLg

        Grid {
            visible: w.showGrid
            Layout.alignment: Qt.AlignHCenter
            columns: w.glassCols
            spacing: Math.max(3, w.glassPx * 0.22)
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            Repeater {
                // The model is the goal COUNT (an int), so a tap moves the bound
                // values in long-lived delegates rather than rebuilding the grid.
                model: w.goal
                delegate: Text { required property int index
                    text: index < w.count ? "💧" : "○"
                    opacity: index < w.count ? 1 : 0.35
                    font.pixelSize: Math.round(w.glassPx) }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignCenter
            spacing: 6

            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                // Micro has no room for a sentence, and the number IS the readout.
                text: w.micro ? (w.count + "/" + w.goal)
                              : (w.count + " of " + w.goal + " glasses")
                elide: Text.ElideRight
                font.pixelSize: Math.round(w.countPx)
                font.bold: w.micro
                font.family: w.micro ? theme.fontMono : theme.fontDisplay
                color: w.micro && w.count >= w.goal ? theme.success
                       : w.micro ? w.effAccent : theme.textSecondary }
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                visible: w.showStreak; elide: Text.ElideRight
                text: "🔥 " + w.streakDisplay + "-day streak"
                font.pixelSize: Math.max(10, Math.round(w.countPx * 0.85))
                color: theme.textTertiary }
            // −1 / +1 - PillButton is theme.touchSecondary (60) tall, above the
            // 52 minimum, and it is kept at EVERY size: logging a glass in one tap
            // is what this widget is for. Micro drops the −1 (it is the undo, not
            // the job) rather than shrinking either target to fit.
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: theme.spacingSm
                PillButton {
                    visible: !w.micro
                    label: "−"; tint: w.effAccent
                    enabledState: w.count > 0
                    onClicked: w.set(w.count - 1)
                }
                PillButton {
                    label: "+1"; glyph: "💧"; primary: true; tint: w.effAccent
                    onClicked: w.set(w.count + 1)
                }
            }
        }
    }

    // ── Overlay room derivation (fit) ────────────────────────────────────────
    // "full" is NOT a full screen. Dashboard hosts the overlay in a live-preview
    // pane (~941x456 landscape / ~656x980 portrait) and the real device is
    // 2560x720 landscape - none of them the tall screen the old 110px count /
    // 88px cell / spacingXl literals imagined. Those summed to ~612px at goal 8
    // (812 at goal 20) and overran the 456-tall landscape pane at BOTH ends,
    // clipping the count off the top and the goal controls - the overlay's whole
    // point - off the bottom, unreachably, at any goal past ~12. So every hero
    // size here now scales to the pane. The two −/+ control rows are PillButtons
    // (touchSecondary tall at every size, like the rest of this widget) and are
    // the fixed floor; the count, the glasses and the air scale around them so
    // the column fits without scrolling. A tall pane keeps the generous look
    // (scale caps at 1); a short one shrinks the count and the glasses instead of
    // spilling. The glass cell is `sqrt(area-budget / N) − spacing`: fixing the
    // grid's total AREA to a bounded share of the box makes it hold ~that share
    // of the height whatever the goal, so 20 glasses fill more columns rather
    // than a taller stack. The Flow wraps by width, so the column count follows.
    readonly property real ovlColW: Math.min(width, 600)
    readonly property real ovlInnerW: ovlColW - 2 * theme.spacingLg
    readonly property real ovlScale: Math.max(0.5, Math.min(1.0, height / 720))
    readonly property real ovlCountPx: Math.round(Math.max(42, Math.min(110 * ovlScale, height * 0.14)))
    readonly property real ovlSubPx: Math.round(Math.max(12, Math.min(20, ovlCountPx * 0.19)))
    readonly property real ovlVolPx: Math.round(Math.max(11, Math.min(16, ovlCountPx * 0.15)))
    readonly property real ovlSpacing: Math.round(Math.max(5, Math.min(theme.spacingXl, height * 0.026)))
    readonly property int ovlGlassN: Math.max(w.goal, w.count)
    readonly property real ovlCellSpacing: Math.round(Math.max(4, theme.spacingMd * ovlScale))
    readonly property real ovlCell: Math.floor(Math.max(22, Math.min(
        Math.sqrt(height * 0.18 * ovlInnerW / ovlGlassN) - ovlCellSpacing, height * 0.16, 88)))
    readonly property real ovlDropPx: Math.round(ovlCell * 0.48)

    // ── Expanded: one large, centered, cohesive block ──
    ColumnLayout {
        anchors.centerIn: parent
        width: w.ovlColW
        visible: w.expanded
        spacing: w.ovlSpacing

        Text { Layout.alignment: Qt.AlignHCenter; text: w.count + " / " + w.goal
            font.pixelSize: Math.round(w.ovlCountPx); font.bold: true; font.family: theme.fontMono
            color: w.count >= w.goal ? theme.success : w.effAccent }
        Text { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: -Math.round(theme.spacingMd * w.ovlScale)
            text: w.count > w.goal ? ("Overachiever! +" + (w.count - w.goal) + " 💪")
                  : (w.count === w.goal ? "Daily goal reached! 🎉" : "glasses of water today")
            font.pixelSize: Math.round(w.ovlSubPx); color: theme.textSecondary }
        Text { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: -Math.round(theme.spacingLg * w.ovlScale)
            text: w.volumeText() + " today" + (w.streakDisplay > 1 ? "   ·   🔥 " + w.streakDisplay + "-day streak" : "")
            font.pixelSize: Math.round(w.ovlVolPx); color: theme.textTertiary }

        Flow {
            Layout.alignment: Qt.AlignHCenter
            // Pinned to the inner width (not fillWidth), so the cell arithmetic
            // above and the Flow's own wrapping agree on how many columns fit.
            Layout.preferredWidth: w.ovlInnerW
            spacing: w.ovlCellSpacing
            Repeater {
                // Render goal cells, plus any extra "bonus" glasses when overfilled.
                model: w.ovlGlassN
                delegate: Rectangle {
                    required property int index
                    readonly property bool filled: index < w.count
                    readonly property bool bonus: index >= w.goal
                    width: w.ovlCell; height: w.ovlCell; radius: theme.radiusMd
                    color: filled ? Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b, bonus ? 0.28 : 0.18) : "transparent"
                    border.width: 2
                    border.color: filled ? (bonus ? theme.success : w.effAccent) : theme.cardBorder
                    Text { anchors.centerIn: parent; text: filled ? "💧" : "○"
                        font.pixelSize: Math.round(w.ovlDropPx); opacity: filled ? 1 : 0.4 }
                    MouseArea { anchors.fill: parent; onClicked: w.set(index + 1) }
                }
            }
        }

        // The overlay's hero actions. These are deliberately LARGE - far wider
        // than their text needs (measured: "Remove" wants 99px at textScale 1.0
        // and 141 at the 1.6 maximum; "Add a glass" 133 and 193) - because this
        // is the full-screen view of a widget whose entire job is one tap. That
        // generosity was written as `implicitWidth: 170` / `240`, which states it
        // as the BOX rather than as a MINIMUM: the pill was pinned to exactly
        // that width and could never grow past it, so a longer label (a
        // translation, a relabel) would elide inside a button with no reason to
        // be narrow. `minWidth` says the same thing as a floor - identical
        // rendering today at every reachable textScale, and content wins if it
        // ever exceeds it. They are NOT a matched pair and never were: 170 != 240,
        // and nothing in the column aligns to either number.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: Math.round(theme.spacingMd * w.ovlScale); spacing: theme.spacingLg
            PillButton { label: "Remove"; glyph: "−"; minWidth: 170; onClicked: w.set(w.count - 1) }
            PillButton { label: "Add a glass"; glyph: "💧"; primary: true; tint: w.effAccent
                minWidth: 240; onClicked: w.set(w.count + 1) }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingMd
            Text { text: "Daily goal:"; color: theme.textSecondary; font.pixelSize: 16; Layout.alignment: Qt.AlignVCenter }
            PillButton { label: "−"; onClicked: w.setGoal(w.goal - 1) }
            Text { text: w.goal + " glasses"; color: theme.textPrimary; font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter; Layout.preferredWidth: 100; horizontalAlignment: Text.AlignHCenter }
            PillButton { label: "+"; onClicked: w.setGoal(w.goal + 1) }
        }
    }
}
