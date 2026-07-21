import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Wg

// RingProgress (ui/qml/widgets/RingProgress.qml) - a Canvas progress ring. Canvas
// does not paint offscreen, so we assert the DRIVING PROPERTIES (value / thickness
// / colours) and the guards that keep the paint path from throwing, never pixels.
Item {
    id: root
    width: 300; height: 300

    property alias theme: _theme
    App.Theme { id: _theme }

    Item {
        id: host
        width: 200; height: 200
        Wg.RingProgress { id: ring; anchors.fill: parent }
    }

    // A separately-sized host to check the implicit thickness formula reacts to size.
    Item {
        id: tinyHost
        width: 40; height: 40
        Wg.RingProgress { id: tinyRing; anchors.fill: parent }
    }

    TestCase {
        name: "RingProgress"
        when: windowShown

        function init() { ring.value = 0.0; ring.thickness = Qt.binding(function () {
            return Math.max(6, Math.min(ring.width, ring.height) * 0.08) }) }

        // ── Driving props ────────────────────────────────────────────────────
        function test_default_colors_from_theme() {
            verify(Qt.colorEqual(ring.trackColor, _theme.cardBorder), "track defaults to cardBorder")
            verify(Qt.colorEqual(ring.progressColor, _theme.accent), "progress defaults to accent")
            verify(Qt.colorEqual(ring.progressColor2, _theme.accent2), "progress2 defaults to accent2")
        }

        function test_value_roundtrips() {
            ring.value = 0.5
            fuzzyCompare(ring.value, 0.5, 1e-9, "value stored")
        }

        function test_progress_color_override() {
            ring.progressColor = "#123456"
            verify(Qt.colorEqual(ring.progressColor, "#123456"), "progressColor override applied")
            ring.progressColor2 = "#654321"
            verify(Qt.colorEqual(ring.progressColor2, "#654321"), "progressColor2 override applied")
        }

        function test_thickness_override() {
            ring.thickness = 20
            compare(ring.thickness, 20, "explicit thickness applied")
        }

        // ── Implicit thickness formula scales with size ──────────────────────
        function test_implicit_thickness_scales_with_size() {
            // 200px host → 200*0.08 = 16.
            fuzzyCompare(ring.thickness, 16, 0.001, "thickness follows min(w,h)*0.08 at 200px")
            // 40px host → 40*0.08 = 3.2, floored to the 6px minimum.
            compare(tinyRing.thickness, 6, "thickness never drops below the 6px floor on a tiny ring")
        }

        // ── Progress clamping is tolerated (Canvas clamps frac internally) ────
        function test_over_full_value_accepted() {
            var threw = false
            try { ring.value = 1.5 } catch (e) { threw = true }
            verify(!threw, "value > 1 is accepted (clamped to full inside paint)")
            fuzzyCompare(ring.value, 1.5, 1e-9, "raw value is retained on the property")
        }

        function test_negative_value_accepted() {
            var threw = false
            try { ring.value = -0.4 } catch (e) { threw = true }
            verify(!threw, "value < 0 is accepted (clamped to empty inside paint)")
        }

        function test_zero_value_is_idle() {
            ring.value = 0
            compare(ring.value, 0, "an idle ring holds value 0 (paint short-circuits, no spurious dot)")
        }

        // ── Zero/degenerate size does not throw (r<=0 guard) ─────────────────
        function test_zero_size_does_not_throw() {
            var probe = Qt.createQmlObject(
                'import "../../ui/qml/widgets" as W; W.RingProgress { width: 0; height: 0; value: 0.5 }',
                root, "zeroRing")
            verify(probe !== null, "a zero-sized ring instantiates without throwing (radius guard)")
            probe.destroy()
        }

        // ── glow follows theme ───────────────────────────────────────────────
        function test_glow_follows_theme() {
            compare(ring.glow, _theme.glow, "glow mirrors theme.glow by default")
        }

        // ── Opt-in value smoothing (W3) ──────────────────────────────────────
        // Data-driven rings (MetricGauge) ease between samples; timer rings keep
        // their honest 1Hz step because animateValue defaults to FALSE. The ease
        // rides theme.motionValue, so reduce-motion collapses it to a jump.
        function test_animate_value_defaults_off_and_is_instant() {
            compare(ring.animateValue, false, "smoothing is opt-in (timers keep stepping)")
            ring.value = 0.7
            fuzzyCompare(ring.value, 0.7, 1e-9, "default assignment lands instantly")
            ring.value = 0
        }

        function test_animate_value_eases_then_lands() {
            _theme.reduceMotion = false
            ring.value = 0
            ring.animateValue = true
            ring.value = 1.0
            verify(ring.value < 0.9, "right after the sample the sweep is still en route ("
                   + ring.value + ")")
            tryVerify(function () { return ring.value >= 0.999 }, 2000, "…then lands on the target")
            ring.animateValue = false
            ring.value = 0
        }

        function test_animate_value_collapses_under_reduce_motion() {
            ring.animateValue = true
            _theme.reduceMotion = true
            compare(_theme.motionValue, 0, "token zeroed")
            ring.value = 0.8
            tryVerify(function () { return Math.abs(ring.value - 0.8) < 1e-6 }, 50,
                      "reduce-motion: the sweep snaps instead of gliding")
            _theme.reduceMotion = false
            ring.animateValue = false
            ring.value = 0
        }
    }
}
