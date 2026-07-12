import QtQuick
import QtQuick.Layouts

// Quick note / scratchpad — persisted. Uses a plain TextEdit (not Controls
// TextArea) for consistent theming and to avoid style-specific issues. The
// editor initialises from stored text and saves on edit; the compact tile
// shows a live preview via the reactive `cfg`.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Quick Note"; iconName: "notes"; accentColor: theme.catInfo
    big: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string current: cfg.text || ""
    function save(t) { if (store) store.setSetting(instanceId, "text", t) }

    // Compact preview
    Text {
        anchors.fill: parent; anchors.margins: theme.spacingSm
        visible: !w.expanded
        text: w.current.length ? w.current : "Tap to jot a note…"
        color: w.current.length ? theme.textPrimary : theme.textTertiary
        font.pixelSize: 13; wrapMode: Text.WordWrap; elide: Text.ElideRight
    }

    // Expanded editor
    Flickable {
        anchors.fill: parent
        visible: w.expanded
        contentHeight: editor.contentHeight + 12
        clip: true
        TextEdit {
            id: editor
            width: parent.width
            text: w.current
            font.pixelSize: 18; color: theme.textPrimary
            wrapMode: TextEdit.Wrap; selectByMouse: true
            persistentSelection: true
            onTextChanged: w.save(text)
            // Re-sync from the store only when (re)opened, to avoid clobbering typing.
            Connections {
                target: w
                function onExpandedChanged() { if (w.expanded) editor.text = w.current }
            }
        }
        Text {
            x: editor.x; y: editor.y
            visible: editor.text.length === 0
            text: "Type anything — it saves automatically."
            color: theme.textTertiary; font.pixelSize: 18
        }
    }
}
