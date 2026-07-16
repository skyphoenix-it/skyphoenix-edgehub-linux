import QtQuick
import QtTest
import "fixtures.js" as Fx
import "../../ui/qml/widgets" as W

// ─────────────────────────────────────────────────────────────────────────
// tst_nownext — ui/qml/widgets/NowNextWidget.qml.
//
// The widget derives now/next from a nested CalendarWidget's ICS model rather
// than parsing ICS a second time. Two consequences this file has to prove:
//   1. The derivation is right — including the all-day case, where CalendarWidget
//      leaves end == start and a naive start<=now<end would report that an all-day
//      event is never happening.
//   2. Embedding a Calendar did not smuggle a fetch around the egress gate. The
//      nested instance must obey the SAME NetHub kill switch and allowlist, or the
//      "no telemetry / local-only" claim has a hole in it that no lint would see
//      (check_no_raw_xhr.sh only proves this file builds no XHR itself — it cannot
//      prove the one it delegates to is gated).
//
// Events are injected straight into the nested model where the ICS layer is not
// what is under test, and driven through a FakeXHR where it is.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 1000; height: 760

    WidgetHarness {
        id: h; x: 0; y: 0; width: 620; height: parent.height
        widgetFile: "NowNextWidget.qml"; expanded: true
    }
    W.NetHub { id: gate }

    function clearSettings(harness) {
        var s = harness.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        harness.storeCtl._touchSettings()
    }
    // The nested agenda model, reached the way a caller never should — this is the
    // one place that is allowed to know it exists.
    function agenda() {
        var kids = root.findAll(h.item, function (n) { return n.hasOwnProperty("parseICS") }, [])
        return kids.length ? kids[0] : null
    }
    function findAll(node, pred, acc) {
        acc = acc || []
        if (!node) return acc
        if (pred(node)) acc.push(node)
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) findAll(kids[i], pred, acc)
        return acc
    }
    // A Timer is not a visual child — it is a resource. `data` is the union of
    // children and resources, so this is the only walk that can see one.
    function findAllData(node, pred, acc) {
        acc = acc || []
        if (!node) return acc
        if (pred(node)) acc.push(node)
        var kids = node.data
        for (var i = 0; kids && i < kids.length; i++) findAllData(kids[i], pred, acc)
        return acc
    }
    function ev(title, startDelta, durMin, allDay) {
        var s = new Date(Date.now() + startDelta * 60000)
        return { title: title, location: "", allDay: !!allDay,
                 start: s, end: new Date(s.getTime() + durMin * 60000) }
    }
    function setEvents(list) { var a = root.agenda(); a.events = list }

    // ── now / next derivation ────────────────────────────────────────────
    TestCase {
        name: "NowNextDerivation"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clearSettings(h); h.active = false
            // The url change below arms CalendarWidget's 300 ms refresh debounce.
            // Hand it a fake that never resolves, so a stray fire can neither reach
            // the network nor overwrite the events this test injects.
            h.item.xhrFactory = function () { return Fx.makeFakeXHR() }
            h.storeCtl.patchSettings("test-instance", { url: "https://example.com/cal.ics" })
            verify(root.agenda() !== null, "the nested agenda model exists")
            root.setEvents([])
        }

        function test_an_event_in_progress_is_now() {
            root.setEvents([ root.ev("Standup", -10, 30) ])       // started 10 min ago, 30 min long
            verify(h.item.nowEvent !== null, "an in-progress event is 'now'")
            compare(h.item.nowEvent.title, "Standup")
            compare(h.item.nextEvent, null, "and there is nothing after it")
        }

        function test_the_soonest_future_event_is_next() {
            root.setEvents([ root.ev("Soon", 30, 60), root.ev("Later", 300, 60) ])
            compare(h.item.nowEvent, null, "nothing is happening yet")
            compare(h.item.nextEvent.title, "Soon", "the soonest upcoming event is next")
        }

        function test_now_and_next_are_reported_together() {
            root.setEvents([ root.ev("Standup", -5, 25), root.ev("Review", 60, 30) ])
            compare(h.item.nowEvent.title, "Standup")
            compare(h.item.nextEvent.title, "Review", "next is the one after the current one")
        }

        // The boundary that matters: an event that has just ended is not 'now'.
        function test_a_finished_event_is_neither_now_nor_next() {
            root.setEvents([ root.ev("Done", -120, 30) ])
            compare(h.item.nowEvent, null, "an ended event is not 'now'")
            compare(h.item.nextEvent, null, "and it is certainly not 'next'")
        }

        // CalendarWidget leaves dur = 0 for an all-day event with no DTEND, so
        // end == start (midnight). Without endOf()'s day-long floor, an all-day
        // event today would never be 'now'.
        function test_an_allday_event_today_is_now() {
            var midnight = new Date(); midnight.setHours(0, 0, 0, 0)
            root.setEvents([ { title: "Conference", location: "", allDay: true,
                               start: midnight, end: midnight } ])
            verify(h.item.nowEvent !== null, "a zero-length all-day event today still counts as now")
            compare(h.item.nowEvent.title, "Conference")
            compare(h.item.untilText(h.item.nowEvent), "all day")
        }

        function test_endOf_gives_an_allday_event_its_whole_day() {
            var midnight = new Date(); midnight.setHours(0, 0, 0, 0)
            var e = { title: "X", allDay: true, start: midnight, end: midnight }
            compare(h.item.endOf(e), midnight.getTime() + 86400000, "all-day spans 24 h")
            var timed = root.ev("Y", 0, 30)
            compare(h.item.endOf(timed), timed.end.getTime(), "a timed event keeps its real end")
        }

        function test_no_events_means_no_now_and_no_next() {
            root.setEvents([])
            compare(h.item.nowEvent, null)
            compare(h.item.nextEvent, null)
        }
    }

    // ── copy ─────────────────────────────────────────────────────────────
    TestCase {
        name: "NowNextCopy"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clearSettings(h); h.active = false
            // The url change below arms CalendarWidget's 300 ms refresh debounce.
            // Hand it a fake that never resolves, so a stray fire can neither reach
            // the network nor overwrite the events this test injects.
            h.item.xhrFactory = function () { return Fx.makeFakeXHR() }
            h.storeCtl.patchSettings("test-instance", { url: "https://example.com/cal.ics" })
            root.setEvents([])
        }

        function test_humanDelta_reads_naturally() {
            var w = h.item
            compare(w.humanDelta(0), "now")
            compare(w.humanDelta(-5), "now", "a past start never reads as negative time")
            compare(w.humanDelta(1), "in 1 min")
            compare(w.humanDelta(45), "in 45 min")
            compare(w.humanDelta(60), "in 1 h")
            compare(w.humanDelta(90), "in 1 h 30 min")
            compare(w.humanDelta(1440), "in 1 day")
            compare(w.humanDelta(2880), "in 2 days")
        }

        // Rounding UP: for the 59 s before a meeting, "in 0 min" would be wrong.
        function test_minutesUntil_rounds_up() {
            var w = h.item
            compare(w.minutesUntil(new Date(Date.now() + 30000)), 1, "30 s away is 'in 1 min'")
            compare(w.minutesUntil(new Date(Date.now() + 61000)), 2)
        }

        function test_whenText_shows_the_clock_time_and_the_delta() {
            var e = root.ev("Review", 45, 30)
            var t = h.item.whenText(e)
            compare(t.indexOf(Qt.formatTime(e.start, "HH:mm")) >= 0, true, "shows the start time")
            compare(t.indexOf("in 45 min") >= 0, true, "and how long until it")
        }
    }

    // ── settings ─────────────────────────────────────────────────────────
    TestCase {
        name: "NowNextSettings"
        when: windowShown
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clearSettings(h); h.active = false
            // The url change below arms CalendarWidget's 300 ms refresh debounce.
            // Hand it a fake that never resolves, so a stray fire can neither reach
            // the network nor overwrite the events this test injects.
            h.item.xhrFactory = function () { return Fx.makeFakeXHR() }
        }

        // One tile, one source of truth: the nested model must read the SAME url
        // setting, not a second copy of it.
        function test_the_url_setting_reaches_the_nested_agenda() {
            h.storeCtl.patchSettings("test-instance", { url: "https://example.com/cal.ics" })
            compare(h.item.url, "https://example.com/cal.ics")
            compare(root.agenda().url, "https://example.com/cal.ics",
                    "the agenda model reads the same setting, not its own")
        }

        function test_no_url_asks_for_one_rather_than_inventing_events() {
            // Seed a real agenda first, so this proves the empty url CLEARS it
            // rather than merely observing a model that was already empty.
            h.storeCtl.patchSettings("test-instance", { url: "https://example.com/cal.ics" })
            root.setEvents([ root.ev("Standup", -5, 30) ])
            verify(h.item.nowEvent !== null, "there is something to lose")
            h.storeCtl.patchSettings("test-instance", { url: "" })
            h.item.refresh()
            compare(h.item.url, "")
            compare(h.item.events.length, 0, "no url → the agenda is emptied…")
            compare(h.item.nowEvent, null, "…so nothing is invented")
            compare(h.item.nextEvent, null)
        }
    }

    // ── the egress gate ──────────────────────────────────────────────────
    // Embedding CalendarWidget must not create a fetch that escapes the gate.
    TestCase {
        name: "NowNextGate"
        when: windowShown
        property var lastFake: null
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clearSettings(h); h.active = false; lastFake = null
            h.storeCtl.patchSettings("test-instance", { url: "https://example.com/cal.ics" })
            gate.offline = false; gate.allowHosts = []
            gate.requests = 0; gate.blocked = 0
            h.item.netHub = gate
            var tc = this
            h.item.xhrFactory = function () { tc.lastFake = Fx.makeFakeXHR(); return tc.lastFake }
        }
        function cleanup() { gate.offline = false; gate.allowHosts = [] }

        function test_offline_refuses_the_agenda_fetch() {
            gate.offline = true
            h.item.refresh()
            compare(lastFake, null, "the kill switch refuses before any socket is opened")
            compare(gate.requests, 0, "nothing counted as sent")
            compare(gate.blocked, 1, "the refusal is counted (attestation)")
            compare(h.item.errorText, "Calendar is offline", "and the tile says why")
        }

        function test_an_unlisted_host_is_blocked() {
            gate.allowHosts = ["intranet.example.com"]
            h.item.refresh()
            compare(lastFake, null, "an unlisted host never gets a socket")
            compare(gate.blocked, 1, "counted as blocked")
            compare(h.item.errorText, "Calendar host not allowed")
        }

        // The end-to-end path: a real ICS body through the gate becomes now/next.
        function test_an_allowed_fetch_parses_into_now_and_next() {
            gate.allowHosts = ["example.com"]
            h.item.refresh()
            verify(lastFake !== null && lastFake.sent, "listing the host lets the fetch through")
            compare(gate.requests, 1, "counted as sent")
            lastFake.resolveWith(200, Fx.icsValid())
            verify(h.item.events.length > 0, "the ICS parsed via the nested model")
            verify(h.item.nowEvent !== null || h.item.nextEvent !== null,
                   "and it resolved into something to show")
        }

        function test_the_poll_is_gated_on_active() {
            var a = root.agenda()
            h.active = false
            var timers = root.findAllData(a, function (n) {
                return n.hasOwnProperty("interval") && n.interval === 900000
            }, [])
            verify(timers.length === 1, "the agenda has its 15-minute poll")
            compare(timers[0].running, false, "an inactive tile does not poll")
            h.active = true
            compare(timers[0].running, true, "an active tile with a URL does")
            h.active = false
        }
    }
}
