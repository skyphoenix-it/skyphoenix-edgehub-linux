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
//
// Sizing (W1 wave 2b): a queue earns MORE ROWS, not bigger ones.
//   • wide  — the capture column BESIDE the queue. Stacking a bottom bar into a
//             846x306 banner leaves ~3 rows; beside it, ~5, and the field is
//             where the eye already is.
//   • every other shape — the queue with the capture row beneath it, as before.
// The capture row is theme.touchSecondary (60) at EVERY size; it used to be a
// fixed 40px, under theme.touchTertiary (52), which is a real miss on the one
// control the widget exists for. Entry rows carry NO tap target on a tile
// (removal is expanded-only, deliberately), so they are a readout and may be
// denser — density is only free where nothing is tappable.
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
    // NOTE (W1 wave 2b, measured — do not "fix" this without re-measuring).
    // `cfg` is a fresh deep copy on every store.revision bump, and revision is
    // GLOBAL: it bumps on ANY widget's write, including the metric tiles' `hist`
    // sparkline write every ~2s. So `entries` below IS a new array roughly every
    // two seconds, which looks exactly like the SensorsWidget clunk (a model bound
    // to something that changes every tick).
    // It is NOT. Measured on a 40-entry list, an unrelated `hist` write leaves all
    // 28 realised delegates alive and does not move contentY: a ListView fed a JS
    // array diffs it against the previous one and reuses the delegates when the
    // content is equal. Pinning identity here (deriving `entries` off a JSON
    // signature) was tried and reverted — it swapped Qt's diff for an equivalent
    // JS stringify and fixed nothing observable.
    // tst_braindump's "BraindumpIdentity" case pins the property that actually
    // matters, so a future change that DOES start rebuilding delegates fails there.
    readonly property var entries: cfg.entries || []
    readonly property bool showTimes: cfg.showTimes !== undefined ? cfg.showTimes : true

    // The cap exists to bound config.toml, not to discipline the user. Oldest go
    // first because this is a queue you drain from the top.
    readonly property int maxEntries: 100

    status: w.expanded || !w.entries.length ? "" : "" + w.entries.length

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    readonly property bool horiz: sizeClass === "wide"
    // Entry rows are a READOUT on a tile (no tap target), so they scale with the
    // box rather than sitting at a fixed 22px.
    readonly property real rowH: w.expanded ? 44
        : Math.max(24, Math.min(height * 0.055, 40))
    readonly property real rowFont: w.expanded ? 17
        : Math.max(12, Math.min(w.rowH * 0.44, 16))
    readonly property real stampFont: Math.max(9, Math.round(w.rowFont * 0.78))
    // Clearing is a deliberate act and needs the room: the overlay always, and a
    // wide box whose capture column has spare height.
    readonly property bool showClear: (w.expanded || w.horiz) && w.entries.length > 0

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

    // `columns` flips for a wide box: the capture column sits BESIDE the queue
    // rather than under it. Only a reshape — the ListView is not rebuilt.
    GridLayout {
        anchors.fill: parent
        columns: w.horiz ? 2 : 1
        rowSpacing: theme.spacingSm
        columnSpacing: theme.spacingLg

        // ── The queue ──
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            ListView {
                id: list
                readonly property real rowPitch: w.rowH + spacing
                width: parent.width
                // Snapped to a WHOLE number of rows: filling outright slices the
                // last entry in half at the card edge.
                height: Math.max(w.rowH,
                                 Math.floor(parent.height / rowPitch) * rowPitch - spacing)
                anchors.top: parent.top
                clip: true; spacing: 3
                interactive: w.expanded
                model: w.entries
                // Newest-first, so an add showing you the new row at the top is
                // correct — unlike TasksWidget, which restores scroll.
                delegate: RowLayout {
                    id: entryRow
                    required property int index
                    required property var modelData
                    width: ListView.view ? ListView.view.width : 0
                    height: w.rowH
                    spacing: theme.spacingSm

                    Text {
                        visible: w.showTimes
                        text: w.stampOf(entryRow.modelData)
                        color: theme.textTertiary; font.family: theme.fontMono
                        font.pixelSize: Math.round(w.stampFont)
                        Layout.preferredWidth: Math.round(w.stampFont * 4.4)
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        text: entryRow.modelData && entryRow.modelData.text !== undefined
                              ? entryRow.modelData.text : ""
                        color: theme.textPrimary; elide: Text.ElideRight
                        font.pixelSize: Math.round(w.rowFont)
                    }
                    // Removal is expanded-only: on a small tile the ✕ would sit a
                    // thumb-width from the text and this list is meant to be added
                    // to in a hurry. Clearing is a deliberate act, so it needs room.
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
                anchors.centerIn: parent
                visible: w.entries.length === 0
                width: parent.width - 2 * theme.spacingSm
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: w.expanded ? "Nothing here. Type a thought below and press Enter." : "Empty"
                color: theme.textTertiary; font.pixelSize: w.expanded ? 15 : 12
            }
        }

        // ── Capture. Always present, at every size — the capture path IS the
        // product, so it is the one thing that never gets traded for a row.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: w.horiz ? w.width * 0.42 : Number.POSITIVE_INFINITY
            Layout.alignment: w.horiz ? Qt.AlignVCenter : Qt.AlignBottom
            spacing: theme.spacingSm

            RowLayout {
                Layout.fillWidth: true; spacing: theme.spacingSm
                TextField {
                    id: input
                    Layout.fillWidth: true
                    // theme.touchSecondary at EVERY size: this was a fixed 40px on
                    // tiles, under theme.touchTertiary (52).
                    Layout.preferredHeight: theme.touchSecondary
                    placeholderText: w.expanded || w.horiz ? "What's on your mind?" : "Dump…"
                    color: theme.textPrimary; font.pixelSize: w.expanded ? 16 : 14
                    placeholderTextColor: theme.textTertiary
                    background: Rectangle {
                        radius: theme.radiusSm; color: theme.backgroundColor
                        border.color: input.activeFocus ? w.effAccent : theme.cardBorder; border.width: 1
                    }
                    onAccepted: { w.add(text); text = "" }
                }
                PillButton {
                    label: w.expanded ? "Add" : ""; glyph: "＋"; primary: true; tint: w.effAccent
                    onClicked: { w.add(input.text); input.text = "" }
                }
            }

            PillButton {
                Layout.alignment: Qt.AlignHCenter
                visible: w.showClear
                label: "Clear all " + w.entries.length; glyph: "🧹"; tint: theme.textSecondary
                onClicked: w.clearAll()
            }
        }
    }
}
