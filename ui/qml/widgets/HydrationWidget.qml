import QtQuick
import QtQuick.Layouts

// Hydration — count glasses toward a daily goal. Persisted; auto-resets each day.
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Hydration"; icon: "💧"; accentColor: theme.catInfo
    big: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    property int goal: cfg.goal || 8
    property string todayKey: (w.tick, Qt.formatDate(new Date(), "yyyy-MM-dd"))
    property int count: cfg.day === todayKey ? (cfg.count || 0) : 0
    status: count + "/" + goal

    function set(n) {
        if (store) store.patchSettings(instanceId, { "day": todayKey, "count": Math.max(0, Math.min(goal, n)) })
    }

    ColumnLayout {
        anchors.centerIn: parent; width: parent.width * 0.92; spacing: w.expanded ? 16 : 6
        Flow {
            Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: w.goal
                delegate: Text {
                    required property int index
                    text: index < w.count ? "💧" : "○"
                    opacity: index < w.count ? 1 : 0.35
                    font.pixelSize: w.expanded ? 30 : 16
                }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded; spacing: theme.spacingMd
            PillButton { label: "−"; onClicked: w.set(w.count - 1) }
            PillButton { label: "+ Glass"; glyph: "💧"; primary: true; tint: theme.catInfo; onClicked: w.set(w.count + 1) }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: w.count >= w.goal ? "Goal reached! 🎉" : (w.count + " of " + w.goal + " glasses")
            font.pixelSize: w.expanded ? 16 : 10; color: theme.textSecondary
        }
    }

    // Tap anywhere on the compact tile adds a glass (quick logging).
    MouseArea { anchors.fill: parent; enabled: !w.expanded; onClicked: w.set(w.count + 1) }
}
