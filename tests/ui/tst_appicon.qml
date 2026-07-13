import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Wg

// AppIcon (ui/qml/widgets/AppIcon.qml) — a tinted SVG via MultiEffect. MultiEffect
// does not render offscreen, so we assert the DRIVING PROPS: source resolution
// (name → qrc path, iconSource override), the tint routing (Image vs MultiEffect
// visibility + colorizationColor), size, and the empty-input fallback.
Item {
    id: root
    width: 200; height: 200

    property alias theme: _theme
    App.Theme { id: _theme }

    Wg.AppIcon { id: icon; name: "cpu"; color: "#112233"; size: 30 }

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
    function imageOf(i) {
        return findPred(i, function (n) {
            return n.source !== undefined && n.sourceSize !== undefined && n.fillMode !== undefined
        })
    }
    function effectOf(i) {
        return findPred(i, function (n) { return n.colorization !== undefined && n.colorizationColor !== undefined })
    }

    TestCase {
        name: "AppIcon"
        when: windowShown

        function init() {
            icon.name = "cpu"; icon.iconSource = ""; icon.color = "#112233"
            icon.size = 30; icon.tint = true
        }

        function test_defaults() {
            var d = Qt.createQmlObject('import "../../ui/qml/widgets" as W; W.AppIcon {}', root, "def")
            compare(d.size, 24, "default size 24")
            compare(d.tint, true, "tinting on by default")
            verify(Qt.colorEqual(d.color, "#FFFFFF"), "default colour white")
            d.destroy()
        }

        function test_implicit_size_follows_size() {
            icon.size = 40
            compare(icon.implicitWidth, 40, "implicitWidth follows size")
            compare(icon.implicitHeight, 40, "implicitHeight follows size")
        }

        function test_name_resolves_to_qrc_svg_path() {
            icon.name = "gpu"
            var img = imageOf(icon)
            verify(img !== null, "image element present")
            compare(String(img.source), "qrc:/icons/gpu.svg", "name resolves to the bundled SVG path")
        }

        function test_iconSource_override_wins_over_name() {
            icon.iconSource = "qrc:/wallpapers/nebula.png"
            var img = imageOf(icon)
            compare(String(img.source), "qrc:/wallpapers/nebula.png",
                    "a full-colour iconSource overrides the name-derived path")
        }

        function test_tint_routes_to_multieffect() {
            icon.tint = true; icon.iconSource = ""
            var img = imageOf(icon)
            var fx = effectOf(icon)
            verify(fx !== null, "MultiEffect present")
            verify(!img.visible, "the raw white glyph is hidden when tinting")
            verify(fx.visible, "the MultiEffect renders the tinted glyph")
            verify(Qt.colorEqual(fx.colorizationColor, icon.color),
                   "the tint colour is the icon colour")
        }

        function test_untinted_shows_raw_image() {
            icon.tint = false
            var img = imageOf(icon)
            var fx = effectOf(icon)
            verify(img.visible, "raw image visible when not tinting")
            verify(!fx.visible, "the MultiEffect is off when not tinting")
        }

        function test_colorization_color_tracks_color() {
            icon.tint = true; icon.iconSource = ""; icon.color = "#00FF88"
            var fx = effectOf(icon)
            verify(Qt.colorEqual(fx.colorizationColor, "#00FF88"), "colorizationColor follows color")
        }

        // Empty name + empty source is the "fallback" state: an empty source, no throw.
        function test_empty_inputs_fall_back_to_empty_source() {
            icon.name = ""; icon.iconSource = ""
            var img = imageOf(icon)
            compare(String(img.source), "", "no name and no source yields an empty (blank) source, not an error")
        }
    }
}
