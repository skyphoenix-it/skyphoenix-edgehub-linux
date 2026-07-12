import QtQuick
import QtTest
import "../../ui/qml" as App

// Coverage for the page-level store functions added for per-page backgrounds,
// per-page columns, and unique page naming.
Item {
    width: 100; height: 100
    App.DashboardStore { id: store }

    TestCase {
        name: "StorePages"
        when: windowShown
        function init() { store.load("blank") }

        function test_unique_page_names() {
            // Blank layout starts with one "Home" page.
            store.addPage("")
            store.addPage("")
            var names = store.pages().map(function (p) { return p.name })
            var seen = {}
            for (var i = 0; i < names.length; i++) {
                verify(seen[names[i]] === undefined, "page name not duplicated: " + names[i])
                seen[names[i]] = true
            }
        }

        function test_unique_name_avoids_collision() {
            // Force a collision: rename to the name addPage would pick, then add.
            store.addPage("")           // now 2 pages
            store.renamePage(1, "Page 3")
            store.addPage("")           // would want "Page 3" → must skip to "Page 4"
            var names = store.pages().map(function (p) { return p.name })
            compare(names.filter(function (n) { return n === "Page 3" }).length, 1)
        }

        function test_per_page_background() {
            compare(store.pageBackground(0).style, undefined)
            store.setPageBackground(0, "style", "waves")
            compare(store.pageBackground(0).style, "waves")
            store.setPageBackground(0, "wallpaper", "/tmp/a.png")
            compare(store.pageBackground(0).wallpaper, "/tmp/a.png")
            // Empty clears the override (fall back to global).
            store.setPageBackground(0, "style", "")
            compare(store.pageBackground(0).style, undefined)
        }

        function test_per_page_columns() {
            compare(store.pageColumns(0), 0)         // 0 = use global
            store.setPageColumns(0, 2)
            compare(store.pageColumns(0), 2)
            store.setPageColumns(0, 0)               // clear
            compare(store.pageColumns(0), 0)
        }

        function test_global_gridcols_appearance() {
            store.setAppearance("gridCols", 2)
            compare(store.appearance().gridCols, 2)
            store.setAppearance("orientation", "landscape")
            compare(store.appearance().orientation, "landscape")
        }

        function test_bounds_guarded() {
            // Out-of-range page indices must not throw.
            store.setPageBackground(99, "style", "orbs")
            store.setPageColumns(-1, 2)
            compare(store.pageBackground(99).style, undefined)
            verify(true)
        }
    }
}
