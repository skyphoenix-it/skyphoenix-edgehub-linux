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
    status: (w.tick, Qt.formatDate(w.zonedNow(), "ddd"))

    // Live per-instance config (see WidgetConfigSchema "clock"). Clone-on-read
    // (JSON round-trip) so a new object is returned each revision — otherwise QML
    // sees the same object reference and cfg-derived properties never re-evaluate,
    // i.e. config edits wouldn't update the widget live.
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property bool format24: cfg.format24 !== undefined ? cfg.format24 : false
    readonly property bool showSeconds: cfg.showSeconds !== undefined ? cfg.showSeconds : false
    readonly property bool showDate: cfg.showDate !== undefined ? cfg.showDate : true
    readonly property string dateStyle: cfg.dateStyle !== undefined ? cfg.dateStyle : "full"
    // World-clock: show a specific UTC offset instead of local time.
    readonly property bool customZone: cfg.customZone !== undefined ? cfg.customZone : false
    readonly property real utcOffset: cfg.utcOffset !== undefined ? cfg.utcOffset : 0
    readonly property string zoneLabel: cfg.zoneLabel || ""

    // The current time in the configured zone (local unless customZone is on).
    // NB: a fixed UTC offset — it doesn't track daylight-saving transitions.
    function zonedNow() {
        var d = new Date()
        if (!w.customZone) return d
        var utcMs = d.getTime() + d.getTimezoneOffset() * 60000
        return new Date(utcMs + w.utcOffset * 3600000)
    }

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
    function offsetLabel() {
        var s = w.utcOffset >= 0 ? "+" + w.utcOffset : "" + w.utcOffset
        return "UTC" + s
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: w.expanded ? 8 : 2
        // Zone name (world-clock mode).
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: w.customZone && (w.zoneLabel.length > 0 || w.expanded)
            text: w.zoneLabel.length ? w.zoneLabel : w.offsetLabel()
            font.pixelSize: w.expanded ? 22 : 12; font.bold: true
            font.family: theme.fontDisplay; color: theme.accent
            elide: Text.ElideRight; Layout.maximumWidth: w.width * 0.9
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: (w.tick, Qt.formatTime(w.zonedNow(), w.timeFmt))
            font.pixelSize: w.expanded ? 168 : Math.max(30, Math.min(w.width * 0.24, 74))
            font.bold: true; font.family: theme.fontMono; color: theme.textPrimary
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded && w.showSeconds
            text: (w.tick, Qt.formatTime(w.zonedNow(), "ss")) + " sec"
            font.pixelSize: 24; font.family: theme.fontMono; color: theme.accent
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: w.showDate
            text: (w.tick, Qt.formatDate(w.zonedNow(), w.dateFmt))
            font.pixelSize: w.expanded ? 26 : 13; color: theme.textSecondary
        }
    }
}
