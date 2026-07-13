import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Wg

// Sparkline (ui/qml/widgets/Sparkline.qml) — a Canvas history chart. Canvas does
// not paint offscreen, so we assert the DRIVING PROPERTIES and the in-place
// mutation signature (the mechanism that decides when to repaint), never pixels.
Item {
    id: root
    width: 300; height: 160

    // File-root `theme` so the directly-instantiated Sparkline resolves the
    // `theme` global (its default `color: theme.accent`).
    property alias theme: _theme
    App.Theme { id: _theme }

    Item {
        id: host
        width: 240; height: 80
        Wg.Sparkline { id: sl; anchors.fill: parent }
    }

    TestCase {
        name: "Sparkline"
        when: windowShown

        function init() { sl.values = []; sl.fill = true; sl.color = _theme.accent }

        // ── Driving props ────────────────────────────────────────────────────
        function test_default_color_is_theme_accent() {
            verify(Qt.colorEqual(sl.color, _theme.accent),
                   "default sparkline colour is theme.accent")
        }

        function test_values_property_roundtrips() {
            var v = [0.1, 0.4, 0.9, 0.3]
            sl.values = v
            compare(sl.values.length, 4, "values array is stored")
            compare(sl.values[2], 0.9, "value content preserved")
        }

        function test_color_property_settable() {
            sl.color = "#FF0000"
            verify(Qt.colorEqual(sl.color, "#FF0000"), "colour override applied")
        }

        function test_fill_toggle() {
            sl.fill = false
            compare(sl.fill, false, "fill can be turned off")
            sl.fill = true
            compare(sl.fill, true, "fill can be turned on")
        }

        // ── Layout / implicit size ───────────────────────────────────────────
        function test_lays_out_at_host_size() {
            compare(sl.width, host.width, "sparkline fills its host width")
            compare(sl.height, host.height, "sparkline fills its host height")
        }

        // ── Signature (repaint driver) ───────────────────────────────────────
        function test_empty_values_signature_is_stable() {
            sl.values = []
            compare(sl._signature(), "0:", "an empty array has the empty-length signature")
        }

        function test_null_values_signature_is_degenerate() {
            sl.values = null
            compare(sl._signature(), "0", "a null values input is a degenerate signature (draws nothing)")
        }

        function test_single_point_does_not_throw_and_signs() {
            var threw = false
            try { sl.values = [0.5] } catch (e) { threw = true }
            verify(!threw, "a single-point series must not throw (n<2 guard)")
            compare(sl._signature(), "1:0.5,", "single-point signature")
        }

        function test_signature_tracks_content() {
            sl.values = [0.2, 0.8]
            compare(sl._signature(), "2:0.2,0.8,", "signature encodes length + samples")
            sl.values = [0.2, 0.8, 0.5]
            compare(sl._signature(), "3:0.2,0.8,0.5,", "signature follows a reassignment")
        }

        function test_nonfinite_samples_marked_in_signature() {
            sl.values = [0.5, NaN, 0.7]
            compare(sl._signature(), "3:0.5,x,0.7,",
                    "a non-finite sample is encoded as 'x' so it is skipped, not drawn")
        }

        // _sig is refreshed on reassignment (onValuesChanged), so the poll timer
        // sees no spurious change on the next tick.
        function test_sig_refreshed_on_reassignment() {
            sl.values = [0.1, 0.9]
            compare(sl._sig, sl._signature(), "_sig is synced when values are reassigned")
        }

        // In-place mutation (history.push) fires no NOTIFY; the 100ms poll picks it
        // up and re-syncs _sig. This is the core "live sparkline" mechanism.
        function test_in_place_mutation_detected_by_poll() {
            sl.values = [0.1, 0.2]
            sl.values.push(0.3)                 // mutate in place, no reassignment
            verify(sl._sig !== sl._signature(), "the mutated array is not yet reflected in _sig")
            tryVerify(function () { return sl._sig === sl._signature() }, 1000,
                      "the poll timer re-syncs _sig after an in-place push")
        }

        // ── Out-of-range values are tolerated (Canvas clamps internally) ──────
        function test_out_of_range_values_do_not_throw() {
            var threw = false
            try { sl.values = [-3, 0.5, 42] } catch (e) { threw = true }
            verify(!threw, "out-of-range samples are accepted (clamped inside the Canvas Y())")
            compare(sl.values.length, 3, "values still stored")
        }
    }
}
