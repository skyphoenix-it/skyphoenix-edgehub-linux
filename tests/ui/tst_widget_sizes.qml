import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: fn:WidgetSizes.isLegal, fn:WidgetSizes.all, fn:WidgetSizes.area
// COVERS: fn:WidgetSizes.halfUnits, fn:WidgetSizes.gridColumns, fn:WidgetSizes.gridRows
// COVERS: fn:WidgetSizes.isFullScreen
//
// WidgetSizes - the fixed size set. These tests are the SPEC:
//   1x1 = 1/3 of the display (the baseline; 3 of them fill it)
//   0.5x1 and 1x0.5 = 1/6 · 0.5x0.5 = 1/12 · 1x1.5 = 1/2 · 1x2 = 2/3 · 1x3 = all
// The fractions are asserted as literals, not recomputed from the table, so a
// change to the table has to change these numbers - which is the point.
Item {
    App.WidgetSizes { id: sz }

    TestCase {
        name: "WidgetSizes"
        when: windowShown

        // The spec, verbatim.
        function test_areas_match_the_specified_fractions() {
            fuzzyCompare(sz.area("1x1"), 1 / 3, 1e-9, "1x1 is a THIRD of the display - the baseline")
            fuzzyCompare(sz.area("0.5x1"), 1 / 6, 1e-9, "0.5x1 is a sixth")
            fuzzyCompare(sz.area("1x0.5"), 1 / 6, 1e-9, "1x0.5 is a sixth")
            fuzzyCompare(sz.area("0.5x0.5"), 1 / 12, 1e-9, "0.5x0.5 is a twelfth")
            fuzzyCompare(sz.area("1x1.5"), 1 / 2, 1e-9, "1x1.5 is half the display")
            fuzzyCompare(sz.area("1x2"), 2 / 3, 1e-9, "1x2 is two thirds")
            fuzzyCompare(sz.area("1x3"), 1, 1e-9, "1x3 is the ENTIRE display")
            compare(sz.area("nonsense"), 0, "an unknown size has no area")
        }

        // The headline promise: the default screen is three 1x1 widgets, and they
        // exactly fill it. If this ever fails the baseline is wrong.
        function test_three_baseline_widgets_fill_the_screen() {
            fuzzyCompare(sz.area(sz.baseline) * 3, 1, 1e-9,
                         "3 x 1x1 fills the display exactly - the default layout")
            compare(sz.baseline, "1x1")
        }

        function test_only_the_seven_sizes_are_legal() {
            compare(sz.all().length, 7, "exactly seven sizes: " + sz.all().join(", "))
            verify(sz.isLegal("1x1"))
            verify(sz.isLegal("0.5x0.5"))
            verify(!sz.isLegal("2x2"), "the old span vocabulary is NOT a size")
            verify(!sz.isLegal("1x2.5"), "an unlisted fraction is illegal")
            verify(!sz.isLegal(""), "empty is illegal")
            verify(!sz.isLegal("constructor"),
                   "a prototype key is not a size (the table is user/file-fed)")
        }

        function test_all_is_ordered_smallest_first() {
            var a = sz.all()
            for (var i = 1; i < a.length; i++)
                verify(sz.area(a[i]) >= sz.area(a[i - 1]),
                       a[i - 1] + " (" + sz.area(a[i - 1]) + ") <= " + a[i] + " (" + sz.area(a[i]) + ")")
            compare(a[0], "0.5x0.5", "smallest first")
            compare(a[a.length - 1], "1x3", "largest last")
        }

        // ── Orientation ──────────────────────────────────────────────────────
        // The device rotates and main.qml SWAPS the container's width/height, so the
        // dashboard really re-lays-out. "Three widgets, each a third" must hold both
        // ways: they run DOWN the screen in portrait and ACROSS it in landscape.
        function test_portrait_puts_the_thirds_down_the_screen() {
            var u = sz.halfUnits("1x1", false)
            compare(u.w, 2, "1x1 spans the full width (2 half-cells) in portrait")
            compare(u.h, 2, "and a third of the height (2 of 6 half-cells)")
            compare(sz.gridColumns(false), 2, "portrait grid is 2 half-cells wide")
            compare(sz.gridRows(false), 6, "and 6 half-cells tall")
        }

        function test_landscape_transposes_the_grid() {
            var u = sz.halfUnits("1x1", true)
            compare(u.w, 2, "1x1 is a third of the WIDTH in landscape (2 of 6)")
            compare(u.h, 2, "and the full height (2 half-cells)")
            compare(sz.gridColumns(true), 6, "the grid transposes: 6 across")
            compare(sz.gridRows(true), 2, "2 down")
        }

        // 1x3 is the whole screen in BOTH orientations - the case that would break
        // if the names were pinned to width/height instead of short/long.
        function test_full_screen_is_full_screen_in_either_orientation() {
            var p = sz.halfUnits("1x3", false), l = sz.halfUnits("1x3", true)
            compare(p.w, 2); compare(p.h, 6, "portrait: full width, all 6 rows")
            compare(l.w, 6); compare(l.h, 2, "landscape: all 6 columns, full height")
            compare(p.w * p.h, l.w * l.h, "same number of half-cells either way")
            verify(sz.isFullScreen("1x3"))
            verify(!sz.isFullScreen("1x2"))
        }

        // The half-axis follows the SHORT screen axis, so it flips physical meaning.
        function test_the_half_splits_the_short_axis_in_both_orientations() {
            var p = sz.halfUnits("0.5x1", false)
            compare(p.w, 1, "portrait: 0.5 halves the WIDTH")
            compare(p.h, 2, "and it is still a third tall")
            var l = sz.halfUnits("0.5x1", true)
            compare(l.w, 2, "landscape: still a third along the long axis")
            compare(l.h, 1, "but 0.5 now halves the HEIGHT")
        }

        function test_every_size_fits_inside_the_grid() {
            var names = sz.all()
            for (var i = 0; i < names.length; i++) {
                for (var o = 0; o < 2; o++) {
                    var land = (o === 1)
                    var u = sz.halfUnits(names[i], land)
                    verify(u.w >= 1 && u.h >= 1, names[i] + " occupies at least one half-cell")
                    verify(u.w <= sz.gridColumns(land),
                           names[i] + " fits the grid width in " + (land ? "landscape" : "portrait"))
                    verify(u.h <= sz.gridRows(land),
                           names[i] + " fits the grid height in " + (land ? "landscape" : "portrait"))
                }
            }
        }

        // COVERS: fn:WidgetSizes.semiUnits
        // Packing must happen in THIS space. Packing in physical coordinates makes a
        // rotation re-pack into a different layout (measured: 99.2% of 5-tile pages
        // scramble); in semantic space orientation is not an input, so there is one
        // packing and rotation is a pure projection.
        function test_semiUnits_is_orientation_free() {
            var u = sz.semiUnits("0.5x1")
            compare(u.s, 1, "half the short axis")
            compare(u.l, 2, "a third of the long axis")
            // The defining property: no orientation argument exists, so the same size
            // cannot yield two different packings.
            compare(JSON.stringify(sz.semiUnits("1x1")), JSON.stringify({ s: 2, l: 2 }))
            compare(JSON.stringify(sz.semiUnits("1x3")), JSON.stringify({ s: 2, l: 6 }))
            compare(sz.semiUnits("2x2"), null, "an unknown size has no units")
        }

        // halfUnits is semiUnits PROJECTED - the projection is the only place
        // orientation may enter.
        function test_halfUnits_is_semiUnits_projected() {
            var names = sz.all()
            for (var i = 0; i < names.length; i++) {
                var u = sz.semiUnits(names[i])
                var p = sz.halfUnits(names[i], false)
                var l = sz.halfUnits(names[i], true)
                compare(p.w, u.s, names[i] + ": portrait width is the SHORT axis")
                compare(p.h, u.l, names[i] + ": portrait height is the LONG axis")
                compare(l.w, u.l, names[i] + ": landscape width is the LONG axis")
                compare(l.h, u.s, names[i] + ": landscape height is the SHORT axis")
                compare(p.w * p.h, l.w * l.h, names[i] + ": rotation conserves area")
            }
        }

        function test_unknown_size_yields_null_not_a_default() {
            // Must NOT silently become 1x1: a bad value has to be visible.
            compare(sz.halfUnits("2x2", false), null)
            compare(sz.halfUnits("", true), null)
        }

    }
}
