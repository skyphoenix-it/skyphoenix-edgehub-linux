import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as W

// Backgrounds — verifies every animated background style declared in
// BackgroundCatalog actually loads a real backdrop component in BackdropLayer
// (catches a broken/missing component or catalog↔map drift — the "some styles
// don't show" class of bug). Theme-driven visibility (e.g. high-contrast turning
// decoration off) is a separate, intentional behaviour tested elsewhere.
Item {
    width: 400; height: 700
    App.Theme { id: theme }
    App.BackgroundCatalog { id: bgc }
    W.BackdropLayer { id: bl; anchors.fill: parent; running: true }

    TestCase {
        name: "Backgrounds"
        when: windowShown

        function test_catalog_has_expected_styles() {
            var names = bgc.styles.map(function (s) { return s.v })
            var expected = ["none", "orbs", "mesh", "aurora", "waves", "stars", "bokeh", "grid"]
            for (var i = 0; i < expected.length; i++)
                verify(names.indexOf(expected[i]) >= 0, "catalog includes '" + expected[i] + "'")
        }

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
    }
}
