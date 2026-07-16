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
    // Header weekday only when it ISN'T already shown elsewhere: hidden when the
    // date row is off (showDate=false hides ALL date info) and when the full date
    // row already spells out the weekday (avoid duplicating it). Short style
    // ("dd/MM") carries no weekday, so the header still supplies it.
    status: (w.showDate && w.dateStyle !== "full")
            ? (w.tick, w.formatAt("ddd"))
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
    // World-clock: show another zone instead of local time. `zoneId` is a real IANA
    // zone (DST-correct); `utcOffset` is the legacy fixed-offset model kept for
    // configs saved before zoneId existed — zoneId: "" selects it, so an existing
    // saved clock keeps its exact meaning instead of being silently re-pointed.
    readonly property bool customZone: cfg.customZone !== undefined ? cfg.customZone : false
    readonly property string zoneId: cfg.zoneId || ""
    readonly property real utcOffset: cfg.utcOffset !== undefined ? cfg.utcOffset : 0
    readonly property string zoneLabel: cfg.zoneLabel || ""

    // ── IANA zones ───────────────────────────────────────────────────────────
    // Resolved by the C++ TimeZoneBridge (app/src/timezone_bridge.h), injected as
    // `timeZones`. QML cannot do this itself and the near-misses are traps: Qt's V4
    // engine has NO `Intl` (probed on 6.11, which is ahead of CI's 6.7), and
    // Date.toLocaleString SILENTLY IGNORES a { timeZone } option, returning local
    // time — a wrong clock with no error. The bridge is backed by the OS tzdata, so
    // every IANA zone works and the rules stay correct through a tzdata update; a
    // hand-written rule table would cover only listed zones and go quietly wrong the
    // day a country changes its law.
    property var timeZones: null
    function _tz() { return w.timeZones ? w.timeZones : (typeof timeZones !== "undefined" ? timeZones : null) }

    // True when a real zone is picked AND resolvable here. A zoneId from a newer
    // build (or a tzdata this box lacks) is NOT resolvable, and must fall back to
    // the user's stored offset rather than render a confidently wrong time.
    function zoneResolvable() {
        var tz = w._tz()
        return !!(tz && w.zoneId.length && tz.isValid(w.zoneId))
    }

    // The zone's UTC offset in hours at instant `at`, or undefined if unknown.
    function zoneOffsetAt(zoneId, at) {
        var tz = w._tz()
        if (!tz || !zoneId || !tz.isValid(zoneId)) return undefined
        return tz.offsetSecsAt(zoneId, at.getTime()) / 3600
    }
    // The offset actually used: the real zone when resolvable, else the legacy fixed
    // offset (also the fallback for an unmappable zoneId — degrade to the user's
    // offset, never to UTC).
    function effectiveOffsetAt(at) {
        var o = w.zoneOffsetAt(w.zoneId, at)
        return o !== undefined ? o : w.utcOffset
    }
    // The configured zone's city, derived from the IANA id ("America/New_York" ->
    // "New York"). Only a display fallback: zoneLabel wins when the user set one.
    function zoneCity() {
        if (!w.zoneResolvable()) return ""
        var seg = w.zoneId.split("/")
        return seg[seg.length - 1].replace(/_/g, " ")
    }

    // The local zone's own UTC offset in ms at instant `ms`.
    function _localOffsetMs(ms) { return -new Date(ms).getTimezoneOffset() * 60000 }

    // LEGACY path only: shift the instant so local formatters print the target's
    // wall clock. Used when no real zone is resolvable (stored utcOffset, no bridge).
    // Resolved twice because the shift can cross the HOST's own DST switch, which
    // would otherwise leave the tile an hour out. Even so it cannot represent an
    // instant whose target wall clock lands in the host's spring-forward gap — which
    // is precisely why the zone path formats in C++ instead and has no such gap.
    function zonedAt(at) {
        if (!w.customZone) return at
        var t = at.getTime(), target = w.effectiveOffsetAt(at) * 3600000
        var shifted = t - w._localOffsetMs(t) + target
        return new Date(t - w._localOffsetMs(shifted) + target)
    }

    // Format `at` in the configured zone using a Qt date/time format spec.
    // The zone path never builds a local Date, so the host's DST gap cannot bite.
    function formatAt(fmt, at) {
        at = at || new Date()
        if (!w.customZone) return Qt.formatDateTime(at, fmt)
        if (w.zoneResolvable()) return w._tz().format(w.zoneId, at.getTime(), fmt)
        return Qt.formatDateTime(w.zonedAt(at), fmt)
    }
    function zonedNow() { return w.zonedAt(new Date()) }

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
    // Reads the offset in force at `at` (default now), so a DST zone's chip tracks
    // the season (New York reads UTC-5 in January, UTC-4 in July).
    function offsetLabel(at) {
        var o = w.effectiveOffsetAt(at || new Date())
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
        // non-expanded tile with no label falls back to the picked zone's city, or
        // to the UTC offset, so foreign time is never mistaken for a wrong local clock.
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: w.customZone
            text: (w.tick, w.zoneLabel.length ? w.zoneLabel
                                              : (w.zoneCity().length ? w.zoneCity() : w.offsetLabel()))
            font.pixelSize: w.expanded ? 22 : 12; font.bold: true
            font.family: theme.fontDisplay; color: w.effAccent
            elide: Text.ElideRight; Layout.maximumWidth: col.width * 0.95
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: (w.tick, w.formatAt(w.timeFmt))
            font.pixelSize: w.expanded ? 168 : Math.max(30, Math.min(w.width * 0.24, 74))
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 12
            elide: Text.ElideRight
            font.bold: true; font.family: theme.fontMono; color: theme.textPrimary
        }
        Text {
            Layout.fillWidth: true; visible: w.showDate
            horizontalAlignment: Text.AlignHCenter
            text: (w.tick, w.formatAt(w.dateFmt))
            font.pixelSize: w.expanded ? 26 : 13; color: theme.textSecondary
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 9
            elide: Text.ElideRight
        }
    }
}
