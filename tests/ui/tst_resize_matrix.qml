import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: fn:DashboardStore.setTileSize
//
// The RESIZE MATRIX (O3). tst_store_tiles sweeps the whole size vocabulary for a
// SINGLE type (kpi, the one that declares all seven) and resizes exactly one
// widget (clock) in e2e_buildup. Neither proves the catalog-wide claim: that for
// EVERY widget type, EVERY size it declares in WidgetCatalog is one the store
// will actually apply and report back verbatim.
//
// This is that proof. For each (type, size) the catalog declares, it drives a
// real resize through the store's public setTileSize() and asserts the stored
// size equals the requested one - a genuine round-trip that CAN fail:
//   • setTileSize returns false  → the store REFUSED a size the catalog swears
//     the widget can render (a catalog/store disagreement, a real bug);
//   • the stored size differs     → the store SILENTLY COERCED a legal declared
//     size to something else (the coercion rule at DashboardStore.qml ~144 must
//     leave legal, type-supported sizes untouched - if it doesn't, that is a
//     real bug, surfaced here rather than papered over by a looser assertion).
//
// Every size fed here is pulled straight from the catalog, so it is legal AND
// type-supported by construction; the ONLY honest outcome is an exact round-trip.
Item {
    width: 100; height: 100
    App.DashboardStore { id: store }
    App.WidgetSizes { id: sizes }
    App.WidgetCatalog { id: catalog }

    // Guard against a vacuous data-driven pass: a data function that returns zero
    // rows makes test_resize "pass" without asserting anything. This fails loudly
    // if the catalog (or the matrix built from it) ever collapses to near-empty.
    TestCase {
        name: "ResizeMatrixPopulated"
        when: windowShown

        function test_matrix_covers_the_whole_catalog() {
            var items = catalog.items
            verify(items.length >= 20,
                   "the catalog must list every widget type, got " + items.length)
            var combos = 0
            for (var i = 0; i < items.length; i++) {
                var szs = items[i].sizes || []
                verify(szs.length >= 1,
                       "every type declares at least the 1x1 baseline (" +
                       items[i].type + " declares " + szs.length + ")")
                combos += szs.length
            }
            // Empirically 149 today; the floor guards against a matrix that has
            // silently shrunk to nothing (the vacuous-pass trap) without pinning
            // an exact number the catalog is free to grow.
            verify(combos >= 100,
                   "the resize matrix must cover the whole catalog, got " + combos +
                   " (type,size) combinations")
        }
    }

    TestCase {
        name: "ResizeMatrix"
        when: windowShown

        // A fresh blank "Home" page before EACH data row (QtTest calls init/cleanup
        // around every row), so the resize under test is always the only tile on the
        // page - no sibling can steal the one-screen budget and mask a real refusal.
        function init() { store.load("blank") }

        // One named row per (type, size) the catalog declares.
        function test_resize_data() {
            var rows = {}
            var items = catalog.items
            for (var i = 0; i < items.length; i++) {
                var type = items[i].type
                var szs = items[i].sizes || []
                for (var j = 0; j < szs.length; j++)
                    rows[type + " @ " + szs[j]] = { type: type, size: szs[j] }
            }
            return rows
        }

        function test_resize(row) {
            // Preconditions: the matrix only ever feeds legal, type-supported sizes,
            // so an exact round-trip is the only honest outcome. If either fails the
            // catalog itself is inconsistent - assert them so a bad row is diagnosed
            // as a catalog fault, not misread as a store fault below.
            verify(sizes.isLegal(row.size),
                   "precondition: " + row.size + " is a legal WidgetSizes name")
            verify(catalog.supports(row.type, row.size),
                   "precondition: " + row.type + " declares " + row.size)

            var id = store.addTile(0, row.type)
            verify(id, "a " + row.type + " tile was added")

            var ok = store.setTileSize(0, id, row.size)
            verify(ok, "setTileSize must ACCEPT the declared size " + row.size +
                       " for " + row.type + " (refusal = catalog/store disagreement)")

            // The load-bearing, failable assertion: the store reports back EXACTLY
            // the size requested. A different value means a legal declared size was
            // silently coerced - a real bug, not something to loosen away.
            compare(store.pages()[0].tiles[0].size, row.size,
                    "the store must report the requested size verbatim (round-trip)")
        }
    }
}
