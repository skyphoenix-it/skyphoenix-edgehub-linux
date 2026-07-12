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
        return new Date(y, mo, d, h, mi, s)
    }

    function expand(ev, horizonEnd, now) {
        var out = []
        var todayStart = dayStart(now)
        // Duration of the event, used so an occurrence that STARTED before today
        // but hasn't finished yet (multi-day / in-progress) still counts.
        var dur = (ev.end && ev.start) ? (ev.end.getTime() - ev.start.getTime()) : 0
        if (!ev.rrule) {
            var effEnd = ev.end || ev.start
            if (effEnd >= todayStart && ev.start <= horizonEnd) out.push(ev)
            return out
        }
        var parts = {}
        ev.rrule.split(";").forEach(function (p) { var kv = p.split("="); parts[kv[0]] = kv[1] })
        var interval = +(parts.INTERVAL || 1)
        var count = parts.COUNT ? +parts.COUNT : 100000
        var until = parts.UNTIL ? parseDT(parts.UNTIL, "") : horizonEnd
        var stepDays = parts.FREQ === "WEEKLY" ? 7 * interval : (parts.FREQ === "DAILY" ? interval : 0)
        if (stepDays === 0) { // unsupported freq → single instance
            var effEnd0 = ev.end || ev.start
            if (effEnd0 >= todayStart && ev.start <= horizonEnd) out.push(ev)
            return out
        }
        var occ = new Date(ev.start), n = 0
        while (occ <= horizonEnd && occ <= until && n < count && out.length < 200) {
            // Include an occurrence whose end is today or later (so one currently
            // in progress isn't skipped just because it started before midnight).
            if (occ.getTime() + dur >= todayStart.getTime())
                out.push({ title: ev.title, location: ev.location, allDay: ev.allDay,
                           start: new Date(occ), end: new Date(occ.getTime() + dur) })
            occ = new Date(occ.getTime() + stepDays * 86400000); n++
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
                    cur.allDay = key.indexOf("VALUE=DATE") >= 0
                }
                else if (name === "DTEND") cur.end = parseDT(val, key)
            }
        }
        var now = new Date(), horizon = new Date(now.getTime() + 30 * 86400000)
        var all = []
        for (var j = 0; j < evs.length; j++)
            all = all.concat(expand(evs[j], horizon, now))
        all.sort(function (a, b) { return a.start - b.start })
        return all.slice(0, 60)
    }

    function refresh() {
        if (!url.length) { events = []; errorText = ""; return }
        loading = true
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (!w) return
            w.loading = false
            if (xhr.status !== 200) { w.errorText = "Couldn't fetch calendar"; return }
            try {
                w.events = w.parseICS(xhr.responseText)
                w.errorText = w.events.length ? "" : "No upcoming events"
            } catch (e) { w.errorText = "Couldn't read calendar" }
        }
        try { xhr.open("GET", url); xhr.send() }
        catch (e) { loading = false; errorText = "Invalid URL" }
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
                model: Math.min(w.shownEvents.length, 3)
                delegate: RowLayout {
                    required property int index
                    Layout.fillWidth: true; spacing: 6
                    Rectangle { Layout.preferredWidth: 3; Layout.preferredHeight: 26; radius: 2; color: theme.catServices }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        Text { text: w.shownEvents[index].title || "(busy)"; color: theme.textPrimary
                            font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: w.fmtWhen(w.shownEvents[index]); color: theme.textSecondary; font.pixelSize: 12 }
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
                    border.color: urlField.activeFocus ? theme.accent : theme.cardBorder; border.width: 1 }
                onEditingFinished: if (w.store) w.store.setSetting(w.instanceId, "url", text)
            }
            PillButton { label: "Save"; primary: true; tint: theme.catServices
                onClicked: if (w.store) w.store.setSetting(w.instanceId, "url", urlField.text) }
        }

        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6
            model: w.shownEvents
            delegate: RowLayout {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                spacing: theme.spacingSm
                Rectangle { Layout.preferredWidth: 4; Layout.preferredHeight: 40; radius: 2; color: theme.catServices }
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
