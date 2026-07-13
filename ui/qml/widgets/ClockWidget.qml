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
    // Header weekday only when it ISN'T already shown elsewhere: hidden when the
    // date row is off (showDate=false hides ALL date info) and when the full date
    // row already spells out the weekday (avoid duplicating it). Short style
    // ("dd/MM") carries no weekday, so the header still supplies it.
    status: (w.showDate && w.dateStyle !== "full")
            ? (w.tick, Qt.formatDate(w.zonedNow(), "ddd"))
            : ""

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
        var o = w.utcOffset
        var sign = o < 0 ? "-" : "+"
        var a = Math.abs(o)
        var h = Math.floor(a)
        var m = Math.round((a - h) * 60)
        var mm = m > 0 ? ":" + (m < 10 ? "0" : "") + m : ""
        return "UTC" + sign + h + mm
    }

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        // Fill the content body width so children can be width-constrained and
        // shrink-to-fit rather than overflow the tile (S12).
        width: parent.width
        spacing: w.expanded ? 8 : 2
        // Zone name (world-clock mode). Any custom zone shows an indicator — even a
        // non-expanded tile with no label falls back to the UTC offset, so foreign
        // time is never mistaken for a wrong local clock.
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: w.customZone
            text: w.zoneLabel.length ? w.zoneLabel : w.offsetLabel()
            font.pixelSize: w.expanded ? 22 : 12; font.bold: true
            font.family: theme.fontDisplay; color: w.effAccent
            elide: Text.ElideRight; Layout.maximumWidth: col.width * 0.95
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: (w.tick, Qt.formatTime(w.zonedNow(), w.timeFmt))
            font.pixelSize: w.expanded ? 168 : Math.max(30, Math.min(w.width * 0.24, 74))
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 12
            elide: Text.ElideRight
            font.bold: true; font.family: theme.fontMono; color: theme.textPrimary
        }
        Text {
            Layout.fillWidth: true; visible: w.showDate
            horizontalAlignment: Text.AlignHCenter
            text: (w.tick, Qt.formatDate(w.zonedNow(), w.dateFmt))
            font.pixelSize: w.expanded ? 26 : 13; color: theme.textSecondary
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 9
            elide: Text.ElideRight
        }
    }
}
