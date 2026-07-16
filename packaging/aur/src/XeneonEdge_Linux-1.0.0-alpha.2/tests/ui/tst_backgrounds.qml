import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as W

// Backgrounds — verifies every animated background style declared in
// BackgroundCatalog actually loads a real backdrop component in BackdropLayer
// (catches a broken/missing component or catalog↔map drift — the "some styles
// don't show" class of bug). Theme-driven visibility (e.g. high-contrast turning
// decoration off) is a separate, intentional behaviour tested elsewhere.
//
// The character styles (arch/fedora/aubergine) are INLINE components inside
// BackdropLayer, so unlike the file-backed styles they cannot be imported and
// driven directly the way tst_backgrounds_components.qml does. Their motion
// contract is therefore asserted here, through the Loader.
Item {
    id: root
    width: 400; height: 700
    App.Theme { id: theme }
    App.BackgroundCatalog { id: bgc }
    W.BackdropLayer { id: bl; anchors.fill: parent; running: true }

    // Styles implemented inline in BackdropLayer.qml (no importable file).
    readonly property var inlineStyles: ["arch", "fedora", "aubergine"]

    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids) for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
    }
    // Observable motion signal. The animations are property-value-source objects
    // (not reachable in the visual tree), so assert the DRIVING SIGNAL rather than
    // pixels: every descendant's x/y (peaks + ribbons scroll), width (loops swell)
    // and opacity/rotation, so a style that stops moving cannot pass unnoticed.
    function signalOf(node) {
        var acc = ""
        eachItem(node, function (n) {
            acc += (n.x || 0).toFixed(3) + "," + (n.y || 0).toFixed(3) + ","
                 + (n.opacity || 0).toFixed(3) + "," + (n.rotation || 0).toFixed(3) + ","
                 + (n.width || 0).toFixed(3) + ";"
        })
        return acc
    }

    TestCase {
        name: "Backgrounds"
        when: windowShown

        function init() { bl.running = true; theme.reduceMotion = false }
        function cleanup() { bl.running = true; theme.reduceMotion = false }

        function test_catalog_has_expected_styles() {
            var names = bgc.styles.map(function (s) { return s.v })
            var expected = ["none", "orbs", "mesh", "aurora", "waves", "stars", "bokeh", "grid",
                            "arch", "fedora", "aubergine"]
            for (var i = 0; i < expected.length; i++)
                verify(names.indexOf(expected[i]) >= 0, "catalog includes '" + expected[i] + "'")
        }

        // No catalog style may fall through to nothing: every entry either loads a
        // real, instantiated, sized backdrop or is the deliberate no-op gradient.
        function test_every_animated_style_loads_a_backdrop() {
            var styles = bgc.styles
            for (var i = 0; i < styles.length; i++) {
                var v = styles[i].v
                bl.style = v
                if (v === "none" || v === "gradient") {
                    verify(!bl.active, "'" + v + "' loads no backdrop (theme gradient shows through)")
                    continue
                }
                verify(bl.sourceComponent !== null, "'" + v + "' maps to a component in BackdropLayer")
                tryVerify(function () { return bl.item !== null }, 1500,
                          "'" + v + "' backdrop component actually instantiated")
                verify(bl.item.children.length > 0,
                       "'" + v + "' backdrop has visual content (children), got " + bl.item.children.length)
                verify(bl.item.width > 0 && bl.item.height > 0, "'" + v + "' backdrop is sized")
            }
        }

        // reduce-motion / paused: the backdrop must stay PAINTED (not blank), only
        // the animation stops — so switching a page to a style always shows it.
        function test_backdrop_stays_painted_when_not_running() {
            bl.style = "aurora"
            bl.running = false
            tryVerify(function () { return bl.item !== null }, 1500)
            verify(bl.item.children.length > 0, "aurora still has content when not running")
            bl.running = true
        }

        // ── Character styles: motion contract, driven through the Loader ──────
        function test_inline_styles_animate_when_running_data() {
            return root.inlineStyles.map(function (s) { return { tag: s, style: s } })
        }
        function test_inline_styles_animate_when_running(d) {
            bl.style = d.style
            bl.running = true
            tryVerify(function () { return bl.item !== null }, 1500)
            wait(150)
            var s0 = signalOf(bl.item)
            wait(700)
            verify(signalOf(bl.item) !== s0, d.style + " with running:true is moving (signal changes over time)")
        }

        function test_inline_styles_freeze_when_not_running_data() {
            return root.inlineStyles.map(function (s) { return { tag: s, style: s } })
        }
        function test_inline_styles_freeze_when_not_running(d) {
            bl.style = d.style
            bl.running = false
            tryVerify(function () { return bl.item !== null }, 1500)
            wait(250)                       // let animations halt + canvases settle
            var s0 = signalOf(bl.item)
            wait(400)
            compare(signalOf(bl.item), s0, d.style + " with running:false is frozen (no motion)")
            // …and it is still painted, not blanked, while frozen.
            verify(bl.item.children.length > 0, d.style + " still has content when frozen")
        }

        // reduce-motion is driven onto `running` by the host (Dashboard binds
        // running: !reduceMotion) — assert that same wiring end-to-end here.
        function test_inline_styles_static_under_reduce_motion_data() {
            return root.inlineStyles.map(function (s) { return { tag: s, style: s } })
        }
        function test_inline_styles_static_under_reduce_motion(d) {
            bl.style = d.style
            bl.running = Qt.binding(function () { return !theme.effectiveReduceMotion })
            theme.reduceMotion = true
            tryVerify(function () { return bl.item !== null }, 1500)
            wait(250)
            var s0 = signalOf(bl.item)
            wait(400)
            compare(signalOf(bl.item), s0, d.style + " is static while reduce-motion is on")

            // …and motion resumes once reduce-motion clears (proves the freeze was
            // the flag, not a dead animation).
            theme.reduceMotion = false
            wait(150)
            var r0 = signalOf(bl.item)
            wait(700)
            verify(signalOf(bl.item) !== r0, d.style + " resumes moving when reduce-motion clears")
            bl.running = true
        }

        // The character styles must take their tint from the theme accent, not a
        // hard-coded palette — that is what lets them work under ANY theme.
        function test_inline_styles_follow_the_accent_override_data() {
            return root.inlineStyles.map(function (s) { return { tag: s, style: s } })
        }
        function test_inline_styles_follow_the_accent_override(d) {
            bl.style = d.style
            tryVerify(function () { return bl.item !== null }, 1500)
            compare(bl.item.accent, theme.accent, d.style + " defaults its accent to the theme accent")
            bl.accent = "#FF00AA"
            compare(bl.item.accent, Qt.color("#FF00AA"), d.style + " honours a per-page accent override")
            bl.accent = Qt.binding(function () { return theme.accent })
        }
    }
}
