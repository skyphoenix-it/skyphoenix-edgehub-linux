import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Calendar — real agenda from an ICS subscription URL (Google/Outlook/Nextcloud
// all provide one). Fetched + parsed in QML (no extra deps). Handles VEVENT +
// simple DAILY/WEEKLY recurrence; MONTHLY/YEARLY fall back to a single instance.
// Genuine empty state prompts for a URL rather than showing fake events.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0
    // Test seam: when set, called instead of `new XMLHttpRequest()` so a FakeXHR
    // can be injected. null in production → real XHR (behaviour unchanged).
    property var xhrFactory: null

    title: "Calendar"; iconName: "calendar"; accentColor: theme.catServices
    big: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string url: cfg.url || ""
    readonly property int maxEvents: cfg.maxEvents !== undefined ? cfg.maxEvents : 5
    property var events: []        // expanded, sorted upcoming
    readonly property var shownEvents: events.slice(0, maxEvents)
    property string errorText: ""
    property bool loading: false

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function dayStart(d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x }

    function parseDT(val, key) {
        val = val.trim()
        var y = +val.substr(0, 4), mo = +val.substr(4, 2) - 1, d = +val.substr(6, 2)
        if (val.length <= 8) return new Date(y, mo, d)
        var h = +val.substr(9, 2), mi = +val.substr(11, 2), s = +val.substr(13, 2) || 0
        if (val.indexOf("Z") >= 0) return new Date(Date.UTC(y, mo, d, h, mi, s))
        // A named zone (DTSTART;TZID=…) is NOT a floating wall time: anchor it to
        // the zone's offset. Only a bare timed value stays device-local.
        var tz = tzidOf(key)
        var off = tz ? tzOffsetMinutes(tz, y, mo, d) : null
        if (off !== null) return new Date(Date.UTC(y, mo, d, h, mi, s) - off * 60000)
        return new Date(y, mo, d, h, mi, s)
    }

    // Extract a TZID parameter from a property line's key part.
    function tzidOf(key) { var m = /TZID=([^;:]+)/.exec(key || ""); return m ? m[1].trim() : null }

    // Best-effort zone → offset (minutes east of UTC) WITHOUT a tz database
    // (QML's JS engine has no Intl). Explicit numeric-offset zones resolve
    // exactly; a table of common IANA zones carries US/EU daylight-saving rules;
    // anything unrecognised returns null so the caller falls back to floating.
    function tzOffsetMinutes(tzid, y, mo, d) {
        if (!tzid) return null
        var m = /(?:GMT|UTC)?\s*([+-])(\d{2}):?(\d{2})/.exec(tzid)
        if (m) { var v = (+m[2]) * 60 + (+m[3]); return m[1] === "-" ? -v : v }
        var eg = /Etc\/GMT([+-])(\d{1,2})/.exec(tzid)   // POSIX sign is inverted
        if (eg) return (eg[1] === "+" ? -1 : 1) * (+eg[2]) * 60
        var zones = {
            "America/New_York": [-300, "US"], "America/Chicago": [-360, "US"],
            "America/Denver": [-420, "US"], "America/Los_Angeles": [-480, "US"],
            "America/Anchorage": [-540, "US"], "America/Phoenix": [-420, null],
            "America/Sao_Paulo": [-180, null], "America/Halifax": [-240, "US"],
            "Europe/London": [0, "EU"], "Europe/Dublin": [0, "EU"], "Europe/Lisbon": [0, "EU"],
            "Europe/Berlin": [60, "EU"], "Europe/Paris": [60, "EU"], "Europe/Madrid": [60, "EU"],
            "Europe/Rome": [60, "EU"], "Europe/Amsterdam": [60, "EU"], "Europe/Zurich": [60, "EU"],
            "Europe/Vienna": [60, "EU"], "Europe/Warsaw": [60, "EU"], "Europe/Athens": [120, "EU"],
            "Europe/Helsinki": [120, "EU"], "Europe/Istanbul": [180, null], "Europe/Moscow": [180, null],
            "UTC": [0, null], "Etc/UTC": [0, null], "GMT": [0, null],
            "Asia/Kolkata": [330, null], "Asia/Dubai": [240, null], "Asia/Shanghai": [480, null],
            "Asia/Singapore": [480, null], "Asia/Hong_Kong": [480, null], "Asia/Tokyo": [540, null],
            "Australia/Sydney": [600, "AUE"], "Pacific/Auckland": [720, "NZ"]
        }
        var z = zones[tzid]
        if (!z) return null
        return z[0] + (z[1] && inDst(z[1], y, mo, d) ? 60 : 0)
    }

    function nthSunday(y, mo, n) {
        var first = new Date(y, mo, 1).getDay()
        return 1 + ((7 - first) % 7) + (n - 1) * 7
    }
    function lastSunday(y, mo) {
        var last = new Date(y, mo + 1, 0)
        return last.getDate() - last.getDay()
    }
    // Approximate daylight-saving membership by local calendar date (mo 0-based).
    function inDst(rule, y, mo, d) {
        if (rule === "US") {   // 2nd Sun Mar → 1st Sun Nov
            if (mo < 2 || mo > 10) return false
            if (mo > 2 && mo < 10) return true
            return mo === 2 ? d >= nthSunday(y, 2, 2) : d < nthSunday(y, 10, 1)
        }
        if (rule === "EU") {   // last Sun Mar → last Sun Oct
            if (mo < 2 || mo > 9) return false
            if (mo > 2 && mo < 9) return true
            return mo === 2 ? d >= lastSunday(y, 2) : d < lastSunday(y, 9)
        }
        if (rule === "AUE") {  // southern: 1st Sun Oct → 1st Sun Apr
            if (mo > 9 || mo < 3) return true
            if (mo > 3 && mo < 9) return false
            return mo === 9 ? d >= nthSunday(y, 9, 1) : d < nthSunday(y, 3, 1)
        }
        if (rule === "NZ") {   // southern: last Sun Sep → 1st Sun Apr
            if (mo > 8 || mo < 3) return true
            if (mo > 3 && mo < 8) return false
            return mo === 8 ? d >= lastSunday(y, 8) : d < nthSunday(y, 3, 1)
        }
        return false
    }

    // BYDAY tokens → weekday numbers (SU=0…SA=6), tolerating ordinal prefixes
    // like "2MO" by keeping only the trailing two-letter day code.
    function weekdayNums(byday) {
        var map = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 }
        var out = []
        byday.split(",").forEach(function (t) {
            var d = t.replace(/[^A-Z]/g, "").slice(-2)
            if (map[d] !== undefined) out.push(map[d])
        })
        return out
    }
    // Comparison key for EXDATE matching: calendar day + hour + minute (robust to
    // the small tz/format variations between DTSTART and EXDATE in real feeds).
    function exKey(d) {
        return d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate() + "-" + d.getHours() + "-" + d.getMinutes()
    }

    function expand(ev, horizonEnd, now) {
        var out = []
        var todayStart = dayStart(now)
        // Duration of the event, used so an occurrence that STARTED before today
        // but hasn't finished yet (multi-day / in-progress) still counts.
        var dur = (ev.end && ev.start) ? (ev.end.getTime() - ev.start.getTime()) : 0
        var excl = {}
        if (ev.exdates) ev.exdates.forEach(function (d) { excl[exKey(d)] = true })
        // Emit one occurrence (honours EXDATE exclusions + horizon/past bounds).
        function emit(occStart) {
            if (excl[exKey(occStart)]) return                          // cancelled (EXDATE)
            if (occStart > horizonEnd) return
            var finished
            if (ev.allDay) {
                // All-day DTEND is exclusive; the event occupies whole days
                // (default 1). Past once its last-occupied day is before today.
                var occEnd = occStart.getTime() + (dur > 0 ? dur : 86400000)
                finished = occEnd <= todayStart.getTime()
            } else {
                // Timed: past only once it has actually ended — compare against
                // now, not start-of-day (else events done earlier today linger).
                finished = occStart.getTime() + dur < now.getTime()
            }
            if (finished) return
            out.push({ title: ev.title, location: ev.location, allDay: ev.allDay,
                       start: new Date(occStart), end: new Date(occStart.getTime() + dur) })
        }
        if (!ev.rrule) {
            var effEnd = ev.end || ev.start
            if (effEnd >= todayStart && ev.start <= horizonEnd) emit(ev.start)
            return out
        }
        var parts = {}
        ev.rrule.split(";").forEach(function (p) { var kv = p.split("="); parts[kv[0]] = kv[1] })
        var interval = +(parts.INTERVAL || 1)
        var count = parts.COUNT ? +parts.COUNT : 100000
        var until = parts.UNTIL ? parseDT(parts.UNTIL, "") : horizonEnd
        var freq = parts.FREQ, n = 0

        // WEEKLY with BYDAY (e.g. MO,WE,FR): walk day-by-day across the horizon and
        // emit each listed weekday that falls on an active interval-week.
        if (freq === "WEEKLY" && parts.BYDAY) {
            var days = weekdayNums(parts.BYDAY)
            var startWeek = dayStart(ev.start); startWeek.setDate(startWeek.getDate() - startWeek.getDay())
            var cursor = dayStart(ev.start)
            if (cursor < todayStart) cursor = new Date(todayStart)
            var guard = 0
            while (cursor <= horizonEnd && cursor <= until && n < count && out.length < 200 && guard < 800) {
                guard++
                if (days.indexOf(cursor.getDay()) >= 0) {
                    var cw = dayStart(cursor); cw.setDate(cw.getDate() - cw.getDay())
                    var weekIdx = Math.round((cw.getTime() - startWeek.getTime()) / (7 * 86400000))
                    if (weekIdx >= 0 && weekIdx % interval === 0) {
                        var occ = new Date(cursor)
                        occ.setHours(ev.start.getHours(), ev.start.getMinutes(), ev.start.getSeconds(), 0)
                        if (occ >= ev.start) { emit(occ); n++ }
                    }
                }
                var nc = new Date(cursor); nc.setDate(nc.getDate() + 1); cursor = nc  // calendar-day step (DST-safe)
            }
            return out
        }

        // MONTHLY / YEARLY: step by calendar month/year, rolling a past DTSTART
        // forward to its upcoming occurrence (birthdays, monthly bills, …).
        if (freq === "MONTHLY" || freq === "YEARLY") {
            var occM = new Date(ev.start), guardM = 0
            while (occM <= horizonEnd && occM <= until && n < count && out.length < 200 && guardM < 100000) {
                guardM++
                emit(occM)
                var nxM = new Date(occM)
                if (freq === "MONTHLY") nxM.setMonth(nxM.getMonth() + interval)
                else nxM.setFullYear(nxM.getFullYear() + interval)
                occM = nxM; n++
            }
            return out
        }

        var stepDays = freq === "WEEKLY" ? 7 * interval : (freq === "DAILY" ? interval : 0)
        if (stepDays === 0) { // unsupported FREQ → single instance
            var effEnd0 = ev.end || ev.start
            if (effEnd0 >= todayStart && ev.start <= horizonEnd) emit(ev.start)
            return out
        }
        // Step by calendar days so the local wall-clock time survives DST
        // transitions (a fixed 86400000ms delta would drift the hour by ±1).
        var occ2 = new Date(ev.start)
        while (occ2 <= horizonEnd && occ2 <= until && n < count && out.length < 200) {
            emit(occ2)
            var nx2 = new Date(occ2); nx2.setDate(nx2.getDate() + stepDays); occ2 = nx2; n++
        }
        return out
    }

    function parseICS(text) {
        var raw = text.replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "") // unfold
        var lines = raw.split("\n")
        var evs = [], cur = null
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            if (line === "BEGIN:VEVENT") cur = {}
            else if (line === "END:VEVENT") { if (cur && cur.start) evs.push(cur); cur = null }
            else if (cur) {
                var ci = line.indexOf(":"); if (ci < 0) continue
                var key = line.substring(0, ci), val = line.substring(ci + 1)
                var name = key.split(";")[0]
                if (name === "SUMMARY") cur.title = val
                else if (name === "LOCATION") cur.location = val
                else if (name === "RRULE") cur.rrule = val
                else if (name === "DTSTART") {
                    cur.start = parseDT(val, key)
                    // VALUE=DATE marks an all-day event, but must NOT match the
                    // longer VALUE=DATE-TIME (which is a normal timed event).
                    cur.allDay = key.indexOf("VALUE=DATE") >= 0 && key.indexOf("VALUE=DATE-TIME") < 0
                }
                else if (name === "DTEND") cur.end = parseDT(val, key)
                else if (name === "EXDATE") {
                    cur.exdates = cur.exdates || []
                    val.split(",").forEach(function (v) { if (v.trim().length) cur.exdates.push(parseDT(v, key)) })
                }
            }
        }
        var now = new Date(), horizon = new Date(now.getTime() + 30 * 86400000)
        var all = []
        for (var j = 0; j < evs.length; j++)
            all = all.concat(expand(evs[j], horizon, now))
        all.sort(function (a, b) { return a.start - b.start })
        return all.slice(0, 60)
    }

    property var _xhr: null
    Component.onDestruction: { if (_xhr) _xhr.abort() }
    function refresh() {
        if (!url.length) { events = []; errorText = ""; return }
        loading = true
        if (_xhr) _xhr.abort()
        var xhr = (w.xhrFactory ? w.xhrFactory() : new XMLHttpRequest())
        _xhr = xhr
        xhr.timeout = 12000
        xhr.ontimeout = function () { if (w._xhr === xhr) { w._xhr = null; w.loading = false; w.errorText = "Calendar timed out" } }
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (w._xhr !== xhr) return   // superseded by a newer fetch
            w._xhr = null
            w.loading = false
            if ([200, 203, 206, 304].indexOf(xhr.status) < 0) { w.errorText = "Couldn't fetch calendar"; return }
            try {
                w.events = w.parseICS(xhr.responseText)
                w.errorText = w.events.length ? "" : "No upcoming events"
            } catch (e) { w.errorText = "Couldn't read calendar" }
        }
        // webcal:// (iCloud/Apple) is just ICS over HTTP(S) — rewrite the scheme
        // rather than handing XMLHttpRequest a scheme it rejects as invalid.
        var reqUrl = /^webcal:/i.test(url) ? url.replace(/^webcal:/i, "https:") : url
        try { xhr.open("GET", reqUrl); xhr.send() }
        catch (e) { _xhr = null; loading = false; errorText = "Invalid URL" }
    }

    property string _urlKey: url
    on_UrlKeyChanged: refreshDebounce.restart()
    Component.onCompleted: refreshDebounce.restart()
    Timer { id: refreshDebounce; interval: 300; onTriggered: w.refresh() }
    Timer { interval: 900000; repeat: true; running: w.active && w.url.length > 0; onTriggered: w.refresh() }

    function fmtWhen(ev) {
        var d = ev.start, now = new Date()
        var sameDay = d.toDateString() === now.toDateString()
        var tomorrow = new Date(now.getTime() + 86400000)
        var isTom = d.toDateString() === tomorrow.toDateString()
        var day = sameDay ? "Today" : (isTom ? "Tomorrow" : Qt.formatDate(d, "ddd MMM d"))
        return ev.allDay ? day : day + " " + Qt.formatTime(d, "HH:mm")
    }

    // ── Compact: next event / prompt ──
    ColumnLayout {
        anchors.fill: parent; anchors.margins: theme.spacingSm
        visible: !w.expanded; spacing: 4
        Text {
            visible: !w.url.length
            Layout.fillWidth: true; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignVCenter
            text: "Add a calendar\n(ICS URL) in settings"
            color: theme.textTertiary; font.pixelSize: 12
        }
        ColumnLayout {
            visible: w.url.length > 0; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 3
            Text { text: (w.tick, "Up next"); font.pixelSize: 12; color: theme.textTertiary }
            Repeater {
                model: w.shownEvents.length
                delegate: RowLayout {
                    required property int index
                    Layout.fillWidth: true; spacing: 6
                    Rectangle { Layout.preferredWidth: 3; Layout.preferredHeight: 26; radius: 2; color: w.effAccent }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        Text { text: w.shownEvents[index].title || "(busy)"; color: theme.textPrimary
                            font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: w.fmtWhen(w.shownEvents[index]); color: theme.textSecondary
                            font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
            }
            Text { visible: w.events.length === 0; text: w.errorText || (w.loading ? "Loading…" : "No upcoming events")
                color: theme.textTertiary; font.pixelSize: 12 }
            Item { Layout.fillHeight: true }
        }
    }

    // ── Expanded: agenda + settings ──
    ColumnLayout {
        anchors.fill: parent; visible: w.expanded; spacing: theme.spacingMd

        RowLayout {
            Layout.fillWidth: true; spacing: theme.spacingSm
            TextField {
                id: urlField; Layout.fillWidth: true; Layout.preferredHeight: theme.touchSecondary
                text: w.url; placeholderText: "Paste an ICS calendar URL…"
                placeholderTextColor: theme.textTertiary; color: theme.textPrimary; font.pixelSize: 15
                background: Rectangle { radius: theme.radiusSm; color: theme.backgroundColor
                    border.color: urlField.activeFocus ? w.effAccent : theme.cardBorder; border.width: 1 }
                onEditingFinished: if (w.store) w.store.setSetting(w.instanceId, "url", text)
                // Re-assert the store value after an external/store push (typing
                // severs the `text:` binding permanently — S2). Skip while editing.
                Connections {
                    target: w
                    function onUrlChanged() { if (!urlField.activeFocus) urlField.text = w.url }
                }
            }
            PillButton { label: "Save"; primary: true; tint: w.effAccent
                onClicked: if (w.store) w.store.setSetting(w.instanceId, "url", urlField.text) }
        }

        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6
            model: w.shownEvents
            delegate: RowLayout {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                spacing: theme.spacingSm
                Rectangle { Layout.preferredWidth: 4; Layout.preferredHeight: 40; radius: 2; color: w.effAccent }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    Text { text: modelData.title || "(busy)"; color: theme.textPrimary; font.pixelSize: 17
                        font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: w.fmtWhen(modelData) + (modelData.location ? "  ·  " + modelData.location : "")
                        color: theme.textSecondary; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }
        }
        Text {
            visible: w.events.length === 0; Layout.alignment: Qt.AlignHCenter
            text: w.loading ? "Loading…" : (w.errorText || (w.url.length ? "No upcoming events" : "Add an ICS URL above to see your agenda."))
            color: theme.textTertiary; font.pixelSize: 15
        }
    }
}
