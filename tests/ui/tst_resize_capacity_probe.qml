import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: fn:DashboardStore.fittingSizesFor

// Probe: does setTileSize enforce page capacity? Fill a page, then try to grow a
// widget (must be REFUSED when the page is full) and shrink one (must succeed and
// must NOT overflow / pull from another page). Isolates the store logic from any
// render/preview behaviour. This is the case O3's matrix never hit (it put one
// widget per page).
Item {
    App.DashboardStore { id: store }

    TestCase {
        name: "ResizeCapacityProbe"
        when: windowShown

        function init() { store.load("blank") }

        function fitsOneScreen() {
            var tiles = store.pages()[0].tiles.map(function (t) {
                return { id: t.id, type: t.type, size: t.size }
            })
            return store._packer.longExtent(store._packer.pack(tiles)) <= store._sizes.longHalves
        }

        // Fill page 0 with CPU tiles (each 1x0.5 default) until the page reports full.
        function fillPage() {
            var ids = []
            for (var i = 0; i < 40 && !store.pageIsFull(0); i++) {
                var id = store.addTile(0, "cpu")
                if (!id || store.pageIndexForTile(id) !== 0) break   // spilled to a new page
                ids.push(id)
            }
            return ids
        }

        function test_grow_on_full_page_is_refused() {
            var ids = fillPage()
            verify(ids.length >= 2, "filled the page with " + ids.length + " tiles")
            verify(store.pageIsFull(0), "page reports full")
            verify(fitsOneScreen(), "full page fits one screen before any resize")

            // Try to GROW the last tile to the biggest size CPU supports.
            var sizes = store._catalogSizesFor ? store._catalogSizesFor("cpu") : null
            // Fall back: 1x1.5 is CPU's largest per WidgetCatalog.
            var big = "1x1.5"
            var before = store.pages()[0].tiles.length
            var ok = store.setTileSize(0, ids[ids.length - 1], big)

            // The store MUST refuse a grow that would overflow, and the page must
            // still fit one screen. A pass here that overflows is THE bug.
            verify(fitsOneScreen(),
                   "after attempting to grow the last tile to " + big
                   + ", the page STILL fits one screen (setTileSize returned " + ok + ")")
            compare(store.pages()[0].tiles.length, before,
                    "the grow did not silently move tiles to another page")
        }

        // B1/B2: the resize DRAG preview snaps only among fittingSizesFor(), so
        // it can never offer a size that overflows the page. This is the
        // deterministic guarantee behind "make bigger with no room doesn't move"
        // and "no transient overflow/scroll while dragging". Proves the store
        // helper the EdgeClone drag relies on actually caps the offered sizes.
        function test_fittingSizes_cap_the_resize_preview_on_a_full_page() {
            var ids = fillPage()
            verify(ids.length >= 2, "page filled with " + ids.length + " tiles")
            verify(store.pageIsFull(0), "page reports full")

            var last = ids[ids.length - 1]
            var declared = store._catalogFn("sizesFor")("cpu") || []
            var fitting = store.fittingSizesFor(0, last)

            compare(store.fittingSizesFor(0, last).join(","), fitting.join(","),
                    "fittingSizesFor is stable for an unchanged full-page layout")
            verify(fitting.length >= 1, "at least the current size fits")
            verify(fitting.length <= declared.length, "fitting is a subset of declared")
            // On a FULL page, a bigger size must NOT be offered: every fitting
            // size, applied, must keep the page within one screen.
            for (var i = 0; i < fitting.length; i++) {
                var probe = store.pages()[0].tiles.map(function (t) {
                    return { id: t.id, type: t.type, size: (t.id === last ? fitting[i] : t.size) }
                })
                verify(store._packer.longExtent(store._packer.pack(probe)) <= store._sizes.longHalves,
                       "offered size '" + fitting[i] + "' keeps the page one screen")
            }
            // And the widget's LARGEST declared size must be excluded on a full
            // page (else the preview could still overflow). CPU's largest is 1x1.5.
            verify(fitting.indexOf("1x1.5") < 0 || declared.indexOf("1x1.5") < 0,
                   "the largest size is not offered when it would overflow")
        }

        function test_shrink_frees_space_no_overflow_no_crosspage_pull() {
            // Two pages: page 0 full-ish, page 1 has a distinctive tile.
            store.load("blank")
            var a = store.addTile(0, "cpu")
            var b = store.addTile(0, "gpu")
            store.setTileSize(0, a, "1x1")
            store.setTileSize(0, b, "1x1")
            store.addPage("")
            var marker = store.addTile(1, "notes")
            var p1_before = store.pages()[1].tiles.length

            // Shrink a tile on page 0 — frees space.
            store.setTileSize(0, a, "0.5x0.5")

            verify(fitsOneScreen(), "page 0 still fits one screen after shrinking")
            // The freed space must NOT have pulled the marker tile off page 1.
            compare(store.pages()[1].tiles.length, p1_before,
                    "shrinking a tile on page 0 did NOT pull tiles from page 1")
            compare(store.pageIndexForTile(marker), 1,
                    "the page-1 marker tile stayed on page 1 (no cross-page bleed)")
        }
    }
}
