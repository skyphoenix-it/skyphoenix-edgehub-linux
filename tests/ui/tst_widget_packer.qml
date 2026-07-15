import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: fn:WidgetPacker.pack, fn:WidgetPacker.longExtent, fn:WidgetPacker.project
// COVERS: fn:WidgetPacker.rect, fn:WidgetPacker.snap, fn:WidgetPacker._grid
// COVERS: fn:WidgetPacker._free, fn:WidgetPacker._fill, fn:WidgetPacker._firstFit
//
// WidgetPacker — the placement authority that replaced GridLayout.
//
// The two properties that matter are asserted head-on, because they are the two
// things GridLayout got wrong and the two things a rewrite could quietly get wrong
// again:
//   1. A tile's size depends ONLY on the screen. GridLayout sized a row by what was
//      in it, so a 0.5x0.5 beside a 1x1 came out at half the screen instead of a
//      twelfth. (The pixel proof against the real Dashboard is in tst_dashboard.)
//   2. Rotation is a PROJECTION, not a re-pack. Orientation is not an input to
//      pack(), so the same page cannot resolve to two different layouts.
Item {
    id: root
    width: 200; height: 200

    App.WidgetPacker { id: packer }
    App.WidgetSizes { id: sz }

    // A tile as the store stores it. Only id/type/size are read.
    function t(id, size, type) { return ({ id: id, type: type || "kpi", size: size }) }

    // The placement of `id`, or null.
    function find(ps, id) {
        for (var i = 0; i < ps.length; i++) if (ps[i].id === id) return ps[i]
        return null
    }
    // "s,l,es,el" — a whole placement as one comparable string.
    function slot(p) { return p ? (p.s + "," + p.l + "," + p.es + "," + p.el) : "none" }

    TestCase {
        name: "WidgetPacker"
        when: windowShown

        // ── The baseline layout ──────────────────────────────────────────────
        // Three 1x1 tiles fill the screen exactly, stacked along the long axis.
        // This is the default dashboard; if it moves, everything has.
        function test_three_baselines_fill_the_screen_in_order() {
            var ps = packer.pack([ t("a", "1x1"), t("b", "1x1"), t("c", "1x1") ])
            compare(ps.length, 3, "every tile placed")
            compare(slot(ps[0]), "0,0,2,2", "first at the origin, full short axis, a third long")
            compare(slot(ps[1]), "0,2,2,2", "second directly after it")
            compare(slot(ps[2]), "0,4,2,2", "third directly after that")
            compare(packer.longExtent(ps), sz.longHalves, "the three of them fill the screen EXACTLY")
        }

        // ── First fit backfills; GridLayout only ever appended ───────────────
        // Two half-wide tiles share ONE long row. The append-only grid would have
        // started a new row for the second and left half the first one empty.
        function test_first_fit_backfills_the_short_axis() {
            var ps = packer.pack([ t("a", "0.5x1"), t("b", "0.5x1"), t("c", "1x1") ])
            compare(slot(ps[0]), "0,0,1,2", "a takes the first half")
            compare(slot(ps[1]), "1,0,1,2", "b takes the OTHER half of the same row — backfilled")
            compare(slot(ps[2]), "0,2,2,2", "c, needing the full short axis, starts the next row")
            compare(packer.longExtent(ps), 4, "three tiles in two thirds of the screen, no hole")
        }

        // The backfill that a purely-append packer cannot do: a hole left EARLIER in
        // the scan is filled by a later, smaller tile.
        function test_first_fit_fills_an_earlier_hole() {
            var ps = packer.pack([ t("a", "0.5x0.5"), t("b", "1x1"), t("c", "0.5x0.5") ])
            compare(slot(ps[0]), "0,0,1,1", "a takes one twelfth at the origin")
            compare(slot(ps[1]), "0,1,2,2", "b cannot fit beside a, so it starts after it")
            compare(slot(ps[2]), "1,0,1,1",
                    "c goes BACK into the gap beside a — the whole point of first fit")
        }

        // ── Determinism ──────────────────────────────────────────────────────
        function test_packing_the_same_page_twice_is_identical() {
            var tiles = [ t("a", "0.5x0.5"), t("b", "1x1.5"), t("c", "0.5x1"), t("d", "1x1") ]
            var one = packer.pack(tiles)
            var two = packer.pack(tiles)
            compare(JSON.stringify(two), JSON.stringify(one), "same tiles in, same placement out")
        }

        // ── ROTATION STABILITY — the reason packing is semantic ──────────────
        // There is only ONE packing, so there is nothing for a rotation to change.
        // Packing in physical coordinates scrambled 99.2% of 5-tile pages here.
        function test_rotation_cannot_change_the_packing() {
            var tiles = [ t("a", "0.5x1"), t("b", "0.5x0.5"), t("c", "1x1"),
                          t("d", "0.5x0.5"), t("e", "1x0.5") ]
            var ps = packer.pack(tiles)
            // pack() takes no orientation argument at all — the defining property.
            compare(packer.pack.length, 1, "pack() accepts ONLY the tiles: orientation cannot enter")
            for (var i = 0; i < ps.length; i++) {
                var p = ps[i]
                var portrait = packer.project(p, false)
                var land = packer.project(p, true)
                // Same semantic slot, both ways round — the tile is where it was.
                compare(land.x, portrait.y, p.id + ": the long axis moves from y to x, unchanged")
                compare(land.y, portrait.x, p.id + ": and the short axis from x to y")
                compare(land.w * land.h, portrait.w * portrait.h, p.id + ": rotation conserves area")
            }
        }

        // The projection agrees with WidgetSizes.halfUnits for the EXTENT — the two
        // must not drift, or a tile would be placed on one grid and sized on another.
        function test_project_extent_matches_halfUnits() {
            var all = sz.all()
            for (var i = 0; i < all.length; i++) {
                var ps = packer.pack([ t("x", all[i]) ])
                for (var o = 0; o < 2; o++) {
                    var land = (o === 1)
                    var h = sz.halfUnits(all[i], land)
                    compare(packer.project(ps[0], land).w, h.w, all[i] + ": projected width matches halfUnits")
                    compare(packer.project(ps[0], land).h, h.h, all[i] + ": projected height matches halfUnits")
                }
            }
        }

        // ── longExtent ───────────────────────────────────────────────────────
        function test_longExtent_measures_the_page_against_the_screen() {
            compare(packer.longExtent(packer.pack([])), 0, "an empty page reaches nowhere")
            compare(packer.longExtent(packer.pack([ t("a", "1x3") ])), 6,
                    "one full-screen tile is exactly one screen")
            compare(packer.longExtent(packer.pack([ t("a", "0.5x0.5") ])), 1, "a twelfth reaches one half-cell")
            // The overflow case the presets hit: six baseline tiles are two screens.
            var six = []
            for (var i = 0; i < 6; i++) six.push(t("t" + i, "1x1"))
            compare(packer.longExtent(packer.pack(six)), 12, "6 x 1x1 = TWO screens (12 half-cells)")
            compare(packer.longExtent(null), 0, "a null page is not a crash")
        }

        // Overflow is placed IN FULL — never dropped, never clipped away. The store
        // and the presets both produce over-long pages; they scroll (Dashboard.qml).
        function test_an_overlong_page_places_every_tile() {
            var many = []
            for (var i = 0; i < 9; i++) many.push(t("t" + i, "1x1"))
            var ps = packer.pack(many)
            compare(ps.length, 9, "all nine placed — capacity is not a thing the packer does")
            for (var j = 0; j < 9; j++)
                compare(slot(ps[j]), "0," + (j * 2) + ",2,2", "tile " + j + " runs on past the screen")
        }

        // ── A bad size is visible, never silently normal ──────────────────────
        function test_an_unknown_size_is_skipped_not_defaulted() {
            var ps = packer.pack([ t("a", "1x1"), t("bad", "2x2"), t("c", "1x1") ])
            compare(ps.length, 2, "the tile with an unknown size is not placed")
            compare(find(ps, "bad"), null, "and it is certainly not silently made a 1x1")
            compare(find(ps, "c").idx, 2, "the survivors keep their index in the STORE's tile array")
        }

        function test_pack_tolerates_junk_input() {
            compare(packer.pack(null).length, 0, "a null page packs to nothing")
            compare(packer.pack([]).length, 0, "an empty page packs to nothing")
            compare(packer.pack([ null, t("a", "1x1") ]).length, 1, "a null tile is skipped, not a throw")
        }

        // ── rect: the semantic slot in pixels ─────────────────────────────────
        // THE HEADLINE: on a page whose cells come from the SCREEN, a 0.5x0.5 beside
        // a 1x1 is a twelfth. Under GridLayout it measured half the screen.
        function test_rect_sizes_a_half_by_half_at_one_twelfth() {
            // A 1200px-long, 240-short page: cellShort 120, cellLong 200.
            var ps = packer.pack([ t("small", "0.5x0.5"), t("big", "1x1") ])
            var small = packer.rect(find(ps, "small"), false, 120, 200, 0)
            var big = packer.rect(find(ps, "big"), false, 120, 200, 0)
            compare(packer.rect(find(ps, "small"), false, 120, 200, 0).width, 120, "half the short axis")
            compare(small.height, 200, "and one sixth of the long axis: a TWELFTH of the screen")
            compare(big.width, 240, "its 1x1 neighbour is unaffected: the full short axis")
            compare(big.height, 400, "and a third of the long axis")
            verify(small.width * small.height < big.width * big.height / 3.9,
                   "the twelfth is a quarter of the third, not equal to it")
        }

        function test_rect_projects_and_insets_the_gap() {
            var ps = packer.pack([ t("a", "1x1"), t("b", "1x1") ])
            // Portrait: long = y.
            var p = packer.rect(ps[1], false, 120, 200, 0)
            compare(p.x, 0); compare(p.y, 400, "portrait: the second third is 400px DOWN")
            // Landscape: the same slot, long = x.
            var l = packer.rect(ps[1], true, 120, 200, 0)
            compare(l.x, 400, "landscape: the same third is 400px ACROSS")
            compare(l.y, 0)
            compare(l.width, 400); compare(l.height, 240, "and it is transposed, not moved")
            // The gap comes out of the TILE — the grid stays screen/(2x6) exactly, so
            // the tile centres do not move when the gap changes.
            var g = packer.rect(ps[1], false, 120, 200, 20)
            compare(g.x, 10, "half a gap of inset")
            compare(g.y, 410, "the slot origin is untouched by the gap")
            compare(g.width, 240 - 20, "a full gap comes out of the width")
            compare(g.height, 400 - 20, "and out of the height")
            compare(g.x + g.width / 2, p.x + p.width / 2, "so the tile's CENTRE does not move")
        }

        // ── snap: a free-form drag onto a legal, SUPPORTED size ──────────────
        function test_snap_picks_the_nearest_size_the_type_declares() {
            // cellShort 100, cellLong 100 → 1x1 is 200x200, 0.5x0.5 is 100x100.
            var cpu = ["0.5x0.5", "0.5x1", "1x0.5", "1x1", "1x1.5"]
            compare(packer.snap(cpu, 205, 195, 100, 100), "1x1", "a box near 1x1 snaps to it")
            compare(packer.snap(cpu, 95, 105, 100, 100), "0.5x0.5", "a small box snaps to the twelfth")
            compare(packer.snap(cpu, 190, 310, 100, 100), "1x1.5", "a tall box snaps to the half screen")
            compare(packer.snap(cpu, 90, 210, 100, 100), "0.5x1", "a narrow tall box snaps to the sixth")
            // A drag WAY past everything cannot invent a bigger size than cpu declares.
            compare(packer.snap(cpu, 9999, 9999, 100, 100), "1x1.5",
                    "a runaway drag stops at the largest size the TYPE allows — never 1x3")
        }

        function test_snap_never_offers_a_size_the_type_lacks() {
            var focus = ["1x1", "1x1.5"]        // focus needs a squarish box; it has only two
            var sizesSeen = {}
            for (var pxS = 20; pxS <= 400; pxS += 20)
                for (var pxL = 20; pxL <= 700; pxL += 20)
                    sizesSeen[packer.snap(focus, pxS, pxL, 100, 100)] = true
            var keys = Object.keys(sizesSeen)
            keys.sort()
            compare(keys.join(","), "1x1,1x1.5",
                    "across 380 drag boxes, snap NEVER proposed anything outside the type's list")
        }

        function test_snap_ties_keep_the_smaller_size() {
            // Exactly between 0.5x0.5 (100x100) and 1x1 (200x200): the scan is strict
            // `<` over a smallest-first list, so a tie must not claim more screen.
            compare(packer.snap(["0.5x0.5", "1x1"], 150, 150, 100, 100), "0.5x0.5",
                    "a drag exactly between two sizes keeps the smaller")
        }

        function test_snap_refuses_when_there_is_nothing_to_snap_to() {
            compare(packer.snap([], 100, 100, 100, 100), "", "an unknown type offers no size at all")
            compare(packer.snap(null, 100, 100, 100, 100), "", "and neither does a null list")
            compare(packer.snap(["2x2", "nonsense"], 100, 100, 100, 100), "",
                    "sizes that are not real sizes are skipped, not snapped to")
        }

        // ── The occupancy grid, directly ─────────────────────────────────────
        // `_free` is a PROBE: first fit calls it past the end of the grid on every
        // scan, so growing there would corrupt the packing it is measuring.
        function test_grid_free_fill_and_firstFit() {
            var g = packer._grid()
            compare(g.cols, sz.shortHalves, "_grid is 2 half-cells across the SHORT axis")
            compare(g.rows.length, 0, "and unbounded along the long axis — it starts empty")

            verify(packer._free(g, 0, 0, 2, 2), "an empty grid is free")
            verify(packer._free(g, 0, 99, 2, 6), "_free probes far past the end without growing it")
            compare(g.rows.length, 0, "the probe really did not grow the grid")

            packer._fill(g, 0, 0, 1, 2, "a")
            compare(g.rows.length, 2, "_fill grew the grid to fit")
            verify(!packer._free(g, 0, 0, 1, 1), "the filled cell is taken")
            verify(packer._free(g, 1, 0, 1, 2), "its neighbour on the short axis is not")

            compare(JSON.stringify(packer._firstFit(g, 1, 2)), JSON.stringify({ s: 1, l: 0 }),
                    "_firstFit finds the free half beside it")
            compare(JSON.stringify(packer._firstFit(g, 2, 2)), JSON.stringify({ s: 0, l: 2 }),
                    "_firstFit appends when nothing among the used rows fits")
        }
    }
}
