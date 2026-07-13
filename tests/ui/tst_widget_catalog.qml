import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: widget:*

// WidgetCatalog (ui/qml/WidgetCatalog.qml) — the registry every widget picker,
// the grid and the expanded overlay read from. Assert every entry is complete,
// the lookup helpers behave, categories are well-formed, and every `source`
// resolves to a real widget file in ui/qml/widgets.
Item {
    id: root
    width: 300; height: 300
    App.WidgetCatalog { id: catalog }

    // Context globals so a widget under test loads cleanly (like WidgetHarness),
    // letting us distinguish a present file (Loader.Ready) from a missing one
    // (Loader.Error). XHR file-reads are blocked under the default harness env,
    // so a Loader is the reliable existence probe.
    property alias theme: _theme
    App.Theme { id: _theme }
    App.DashboardStore { id: store }
    MockMedia { id: media }
    property var metrics: ({})
    property int tick: 0
    property bool expanded: false
    property bool active: true
    Loader { id: probe; anchors.fill: parent; visible: false }

    function fileExists(relPath) {
        probe.source = ""
        probe.source = relPath          // local load is synchronous
        return probe.status === Loader.Ready
    }

    TestCase {
        name: "WidgetCatalog"
        when: windowShown

        function test_items_non_empty() {
            verify(catalog.items.length > 0, "catalog has widgets")
        }

        function test_every_entry_is_complete() {
            var seen = {}
            for (var i = 0; i < catalog.items.length; i++) {
                var it = catalog.items[i]
                verify(it.type && it.type.length > 0, "entry has a type")
                verify(it.title && it.title.length > 0, it.type + " has a title")
                verify(it.category && it.category.length > 0, it.type + " has a category")
                verify(it.source && it.source.length > 0, it.type + " has a source")
                verify(it.defaults !== undefined, it.type + " has a defaults object")
                verify(seen[it.type] === undefined, "duplicate type: " + it.type)
                seen[it.type] = true
            }
        }

        // def / source / title / desc / defaults helpers.
        function test_lookup_helpers() {
            var d = catalog.def("cpu")
            verify(d !== null && d.type === "cpu", "def returns the cpu entry")
            compare(catalog.source("cpu"), "qrc:/qml/CpuWidget.qml", "source() resolves")
            compare(catalog.title("cpu"), "CPU", "title() resolves")
            verify(catalog.desc("cpu").length > 0, "desc() returns a description")
            compare(catalog.def("nonexistent"), null, "def of an unknown type is null")
            compare(catalog.title("nonexistent"), "nonexistent", "title() falls back to the type")
        }

        // defaults() deep-clones so callers can't mutate the catalog's seed.
        function test_defaults_are_deep_cloned() {
            var a = catalog.defaults("focus")
            var b = catalog.defaults("focus")
            verify(a !== b, "each defaults() call returns a fresh object")
            a.preset = "MUTATED"
            compare(catalog.defaults("focus").preset, "classic",
                    "mutating a returned defaults object does not poison the catalog")
        }

        // ── Categories ───────────────────────────────────────────────────────
        function test_categories_non_empty_and_unique() {
            var cats = catalog.categories()
            verify(cats.length > 0, "at least one category")
            var seen = {}
            for (var i = 0; i < cats.length; i++) {
                verify(seen[cats[i]] === undefined, "duplicate category: " + cats[i])
                seen[cats[i]] = true
            }
        }

        function test_categories_in_declaration_order() {
            // First declared entry is 'cpu' → 'System'.
            compare(catalog.categories()[0], "System", "first category follows declaration order")
        }

        function test_inCategory_correctness() {
            var cats = catalog.categories()
            var total = 0
            for (var c = 0; c < cats.length; c++) {
                var members = catalog.inCategory(cats[c])
                verify(members.length > 0, cats[c] + " has members")
                for (var m = 0; m < members.length; m++)
                    compare(members[m].category, cats[c], "every member is in " + cats[c])
                total += members.length
            }
            compare(total, catalog.items.length, "every item belongs to exactly one category bucket")
            compare(catalog.inCategory("NoSuchCategory").length, 0, "an unknown category yields nothing")
        }

        // ── Every source resolves to a real widget file ──────────────────────
        function test_every_source_file_exists() {
            for (var i = 0; i < catalog.items.length; i++) {
                var src = catalog.items[i].source
                // "qrc:/qml/CpuWidget.qml" → the source-tree file under ui/qml/widgets.
                var base = src.substring(src.lastIndexOf("/") + 1)
                var rel = "../../ui/qml/widgets/" + base
                verify(fileExists(rel), catalog.items[i].type + " source file exists: " + base)
            }
        }
    }
}
