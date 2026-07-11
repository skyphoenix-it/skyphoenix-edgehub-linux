import QtQuick
import QtQuick.Layouts

// End of Day — progress through the workday + time remaining. Real (system
// clock). Start/end hours are configurable and persisted.
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "End of Day"; icon: "🌆"; accentColor: theme.catInfo
    big: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    property int startHour: cfg.startHour !== undefined ? cfg.startHour : 9
    property int endHour: cfg.endHour !== undefined ? cfg.endHour : 17

    property real frac: {
        w.tick
        var n = new Date()
        var s = new Date(n); s.setHours(startHour, 0, 0, 0)
        var e = new Date(n); e.setHours(endHour, 0, 0, 0)
        if (e <= s) return 0
        return Math.max(0, Math.min(1, (n - s) / (e - s)))
    }
    property string remaining: {
        w.tick
        var n = new Date(), e = new Date(n); e.setHours(endHour, 0, 0, 0)
        var d = (e - n) / 1000
        if (d <= 0) return "Done! 🎉"
        return Math.floor(d / 3600) + "h " + Math.floor((d % 3600) / 60) + "m"
    }
    function setHours(sh, eh) {
        if (store) store.patchSettings(instanceId, { "startHour": Math.max(0, Math.min(23, sh)), "endHour": Math.max(1, Math.min(24, eh)) })
    }

    ColumnLayout {
        anchors.centerIn: parent; width: parent.width * 0.88; spacing: w.expanded ? 14 : 6
        Text {
            Layout.alignment: Qt.AlignHCenter; text: w.remaining
            font.pixelSize: w.expanded ? 80 : Math.max(24, Math.min(w.width * 0.24, 44))
            font.bold: true; font.family: theme.fontMono; color: theme.catInfo
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: w.expanded ? 14 : 8
            radius: height / 2; color: theme.cardBorder
            Rectangle { height: parent.height; radius: height / 2; width: parent.width * w.frac; color: theme.catInfo
                Behavior on width { NumberAnimation { duration: 500 } } }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Math.round(w.frac * 100) + "% of " + w.startHour + ":00–" + w.endHour + ":00"
            font.pixelSize: w.expanded ? 15 : 10; color: theme.textSecondary
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded; spacing: theme.spacingMd
            PillButton { label: "Start −"; onClicked: w.setHours(w.startHour - 1, w.endHour) }
            PillButton { label: "Start +"; onClicked: w.setHours(w.startHour + 1, w.endHour) }
            PillButton { label: "End −"; onClicked: w.setHours(w.startHour, w.endHour - 1) }
            PillButton { label: "End +"; onClicked: w.setHours(w.startHour, w.endHour + 1) }
        }
    }
}
