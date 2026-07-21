import QtQuick
import QtTest
import "../ui" as UI
import "GuiUtil.js" as G

// Template + self-validation for the visible GUI suite. Proves the three hosting
// recipes work in a REAL rendered window (KWin): (1) host a single widget and
// drive a real interaction, (2) capture grabImage evidence + assert rendered
// pixels, (3) host the REAL Hub shell and assert add-page lands AND stays.
//
// Run visibly: qmltestrunner under QT_QPA_PLATFORM=wayland in a nested KWin with
// -mousedelay/-keydelay. Evidence PNGs land in gui-evidence/ (CWD = repo root).
Item {
    id: root
    width: 1280; height: 760

    // ---- Shell context props (main.qml reads these as `property x: _x`) ----
    property bool _isFirstRun: false
    property string _screens: "[]"
    property string _metricsJson: "{}"
    property string _themeMode: "midnight"
    property string _targetEdidHash: ""
    property string _targetConnector: ""
    property string _targetModel: ""
    property string _configDir: "/tmp"
    property bool _safeMode: false
    property bool _startInDiagnostics: false
    property bool _windowedMode: true
    property int _targetScreenX: 0
    property int _targetScreenY: 0
    property int _targetScreenWidth: 1280
    property int _targetScreenHeight: 760

    // A single-widget host (Dashboard-equivalent scope injection).
    UI.WidgetHarness {
        id: wh
        anchors.left: parent.left; anchors.top: parent.top
        width: 200; height: 200
        widgetFile: "ClockWidget.qml"
    }

    TestCase {
        name: "GuiSample"
        when: windowShown
        visible: true

        function snap(item, name) {
            var img = grabImage(item)
            img.save("gui-evidence/sample_" + name + ".png")
            return img
        }

        // (1) + (2): a widget renders real pixels in a real window.
        function test_widget_renders_real_pixels() {
            wh.widgetFile = "ClockWidget.qml"
            tryVerify(function () { return wh.ready }, 4000)
            wait(300)
            var img = snap(wh, "clock")
            verify(G.looksRendered(img), "clock widget rendered non-blank pixels")
            compare(img.width, 200, "grab width matches host")
        }

        // A real interaction changes visible state (Hydration +1).
        function test_widget_real_interaction() {
            wh.widgetFile = "HydrationWidget.qml"
            tryVerify(function () { return wh.ready }, 4000)
            wait(300)
            wh.storeCtl.setSetting(wh.instanceId, "goal", 8)
            wh.storeCtl.setSetting(wh.instanceId, "count", 0)
            wait(200)
            // find a live tap target inside the widget and click it
            var targets = G.liveClickables(wh.item)
            verify(targets.length > 0, "hydration has a tappable area (" + targets.length + ")")
            var ma = targets[0]
            var before = wh.storeCtl.settingsFor(wh.instanceId).count
            mouseClick(ma, ma.width / 2, ma.height / 2)
            wait(300)
            var after = wh.storeCtl.settingsFor(wh.instanceId).count
            snap(wh, "hydration_after")
            verify(after !== before, "a real click changed the hydration count (" + before + "->" + after + ")")
        }

        // (3): the REAL Hub shell - add a page and LAND + STAY (the snap-back bug).
        property var win: null
        function test_shell_add_page_lands_and_stays() {
            var c = Qt.createComponent("../../ui/qml/main.qml")
            tryVerify(function () { return c.status !== Component.Loading }, 6000)
            compare(c.status, Component.Ready, "main.qml compiles: " + c.errorString())
            win = c.createObject(root)
            verify(win !== null, "main.qml instantiated")
            win.orientationMode = "landscape"
            var sv0 = G.findPred(win.contentItem, function (n) {
                return n && typeof n.push === "function" && n.currentItem !== undefined })
            verify(sv0, "found StackView")
            sv0.push(Qt.resolvedUrl("../../ui/qml/Dashboard.qml"))
            var swipe = null, store = null
            tryVerify(function () {
                swipe = G.byObjName(win.contentItem, "pageSwipe")
                store = G.findPred(win.contentItem, function (n) {
                    return n && n.applyExternal !== undefined && n.structureRevision !== undefined })
                return swipe !== null && store !== null
            }, 6000, "Dashboard + SwipeView loaded in the real shell")

            store.load("blank")
            tryVerify(function () { return swipe.count === store.pageCount() }, 3000)
            wait(400)
            snap(win.contentItem, "shell_page0")
            for (var n = 0; n < 3; n++) {
                var target = store.pageCount()
                store.addPage("")
                swipe.goToPage(target)
                tryVerify(function () { return swipe.currentIndex === target }, 4000, "reached new page " + target)
                wait(900)   // outlast a deferred relayout - the snap-back window
                compare(swipe.currentIndex, target, "STAYED on new page " + target)
                snap(win.contentItem, "shell_page" + target)
            }
        }
        function cleanupTestCase() { if (win) win.destroy() }
    }
}
