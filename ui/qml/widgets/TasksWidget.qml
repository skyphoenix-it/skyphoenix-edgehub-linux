import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Task tracker — persisted per-instance. Add / check-off / remove; the tile
// and the expanded view share the same list (via the store + revision).
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

    ColumnLayout {
        anchors.fill: parent
        spacing: theme.spacingSm

        // Progress toward "all done" — a glanceable momentum bar (expanded).
        Rectangle {
            visible: w.expanded && w.items.length > 0
            Layout.fillWidth: true; Layout.preferredHeight: 6
            radius: 3; color: theme.cardBorder
            Rectangle {
                height: parent.height; radius: 3
                width: parent.width * (w.items.length ? w.doneCount / w.items.length : 0)
                color: w.effAccent
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }

        ListView {
            id: taskList
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 3
            interactive: w.expanded
            model: w.visibleItems
            // The model is a fresh array on every revision bump, which resets the
            // view to the top. Remember where the user was and restore it so an
            // add / external push doesn't yank the list back to row 0.
            property real _savedY: 0
            onContentYChanged: if (contentY > 0) _savedY = contentY
            onModelChanged: contentY = _savedY
            delegate: RowLayout {
                required property int index
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                height: w.expanded ? 48 : 24
                spacing: theme.spacingSm
                // Checkbox in a >=44px touch cell (visual box stays compact).
                Item {
                    Layout.preferredWidth: w.expanded ? theme.touchTertiary : 18
                    Layout.fillHeight: true
                    Rectangle {
                        anchors.centerIn: parent
                        width: w.expanded ? 30 : 16; height: width; radius: 7
                        color: modelData.done ? w.effAccent : "transparent"
                        border.width: 2; border.color: modelData.done ? w.effAccent : theme.cardBorder
                        Text { anchors.centerIn: parent; visible: modelData.done; text: "✓"
                            color: "#0D1117"; font.bold: true; font.pixelSize: w.expanded ? 17 : 10 }
                    }
                    // Tapping the box toggles done in BOTH modes — the compact tile
                    // is now a live control surface (config lives in the corner).
                    MouseArea { anchors.fill: parent; onClicked: w.toggle(modelData.idx) }
                }
                Text {
                    Layout.fillWidth: true; Layout.fillHeight: true; verticalAlignment: Text.AlignVCenter
                    text: modelData.text !== undefined ? modelData.text : ""; elide: Text.ElideRight
                    font.pixelSize: w.expanded ? 18 : 12; font.strikeout: modelData.done
                    color: modelData.done ? theme.textTertiary : theme.textPrimary
                    MouseArea { anchors.fill: parent; onClicked: w.toggle(modelData.idx) }
                }
                // Remove in a >=44px touch cell.
                Item {
                    visible: w.expanded; Layout.preferredWidth: theme.touchTertiary; Layout.fillHeight: true
                    Text { anchors.centerIn: parent; text: "✕"; color: rmMA.pressed ? theme.error : theme.textTertiary
                        font.pixelSize: 22 }
                    MouseArea { id: rmMA; anchors.fill: parent; onClicked: w.remove(modelData.idx) }
                }
            }
        }

        Text {
            // Only claim "no tasks" when the list is genuinely empty — not merely
            // when every task is hidden by hideCompleted (status + Clear button
            // would otherwise contradict it).
            visible: w.items.length === 0
            Layout.alignment: Qt.AlignHCenter
            text: w.expanded ? "No tasks yet — add one below." : "No tasks"
            color: theme.textTertiary; font.pixelSize: w.expanded ? 15 : 12
        }

        // Quick add — available in BOTH modes (compact gets a shorter field + a
        // glyph-only ＋ button so it fits a small tile); both paths call add().
        RowLayout {
            Layout.fillWidth: true; spacing: theme.spacingSm
            TextField {
                id: input
                Layout.fillWidth: true
                Layout.preferredHeight: w.expanded ? theme.touchSecondary : 40
                placeholderText: w.expanded ? "Add a task…" : "Add…"
                color: theme.textPrimary; font.pixelSize: w.expanded ? 16 : 13
                placeholderTextColor: theme.textTertiary
                background: Rectangle { radius: theme.radiusSm; color: theme.backgroundColor
                    border.color: input.activeFocus ? w.effAccent : theme.cardBorder; border.width: 1 }
                onAccepted: { w.add(text); text = "" }
            }
            PillButton { label: w.expanded ? "Add" : ""; glyph: "＋"; primary: true; tint: w.effAccent
                Layout.preferredHeight: w.expanded ? implicitHeight : 40
                onClicked: { w.add(input.text); input.text = "" } }
        }
        // Bulk "clear completed" — only when there's something to clear.
        PillButton {
            Layout.alignment: Qt.AlignHCenter
            visible: w.expanded && w.doneCount > 0
            label: "Clear " + w.doneCount + " completed"; glyph: "🧹"; tint: theme.textSecondary
            onClicked: w.clearCompleted()
        }
    }
}
