import QtQuick
import QtTest

// ClockWidget — verifies every config option actually changes what's shown:
// 12/24-hour, seconds, date visibility + style, and the world-clock UTC offset.
Item {
    width: 420; height: 300
    WidgetHarness { id: h; anchors.fill: parent; widgetFile: "ClockWidget.qml"; expanded: true }

    TestCase {
        name: "ClockWidget"
        when: windowShown

        function init() {
            tryVerify(function () { return h.ready }, 3000)
            var s = h.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            h.storeCtl._touchSettings()
        }
        function set(k, v) { h.storeCtl.setSetting("test-instance", k, v) }

        function test_12h_vs_24h() {
            var w = h.item
            set("format24", false)
            verify(w.timeFmt.indexOf("h:mm") >= 0, "12h uses h:mm")
            verify(w.timeFmt.indexOf("AP") >= 0, "12h shows AM/PM")
            verify(w.timeFmt.indexOf("HH") < 0)
            set("format24", true)
            verify(w.timeFmt.indexOf("HH:mm") >= 0, "24h uses HH:mm")
            verify(w.timeFmt.indexOf("AP") < 0, "24h has no AM/PM")
        }

        function test_show_seconds() {
            var w = h.item
            set("showSeconds", false)
            verify(w.timeFmt.indexOf("ss") < 0, "no seconds by default")
            set("showSeconds", true)
            verify(w.timeFmt.indexOf("ss") >= 0, "seconds added to the format")
        }

        function test_date_style() {
            var w = h.item
            set("dateStyle", "short")
            compare(w.dateFmt, "dd/MM", "short date style")
            set("dateStyle", "full")
            verify(w.dateFmt.indexOf("MMM") >= 0, "full date style uses a month name")
        }

        function test_world_clock_offset() {
            var w = h.item
            set("customZone", false)
            // local: zonedNow ≈ now
            verify(Math.abs(w.zonedNow().getTime() - Date.now()) < 2000, "local mode = now")
            set("customZone", true)
            set("utcOffset", 5)
            var local = new Date()
            var utcMs = local.getTime() + local.getTimezoneOffset() * 60000
            var expected = utcMs + 5 * 3600000
            verify(Math.abs(w.zonedNow().getTime() - expected) < 2000,
                   "world-clock time equals UTC+5")
            // A different offset gives a different time.
            set("utcOffset", -8)
            var expected2 = utcMs - 8 * 3600000
            verify(Math.abs(w.zonedNow().getTime() - expected2) < 2000, "UTC-8 differs correctly")
        }

        function test_zone_label_default() {
            var w = h.item
            set("customZone", true)
            compare(w.zoneLabel, "", "no label by default")
            verify(w.offsetLabel().indexOf("UTC") >= 0, "falls back to a UTC offset label")
            set("zoneLabel", "Tokyo")
            compare(w.zoneLabel, "Tokyo")
        }
    }
}
