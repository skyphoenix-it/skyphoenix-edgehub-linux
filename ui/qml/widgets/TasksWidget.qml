import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Task tracker — persisted per-instance. Add / check-off / remove; the tile
// and the expanded view share the same list (via the store + revision).
//
// Sizing (W1 wave 2b): a checklist earns MORE ROWS, not bigger ones — and never
// a smaller target. The tile rows were 24px with an 18px-wide checkbox cell that
// carried a MouseArea: an 18x24 hit area for "complete this task", a third of
// theme.touchTertiary (52). Rows are touchTertiary at every size now, the
// checkbox owns a full-height touchTertiary cell, and the add field is
// touchSecondary (60) rather than a fixed 40.
//   • wide  — the list BESIDE its progress + add controls; a 696x409 box stacked
//             into bar/list/field/button is almost all chrome.
//   • every other shape — progress, the list, then the add row, as before.
//   • 1x3 (the whole 720x2560 panel) — the same list, ~40 rows of it.
// Removal stays expanded-only, deliberately: a ✕ on a tile is a mis-tap away
// from the checkbox, and the tile's own tap-to-expand is the way to get it.
// (No 0.5x0.5 is declared, so `micro` is never true here — see WidgetCatalog.)
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Tasks"; iconName: "tasks"; accentColor: theme.catProductivity

    // Reactive read: clone from the store keyed on revision so nested edits fire.
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property var items: cfg.items || []
    readonly property bool hideCompleted: cfg.hideCompleted !== undefined ? cfg.hideCompleted : false
    readonly property bool celebrate: cfg.celebrate !== undefined ? cfg.celebrate : true
    // View-only projection: optionally drop done items, but carry each item's
    // original storage index so toggle/remove still target the right entry.
    readonly property var visibleItems: {
        var a = []
        for (var i = 0; i < items.length; i++) {
            if (hideCompleted && items[i].done) continue
            a.push({ text: items[i].text, done: items[i].done, idx: i })
        }
        return a
    }
    property int doneCount: {
        var n = 0
        for (var i = 0; i < items.length; i++) if (items[i].done) n++
        return n
    }
    status: items.length ? doneCount + "/" + items.length : ""

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    readonly property bool horiz: sizeClass === "wide"
    // The progress bar + count is real content, so every size with room shows it
    // rather than keeping it behind the overlay.
    readonly property bool showSummary: !w.micro
    // A row is a real touch target at EVERY size: checking a task off is the
    // point. Room buys rows, never a thinner target.
    readonly property real rowH: theme.touchTertiary
    readonly property real rowFont: w.expanded ? 18
        : Math.max(13, Math.min((w.horiz ? width * 0.55 : width) * 0.032, 18))
    readonly property real boxSize: w.expanded ? 30 : Math.max(20, Math.min(w.rowH * 0.52, 30))

    function _save(arr) { if (store) store.setSetting(instanceId, "items", arr) }
    // Key of the last list we celebrated, so re-completing an already-finished
    // set (un-check then re-check) doesn't re-fire the burst.
    property string _celebratedKey: ""
    function _itemsKey(arr) { return arr.map(function (t) { return String(t.text) }).join("") }
    function toggle(i) {
        // A rendered row's idx can go stale after an external shrink; ignore it
        // rather than crash (a[i].text on undefined) or mutate the wrong entry.
        if (i < 0 || i >= items.length) return
        var a = items.slice()
        var it = a[i]
        // Preserve any extra fields (e.g. a Manager-assigned id) and never
        // re-persist a malformed item with text:undefined.
        a[i] = Object.assign({}, it, { text: it.text !== undefined ? it.text : "", done: !it.done })
        _save(a)
        // Dopamine hit: a burst when checking the box that clears the whole list.
        if (a[i].done && celebrate && a.length > 0 && a.every(function (t) { return t.done })) {
            var key = _itemsKey(a)
            if (key !== _celebratedKey) { _celebratedKey = key; celebrateNow("🎉 All done!") }
        }
    }
    function remove(i) { if (i < 0 || i >= items.length) return; var a = items.slice(); a.splice(i, 1); _save(a) }
    function add(t) { if (!t || !t.trim().length) return; var a = items.slice(); a.push({ text: t.trim(), done: false }); _save(a) }
    function clearCompleted() { _save(items.filter(function (t) { return !t.done })) }

    // Celebration pop, mirroring FocusWidget's honest little reward.
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
        font.pixelSize: w.expanded ? 34 : 18; font.bold: true; font.family: theme.fontDisplay
        color: w.effAccent; horizontalAlignment: Text.AlignHCenter
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

    // `columns` flips for a wide box: the progress + add controls sit BESIDE the
    // list rather than stacking four bands into it. Only a reshape.
    GridLayout {
        anchors.fill: parent
        columns: w.horiz ? 2 : 1
        rowSpacing: theme.spacingSm
        columnSpacing: theme.spacingLg

        // ── The list ──
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            ListView {
                id: taskList
                readonly property real rowPitch: w.rowH + spacing
                width: parent.width
                // Snapped to a WHOLE number of rows: filling outright slices the
                // last task in half at the card edge.
                height: Math.max(w.rowH,
                                 Math.floor(parent.height / rowPitch) * rowPitch - spacing)
                anchors.top: parent.top
                clip: true; spacing: 3
                interactive: w.expanded
                model: w.visibleItems
                // The model is a fresh array on every revision bump. Remember where
                // the user was and restore it so an add / external push doesn't
                // yank the list back to row 0.
                property real _savedY: 0
                onContentYChanged: if (contentY > 0) _savedY = contentY
                onModelChanged: contentY = _savedY
                delegate: RowLayout {
                    required property int index
                    required property var modelData
                    width: ListView.view ? ListView.view.width : 0
                    // A full touch target at EVERY size — see the header.
                    height: w.rowH
                    spacing: theme.spacingSm
                    // Checkbox in a full touchTertiary cell (the visual box stays
                    // smaller). This cell was 18px wide on a tile.
                    Item {
                        Layout.preferredWidth: theme.touchTertiary
                        Layout.fillHeight: true
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.round(w.boxSize); height: width; radius: 7
                            color: modelData.done ? w.effAccent : "transparent"
                            border.width: 2; border.color: modelData.done ? w.effAccent : theme.cardBorder
                            Text { anchors.centerIn: parent; visible: modelData.done; text: "✓"
                                color: "#0D1117"; font.bold: true
                                font.pixelSize: Math.round(w.boxSize * 0.57) }
                        }
                        // Tapping the box toggles done in BOTH modes — the tile is
                        // a live control surface (config lives in the corner).
                        MouseArea { anchors.fill: parent; onClicked: w.toggle(modelData.idx) }
                    }
                    Text {
                        Layout.fillWidth: true; Layout.fillHeight: true; verticalAlignment: Text.AlignVCenter
                        text: modelData.text !== undefined ? modelData.text : ""; elide: Text.ElideRight
                        font.pixelSize: Math.round(w.rowFont); font.strikeout: modelData.done
                        color: modelData.done ? theme.textTertiary : theme.textPrimary
                        MouseArea { anchors.fill: parent; onClicked: w.toggle(modelData.idx) }
                    }
                    // Remove in a full touchTertiary cell. Expanded-only: on a tile
                    // a ✕ is a mis-tap away from the checkbox.
                    Item {
                        visible: w.expanded; Layout.preferredWidth: theme.touchTertiary; Layout.fillHeight: true
                        Text { anchors.centerIn: parent; text: "✕"; color: rmMA.pressed ? theme.error : theme.textTertiary
                            font.pixelSize: 22 }
                        MouseArea { id: rmMA; anchors.fill: parent; onClicked: w.remove(modelData.idx) }
                    }
                }
            }

            Text {
                // Only claim "no tasks" when the list is genuinely empty — not
                // merely when every task is hidden by hideCompleted (status +
                // Clear button would otherwise contradict it).
                anchors.centerIn: parent
                visible: w.items.length === 0
                width: parent.width - 2 * theme.spacingSm
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: w.expanded ? "No tasks yet — add one below." : "No tasks"
                color: theme.textTertiary; font.pixelSize: w.expanded ? 15 : 12
            }
        }

        // ── Progress + add. The wide shape's control column.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: w.horiz ? w.width * 0.4 : Number.POSITIVE_INFINITY
            Layout.alignment: w.horiz ? Qt.AlignVCenter : Qt.AlignBottom
            spacing: theme.spacingSm

            // Progress toward "all done" — a glanceable momentum bar, now earned
            // by any tile with room rather than kept behind the overlay.
            Rectangle {
                visible: w.showSummary && w.items.length > 0
                Layout.fillWidth: true; Layout.preferredHeight: 6
                radius: 3; color: theme.cardBorder
                Rectangle {
                    height: parent.height; radius: 3
                    width: parent.width * (w.items.length ? w.doneCount / w.items.length : 0)
                    color: w.effAccent
                    Behavior on width { NumberAnimation { duration: theme.motionValue; easing.type: Easing.OutCubic } }
                }
            }

            // Quick add — available at EVERY size; both paths call add().
            RowLayout {
                Layout.fillWidth: true; spacing: theme.spacingSm
                TextField {
                    id: input
                    Layout.fillWidth: true
                    // theme.touchSecondary at EVERY size: this was a fixed 40px on
                    // tiles, under theme.touchTertiary (52).
                    Layout.preferredHeight: theme.touchSecondary
                    placeholderText: w.expanded || w.horiz ? "Add a task…" : "Add…"
                    color: theme.textPrimary; font.pixelSize: w.expanded ? 16 : 14
                    placeholderTextColor: theme.textTertiary
                    background: Rectangle { radius: theme.radiusSm; color: theme.backgroundColor
                        border.color: input.activeFocus ? w.effAccent : theme.cardBorder; border.width: 1 }
                    onAccepted: { w.add(text); text = "" }
                }
                PillButton { label: w.expanded ? "Add" : ""; glyph: "＋"; primary: true; tint: w.effAccent
                    onClicked: { w.add(input.text); input.text = "" } }
            }
            // Bulk "clear completed" — only when there's something to clear, and
            // only where there is room for a deliberate act.
            PillButton {
                Layout.alignment: Qt.AlignHCenter
                visible: (w.expanded || w.horiz) && w.doneCount > 0
                label: "Clear " + w.doneCount + " completed"; glyph: "🧹"; tint: theme.textSecondary
                onClicked: w.clearCompleted()
            }
        }
    }
}
