import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ─────────────────────────────────────────────────────────────────────────
// Braindump — timestamped one-liners you add fast and clear often.
//
// NOT a second `notes`. Notes is a scratchpad: one body of text you edit and
// keep. This is a capture queue: many short entries, each stamped with when it
// arrived, newest first, meant to be emptied. The distinction is the whole
// feature — the cost of capture has to be one tap and one line, or the thought
// is gone before the UI is ready for it. So: the input is always present (both
// modes), Enter commits, and nothing else is required — no title, no category,
// no confirm step.
//
// Entries carry `at` (epoch ms) rather than a formatted string so the display
// format stays a rendering decision, and a device timezone change doesn't
// rewrite history.
//
// Persistence: the whole list, written only on add/remove/clear. The list is
// pruned to `maxEntries` on add — an unbounded array here would grow config.toml
// forever, and this widget is explicitly the one you dump INTO without thinking.
// ─────────────────────────────────────────────────────────────────────────
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Braindump"; iconName: "braindump"; accentColor: theme.catProductivity

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property var entries: cfg.entries || []
    readonly property bool showTimes: cfg.showTimes !== undefined ? cfg.showTimes : true

    // The cap exists to bound config.toml, not to discipline the user. Oldest go
    // first because this is a queue you drain from the top.
    readonly property int maxEntries: 100

    status: w.expanded || !w.entries.length ? "" : "" + w.entries.length

    function add(text) {
        if (!store) return
        var t = (text || "").trim()
        if (!t.length) return
        // Newest first: the thing you just captured must be the thing you see,
        // without scrolling — otherwise a full list silently swallows the entry.
        var a = [{ text: t, at: Date.now() }].concat(w.entries)
        if (a.length > w.maxEntries) a = a.slice(0, w.maxEntries)
        store.setSetting(instanceId, "entries", a)
    }
    function remove(i) {
        if (!store || i < 0 || i >= w.entries.length) return
        var a = w.entries.slice(); a.splice(i, 1)
        store.setSetting(instanceId, "entries", a)
    }
    function clearAll() { if (store) store.setSetting(instanceId, "entries", []) }

    // Today → just the time; older → weekday + time. An entry with no usable
    // stamp (hand-edited config, an older schema) renders blank rather than
    // "Invalid Date" — the text is what matters, the stamp is a nicety.
    function stampOf(entry) {
        if (!entry || entry.at === undefined || !isFinite(entry.at)) return ""
        var d = new Date(entry.at)
        if (isNaN(d.getTime())) return ""
        var now = new Date()
        return d.toDateString() === now.toDateString()
            ? Qt.formatTime(d, "HH:mm")
            : Qt.formatDateTime(d, "ddd HH:mm")
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: theme.spacingSm

        ListView {
            id: list
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 3
            interactive: w.expanded
            model: w.entries
            // The model is a fresh array on every revision bump, which resets the
            // view to the top. That is CORRECT here (newest-first: an add should
            // show you the new row) — unlike TasksWidget, which restores scroll.
            delegate: RowLayout {
                id: entryRow
                required property int index
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                height: w.expanded ? 44 : 22
                spacing: theme.spacingSm

                Text {
                    visible: w.showTimes
                    text: w.stampOf(entryRow.modelData)
                    color: theme.textTertiary; font.family: theme.fontMono
                    font.pixelSize: w.expanded ? 13 : 10
                    Layout.preferredWidth: w.expanded ? 76 : 54
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    verticalAlignment: Text.AlignVCenter
                    text: entryRow.modelData && entryRow.modelData.text !== undefined
                          ? entryRow.modelData.text : ""
                    color: theme.textPrimary; elide: Text.ElideRight
                    font.pixelSize: w.expanded ? 17 : 12
                }
                // Removal is expanded-only: on a small tile the ✕ would sit a
                // thumb-width from the text and this list is meant to be added to
                // in a hurry. Clearing is a deliberate act, so it needs the room.
                Item {
                    visible: w.expanded
                    Layout.preferredWidth: theme.touchTertiary; Layout.fillHeight: true
                    Text {
                        anchors.centerIn: parent; text: "✕"; font.pixelSize: 20
                        color: rmMA.pressed ? theme.textPrimary : theme.textTertiary
                    }
                    MouseArea { id: rmMA; anchors.fill: parent; onClicked: w.remove(entryRow.index) }
                }
            }
        }

        Text {
            visible: w.entries.length === 0
            Layout.alignment: Qt.AlignHCenter
            text: w.expanded ? "Nothing here. Type a thought below and press Enter." : "Empty"
            color: theme.textTertiary; font.pixelSize: w.expanded ? 15 : 12
        }

        // Always present, in BOTH modes — the capture path is the product.
        RowLayout {
            Layout.fillWidth: true; spacing: theme.spacingSm
            TextField {
                id: input
                Layout.fillWidth: true
                Layout.preferredHeight: w.expanded ? theme.touchSecondary : 40
                placeholderText: w.expanded ? "What's on your mind?" : "Dump…"
                color: theme.textPrimary; font.pixelSize: w.expanded ? 16 : 13
                placeholderTextColor: theme.textTertiary
                background: Rectangle {
                    radius: theme.radiusSm; color: theme.backgroundColor
                    border.color: input.activeFocus ? w.effAccent : theme.cardBorder; border.width: 1
                }
                onAccepted: { w.add(text); text = "" }
            }
            PillButton {
                label: w.expanded ? "Add" : ""; glyph: "＋"; primary: true; tint: w.effAccent
                Layout.preferredHeight: w.expanded ? implicitHeight : 40
                onClicked: { w.add(input.text); input.text = "" }
            }
        }

        PillButton {
            Layout.alignment: Qt.AlignHCenter
            visible: w.expanded && w.entries.length > 0
            label: "Clear all " + w.entries.length; glyph: "🧹"; tint: theme.textSecondary
            onClicked: w.clearAll()
        }
    }
}
