import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Task tracker — persisted per-instance. Add / check-off / remove; the tile
// and the expanded view share the same list (via the store + revision).
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Tasks"; icon: "✅"; accentColor: theme.catProductivity
    big: expanded

    // Reactive read: clone from the store keyed on revision so nested edits fire.
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property var items: cfg.items || []
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
            model: w.items
            delegate: RowLayout {
                required property int index
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                height: w.expanded ? 40 : 22
                spacing: theme.spacingSm
                Rectangle {
                    Layout.preferredWidth: w.expanded ? 26 : 16
                    Layout.preferredHeight: Layout.preferredWidth; radius: 6
                    color: modelData.done ? theme.catProductivity : "transparent"
                    border.width: 2; border.color: modelData.done ? theme.catProductivity : theme.cardBorder
                    Text { anchors.centerIn: parent; visible: modelData.done; text: "✓"
                        color: "#0D1117"; font.bold: true; font.pixelSize: w.expanded ? 15 : 10 }
                    MouseArea { anchors.fill: parent; onClicked: w.toggle(index) }
                }
                Text {
                    Layout.fillWidth: true; text: modelData.text; elide: Text.ElideRight
                    font.pixelSize: w.expanded ? 18 : 12; font.strikeout: modelData.done
                    color: modelData.done ? theme.textTertiary : theme.textPrimary
                    MouseArea { anchors.fill: parent; onClicked: w.toggle(index) }
                }
                Text {
                    visible: w.expanded; text: "✕"; color: theme.textTertiary
                    font.pixelSize: 18; Layout.preferredWidth: 24; horizontalAlignment: Text.AlignHCenter
                    MouseArea { anchors.fill: parent; onClicked: w.remove(index) }
                }
            }
        }

        Text {
            visible: w.items.length === 0
            Layout.alignment: Qt.AlignHCenter
            text: w.expanded ? "No tasks yet — add one below." : "No tasks"
            color: theme.textTertiary; font.pixelSize: w.expanded ? 15 : 11
        }

        RowLayout {
            Layout.fillWidth: true; visible: w.expanded; spacing: theme.spacingSm
            TextField {
                id: input
                Layout.fillWidth: true
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
