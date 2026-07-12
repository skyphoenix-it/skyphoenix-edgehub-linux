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
    big: expanded

    // Reactive read: clone from the store keyed on revision so nested edits fire.
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property var items: cfg.items || []
    readonly property bool hideCompleted: cfg.hideCompleted !== undefined ? cfg.hideCompleted : false
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
    function toggle(i) { var a = items.slice(); a[i] = { text: a[i].text, done: !a[i].done }; _save(a) }
    function remove(i) { var a = items.slice(); a.splice(i, 1); _save(a) }
    function add(t) { if (!t || !t.trim().length) return; var a = items.slice(); a.push({ text: t.trim(), done: false }); _save(a) }

    ColumnLayout {
        anchors.fill: parent
        spacing: theme.spacingSm

        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 3
            interactive: w.expanded
            model: w.visibleItems
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
                        color: modelData.done ? theme.catProductivity : "transparent"
                        border.width: 2; border.color: modelData.done ? theme.catProductivity : theme.cardBorder
                        Text { anchors.centerIn: parent; visible: modelData.done; text: "✓"
                            color: "#0D1117"; font.bold: true; font.pixelSize: w.expanded ? 17 : 10 }
                    }
                    MouseArea { anchors.fill: parent; onClicked: w.toggle(modelData.idx) }
                }
                Text {
                    Layout.fillWidth: true; Layout.fillHeight: true; verticalAlignment: Text.AlignVCenter
                    text: modelData.text; elide: Text.ElideRight
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
            visible: w.visibleItems.length === 0
            Layout.alignment: Qt.AlignHCenter
            text: w.expanded ? "No tasks yet — add one below." : "No tasks"
            color: theme.textTertiary; font.pixelSize: w.expanded ? 15 : 12
        }

        RowLayout {
            Layout.fillWidth: true; visible: w.expanded; spacing: theme.spacingSm
            TextField {
                id: input
                Layout.fillWidth: true
                Layout.preferredHeight: theme.touchSecondary
                placeholderText: "Add a task…"
                color: theme.textPrimary; font.pixelSize: 16
                placeholderTextColor: theme.textTertiary
                background: Rectangle { radius: theme.radiusSm; color: theme.backgroundColor
                    border.color: input.activeFocus ? theme.accent : theme.cardBorder; border.width: 1 }
                onAccepted: { w.add(text); text = "" }
            }
            PillButton { label: "Add"; glyph: "＋"; primary: true; tint: theme.catProductivity
                onClicked: { w.add(input.text); input.text = "" } }
        }
    }
}
