import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// "Right Now" — one single thing to focus on (ADHD single-tasking aid).
// Persisted; the compact tile shows it large, the expanded view lets you set it.
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Right Now"; icon: "🎈"; accentColor: theme.catProductivity
    big: expanded; showHeader: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string current: cfg.text || ""
    function setText(t) { if (store) store.setSetting(instanceId, "text", t) }

    // Compact / display mode
    Item {
        anchors.fill: parent
        visible: !w.expanded
        Text {
            anchors.centerIn: parent; width: parent.width * 0.9
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: w.current.length ? w.current : "Tap to set your one focus"
            font.pixelSize: w.current.length ? Math.max(16, Math.min(parent.width * 0.11, 30)) : 14
            font.bold: w.current.length > 0
            color: w.current.length ? theme.textPrimary : theme.textTertiary
            maximumLineCount: 3; elide: Text.ElideRight
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
                border.color: field.activeFocus ? theme.accent : theme.cardBorder; border.width: 2 }
            onEditingFinished: w.setText(text)
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingMd
            PillButton { label: "Save"; glyph: "✓"; primary: true; tint: theme.catProductivity
                onClicked: w.setText(field.text) }
            PillButton { label: "Done / Clear"; glyph: "🎉"; tint: theme.textSecondary
                onClicked: { field.text = ""; w.setText("") } }
        }
        Item { Layout.fillHeight: true }
    }

    // Tapping the compact tile opens the expanded editor (handled by the tile),
    // so no extra MouseArea is needed here.
}
