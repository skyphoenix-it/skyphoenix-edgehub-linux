import QtQuick
import QtTest

// Regression: a config change must update an ALREADY-LOADED widget live (the
// "config options in the Manager did nothing" bug - widgets returned the same
// cfg object reference so QML never re-evaluated the derived properties).
Item {
    width: 300; height: 300
    WidgetHarness { id: hc; anchors.fill: parent; widgetFile: "CpuWidget.qml"
        metricsJson: '{"cpu_usage_percent":12,"cpu_temp_celsius":60}' }

    TestCase {
        name: "ConfigLive"
        when: windowShown
        function initTestCase() { tryVerify(function () { return hc.ready }, 3000) }

        function test_cpu_showtemp_updates_live() {
            var w = hc.item
            hc.storeCtl.setSetting("test-instance", "showTemp", true)
            verify(w.status.indexOf("60") >= 0, "temp shown when showTemp on")
            hc.storeCtl.setSetting("test-instance", "showTemp", false)
            compare(w.status, "", "toggling showTemp OFF updates the widget live")
            hc.storeCtl.setSetting("test-instance", "showTemp", true)
            verify(w.status.indexOf("60") >= 0, "and back ON live")
        }

        function test_cpu_warn_threshold_live() {
            var w = hc.item
            hc.storeCtl.setSetting("test-instance", "showTemp", true)
            hc.storeCtl.setSetting("test-instance", "warnTemp", 100)   // 60 < 100 → not error
            verify(String(w.statusColor) !== String(hc.theme.error), "below threshold: not red")
            hc.storeCtl.setSetting("test-instance", "warnTemp", 50)    // 60 > 50 → error
            compare(String(w.statusColor), String(hc.theme.error), "above threshold: red, live")
        }
    }
}
