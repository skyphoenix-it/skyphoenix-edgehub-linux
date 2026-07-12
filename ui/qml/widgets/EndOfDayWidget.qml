import QtQuick
import QtQuick.Layouts

// End of Day — progress through the workday + time remaining. Real (system
// clock). Start/end hours are configurable and persisted.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "End of Day"; iconName: "eod"; accentColor: theme.catInfo
    big: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    property int startHour: cfg.startHour !== undefined ? cfg.startHour : 9
    property int endHour: cfg.endHour !== undefined ? cfg.endHour : 17
    readonly property bool showPercent: cfg.showPercent !== undefined ? cfg.showPercent : true
    readonly property string progressStyle: cfg.progressStyle !== undefined ? cfg.progressStyle : "bar"

    property bool validHours: endHour > startHour
    property real frac: {
        w.tick
        var n = new Date()
        var s = new Date(n); s.setHours(startHour, 0, 0, 0)
        var e = new Date(n); e.setHours(endHour, 0, 0, 0)
        if (e <= s) return 0
        return Math.max(0, Math.min(1, (n - s) / (e - s)))
    }
    function fmtDur(secs) {
        return Math.floor(secs / 3600) + "h " + Math.floor((secs % 3600) / 60) + "m"
    }
    property string remaining: {
        w.tick
        var n = new Date()
        var s = new Date(n); s.setHours(startHour, 0, 0, 0)
        var e = new Date(n); e.setHours(endHour, 0, 0, 0)
        if (e <= s) return "Set hours"                    // invalid (end ≤ start)
        if (n < s) return "Starts in " + fmtDur((s - n) / 1000)  // before the workday
        var d = (e - n) / 1000
        if (d <= 0) return "Done! 🎉"
        return fmtDur(d)
    }
    // Keep a 1-hour minimum span: whichever end the user moved yields, so the
    // work window can never invert (end ≤ start) and get stuck.
    function setHours(sh, eh) {
        var s = Math.max(0, Math.min(23, sh))
        var e = Math.max(1, Math.min(24, eh))
        if (s >= e) { if (sh !== w.startHour) s = e - 1; else e = s + 1 }
        if (store) store.patchSettings(instanceId, { "startHour": s, "endHour": e })
    }

    ColumnLayout {
        anchors.centerIn: parent; width: parent.width * 0.88; spacing: w.expanded ? 14 : 6

        // Optional circular progress (expanded only) with the time in the centre.
        Item {
            visible: w.expanded && w.progressStyle === "ring"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(w.width * 0.7, w.height * 0.55, 320)
            Layout.preferredHeight: Layout.preferredWidth
            RingProgress {
                anchors.fill: parent
                value: w.frac
                progressColor: w.effAccent; progressColor2: w.effAccent
            }
            ColumnLayout {
                anchors.centerIn: parent; spacing: 2
                Text { Layout.alignment: Qt.AlignHCenter; text: w.remaining
                    font.pixelSize: Math.min(parent.parent.width * 0.22, 56)
                    font.bold: true; font.family: theme.fontMono; color: theme.textPrimary }
                Text { Layout.alignment: Qt.AlignHCenter; visible: w.showPercent
                    text: Math.round(w.frac * 100) + "%"; font.pixelSize: 18; color: theme.textSecondary }
            }
        }

        Text {
            visible: !(w.expanded && w.progressStyle === "ring")
            Layout.alignment: Qt.AlignHCenter; text: w.remaining
            font.pixelSize: w.expanded ? 80 : Math.max(24, Math.min(w.width * 0.24, 44))
            font.bold: true; font.family: theme.fontMono; color: w.effAccent
        }
        Rectangle {
            visible: !(w.expanded && w.progressStyle === "ring")
            Layout.fillWidth: true; Layout.preferredHeight: w.expanded ? 14 : 8
            radius: height / 2; color: theme.cardBorder
            Rectangle { height: parent.height; radius: height / 2; width: parent.width * w.frac; color: w.effAccent
                Behavior on width { NumberAnimation { duration: 500 } } }
        }
        Text {
            visible: w.showPercent && !(w.expanded && w.progressStyle === "ring")
            Layout.alignment: Qt.AlignHCenter
            text: Math.round(w.frac * 100) + "% of " + w.startHour + ":00–" + w.endHour + ":00"
            font.pixelSize: w.expanded ? 15 : 12; color: theme.textSecondary
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
