import QtQuick
import QtTest

// Sanity check: the harness resolves theme/store/media and loads a widget.
Item {
    width: 380; height: 760

    WidgetHarness {
        id: h
        anchors.fill: parent
        widgetFile: "ClockWidget.qml"
    }

    TestCase {
        name: "HarnessSelfTest"
        when: windowShown

        function test_theme_present() {
            verify(h.theme !== null)
            compare(h.theme.touchPrimary, 76)
        }
        function test_store_present() {
            verify(h.storeCtl !== null)
            h.storeCtl.setSetting("test-instance", "foo", 42)
            compare(h.storeCtl.settingsFor("test-instance").foo, 42)
        }
        function test_widget_loads() {
            tryVerify(function () { return h.ready }, 2000)
            verify(h.item !== null)
        }
    }
}
