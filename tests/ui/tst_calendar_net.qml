import QtQuick
import QtTest
import "fixtures.js" as Fx

// ─────────────────────────────────────────────────────────────────────────
// tst_calendar_net — network path of ui/qml/widgets/CalendarWidget.qml, driven
// offline through the `xhrFactory` seam. A FakeXHR (fixtures.js) captures the
// request URL and resolves ONLY on an explicit test call — no wall-clock waits,
// no real sockets.
//
// Covers: request URL (pass-through + webcal:// → https:// rewrite), empty-URL
// short-circuit, and every fixture → widget state mapping:
//   valid ICS → events parsed, non-200 → fetch error, empty calendar → "No
//   upcoming events", un-readable body → read error, timeout → timed out.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 640; height: 720

    WidgetHarness {
        id: h; anchors.fill: parent
        widgetFile: "CalendarWidget.qml"; expanded: true
    }

    function clearSettings(harness) {
        var s = harness.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        harness.storeCtl._touchSettings()
    }

    // ── request URL construction / short-circuit ─────────────────────────
    TestCase {
        name: "CalendarNetUrl"
        when: windowShown
        property var lastFake: null
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clearSettings(h); h.active = false; lastFake = null
            var tc = this
            h.item.xhrFactory = function () { tc.lastFake = Fx.makeFakeXHR(); return tc.lastFake }
        }

        function test_empty_url_makes_no_request() {
            var w = h.item
            w.refresh()
            compare(lastFake, null, "an empty URL never constructs an XHR")
            compare(w.loading, false, "empty URL → not loading")
            compare(w.errorText, "", "empty URL → no error")
            compare(w.events.length, 0, "empty URL → no events")
        }

        function test_https_url_passed_through() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { url: "https://example.com/cal.ics" })
            w.refresh()
            verify(lastFake !== null, "factory used instead of a real XHR")
            compare(lastFake.method, "GET", "ICS fetch is a GET")
            verify(lastFake.sent, "send() was called")
            compare(lastFake.url, "https://example.com/cal.ics", "https URL used verbatim")
        }

        // webcal:// (iCloud/Apple) is ICS over HTTP(S); the widget rewrites the
        // scheme rather than handing XMLHttpRequest a scheme it rejects.
        function test_webcal_scheme_rewritten_to_https() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { url: "webcal://example.com/shared.ics" })
            w.refresh()
            verify(lastFake !== null, "webcal is not rejected before a request is built")
            compare(lastFake.url, "https://example.com/shared.ics", "webcal:// → https://")
            verify(w.errorText !== "Invalid URL", "webcal is not treated as invalid")
        }
    }

    // ── response → widget state ──────────────────────────────────────────
    TestCase {
        name: "CalendarNetStates"
        when: windowShown
        property var lastFake: null
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clearSettings(h); h.active = false; lastFake = null
            h.item.events = []; h.item.errorText = ""; h.item.loading = false
            h.storeCtl.patchSettings("test-instance", { url: "https://example.com/cal.ics" })
            var tc = this
            h.item.xhrFactory = function () { tc.lastFake = Fx.makeFakeXHR(); return tc.lastFake }
        }
        function drive(status, body) { h.item.refresh(); lastFake.resolveWith(status, body) }

        function test_valid_ics_parses_events() {
            var w = h.item
            drive(200, Fx.icsValid())
            compare(w.loading, false, "settled")
            compare(w.errorText, "", "a valid feed clears any error")
            compare(w.events.length, 3, "three upcoming VEVENTs parsed")
            verify(w.events[0].start.getTime() <= w.events[1].start.getTime(), "events are sorted ascending")
            var titles = w.events.map(function (e) { return e.title })
            verify(titles.indexOf("Standup") >= 0 && titles.indexOf("Review") >= 0
                   && titles.indexOf("Planning") >= 0, "all three summaries present")
        }

        function test_non_200_sets_fetch_error() {
            var w = h.item
            drive(404, "")
            compare(w.loading, false, "settled")
            compare(w.errorText, "Couldn't fetch calendar", "a 404 reports a fetch error")
            verify(Array.isArray(w.events), "events remains a valid array (uncorrupted)")
        }

        function test_empty_calendar_is_no_upcoming_events() {
            var w = h.item
            drive(200, Fx.ICS_EMPTY)
            compare(w.events.length, 0, "a calendar with no VEVENT yields nothing")
            compare(w.errorText, "No upcoming events", "empty feed → No upcoming events")
        }

        // 200 OK but an unreadable body (parse throws) → read-error branch.
        function test_unreadable_body_is_read_error() {
            var w = h.item
            drive(200, null)   // parseICS(null) throws → caught
            compare(w.errorText, "Couldn't read calendar", "an un-parseable body reports a read error")
        }

        function test_timeout_sets_timed_out() {
            var w = h.item
            w.refresh()
            compare(w.loading, true, "in flight")
            lastFake.fireTimeout()
            compare(w.loading, false, "timeout settles the request")
            compare(w.errorText, "Calendar timed out", "an unresolved socket times out")
        }

        // A superseded fetch's late callback must not overwrite the newer result.
        function test_stale_fetch_ignored_after_supersede() {
            var w = h.item
            w.refresh()
            var stale = lastFake
            w.refresh()
            verify(stale.aborted, "the older in-flight fetch is aborted")
            var fresh = lastFake
            fresh.resolveWith(200, Fx.icsValid())
            compare(w.events.length, 3, "the fresh fetch lands")
            stale.resolveWith(404, "")   // late callback from the aborted fetch
            compare(w.errorText, "", "the stale callback is ignored (no error set)")
            compare(w.events.length, 3, "events untouched by the stale callback")
        }
    }
}
