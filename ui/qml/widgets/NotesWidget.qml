import QtQuick
import QtQuick.Layouts

// Quick note / scratchpad - persisted. Uses a plain TextEdit (not Controls
// TextArea) for consistent theming and to avoid style-specific issues. The
// editor initialises from stored text and saves on edit; the compact tile
// shows a live preview via the reactive `cfg`.
//
// Sizing (W1 wave 2b): this is ONE body of text, so - exactly like a list earning
// more rows - a bigger box earns more LINES, not bigger type. The preview was a
// flat 13px at every size, which is both too small to read on a 696x819 tile and
// the same on a 348x409 one.
//   • 0.5x0.5 (micro) - headerless: at 1/12 the note itself is the tile, and 36px
//                       of chrome is a line of text you cannot spare.
//   • every other size - the preview scales gently with the box (13px in a narrow
//                       column, up to 20px in a wide one - longer lines carry
//                       bigger type) and the taller box simply shows more of them.
//   • full (overlay)  - the editor. Editing is genuinely modal, so THAT stays
//                       keyed off `expanded` rather than off size.
// This widget has the least to gain from a big box of the nine: there is no extra
// content to earn, only more of the same note.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Quick Note"; iconName: "notes"; accentColor: theme.catInfo
    showHeader: !micro

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    // The preview scales with the COLUMN (a wider column means longer lines, which
    // carry bigger type) and is capped so a big box earns more LINES, not a
    // billboard. Height only floors it - a tall narrow sliver must not inflate.
    readonly property real previewPx: w.expanded ? 18
        : Math.max(13, Math.min(width * 0.024, height * 0.045, 20))

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string current: cfg.text || ""
    // Equality guard: a net no-op edit (type + delete back to the stored value)
    // must not bump revision / re-persist / re-broadcast to the Manager.
    function save(t) { if (store && t !== current) store.setSetting(instanceId, "text", t) }
    // Debounce writes so a store save + revision bump doesn't fire on every
    // keystroke; flushed immediately when the editor closes OR is destroyed.
    property string _pending: ""
    property bool _dirty: false
    Timer { id: saveDebounce; interval: 400; onTriggered: { w.save(w._pending); w._dirty = false } }
    function flush() { if (w._dirty) { saveDebounce.stop(); w.save(w._pending); w._dirty = false } }
    // The expanded overlay creates a SEPARATE instance that is destroyed on close
    // - before onExpandedChanged/the debounce can fire - so flush here too, or the
    // last edit is silently lost.
    Component.onDestruction: flush()

    // Tile preview - as many lines as the box holds, at a size the box earns.
    Text {
        anchors.fill: parent; anchors.margins: w.micro ? theme.spacingXs : theme.spacingSm
        visible: !w.expanded
        // A whitespace-only note is effectively empty - show the placeholder.
        text: w.current.trim().length ? w.current
                                      : (w.micro ? "Jot a note…" : "Tap to jot a note…")
        color: w.current.trim().length ? theme.textPrimary : theme.textTertiary
        font.pixelSize: Math.round(w.previewPx)
        wrapMode: Text.WordWrap; elide: Text.ElideRight
    }

    // Expanded editor
    Flickable {
        id: editorFlick
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
            onTextChanged: { w._pending = text; w._dirty = true; saveDebounce.restart() }
            // Keep the caret in view as the note grows past the viewport -
            // otherwise long notes scroll off the bottom while typing.
            onCursorRectangleChanged: {
                var top = cursorRectangle.y
                var bottom = cursorRectangle.y + cursorRectangle.height
                if (top < editorFlick.contentY)
                    editorFlick.contentY = top
                else if (bottom > editorFlick.contentY + editorFlick.height)
                    editorFlick.contentY = bottom - editorFlick.height
            }
            // Re-sync from the store when (re)opened; flush pending text on close.
            Connections {
                target: w
                function onExpandedChanged() {
                    if (w.expanded) editor.text = w.current
                    else w.flush()
                }
                // An external (Manager) push bumps the store revision and changes
                // `current`; re-sync the open editor so it doesn't keep stale local
                // text and a subsequent flush can't clobber the pushed value.
                function onCurrentChanged() {
                    if (w.expanded && editor.text !== w.current) editor.text = w.current
                }
            }
        }
        Text {
            x: editor.x; y: editor.y
            visible: editor.text.length === 0
            text: "Type anything - it saves automatically."
            color: theme.textTertiary; font.pixelSize: 18
        }
    }

    // Character / word count (expanded).
    Text {
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: theme.spacingSm
        // Hidden for an empty or whitespace-only note (0 words → no real content).
        visible: w.expanded && editor.text.trim().length > 0
        text: editor.text.length + " chars · " + editor.text.trim().split(/\s+/).filter(function (s) { return s.length }).length + " words"
        color: theme.textTertiary; font.pixelSize: 12; elide: Text.ElideRight
    }
}
