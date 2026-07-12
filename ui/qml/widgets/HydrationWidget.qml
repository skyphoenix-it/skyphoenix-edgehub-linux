import QtQuick
import QtQuick.Layouts

// Hydration — count glasses toward a daily goal. Persisted; auto-resets daily.
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
    function setGoal(g) {
        if (store) store.patchSettings(instanceId, { "goal": Math.max(1, Math.min(16, g)) })
    }

    // ── Compact tile ──
    ColumnLayout {
        anchors.centerIn: parent; visible: !w.expanded; width: parent.width * 0.92; spacing: 6
        Flow {
            Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; spacing: 4
            Repeater {
                model: w.goal
                delegate: Text { required property int index
                    text: index < w.count ? "💧" : "○"
                    opacity: index < w.count ? 1 : 0.35; font.pixelSize: 16 }
            }
        }
        Text { Layout.alignment: Qt.AlignHCenter; text: w.count + " of " + w.goal + " glasses"
            font.pixelSize: 10; color: theme.textSecondary }
    }
    MouseArea { anchors.fill: parent; enabled: !w.expanded; onClicked: w.set(w.count + 1) }

    // ── Expanded: one large, centered, cohesive block ──
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width, 600)
        visible: w.expanded
        spacing: theme.spacingXl

        Text { Layout.alignment: Qt.AlignHCenter; text: w.count + " / " + w.goal
            font.pixelSize: 110; font.bold: true; font.family: theme.fontMono
            color: w.count >= w.goal ? theme.success : theme.catInfo }
        Text { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: -theme.spacingMd
            text: w.count >= w.goal ? "Daily goal reached! 🎉" : "glasses of water today"
            font.pixelSize: 20; color: theme.textSecondary }

        Flow {
            Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
            spacing: theme.spacingMd
            Repeater {
                model: w.goal
                delegate: Rectangle {
                    required property int index
                    width: 88; height: 88; radius: theme.radiusMd
                    color: index < w.count ? Qt.rgba(theme.catInfo.r, theme.catInfo.g, theme.catInfo.b, 0.18) : "transparent"
                    border.width: 2; border.color: index < w.count ? theme.catInfo : theme.cardBorder
                    Text { anchors.centerIn: parent; text: index < w.count ? "💧" : "○"
                        font.pixelSize: 42; opacity: index < w.count ? 1 : 0.4 }
                    MouseArea { anchors.fill: parent; onClicked: w.set(index + 1) }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: theme.spacingMd; spacing: theme.spacingLg
            PillButton { label: "Remove"; glyph: "−"; implicitWidth: 170; onClicked: w.set(w.count - 1) }
            PillButton { label: "Add a glass"; glyph: "💧"; primary: true; tint: theme.catInfo
                implicitWidth: 240; onClicked: w.set(w.count + 1) }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingMd
            Text { text: "Daily goal:"; color: theme.textSecondary; font.pixelSize: 16; Layout.alignment: Qt.AlignVCenter }
            PillButton { label: "−"; onClicked: w.setGoal(w.goal - 1) }
            Text { text: w.goal + " glasses"; color: theme.textPrimary; font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter; Layout.preferredWidth: 100; horizontalAlignment: Text.AlignHCenter }
            PillButton { label: "+"; onClicked: w.setGoal(w.goal + 1) }
        }
    }
}
