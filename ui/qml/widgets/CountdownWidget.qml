import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Countdown — days until a user-set date. Persisted; genuinely real once set.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Countdown"; iconName: "countdown"; accentColor: theme.catInfo
    big: expanded; showHeader: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string label: cfg.label || ""
    readonly property string dateStr: cfg.date || ""
    readonly property bool repeatYearly: cfg.repeatYearly !== undefined ? cfg.repeatYearly : false
    function dayStart(d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x }
    property int days: {
        w.tick
        if (!dateStr.length) return -999
        // Parse "YYYY-MM-DD" into LOCAL components — new Date(str) would treat it as
        // UTC midnight and, west of UTC, land the countdown one day off.
        var p = ("" + dateStr).split("-")
        if (p.length < 3) return -999
        var y = +p[0], mo = +p[1] - 1, d = +p[2]
        if (isNaN(y) || isNaN(mo) || isNaN(d) || mo < 0 || mo > 11 || d < 1 || d > 31) return -999
        var today0 = dayStart(new Date())
        var target = new Date(y, mo, d)
        if (isNaN(target.getTime())) return -999
        if (w.repeatYearly) {
            // Recur every year: aim at this year's occurrence, or next year's if it
            // has already passed, so a birthday/anniversary never reads "passed".
            target = new Date(today0.getFullYear(), mo, d)
            if (dayStart(target) < today0) target = new Date(today0.getFullYear() + 1, mo, d)
        }
        return Math.round((dayStart(target) - today0) / 86400000)
    }
    property bool valid: days > -999

    ColumnLayout {
        anchors.centerIn: parent; visible: !w.expanded || w.valid; spacing: w.expanded ? 8 : 2
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: !w.valid ? "—" : (w.days > 0 ? w.days : (w.days === 0 ? "🎉" : Math.abs(w.days)))
            font.pixelSize: w.expanded ? 120 : Math.max(30, Math.min(w.width * 0.34, 68))
            font.bold: true; font.family: theme.fontMono; color: w.effAccent
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: !w.valid ? "Set a date below" :
                  (w.days > 0 ? (w.days === 1 ? "day until " : "days until ") + (w.label || "the day")
                   : w.days === 0 ? (w.label || "Today") + "!"
                   : (w.label || "the day") + " passed")
            font.pixelSize: w.expanded ? 22 : 12; color: theme.textSecondary
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            Layout.preferredWidth: w.width * 0.9
        }
    }

    // Settings (expanded)
    ColumnLayout {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        visible: w.expanded; spacing: theme.spacingSm
        RowLayout {
            Layout.fillWidth: true; spacing: theme.spacingSm
            TextField {
                id: labelField; Layout.fillWidth: true; Layout.preferredHeight: theme.touchSecondary; text: w.label
                placeholderText: "Label (e.g. Vacation)"; placeholderTextColor: theme.textTertiary
                color: theme.textPrimary; font.pixelSize: 15
                background: Rectangle { radius: theme.radiusSm; color: theme.backgroundColor
                    border.color: labelField.activeFocus ? theme.accent : theme.cardBorder; border.width: 1 }
                onEditingFinished: if (w.store) w.store.setSetting(w.instanceId, "label", text)
            }
            TextField {
                id: dateField; Layout.preferredWidth: 150; Layout.preferredHeight: theme.touchSecondary; text: w.dateStr
                placeholderText: "YYYY-MM-DD"; placeholderTextColor: theme.textTertiary
                color: theme.textPrimary; font.pixelSize: 15; inputMask: "9999-99-99"
                background: Rectangle { radius: theme.radiusSm; color: theme.backgroundColor
                    border.color: dateField.activeFocus ? theme.accent : theme.cardBorder; border.width: 1 }
                onEditingFinished: if (w.store) w.store.setSetting(w.instanceId, "date", text)
            }
            PillButton { label: "Save"; primary: true; tint: w.effAccent
                onClicked: if (w.store) w.store.patchSettings(w.instanceId, { "label": labelField.text, "date": dateField.text }) }
        }
    }
}
