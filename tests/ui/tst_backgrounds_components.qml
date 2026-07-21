import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Wg

// Each animated background (ui/qml/widgets/*Background.qml). Their animations are
// property-value-source objects (not reachable in the visual tree), so we assert
// the OBSERVABLE DRIVING SIGNAL instead of pixels: descendant geometry/opacity for
// the drifting styles, and `phase` for the grid. For each style we verify:
//   • active=true  → the signal changes over time (running)
//   • active=false → the signal is frozen (static)
//   • reduce-motion (driven onto `active` by the host) forces the static state
Item {
    id: root
    width: 360; height: 360

    property alias theme: _theme
    App.Theme { id: _theme }

    // A single host-side controller. Every backdrop binds `active` to it exactly
    // as WidgetChrome/BackdropLayer do (running: !theme.reduceMotion). Mutating
    // these two booleans never severs the binding.
    property bool motionOn: true

    // 7 styles, each in its own sized host (overlapping is fine - offscreen).
    Wg.AnimatedBackground   { id: orbs;   anchors.fill: parent; active: root.motionOn && !_theme.reduceMotion }
    Wg.AuroraBackground     { id: aurora; anchors.fill: parent; active: root.motionOn && !_theme.reduceMotion }
    Wg.BokehBackground      { id: bokeh;  anchors.fill: parent; active: root.motionOn && !_theme.reduceMotion }
    Wg.MeshGradientBackground { id: mesh; anchors.fill: parent; active: root.motionOn && !_theme.reduceMotion }
    Wg.WavesBackground      { id: waves;  anchors.fill: parent; active: root.motionOn && !_theme.reduceMotion }
    Wg.StarfieldBackground  { id: stars;  anchors.fill: parent; active: root.motionOn && !_theme.reduceMotion }
    Wg.GridBackground       { id: grid;   anchors.fill: parent; active: root.motionOn && !_theme.reduceMotion }

    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids) for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
    }
    // Observable motion signal: all descendant x/y/opacity, plus the style's own
    // scroll `phase` if it has one (GridBackground animates phase, not geometry).
    function signalOf(node) {
        var acc = (node.phase !== undefined ? node.phase.toFixed(4) : "") + "|"
        eachItem(node, function (n) {
            acc += (n.x || 0).toFixed(3) + "," + (n.y || 0).toFixed(3) + "," + (n.opacity || 0).toFixed(3) + ";"
        })
        return acc
    }

    TestCase {
        name: "Backgrounds"
        when: windowShown

        function init() { root.motionOn = true; _theme.reduceMotion = false }
        function cleanup() { root.motionOn = true; _theme.reduceMotion = false }

        // ── Reusable assertions (props/signal, never pixels) ─────────────────
        function assertDefaultActive(name) {
            var probe = Qt.createQmlObject(
                'import "../../ui/qml/widgets" as W; W.' + name + ' { width: 100; height: 100 }',
                root, "def" + name)
            compare(probe.active, true, name + " defaults to active:true")
            probe.destroy()
        }
        function assertAnimated(obj, name) {
            root.motionOn = true; _theme.reduceMotion = false
            wait(120)
            var a0 = signalOf(obj)
            wait(700)
            verify(signalOf(obj) !== a0, name + " with active:true is moving (signal changes over time)")
        }
        function assertStaticWhenInactive(obj, name) {
            root.motionOn = false; _theme.reduceMotion = false
            wait(150)                       // let animations halt
            var s0 = signalOf(obj)
            wait(350)
            compare(signalOf(obj), s0, name + " with active:false is frozen (no motion)")
        }
        function assertReduceMotionForcesStatic(obj, name) {
            root.motionOn = true; _theme.reduceMotion = true   // host drives active→false
            wait(150)
            var s0 = signalOf(obj)
            wait(350)
            compare(signalOf(obj), s0, name + " is static while reduce-motion is on")
            // …and motion resumes once reduce-motion clears.
            _theme.reduceMotion = false
            wait(120)
            var r0 = signalOf(obj)
            wait(700)
            verify(signalOf(obj) !== r0, name + " resumes moving when reduce-motion clears")
        }
        function runStyle(obj, name) {
            assertDefaultActive(name)
            assertAnimated(obj, name)
            assertStaticWhenInactive(obj, name)
            assertReduceMotionForcesStatic(obj, name)
        }

        function test_animated_orbs()  { runStyle(orbs,   "AnimatedBackground") }
        function test_aurora()         { runStyle(aurora, "AuroraBackground") }
        function test_bokeh()          { runStyle(bokeh,  "BokehBackground") }
        function test_mesh()           { runStyle(mesh,   "MeshGradientBackground") }
        function test_waves()          { runStyle(waves,  "WavesBackground") }
        function test_starfield()      { runStyle(stars,  "StarfieldBackground") }
        function test_grid()           { runStyle(grid,   "GridBackground") }
    }
}
