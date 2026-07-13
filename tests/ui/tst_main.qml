import QtQuick
import QtTest

// COVERS: fn:main.bindStackItem
//
// ui/qml/main.qml — bindStackItem (binds/rebinds cleanly, skips null +
// items without the shell properties) and the readonly `contentRotation`
// mapping for every orientation mode (portrait 0 / landscape 90 /
// inverted-portrait 180 / inverted-landscape 270 / auto-follows-sensor), plus
// the contentRoot width/height swap for the 90°/270° landscape aspect.
//
// main.qml is an ApplicationWindow that reads a set of `_`-prefixed context
// properties injected by the C++ shell. We declare them on this wrapper so the
// window resolves them through the context scope (exactly as the widget harness
// feeds `theme`/`store` to widgets), then instantiate the REAL main.qml. Its
// initialItem is a qrc: URL that isn't registered under qmltestrunner, so the
// StackView starts empty — irrelevant here: we drive bindStackItem with our own
// stub item and assert the rotation binding directly (props, never pixels).
Item {
    id: root
    width: 200; height: 200

    // Shell-provided context properties (mirror main.qml's `property x: _x`).
    property bool _isFirstRun: false
    property string _screens: "[]"
    property string _metricsJson: "{}"
    property string _themeMode: "dark"
    property string _targetEdidHash: ""
    property string _targetConnector: ""
    property string _targetModel: ""
    property string _configDir: "/tmp"
    property bool _safeMode: false
    property bool _startInDiagnostics: false
    property bool _windowedMode: true
    property int _targetScreenX: 0
    property int _targetScreenY: 0
    property int _targetScreenWidth: 1920
    property int _targetScreenHeight: 1080

    // A stand-in for a StackView page that declares the shell-bound properties.
    Component {
        id: pageStub
        QtObject {
            property string metricsJson: ""
            property string screensData: ""
            property string configJson: ""
        }
    }
    // A page that declares NONE of them (bindStackItem must leave it untouched).
    Component {
        id: barePage
        QtObject { property int marker: 7 }
    }

    property var win: null

    // ── tree helpers ─────────────────────────────────────────────────────────
    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids) for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
    }
    function findPred(node, pred) {
        var f = null
        eachItem(node, function (n) { if (!f && pred(n)) f = n })
        return f
    }

    TestCase {
        name: "Main"
        when: windowShown

        function initTestCase() {
            var c = Qt.createComponent("../../ui/qml/main.qml")
            tryVerify(function () { return c.status !== Component.Loading }, 5000)
            compare(c.status, Component.Ready, "main.qml compiles: " + c.errorString())
            win = c.createObject(root)
            verify(win !== null, "main.qml instantiated")
        }
        function cleanupTestCase() { if (win) win.destroy() }

        // ── bindStackItem ─────────────────────────────────────────────────────
        function test_bindStackItem_binds_live_shell() {
            root._metricsJson = "{\"cpu\":1}"
            root._screens = "[{\"n\":1}]"
            var pg = pageStub.createObject(root)
            win.bindStackItem(pg)
            compare(pg.metricsJson, win.metricsJson, "bindStackItem bound the page's metricsJson to the window")
            compare(pg.metricsJson, "{\"cpu\":1}", "reflects current shell value")
            compare(pg.screensData, win.screensData, "screensData bound to the window")
            // configJson: no configBridge in the test → the binding yields "".
            compare(pg.configJson, "", "configJson binding falls back to empty")

            // A LIVE shell update must flow through the binding (not a one-shot copy).
            root._metricsJson = "{\"cpu\":99}"
            compare(win.metricsJson, "{\"cpu\":99}", "window property tracks the shell")
            compare(pg.metricsJson, "{\"cpu\":99}", "bound page updates live")
            pg.destroy()
        }

        function test_bindStackItem_rebinds_cleanly() {
            var pg = pageStub.createObject(root)
            win.bindStackItem(pg)
            win.bindStackItem(pg)                    // second bind must not throw
            root._metricsJson = "{\"v\":2}"
            compare(pg.metricsJson, "{\"v\":2}", "still tracks after a rebind")
            pg.destroy()
        }

        function test_bindStackItem_ignores_null_and_bare_items() {
            win.bindStackItem(null)                  // no throw
            var bare = barePage.createObject(root)
            win.bindStackItem(bare)                  // item lacks the props → untouched
            compare(bare.marker, 7, "an item without shell props is left alone")
            verify(!bare.hasOwnProperty("metricsJson"), "no property was injected")
            bare.destroy()
            verify(true, "null + bare items handled without error")
        }

        // ── contentRotation (fixed modes) ─────────────────────────────────────
        function test_content_rotation_fixed_modes_data() {
            return [
                { tag: "portrait",           mode: "portrait",           rot: 0 },
                { tag: "landscape",          mode: "landscape",          rot: 90 },
                { tag: "inverted-portrait",  mode: "inverted-portrait",  rot: 180 },
                { tag: "inverted-landscape", mode: "inverted-landscape", rot: 270 },
            ]
        }
        function test_content_rotation_fixed_modes(d) {
            win.orientationMode = d.mode
            compare(win.contentRotation, d.rot, d.mode + " → " + d.rot + "°")
        }

        // Auto mode ignores manual rotation and follows the (debounced) sensor.
        // The FIRST reading is applied promptly (no wall-clock wait needed).
        function test_content_rotation_auto_follows_sensor() {
            win.orientationMode = "auto"
            win.sensorRotation = -1
            win._stableSensorRotation = -1
            compare(win.contentRotation, 0, "auto with no sensor reading stays upright")
            win.sensorRotation = 90               // first reading applies immediately
            compare(win._stableSensorRotation, 90, "first sensor reading applied promptly")
            compare(win.contentRotation, 90, "auto follows the sensor to 90°")
        }

        // The rotating container (main.qml contentRoot) swaps width/height
        // (portrait↔landscape aspect) only for the 90°/270° quarter turns. We
        // tree-walk the window for the REAL contentRoot (the object exposing
        // `swapped`) and read its actual `swapped`/`width`/`height` — so a broken
        // `swapped:` predicate OR a broken width/height swap fails here.
        function test_content_root_swaps_aspect_at_quarter_turns() {
            var cr = findPred(win.contentItem, function (n) {
                return n && typeof n.swapped === "boolean" })
            verify(cr !== null, "found contentRoot (the rotating aspect container)")
            // Distinct window dimensions so an actual width/height swap is observable.
            win.width = 300; win.height = 500

            // 0° portrait — upright, keeps the window aspect (not swapped).
            win.orientationMode = "portrait"
            compare(win.contentRotation, 0)
            compare(cr.swapped, false, "0° is not swapped")
            compare(cr.width, win.width, "0°: contentRoot width tracks the window width")
            compare(cr.height, win.height, "0°: contentRoot height tracks the window height")

            // 90° landscape — swapped: width takes the window HEIGHT and vice-versa.
            win.orientationMode = "landscape"
            compare(win.contentRotation, 90)
            compare(cr.swapped, true, "90° is a swapped (landscape) orientation")
            compare(cr.width, win.height, "90°: contentRoot width takes the window HEIGHT (aspect swapped)")
            compare(cr.height, win.width, "90°: contentRoot height takes the window WIDTH")

            // 180° inverted-portrait — back to the portrait aspect (not swapped).
            win.orientationMode = "inverted-portrait"
            compare(win.contentRotation, 180)
            compare(cr.swapped, false, "180° keeps the portrait aspect (not swapped)")
            compare(cr.width, win.width, "180°: contentRoot width back to the window width")
            compare(cr.height, win.height, "180°: contentRoot height back to the window height")

            // 270° inverted-landscape — swapped again.
            win.orientationMode = "inverted-landscape"
            compare(win.contentRotation, 270)
            compare(cr.swapped, true, "270° is a swapped (landscape) orientation")
            compare(cr.width, win.height, "270°: contentRoot width takes the window HEIGHT")
            compare(cr.height, win.width, "270°: contentRoot height takes the window WIDTH")
        }
    }
}
