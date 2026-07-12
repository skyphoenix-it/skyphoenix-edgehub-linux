import QtQuick
import QtQuick.Layouts

// Digital clock — driven by the shared dashboard tick (no per-widget timer).
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Clock"; iconName: "clock"; accentColor: theme.catSystem
    big: expanded
    status: (w.tick, Qt.formatDate(new Date(), "ddd"))

    // Live per-instance config (see WidgetConfigSchema "clock").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? store.settingsFor(instanceId) : ({})
    }
    readonly property bool format24: cfg.format24 !== undefined ? cfg.format24 : false
    readonly property bool showSeconds: cfg.showSeconds !== undefined ? cfg.showSeconds : false
    readonly property bool showDate: cfg.showDate !== undefined ? cfg.showDate : true
    readonly property string dateStyle: cfg.dateStyle !== undefined ? cfg.dateStyle : "full"

    // 12h uses "h" (no leading zero) + AM/PM; 24h uses "HH" (2 digits).
    readonly property string timeFmt: {
        var base = w.format24 ? "HH:mm" : "h:mm"
        if (w.showSeconds) base += ":ss"
        if (!w.format24) base += " AP"
        return base
    }
    readonly property string dateFmt: w.dateStyle === "short"
        ? "dd/MM"
        : (w.expanded ? "dddd, MMMM d yyyy" : "ddd, d MMM")

    ColumnLayout {
        anchors.centerIn: parent
        spacing: w.expanded ? 8 : 2
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: (w.tick, Qt.formatTime(new Date(), w.timeFmt))
            font.pixelSize: w.expanded ? 168 : Math.max(30, Math.min(w.width * 0.24, 74))
            font.bold: true; font.family: theme.fontMono; color: theme.textPrimary
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded && w.showSeconds
            text: (w.tick, Qt.formatTime(new Date(), "ss")) + " sec"
            font.pixelSize: 24; font.family: theme.fontMono; color: theme.accent
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: w.showDate
            text: (w.tick, Qt.formatDate(new Date(), w.dateFmt))
            font.pixelSize: w.expanded ? 26 : 13; color: theme.textSecondary
        }
    }
}
