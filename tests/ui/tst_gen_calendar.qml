import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: schema:maxEvents, schema:url

// ─────────────────────────────────────────────────────────────────────────
// tst_gen_calendar — COMPREHENSIVE coverage for area "widget:calendar"
// (ui/qml/widgets/CalendarWidget.qml, an ICS agenda widget).
//
// Exercises DTSTART/zone parsing, recurrence expansion (DAILY/WEEKLY/BYDAY/
// MONTHLY/YEARLY), EXDATE handling, horizon + past-event pruning, all-day
// semantics, config (url / maxEvents) honouring + reactivity through
// store.revision, effAccent recolouring, host-injected chrome props, the
// fetch state machine, and the schema↔widget key sync.
//
// Several assertions deliberately encode the CORRECT expected behaviour and
// therefore FAIL against real bugs flagged in the audit (MONTHLY/YEARLY
// recurrence dropped entirely, TZID ignored, past-today events not pruned,
// exclusive all-day DTEND over-shown, compact face ignoring maxEvents,
// webcal:// not rewritten). Those failures are the point and are reported as
// likelyRealBug.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 640; height: 960

    // Main harness: expanded — parsing / config / reactivity / accent.
    WidgetHarness {
        id: h; x: 0; y: 0; width: 460; height: 700
        widgetFile: "CalendarWidget.qml"; expanded: true
    }
    // Compact tile — the collapsed face (maxEvents cap behaviour).
    WidgetHarness {
        id: hTile; x: 0; y: 700; width: 320; height: 220
        widgetFile: "CalendarWidget.qml"; expanded: false
    }

    // Shared config-schema area, instantiated directly.
    App.WidgetConfigSchema { id: sc }

    // ── helpers ───────────────────────────────────────────────────────────
    function pad(n) { return (n < 10 ? "0" : "") + n }
    function icsDay(d) { return d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) }
    function icsDateTime(d) {
        return icsDay(d) + "T" + pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds())
    }
    function atNine(d) { var x = new Date(d); x.setHours(9, 0, 0, 0); return x }
    function daysFromNow(n) { var d = atNine(new Date()); d.setDate(d.getDate() + n); return d }
    function midnight(d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x }

    function vcal(body) { return "BEGIN:VCALENDAR\n" + body + "END:VCALENDAR\n" }
    function vevent(lines) { return "BEGIN:VEVENT\n" + lines + "END:VEVENT\n" }

    // Deterministic fake occurrences (bypasses the network / parser).
    function fakeEvents(n) {
        var out = []
        var base = daysFromNow(1)
        for (var i = 0; i < n; i++) {
            var s = new Date(base.getTime() + i * 3600000)
            out.push({ title: "E" + i, location: "", allDay: false,
                       start: s, end: new Date(s.getTime() + 1800000) })
        }
        return out
    }

    function clear(harness) {
        var s = harness.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        harness.storeCtl._touchSettings()
    }

    // Text-node harvesting (mirrors tst_gen_clock).
    function isText(c) {
        return c && typeof c.paintedWidth === "number"
                 && typeof c.text === "string" && typeof c.font !== "undefined"
    }
    function collectTexts(node, out) {
        if (!node || !node.children) return
        for (var i = 0; i < node.children.length; i++) {
            var c = node.children[i]
            if (isText(c)) out.push(c)
            collectTexts(c, out)
        }
    }
    function allTexts(harness) { var out = []; collectTexts(harness.item, out); return out }
    function textEquals(harness, str) {
        var t = allTexts(harness)
        for (var i = 0; i < t.length; i++) if (t[i].text === str) return t[i]
        return null
    }
    // Count VISIBLE text nodes whose text matches /^E\d+$/ (our fake titles).
    function visibleEventRowCount(harness) {
        var t = allTexts(harness), n = 0
        for (var i = 0; i < t.length; i++)
            if (/^E\d+$/.test(t[i].text) && t[i].visible) n++
        return n
    }

    // ── DTSTART / zone parsing ──────────────────────────────────────────────
    TestCase {
        name: "CalendarParseDT"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); clear(h) }

        function test_floating_datetime_is_device_local() {
            var w = h.item
            var got = w.parseDT("20260712T090000", "DTSTART;VALUE=DATE-TIME")
            var exp = new Date(2026, 6, 12, 9, 0, 0)
            compare(got.getTime(), exp.getTime(), "floating DTSTART is device-local")
        }
        function test_utc_datetime_converts_from_zulu() {
            var w = h.item
            var got = w.parseDT("20260712T090000Z", "DTSTART")
            compare(got.getTime(), Date.UTC(2026, 6, 12, 9, 0, 0), "…Z is UTC")
        }
        function test_value_date_is_local_midnight() {
            var w = h.item
            var got = w.parseDT("20260712", "DTSTART;VALUE=DATE")
            var exp = new Date(2026, 6, 12)
            compare(got.getTime(), exp.getTime(), "VALUE=DATE → local midnight")
        }
        // AUDIT (high): DTSTART;TZID=… is ignored — parsed as floating-local. A
        // correct parser must treat the named zone differently from a floating
        // wall time, so on any host NOT in that zone the two instants differ.
        function test_tzid_is_not_treated_as_floating_local() {
            var w = h.item
            var tzid  = w.parseDT("20260712T090000", "DTSTART;TZID=America/New_York")
            var float = w.parseDT("20260712T090000", "DTSTART")
            verify(tzid.getTime() !== float.getTime(),
                   "TZID=America/New_York must not resolve to the same instant as a floating local time")
        }
        function test_malformed_dtstart_is_skipped_no_invalid_date() {
            var w = h.item
            var ics = vcal(
                vevent("SUMMARY:Broken\nDTSTART;VALUE=DATE-TIME:\n") +
                vevent("SUMMARY:Good\nDTSTART;VALUE=DATE-TIME:" + icsDateTime(daysFromNow(1)) + "\n"))
            var evs = w.parseICS(ics)
            for (var i = 0; i < evs.length; i++)
                verify(!isNaN(evs[i].start.getTime()), "no Invalid Date leaks into the sorted list")
            var titles = evs.map(function (e) { return e.title })
            verify(titles.indexOf("Good") >= 0, "the valid event still parses")
        }
    }

    // ── weekdayNums / exKey primitives ──────────────────────────────────────
    TestCase {
        name: "CalendarPrimitives"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000) }

        function test_weekday_nums() {
            var w = h.item
            compare(w.weekdayNums("MO,WE,FR"), [1, 3, 5], "MO,WE,FR")
            compare(w.weekdayNums("SU,SA"), [0, 6], "SU,SA")
            compare(w.weekdayNums("2MO"), [1], "ordinal prefix tolerated")
        }
        function test_daystart_zeroes_time() {
            var w = h.item
            var ds = w.dayStart(new Date(2026, 6, 12, 15, 30, 0))
            compare(ds.getHours(), 0)
            compare(ds.getMinutes(), 0)
        }
    }

    // ── recurrence expansion ────────────────────────────────────────────────
    TestCase {
        name: "CalendarRecurrence"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000) }

        function only(evs, title) { return evs.filter(function (e) { return e.title === title }) }

        function test_single_event_shows() {
            var w = h.item
            var ics = vcal(vevent("SUMMARY:One\nDTSTART;VALUE=DATE-TIME:" + icsDateTime(daysFromNow(2)) + "\n"))
            compare(only(w.parseICS(ics), "One").length, 1, "a lone future event appears once")
        }
        function test_daily_byday_free_expands_multiple() {
            var w = h.item
            var ics = vcal(vevent(
                "SUMMARY:Daily\nDTSTART;VALUE=DATE-TIME:" + icsDateTime(daysFromNow(-1)) + "\n" +
                "RRULE:FREQ=DAILY\n"))
            verify(only(w.parseICS(ics), "Daily").length > 5, "DAILY yields many occurrences across the horizon")
        }
        function test_daily_count_bounds_occurrences() {
            var w = h.item
            var ics = vcal(vevent(
                "SUMMARY:Cnt\nDTSTART;VALUE=DATE-TIME:" + icsDateTime(daysFromNow(0)) + "\n" +
                "RRULE:FREQ=DAILY;COUNT=3\n"))
            var evs = only(w.parseICS(ics), "Cnt")
            verify(evs.length >= 1 && evs.length <= 3, "COUNT=3 caps the series (got " + evs.length + ")")
        }
        function test_daily_until_bounds_occurrences() {
            var w = h.item
            var until = daysFromNow(3)
            var ics = vcal(vevent(
                "SUMMARY:Unt\nDTSTART;VALUE=DATE-TIME:" + icsDateTime(daysFromNow(0)) + "\n" +
                "RRULE:FREQ=DAILY;UNTIL=" + icsDateTime(until) + "\n"))
            var evs = only(w.parseICS(ics), "Unt")
            for (var i = 0; i < evs.length; i++)
                verify(evs[i].start.getTime() <= until.getTime() + 1000, "no occurrence past UNTIL")
        }
        function test_weekly_byday_only_listed_weekdays() {
            var w = h.item
            var ics = vcal(vevent(
                "SUMMARY:Standup\nDTSTART;VALUE=DATE-TIME:" + icsDateTime(daysFromNow(-1)) + "\n" +
                "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR\n"))
            var evs = only(w.parseICS(ics), "Standup")
            verify(evs.length > 1, "multiple weekly occurrences")
            for (var i = 0; i < evs.length; i++) {
                var dow = evs[i].start.getDay()
                verify(dow === 1 || dow === 3 || dow === 5, "only Mon/Wed/Fri")
            }
        }
        function test_weekly_byday_interval_skips_weeks() {
            var w = h.item
            var ics = vcal(vevent(
                "SUMMARY:Fort\nDTSTART;VALUE=DATE-TIME:" + icsDateTime(daysFromNow(-1)) + "\n" +
                "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;INTERVAL=2\n"))
            var evs = only(w.parseICS(ics), "Fort")
            // Collect the distinct (Sunday-anchored) week indices the occurrences fall in.
            var weeks = {}
            for (var i = 0; i < evs.length; i++) {
                var d = w.dayStart(evs[i].start); d.setDate(d.getDate() - d.getDay())
                weeks[Math.round(d.getTime() / (7 * 86400000))] = true
            }
            var idx = Object.keys(weeks).map(Number).sort(function (a, b) { return a - b })
            for (var j = 1; j < idx.length; j++)
                verify(idx[j] - idx[j - 1] >= 2, "INTERVAL=2 leaves a gap between active weeks (got "
                       + idx.join(",") + ")")
        }

        // AUDIT (high): MONTHLY recurrence started in the past is dropped entirely.
        function test_monthly_started_last_month_shows_this_period() {
            var w = h.item
            var target = daysFromNow(3)
            var ds = new Date(target); ds.setMonth(ds.getMonth() - 1)
            var ics = vcal(vevent(
                "SUMMARY:Monthly\nDTSTART;VALUE=DATE-TIME:" + icsDateTime(ds) + "\n" +
                "RRULE:FREQ=MONTHLY\n"))
            verify(only(w.parseICS(ics), "Monthly").length >= 1,
                   "a MONTHLY event started last month should show its upcoming occurrence")
        }
        // AUDIT (high): YEARLY recurrence (birthday) whose DTSTART is years ago is
        // dropped entirely rather than rolling to the next anniversary.
        function test_yearly_birthday_shows_next_anniversary() {
            var w = h.item
            var md = daysFromNow(5)          // this year's anniversary, 5 days out
            var old = new Date(md); old.setFullYear(2015)
            var ics = vcal(vevent(
                "SUMMARY:Birthday\nDTSTART;VALUE=DATE:" + icsDay(old) + "\n" +
                "RRULE:FREQ=YEARLY\n"))
            verify(only(w.parseICS(ics), "Birthday").length >= 1,
                   "a YEARLY birthday should appear on its next anniversary within the horizon")
        }
    }

    // ── expand(): horizon, duration, past-pruning, EXDATE (controlled clock) ──
    TestCase {
        name: "CalendarExpandBounds"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000) }

        function horizonFrom(now) { return new Date(now.getTime() + 30 * 86400000) }

        function test_in_progress_multiday_event_still_shows() {
            var w = h.item
            var now = new Date(); now.setHours(15, 0, 0, 0)
            var start = new Date(now); start.setDate(start.getDate() - 1); start.setHours(20, 0, 0, 0)
            var end = new Date(now); end.setDate(end.getDate() + 1); end.setHours(20, 0, 0, 0)
            var ev = { title: "Trip", start: start, end: end, allDay: false }
            compare(w.expand(ev, horizonFrom(now), now).length, 1,
                    "a multi-day event straddling now is still shown")
        }
        // AUDIT (medium): an event that already ENDED earlier today keeps showing
        // because the guard compares against start-of-day, not now.
        function test_event_ended_earlier_today_is_pruned() {
            var w = h.item
            var now = new Date(); now.setHours(15, 0, 0, 0)
            var start = new Date(now); start.setHours(10, 0, 0, 0)
            var end = new Date(now); end.setHours(11, 0, 0, 0)
            var ev = { title: "Done", start: start, end: end, allDay: false }
            compare(w.expand(ev, horizonFrom(now), now).length, 0,
                    "an event that ended earlier today should be pruned")
        }
        // AUDIT: all-day DTEND is exclusive; an all-day event whose end is today
        // occupied only yesterday and must not be shown today.
        function test_allday_exclusive_end_not_shown_extra_day() {
            var w = h.item
            var now = new Date(); now.setHours(15, 0, 0, 0)
            var start = midnight(now); start.setDate(start.getDate() - 1)
            var end = midnight(now)              // exclusive → yesterday only
            var ev = { title: "Yday", start: start, end: end, allDay: true }
            compare(w.expand(ev, horizonFrom(now), now).length, 0,
                    "an all-day event ending (exclusive) today should not appear today")
        }
        function test_event_beyond_horizon_excluded() {
            var w = h.item
            var now = new Date(); now.setHours(9, 0, 0, 0)
            var start = new Date(now.getTime() + 40 * 86400000)   // past the 30-day horizon
            var ev = { title: "Far", start: start, end: new Date(start.getTime() + 3600000), allDay: false }
            compare(w.expand(ev, horizonFrom(now), now).length, 0, "beyond horizon → not shown")
        }
        function test_exdate_excludes_matching_occurrence() {
            var w = h.item
            var now = new Date(); now.setHours(0, 0, 0, 0)
            var start = new Date(now); start.setHours(9, 0, 0, 0)
            var skip = new Date(start.getTime() + 86400000)       // tomorrow's occurrence
            var ev = { title: "Ex", start: start, end: new Date(start.getTime() + 3600000),
                       allDay: false, rrule: "FREQ=DAILY;COUNT=4", exdates: [skip] }
            var occ = w.expand(ev, horizonFrom(now), now)
            for (var i = 0; i < occ.length; i++)
                verify(w.exKey(occ[i].start) !== w.exKey(skip), "the EXDATE instance is excluded")
        }
        function test_allday_exdate_excludes_by_date() {
            var w = h.item
            var now = midnight(new Date())
            var start = new Date(now)                             // all-day, midnight
            var skip = new Date(now.getTime() + 86400000)
            var ev = { title: "AX", start: start, end: new Date(start.getTime() + 86400000),
                       allDay: true, rrule: "FREQ=DAILY;COUNT=4", exdates: [skip] }
            var occ = w.expand(ev, horizonFrom(now), now)
            var skipKey = skip.getFullYear() + "-" + skip.getMonth() + "-" + skip.getDate()
            for (var i = 0; i < occ.length; i++) {
                var k = occ[i].start.getFullYear() + "-" + occ[i].start.getMonth() + "-" + occ[i].start.getDate()
                verify(k !== skipKey, "the excluded all-day date does not appear")
            }
        }
        // DAILY stepping must keep a constant local wall-clock time. Within a
        // non-DST horizon this holds; across a DST transition (host-dependent)
        // the fixed-ms stepping drifts (audit medium).
        function test_daily_stepping_keeps_local_hour() {
            var w = h.item
            var now = new Date(); now.setHours(9, 0, 0, 0)
            var ev = { title: "Nine", start: new Date(now),
                       end: new Date(now.getTime() + 3600000), allDay: false, rrule: "FREQ=DAILY" }
            var occ = w.expand(ev, horizonFrom(now), now)
            verify(occ.length >= 20, "a month of daily occurrences")
            for (var i = 0; i < occ.length; i++)
                compare(occ[i].start.getHours(), 9, "occurrence " + i + " keeps 09:00 local")
        }
        // AUDIT (medium): a decades-old unbounded DAILY series must not iterate
        // without a guard. It should still complete quickly and yield today's run.
        function test_ancient_daily_completes_and_yields_current_run() {
            var w = h.item
            var ics = vcal(vevent(
                "SUMMARY:Ancient\nDTSTART;VALUE=DATE-TIME:20000101T090000\nRRULE:FREQ=DAILY\n"))
            var t0 = Date.now()
            var evs = w.parseICS(ics).filter(function (e) { return e.title === "Ancient" })
            var dt = Date.now() - t0
            verify(evs.length > 0, "still yields upcoming occurrences")
            verify(dt < 4000, "parse of a 26-year DAILY series completed in " + dt + "ms")
        }
    }

    // ── all-day vs timed classification (parseICS) ──────────────────────────
    TestCase {
        name: "CalendarAllDay"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000) }

        function test_value_date_is_all_day_datetime_is_not() {
            var w = h.item
            var when = daysFromNow(1)
            var ics = vcal(
                vevent("SUMMARY:Timed\nDTSTART;VALUE=DATE-TIME:" + icsDateTime(when) + "\n") +
                vevent("SUMMARY:Allday\nDTSTART;VALUE=DATE:" + icsDay(when) + "\n"))
            var evs = w.parseICS(ics)
            var timed = null, all = null
            for (var i = 0; i < evs.length; i++) {
                if (evs[i].title === "Timed") timed = evs[i]
                if (evs[i].title === "Allday") all = evs[i]
            }
            verify(timed && all, "both parsed")
            compare(timed.allDay, false, "DATE-TIME is not all-day")
            compare(all.allDay, true, "DATE is all-day")
        }
    }

    // ── fmtWhen labelling ───────────────────────────────────────────────────
    TestCase {
        name: "CalendarFmtWhen"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000) }

        function test_today_tomorrow_and_dated() {
            var w = h.item
            var now = new Date()
            var todayEv = { start: new Date(now.getTime() + 3600000), allDay: false }
            verify(w.fmtWhen(todayEv).indexOf("Today") === 0, "same-day → 'Today …'")
            var tomEv = { start: new Date(now.getTime() + 26 * 3600000), allDay: false }
            verify(w.fmtWhen(tomEv).indexOf("Tomorrow") === 0, "next-day → 'Tomorrow …'")
            var farEv = { start: new Date(now.getTime() + 6 * 86400000), allDay: false }
            var lbl = w.fmtWhen(farEv)
            verify(lbl.indexOf("Today") !== 0 && lbl.indexOf("Tomorrow") !== 0, "far event → dated label")
        }
        function test_allday_omits_time() {
            var w = h.item
            var ev = { start: new Date(), allDay: true }
            verify(w.fmtWhen(ev).indexOf(":") < 0, "all-day label carries no HH:mm")
        }
    }

    // ── config: url + maxEvents honouring & reactivity ──────────────────────
    TestCase {
        name: "CalendarConfig"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); clear(h) }
        function set(k, v) { h.storeCtl.setSetting("test-instance", k, v) }

        function test_default_max_events_is_five() {
            compare(h.item.maxEvents, 5, "maxEvents defaults to 5")
        }
        function test_url_reacts_to_store_edit() {
            var w = h.item
            compare(w.url, "", "starts empty")
            set("url", "https://example.com/a.ics")
            compare(w.url, "https://example.com/a.ics", "cfg/url reacts to a store edit (revision bump)")
        }
        function test_shown_events_honours_max_events() {
            var w = h.item
            w.events = fakeEvents(8)
            set("maxEvents", 3)
            compare(w.shownEvents.length, 3, "shownEvents capped to maxEvents=3")
            set("maxEvents", 6)
            compare(w.shownEvents.length, 6, "raising maxEvents reveals more")
            set("maxEvents", 12)
            compare(w.shownEvents.length, 8, "…but never more than the available events")
        }
    }

    // ── compact tile: maxEvents on the collapsed face (audit low) ────────────
    TestCase {
        name: "CalendarCompactCap"
        when: windowShown
        function init() { tryVerify(function () { return hTile.ready }, 3000); clear(hTile) }

        // AUDIT: the compact face hard-caps at 3 and ignores maxEvents.
        function test_compact_face_honours_max_events() {
            var w = hTile.item
            // A non-empty url makes the event rows (not the empty prompt) visible;
            // the unreachable host fails fast without clobbering w.events.
            hTile.storeCtl.patchSettings("test-instance", { url: "http://127.0.0.1:1/x.ics", maxEvents: 6 })
            w.events = fakeEvents(8)
            compare(w.shownEvents.length, 6, "shownEvents honours maxEvents=6")
            wait(50)
            compare(visibleEventRowCount(hTile), 6,
                    "the compact tile should render maxEvents rows, not a hardcoded 3")
        }
    }

    // ── effAccent + host-injected chrome props ──────────────────────────────
    TestCase {
        name: "CalendarChrome"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clear(h)
            h.item.accentName = ""; h.item.titleOverride = ""; h.item.cardBackdrop = "none"
        }

        function test_default_accent_is_services_category() {
            compare(String(h.item.effAccent), String(h.theme.catServices), "defaults to the Services accent")
        }
        function test_accent_preset_recolours_and_paints_bars() {
            var w = h.item
            w.events = fakeEvents(3)
            w.accentName = "purple"
            compare(String(w.effAccent), String(Qt.color(h.theme.accentPresets["purple"].a)),
                    "effAccent tracks the configured accent preset")
        }
        function test_title_override_reflected_in_header() {
            var w = h.item
            w.titleOverride = "My Agenda"
            var node = textEquals(h, "My Agenda")
            verify(node !== null && node.visible, "WidgetChrome header shows the injected titleOverride")
        }
        function test_card_backdrop_prop_injected() {
            var w = h.item
            w.cardBackdrop = "aurora"
            compare(w.cardBackdrop, "aurora", "injected cardBackdrop is honoured by the chrome")
        }
    }

    // ── fetch state machine (no live server) ────────────────────────────────
    TestCase {
        name: "CalendarFetch"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); clear(h) }
        function set(k, v) { h.storeCtl.setSetting("test-instance", k, v) }

        function test_empty_url_makes_no_request() {
            var w = h.item
            w.refresh()
            compare(w.loading, false, "empty url → not loading")
            compare(w.errorText, "", "empty url → no error")
            compare(w.events.length, 0, "empty url → no events")
        }
        function test_unreachable_url_sets_error_without_corrupting_events() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { url: "http://127.0.0.1:1/nope.ics" })
            w.refresh()   // drive directly; avoid the 300ms debounce race
            tryVerify(function () { return !w.loading && w.errorText.length > 0 }, 14000,
                      "an unreachable URL settles with an error")
            verify(Array.isArray(w.events), "events remains a valid (uncorrupted) array")
        }
        // AUDIT (medium): webcal:// links (iCloud/Apple) are handed straight to
        // XMLHttpRequest with no https rewrite; a correct impl rewrites the scheme
        // rather than rejecting the URL as invalid.
        function test_webcal_url_is_not_rejected_as_invalid() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { url: "webcal://127.0.0.1:1/shared.ics" })
            w.refresh()
            tryVerify(function () { return !w.loading }, 14000, "fetch settles")
            verify(w.errorText !== "Invalid URL",
                   "webcal:// should be rewritten to https, not rejected as an invalid URL (got '"
                   + w.errorText + "')")
        }
    }

    // ── schema ↔ widget key sync (shared config-schema area) ────────────────
    TestCase {
        name: "CalendarSchema"
        when: windowShown

        function keysOf(s) {
            var keys = {}
            for (var i = 0; i < s.sections.length; i++)
                for (var j = 0; j < (s.sections[i].fields || []).length; j++)
                    if (s.sections[i].fields[j].key) keys[s.sections[i].fields[j].key] = true
            return keys
        }
        function fieldOf(s, key) {
            for (var i = 0; i < s.sections.length; i++)
                for (var j = 0; j < (s.sections[i].fields || []).length; j++)
                    if (s.sections[i].fields[j].key === key) return s.sections[i].fields[j]
            return null
        }

        function test_calendar_schema_exposes_url_and_max_events() {
            var s = sc.schemaFor("calendar")
            verify(s && s.sections && s.sections.length > 0, "calendar has a schema")
            var keys = keysOf(s)
            verify(keys["url"] === true, "schema exposes 'url'")
            verify(keys["maxEvents"] === true, "schema exposes 'maxEvents'")
        }
        function test_max_events_field_bounds_match_widget() {
            var f = fieldOf(sc.schemaFor("calendar"), "maxEvents")
            verify(f !== null, "maxEvents field present")
            compare(f.min, 1, "min 1")
            compare(f.max, 12, "max 12")
            compare(f.dflt, 5, "default 5 matches the widget's fallback")
        }
    }
}
