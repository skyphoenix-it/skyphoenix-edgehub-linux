import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// "Right Now" — one single thing to focus on (ADHD single-tasking aid).
// Persisted; the compact tile shows it large, the expanded view lets you set it.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Right Now"; iconName: "rightnow"; accentColor: theme.catProductivity
    big: expanded; showHeader: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string current: cfg.text || ""
    property string todayKey: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property int finishedToday: cfg.day === todayKey ? (cfg.finishedToday || 0) : 0
    function setText(t) { if (store) store.setSetting(instanceId, "text", t) }
    // Finishing a focus is a small win — count it and celebrate, then clear.
    function finish() {
        var had = w.current.trim().length > 0
        var patch = { text: "" }
        if (had) { patch.finishedToday = finishedToday + 1; patch.day = todayKey; celebrateNow("🎉 Done!") }
        if (store) store.patchSettings(instanceId, patch)
    }

    // Celebration pop (mirrors FocusWidget).
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
        font.pixelSize: w.expanded ? 40 : 22; font.bold: true; font.family: theme.fontDisplay
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
                border.color: field.activeFocus ? w.effAccent : theme.cardBorder; border.width: 2 }
            onEditingFinished: w.setText(text)
            // Resync when the focus changes elsewhere (e.g. cleared by "Done").
            Connections { target: w; function onCurrentChanged() { if (!field.activeFocus) field.text = w.current } }
        }
        Text {
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
            visible: w.finishedToday > 0
            text: "✓ " + w.finishedToday + (w.finishedToday === 1 ? " finished today" : " finished today")
            font.pixelSize: 15; color: theme.textTertiary
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingMd
            PillButton { label: "Save"; glyph: "✓"; primary: true; tint: w.effAccent
                onClicked: w.setText(field.text) }
            PillButton { label: "Done!"; glyph: "🎉"; tint: theme.textSecondary
                enabled: w.current.trim().length > 0
                onClicked: { field.text = ""; w.finish() } }
        }
        Item { Layout.fillHeight: true }
    }

    // Tapping the compact tile opens the expanded editor (handled by the tile),
    // so no extra MouseArea is needed here.
}
