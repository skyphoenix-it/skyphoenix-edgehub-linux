import QtQuick
import QtTest
import "fixtures.js" as Fx

// ─────────────────────────────────────────────────────────────────────────
// tst_weather_net — network path of ui/qml/widgets/WeatherWidget.qml, driven
// entirely offline through the `xhrFactory` seam. A FakeXHR (fixtures.js)
// captures the request URL and resolves ONLY on an explicit test call
// (resolveWith / fireTimeout) — no wall-clock waits, no real sockets.
//
// Covers: forecast URL construction (lat/lon/units/forecast_days), geocode URL
// (encodeURIComponent of the city), and every fixture → widget state mapping:
//   valid forecast → loaded/rendered, non-200 → Offline, missing daily → No
//   data, malformed → Parse error, timeout → Timed out; geocode valid →
//   settings patched, empty → City not found.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 760; height: 620

    WidgetHarness {
        id: h; anchors.fill: parent
        widgetFile: "WeatherWidget.qml"; expanded: true
    }

    function clearSettings(harness) {
        var s = harness.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        harness.storeCtl._touchSettings()
    }

    // ── forecast URL construction ────────────────────────────────────────
    TestCase {
        name: "WeatherNetForecastUrl"
        when: windowShown
        property var lastFake: null
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clearSettings(h); h.active = false
            var tc = this
            h.item.xhrFactory = function () { tc.lastFake = Fx.makeFakeXHR(); return tc.lastFake }
        }

        function test_default_forecast_url_carries_all_inputs() {
            var w = h.item
            w.refresh()
            verify(lastFake !== null, "factory was used instead of a real XHR")
            compare(lastFake.method, "GET", "forecast is a GET")
            verify(lastFake.sent, "send() was called")
            var u = lastFake.url
            verify(u.indexOf("https://api.open-meteo.com/v1/forecast") === 0, "hits the Open-Meteo forecast API")
            verify(u.indexOf("latitude=52.52") >= 0, "default Berlin latitude in the query (" + u + ")")
            verify(u.indexOf("longitude=13.405") >= 0, "default Berlin longitude in the query")
            // forecastDays defaults to 4 → the request asks for forecast_days=5.
            verify(u.indexOf("forecast_days=5") >= 0, "forecast_days = forecastDays+1")
            verify(u.indexOf("temperature_unit=fahrenheit") < 0, "celsius default omits the unit override")
        }

        function test_config_flows_into_forecast_url() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance",
                { lat: 35.68, lon: 139.69, units: "fahrenheit", forecastDays: 7 })
            w.refresh()
            var u = lastFake.url
            verify(u.indexOf("latitude=35.68") >= 0, "configured latitude used")
            verify(u.indexOf("longitude=139.69") >= 0, "configured longitude used")
            verify(u.indexOf("temperature_unit=fahrenheit") >= 0, "fahrenheit adds the unit override")
            verify(u.indexOf("forecast_days=8") >= 0, "7 forecast days → forecast_days=8")
        }
    }

    // ── forecast response → widget state ─────────────────────────────────
    TestCase {
        name: "WeatherNetForecastStates"
        when: windowShown
        property var lastFake: null
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clearSettings(h); h.active = false
            h.item.loaded = false; h.item.errorText = ""   // reset render state between cases
            var tc = this
            h.item.xhrFactory = function () { tc.lastFake = Fx.makeFakeXHR(); return tc.lastFake }
        }
        function drive(status, body) { h.item.refresh(); lastFake.resolveWith(status, body) }

        function test_valid_forecast_renders() {
            var w = h.item
            drive(200, Fx.FORECAST_VALID)
            compare(w.loaded, true, "valid payload marks the tile loaded")
            compare(w.errorText, "", "no error on success")
            fuzzyCompare(w.curTemp, 21.4, 0.001, "current temperature parsed")
            fuzzyCompare(w.feels, 19.8, 0.001, "apparent temperature parsed")
            compare(w.curCode, 3, "current weather code parsed")
            compare(w.days.length, 5, "five daily rows parsed")
            compare(w.days[0].day, "Today", "first row labelled Today")
            compare(w.days[1].max, 23, "day-2 max rounded from 22.6")
        }

        function test_non_200_goes_offline() {
            var w = h.item
            drive(503, "")
            compare(w.loaded, false, "a server error clears loaded (no stale reading shown as live)")
            compare(w.errorText, "Offline", "non-200 → Offline")
        }

        function test_missing_daily_is_no_data() {
            var w = h.item
            drive(200, Fx.FORECAST_MISSING_DAILY)
            compare(w.loaded, false, "missing daily.time is not a valid render")
            compare(w.errorText, "No data", "missing fields → No data")
        }

        function test_malformed_body_is_parse_error() {
            var w = h.item
            drive(200, Fx.MALFORMED_JSON)
            compare(w.loaded, false, "un-parseable body is not loaded")
            compare(w.errorText, "Parse error", "malformed JSON → Parse error")
        }

        function test_timeout_sets_timed_out() {
            var w = h.item
            w.refresh()
            compare(w.loaded, false, "no data yet")
            lastFake.fireTimeout()
            compare(w.errorText, "Timed out", "an unresolved socket times out")
        }

        // A superseded (aborted) request must not clobber the newer one's result.
        function test_stale_request_is_ignored_after_supersede() {
            var w = h.item
            w.refresh()
            var stale = lastFake
            w.refresh()               // supersedes: aborts `stale`, installs a new fake
            verify(stale.aborted, "the older in-flight request is aborted")
            var fresh = lastFake
            fresh.resolveWith(200, Fx.FORECAST_VALID)
            compare(w.loaded, true, "the fresh request lands")
            stale.resolveWith(200, Fx.FORECAST_MISSING_DAILY)  // late callback from the aborted one
            compare(w.loaded, true, "the stale late callback is ignored (loaded stays true)")
            compare(w.errorText, "", "stale callback did not overwrite the good result")
        }
    }

    // ── geocode path ─────────────────────────────────────────────────────
    TestCase {
        name: "WeatherNetGeocode"
        when: windowShown
        property var lastFake: null
        function init() {
            tryVerify(function () { return h.ready }, 3000)
            clearSettings(h); h.active = false
            var tc = this
            h.item.xhrFactory = function () { tc.lastFake = Fx.makeFakeXHR(); return tc.lastFake }
        }

        function test_geocode_url_encodes_city() {
            var w = h.item
            w.geocode("New York")
            compare(w.geocoding, true, "a valid name starts a lookup")
            verify(lastFake !== null, "factory used for geocode")
            var u = lastFake.url
            verify(u.indexOf("https://geocoding-api.open-meteo.com/v1/search") === 0, "hits the geocoding API")
            verify(u.indexOf("name=New%20York") >= 0, "city name is URL-encoded (" + u + ")")
            verify(u.indexOf("count=1") >= 0, "asks for a single best match")
        }

        function test_geocode_valid_patches_settings() {
            var w = h.item
            w.geocode("Tokyo")
            lastFake.resolveWith(200, Fx.GEOCODE_VALID)
            compare(w.geocoding, false, "lookup finished")
            var s = h.storeCtl.settingsFor("test-instance")
            fuzzyCompare(s.lat, 35.6895, 0.0001, "latitude persisted from the geocode result")
            fuzzyCompare(s.lon, 139.6917, 0.0001, "longitude persisted")
            compare(s.place, "Tokyo, Tokyo, JP", "labelled name/admin1/country persisted")
        }

        function test_geocode_empty_is_city_not_found() {
            var w = h.item
            w.geocode("Nowhereville")
            lastFake.resolveWith(200, Fx.GEOCODE_EMPTY)
            compare(w.geocoding, false, "lookup finished")
            compare(w.errorText, "City not found", "no results → City not found")
        }

        function test_geocode_malformed_is_lookup_failed() {
            var w = h.item
            w.geocode("Tokyo")
            lastFake.resolveWith(200, Fx.MALFORMED_JSON)
            compare(w.errorText, "Lookup failed", "un-parseable geocode body → Lookup failed")
        }
    }
}
