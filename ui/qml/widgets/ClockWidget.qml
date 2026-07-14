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
    // World-clock: show another zone instead of local time. `zoneId` is a real IANA
    // zone (DST-correct); `utcOffset` is the legacy fixed-offset model kept for
    // configs saved before zoneId existed — zoneId: "" selects it, so an existing
    // saved clock keeps its exact meaning instead of being silently re-pointed.
    readonly property bool customZone: cfg.customZone !== undefined ? cfg.customZone : false
    readonly property string zoneId: cfg.zoneId || ""
    readonly property real utcOffset: cfg.utcOffset !== undefined ? cfg.utcOffset : 0
    readonly property string zoneLabel: cfg.zoneLabel || ""

    // ── IANA zones ───────────────────────────────────────────────────────────
    // Qt's V4 engine ships no ECMA-402, so there is no `Intl` to ask: probing it
    // on 6.11 (AHEAD of CI's 6.7, and engines gain features rather than lose them)
    // gives `typeof Intl === "undefined"`. Worse, Date.toLocaleString SILENTLY
    // IGNORES a { timeZone } option and returns local time — a wrong clock with no
    // error. QTimeZone has no QML binding either, so the DST rules are carried here.
    //
    // `std` is the standard (winter) offset in hours; `rule` names the DST law,
    // which is +1h while in force. Encoding laws (not a per-year transition
    // table) is what keeps this correct in future years without a data refresh.
    // Valid for the current rules: US post-2007, EU post-1996, São Paulo post-2019
    // (DST abolished). Historical instants before those reforms are not modelled —
    // a clock shows present time, so this is a deliberate limit.
    readonly property var zoneTable: ({
        "UTC":                   { std:   0,   rule: "none", city: "UTC" },
        "Pacific/Honolulu":      { std: -10,   rule: "none", city: "Honolulu" },
        "America/Los_Angeles":   { std:  -8,   rule: "us",   city: "Los Angeles" },
        "America/Denver":        { std:  -7,   rule: "us",   city: "Denver" },
        "America/Chicago":       { std:  -6,   rule: "us",   city: "Chicago" },
        "America/New_York":      { std:  -5,   rule: "us",   city: "New York" },
        "America/Sao_Paulo":     { std:  -3,   rule: "none", city: "São Paulo" },
        "Europe/London":         { std:   0,   rule: "eu",   city: "London" },
        "Europe/Paris":          { std:   1,   rule: "eu",   city: "Paris" },
        "Europe/Berlin":         { std:   1,   rule: "eu",   city: "Berlin" },
        "Europe/Athens":         { std:   2,   rule: "eu",   city: "Athens" },
        "Africa/Johannesburg":   { std:   2,   rule: "none", city: "Johannesburg" },
        "Europe/Moscow":         { std:   3,   rule: "none", city: "Moscow" },
        "Asia/Dubai":            { std:   4,   rule: "none", city: "Dubai" },
        "Asia/Kolkata":          { std:   5.5, rule: "none", city: "Mumbai" },
        "Asia/Singapore":        { std:   8,   rule: "none", city: "Singapore" },
        "Asia/Hong_Kong":        { std:   8,   rule: "none", city: "Hong Kong" },
        "Asia/Tokyo":            { std:   9,   rule: "none", city: "Tokyo" },
        "Australia/Sydney":      { std:  10,   rule: "au",   city: "Sydney" },
        "Pacific/Auckland":      { std:  12,   rule: "nz",   city: "Auckland" }
    })

    // UTC ms of the nth (1-based) Sunday of month `m`, 00:00 UTC.
    function _nthSundayUtc(y, m, n) {
        var first = new Date(Date.UTC(y, m, 1))
        return Date.UTC(y, m, 1 + (7 - first.getUTCDay()) % 7 + (n - 1) * 7)
    }
    // UTC ms of the last Sunday of month `m`, 00:00 UTC.
    function _lastSundayUtc(y, m) {
        var last = new Date(Date.UTC(y, m + 1, 0))
        return Date.UTC(y, m, last.getUTCDate() - last.getUTCDay())
    }
    // Is DST in force at UTC instant `t` (ms)? Each law's switchover is defined in
    // LOCAL wall time, so it converts to UTC by subtracting the offset in force
    // just before the switch — standard when springing forward, DST when falling
    // back. Southern rules (au/nz) straddle New Year, hence the OR.
    function _isDst(rule, std, t) {
        var y = new Date(t).getUTCFullYear(), start, end
        switch (rule) {
        case "us": // 2nd Sun Mar 02:00 std → 1st Sun Nov 02:00 dst
            start = w._nthSundayUtc(y, 2, 2) + (2 - std) * 3600000
            end   = w._nthSundayUtc(y, 10, 1) + (2 - (std + 1)) * 3600000
            return t >= start && t < end
        case "eu": // last Sun Mar → last Sun Oct, both at 01:00 UTC everywhere
            start = w._lastSundayUtc(y, 2) + 3600000
            end   = w._lastSundayUtc(y, 9) + 3600000
            return t >= start && t < end
        case "au": // 1st Sun Oct 02:00 std → 1st Sun Apr 03:00 dst
            start = w._nthSundayUtc(y, 9, 1) + (2 - std) * 3600000
            end   = w._nthSundayUtc(y, 3, 1) + (3 - (std + 1)) * 3600000
            return t >= start || t < end
        case "nz": // last Sun Sep 02:00 std → 1st Sun Apr 03:00 dst
            start = w._lastSundayUtc(y, 8) + (2 - std) * 3600000
            end   = w._nthSundayUtc(y, 3, 1) + (3 - (std + 1)) * 3600000
            return t >= start || t < end
        }
        return false
    }
    // The zone's UTC offset in hours at instant `at`, or undefined if unknown.
    // hasOwnProperty-guarded: zoneId is user/file-supplied text, and a bare lookup
    // of e.g. "constructor" would hit Object.prototype and yield a NaN offset.
    function zoneOffsetAt(zoneId, at) {
        if (!zoneId || !w.zoneTable.hasOwnProperty(zoneId)) return undefined
        var z = w.zoneTable[zoneId]
        return z.std + (w._isDst(z.rule, z.std, at.getTime()) ? 1 : 0)
    }
    // The offset actually used: the real zone when one is picked, else the legacy
    // fixed offset (which is also the fallback for a zoneId this build can't map,
    // so a config from a newer build degrades to the user's offset, not to UTC).
    function effectiveOffsetAt(at) {
        var o = w.zoneOffsetAt(w.zoneId, at)
        return o !== undefined ? o : w.utcOffset
    }
    // The configured zone's city name, when a real zone is picked.
    function zoneCity() {
        return w.zoneTable.hasOwnProperty(w.zoneId) ? w.zoneTable[w.zoneId].city : ""
    }

    // The local zone's own UTC offset in ms at instant `ms`.
    function _localOffsetMs(ms) { return -new Date(ms).getTimezoneOffset() * 60000 }

    // The time in the configured zone at instant `at` (local unless customZone).
    // Shifts the instant so the LOCAL-zone formatters print the target's wall clock.
    // The shift is resolved TWICE: Qt renders the shifted instant with whatever
    // offset the local zone has *there*, so when the shift jumps across the local
    // zone's own DST switch, cancelling with the offset at `at` leaves the tile an
    // hour out (e.g. a Berlin desk showing Tokyo around Berlin's March change).
    // Re-cancelling with the offset actually in force at the shifted instant is
    // what makes the printed wall clock the target's in every local zone.
    // Measured over 2026 (6 zones x hourly) this cuts wrong hours from 77-121/yr to
    // 5-6/yr on a DST-observing host. The remainder is irreducible here: they are the
    // instants whose target wall clock falls inside the LOCAL zone's spring-forward
    // gap — an hour that does not exist locally, so no local Date can render it, and
    // Qt only ever formats in local time. Hand-rolling the formatting would trade
    // Qt's locale-aware date strings for ~1 hour a year, so it is left as is.
    function zonedAt(at) {
        if (!w.customZone) return at
        var t = at.getTime(), target = w.effectiveOffsetAt(at) * 3600000
        var shifted = t - w._localOffsetMs(t) + target
        return new Date(t - w._localOffsetMs(shifted) + target)
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
