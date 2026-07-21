import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// "Right Now" - one single thing to focus on (ADHD single-tasking aid).
// Persisted; the compact tile shows it large, the expanded view lets you set it.
//
// Two things here are legitimately keyed off the MODE rather than the room, and
// both stay:
//   • `showHeader: expanded` - chrome-header CONTENT, not a dimension. Tiles are
//     headerless at every size by design (the eyebrow carries the identity); the
//     overlay, a titled view of one widget, gets a header.
//   • the tile/editor split (`visible: !w.expanded` / `visible: w.expanded`) -
//     two genuinely different VIEWS, not one view at two scales. A tile displays
//     the focus; the overlay is where you type it. Room does not make a display
//     into an editor.
// Only the celebration banner was a SIZE wearing the mode's clothes - see
// celebratePx.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Right Now"; iconName: "rightnow"; accentColor: theme.catProductivity
    showHeader: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string current: cfg.text || ""
    // A focus counts only if it has real (non-whitespace) content.
    readonly property bool hasFocus: current.trim().length > 0
    // Reactive on `tick` (bumped every second by the Dashboard) so it rolls over
    // at local midnight on a 24/7 device instead of freezing at load time.
    property string todayKey: (w.tick, Qt.formatDate(new Date(), "yyyy-MM-dd"))
    // Recompute the real current day here rather than trusting the todayKey
    // property: even if that ever went stale, the counter still resets correctly.
    property int finishedToday: {
        var _ = w.tick
        var key = Qt.formatDate(new Date(), "yyyy-MM-dd")
        return cfg.day === key ? (cfg.finishedToday || 0) : 0
    }
    function setText(t) { if (store && t !== w.current) store.setSetting(instanceId, "text", t) }
    // Finishing a focus is a small win - count it and celebrate, then clear.
    // Operates on the visible text when given (Done!), else the saved focus.
    function finish(explicitText) {
        var t = explicitText !== undefined ? explicitText : w.current
        var had = t.trim().length > 0
        var patch = { text: "" }
        if (had) { patch.finishedToday = finishedToday + 1; patch.day = todayKey; celebrateNow("🎉 Done!") }
        if (store) store.patchSettings(instanceId, patch)
    }

    // Celebration pop (mirrors FocusWidget).
    //
    // The banner spans the whole CARD, so the card is what sizes it. `expanded ?
    // 40 : 22` asked the wrong question and got both answers wrong: a 696x819
    // baseline tile has more room than the overlay's live-preview pane and still
    // popped at 22, while the overlay kept its 40 after W5 shrank that pane to 38%
    // of the width in landscape (~941x456 there, ~656x980 stacked in portrait).
    // Both axes bind - a wide-but-short pane must not overreach - and 40 stays the
    // designed ceiling.
    readonly property real celebratePx: Math.max(12, Math.min(width * 0.055,
                                                              height * 0.075, 40))
    property string celebrateMsg: ""
    function celebrateNow(msg) { celebrateMsg = msg; celebrateAnim.restart(); flash.restart() }
    Rectangle {
        anchors.fill: parent; radius: theme.radiusLg; color: w.effAccent; opacity: 0; z: 5
        SequentialAnimation on opacity {
            id: flash; running: false
            NumberAnimation { to: 0.30; duration: 120 }
            NumberAnimation { to: 0.0; duration: 500 }
        }
    }
    Text {
        id: celebrateLabel; anchors.centerIn: parent; z: 20
        text: w.celebrateMsg; opacity: 0
        font.pixelSize: Math.round(w.celebratePx); font.bold: true; font.family: theme.fontDisplay
        color: w.effAccent; horizontalAlignment: Text.AlignHCenter
        SequentialAnimation {
            id: celebrateAnim; running: false
            PropertyAction { target: celebrateLabel; property: "scale"; value: 0.6 }
            ParallelAnimation {
                NumberAnimation { target: celebrateLabel; property: "opacity"; from: 0; to: 1; duration: 180 }
                NumberAnimation { target: celebrateLabel; property: "scale"; to: 1.12
                    duration: 260; easing.type: theme.reduceMotion ? Easing.Linear : Easing.OutBack }
            }
            PauseAnimation { duration: 850 }
            NumberAnimation { target: celebrateLabel; property: "opacity"; to: 0; duration: 500 }
        }
    }

    // ── Per-size layout (sizeClass is injected by Dashboard) ─────────────────
    // 0.5x0.5 and 1x1 are both "compact" (shape, not footprint); the micro
    // half-cell is told apart by the box (~344-416px short side vs ~690px+).
    readonly property bool micro: sizeClass === "compact" && Math.min(width, height) < 480
    readonly property bool horiz: sizeClass === "wide"
    // What each size earns: micro is the focus text alone (a pure cue); every
    // larger size adds the eyebrow (identity - the header is hidden on tiles),
    // the daily momentum line, and a Done button - the single most useful
    // action, so a finished focus doesn't need a trip through the overlay.
    readonly property bool showEyebrow: !micro
    readonly property bool showDoneTile: !micro && hasFocus
    readonly property bool showCount: !micro && finishedToday > 0
    readonly property real heroPx: {
        if (micro) return Math.max(14, Math.min(width * 0.12, 22))
        if (sizeClass === "compact") return Math.max(16, Math.min(width * 0.055, 34))
        if (horiz) return Math.max(18, Math.min(height * 0.13, width * 0.045, 40))
        return Math.max(16, Math.min(width * 0.10, 44))   // tall
    }

    // Tile / display mode
    GridLayout {
        id: tileLayout
        anchors.centerIn: parent
        width: parent.width * 0.92
        visible: !w.expanded
        columns: w.horiz ? 2 : 1
        columnSpacing: theme.spacingLg
        rowSpacing: w.micro ? 0 : theme.spacingSm

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: w.micro ? 2 : theme.spacingXs
            Text {
                visible: w.showEyebrow
                Layout.fillWidth: true
                horizontalAlignment: w.horiz ? Text.AlignLeft : Text.AlignHCenter
                text: "RIGHT NOW"
                font.pixelSize: Math.max(11, Math.min(w.width * 0.026, 15))
                font.letterSpacing: 2; font.weight: Font.DemiBold
                color: theme.textTertiary
                elide: Text.ElideRight; maximumLineCount: 1
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: w.horiz ? Text.AlignLeft : Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: w.hasFocus ? w.current : "Tap to set your one focus"
                font.pixelSize: w.hasFocus ? w.heroPx : Math.max(14, Math.min(w.width * 0.035, 18))
                font.bold: w.hasFocus
                // Hero content adopts the per-instance accent (S7); placeholder stays muted.
                color: w.hasFocus ? w.effAccent : theme.textTertiary
                maximumLineCount: w.micro ? 3 : (w.sizeClass === "tall" ? 5 : 3)
                elide: Text.ElideRight
            }
        }
        ColumnLayout {
            visible: w.showDoneTile || w.showCount
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            spacing: theme.spacingXs
            PillButton {
                visible: w.showDoneTile
                Layout.alignment: Qt.AlignHCenter
                label: "Done"; glyph: "✓"; primary: true; tint: w.effAccent
                onClicked: w.finish()
            }
            Text {
                visible: w.showCount
                Layout.alignment: Qt.AlignHCenter
                text: "✓ " + w.finishedToday + " today"
                font.pixelSize: Math.max(12, Math.min(w.width * 0.03, 15))
                color: theme.textTertiary
            }
        }
    }

    // Expanded / edit mode
    ColumnLayout {
        anchors.fill: parent
        visible: w.expanded
        spacing: theme.spacingLg
        Item { Layout.fillHeight: true }
        Text {
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
            text: "What's the one thing right now?"
            font.pixelSize: 18; color: theme.textSecondary
        }
        TextField {
            id: field
            Layout.fillWidth: true; Layout.preferredHeight: theme.touchPrimary
            text: w.current
            font.pixelSize: 28; horizontalAlignment: Text.AlignHCenter
            color: theme.textPrimary; placeholderText: "e.g. Finish the report"
            placeholderTextColor: theme.textTertiary
            background: Rectangle { radius: theme.radiusMd; color: theme.backgroundColor
                border.color: field.activeFocus ? w.effAccent : theme.cardBorder; border.width: 2 }
            onEditingFinished: w.setText(text)
            // Resync when the focus changes elsewhere (e.g. cleared by "Done").
            Connections { target: w; function onCurrentChanged() { if (!field.activeFocus) field.text = w.current } }
        }
        Text {
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
            visible: w.finishedToday > 0
            text: "✓ " + w.finishedToday + (w.finishedToday === 1 ? " thing finished today" : " things finished today")
            font.pixelSize: 15; color: theme.textTertiary
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingMd
            PillButton { label: "Save"; glyph: "✓"; primary: true; tint: w.effAccent
                onClicked: w.setText(field.text) }
            PillButton { label: "Done!"; glyph: "🎉"; tint: theme.textSecondary
                // Act on the text the user actually sees, not the stale saved value.
                enabled: field.text.trim().length > 0
                onClicked: { w.finish(field.text); field.text = "" } }
        }
        Item { Layout.fillHeight: true }
    }

    // Tapping the compact tile opens the expanded editor (handled by the tile),
    // so no extra MouseArea is needed here.
}
