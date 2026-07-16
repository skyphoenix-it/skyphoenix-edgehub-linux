import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Wg

// AppIcon (ui/qml/widgets/AppIcon.qml) — a tinted SVG via MultiEffect. MultiEffect
// does not render offscreen, so we assert the DRIVING PROPS: source resolution
// (name → qrc path, iconSource override), the tint routing (Image vs MultiEffect
// visibility + colorizationColor), size, and the empty-input fallback.
//
// W5 finding 4: MultiEffect renders NOTHING under the software scenegraph, so
// AppIcon carries `effectsAvailable` (default-bound to GraphicsInfo.api !==
// Software) and falls back to the plain untinted Image when effects can't
// render. The scenegraph backend cannot be swapped mid-run, so the routing
// tests drive the SEAM (both branches) and a separate test proves the default
// detection binding agrees with the real GraphicsInfo of this run.
Item {
    id: root
    width: 200; height: 200

    property alias theme: _theme
    App.Theme { id: _theme }

    // What THIS run's scenegraph actually is, read the only way an attached
    // property can be: from an Item's own binding.
    Item { id: gfxProbe; readonly property bool softwareSg: GraphicsInfo.api === GraphicsInfo.Software }

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
            // Pin the seam so the routing tests below mean the same thing on a
            // GL dev box and in a software-rendered CI run alike.
            icon.effectsAvailable = true
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

        // ── W5 finding 4: the software-scenegraph fallback ───────────────────
        // Under a software renderer MultiEffect draws nothing; the raw image
        // must take over (untinted beats invisible). Driven via the seam — the
        // backend itself cannot be swapped inside one test run.
        function test_software_fallback_shows_untinted_image() {
            icon.tint = true; icon.iconSource = ""
            icon.effectsAvailable = false
            var img = imageOf(icon)
            var fx = effectOf(icon)
            verify(img.visible, "no effects → the raw glyph is shown instead of a blank square")
            verify(!fx.visible, "no effects → the MultiEffect (which would render nothing) is off")
            compare(String(img.source), "qrc:/icons/cpu.svg", "…and it is the real glyph, not an empty source")
            // The fallback must never break the untinted/full-colour path.
            icon.tint = false
            verify(img.visible, "untinted icons still render under the fallback")
        }

        function test_effects_return_restores_tinting() {
            icon.effectsAvailable = false
            var img = imageOf(icon)
            verify(img.visible, "fallback active")
            icon.effectsAvailable = true
            var fx = effectOf(icon)
            verify(fx.visible, "effects back → tint routing returns to the MultiEffect")
            verify(!img.visible, "…and the raw white glyph hides again")
        }

        // The default DETECTION binding: a fresh AppIcon must agree with what
        // GraphicsInfo actually reports for this run's scenegraph, whichever
        // backend the runner picked (GL locally, software in headless CI).
        function test_effectsAvailable_detection_matches_the_scenegraph() {
            var d = Qt.createQmlObject('import "../../ui/qml/widgets" as W; W.AppIcon {}', root, "det")
            compare(d.effectsAvailable, !gfxProbe.softwareSg,
                    "effectsAvailable default tracks GraphicsInfo (softwareSg=" + gfxProbe.softwareSg + ")")
            d.destroy()
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
