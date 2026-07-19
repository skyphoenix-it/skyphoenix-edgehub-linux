import QtQuick
import QtTest
import "GuiUtil.js" as G

// De-risk: host the REAL Manager window in a real compositor, prove it renders,
// switches tabs, and captures evidence. Template for the Manager GUI cases.
Item {
    id: root
    width: 100; height: 100
    ManagerHarness { id: mh }

    TestCase {
        name: "GuiMgrSmoke"
        when: windowShown
        visible: true

        function snap(item, name) { var img = grabImage(item); img.save("gui-evidence/mgr_" + name + ".png"); return img }

        // Create the Manager window ONCE (QtTest runs test_* alphabetically, so
        // per-test creation would race — the canonical Manager GUI pattern).
        function initTestCase() {
            var w = mh.create()
            verify(w !== null, "Manager.qml instantiated")
            tryVerify(function () { return mh.ready }, 8000, "Manager window became visible")
        }

        function test_manager_window_renders() {
            wait(500)
            var img = snap(mh.win.contentItem, "window")
            verify(G.looksRendered(img), "Manager window rendered non-blank pixels")
        }

        function test_manager_tabs_switch() {
            // Find the 5-tab StackLayout by its test-seam objectName.
            var nav = G.byObjName(mh.win.contentItem, "managerTabs")
            verify(nav !== null, "found the managerTabs StackLayout")
            compare(nav.count, 5, "5 tabs")
            for (var i = 0; i < 5; i++) {
                nav.currentIndex = i
                wait(300)
                compare(nav.currentIndex, i, "tab " + i + " selected")
                snap(mh.win.contentItem, "tab" + i)
            }
        }
        function cleanupTestCase() { mh.destroyWin() }
    }
}
