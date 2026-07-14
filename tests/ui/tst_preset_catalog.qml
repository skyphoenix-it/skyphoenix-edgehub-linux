import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: fn:PresetCatalog.list, fn:PresetCatalog.def, fn:PresetCatalog.has, fn:PresetCatalog.buildDoc
//
// The curated preset library (ui/qml/PresetCatalog.qml) drives the first-run
// "choose a screen" picker and DashboardStore.seed(). These tests guarantee the
// presets are well-formed, NOT overloaded, reference only real widget types, and
// apply cleanly through the real store (which hardens them via _normaliseDoc).
Item {
    id: root
    width: 100; height: 100

    App.PresetCatalog { id: presets }
    App.WidgetCatalog { id: catalog }
    App.DashboardStore { id: store }
    // The store resolves `configBridge` by unqualified name via the scope chain;
    // null = no persistence bridge (pure in-memory), so nothing touches disk.
    property var configBridge: null

    TestCase {
        name: "PresetCatalog"
        when: windowShown

        function test_library_size_and_unique_ids() {
            var list = presets.list()
            verify(list.length >= 12, "at least 12 curated presets, got " + list.length)
            verify(list.length <= 20, "not an unbounded dump, got " + list.length)
            var ids = ({})
            for (var i = 0; i < list.length; i++) {
                var p = list[i]
                verify(p.id && p.id.length, "preset has an id")
                verify(!ids[p.id], "unique preset id: " + p.id)
                ids[p.id] = 1
                verify(p.title && p.title.length, p.id + " has a title")
                verify(p.blurb && p.blurb.length, p.id + " has a blurb")
                verify(p.pages && p.pages.length >= 1, p.id + " has at least one page")
            }
        }

        // Every preset tile type MUST exist in WidgetCatalog, and no page may be
        // overloaded (the user requirement: purposeful, well-defined, not a dump).
        function test_tiles_exist_and_not_overloaded() {
            var list = presets.list()
            for (var i = 0; i < list.length; i++) {
                var p = list[i]
                for (var pg = 0; pg < p.pages.length; pg++) {
                    var tiles = p.pages[pg].tiles
                    verify(tiles.length >= 1 && tiles.length <= 6,
                           p.id + " page '" + p.pages[pg].name + "' has 1-6 tiles (not overloaded), got " + tiles.length)
                    for (var t = 0; t < tiles.length; t++) {
                        verify(catalog.def(tiles[t].type) !== null,
                               p.id + ": tile type '" + tiles[t].type + "' exists in WidgetCatalog")
                    }
                }
            }
        }

        // buildDoc materializes a valid ui_state with unique tile ids.
        function test_buildDoc_valid_unique_ids() {
            var list = presets.list()
            for (var i = 0; i < list.length; i++) {
                var doc = presets.buildDoc(list[i].id)
                verify(doc && doc.pages && doc.pages.length >= 1, list[i].id + " buildDoc has pages")
                compare(doc.version, 1, "doc version")
                var seen = ({})
                for (var pg = 0; pg < doc.pages.length; pg++) {
                    var tiles = doc.pages[pg].tiles
                    for (var t = 0; t < tiles.length; t++) {
                        var id = tiles[t].id
                        verify(id && !seen[id], list[i].id + ": unique tile id " + id)
                        seen[id] = 1
                        verify(tiles[t].type && tiles[t].type.length, "tile has a type")
                    }
                }
            }
        }

        // Every preset applies through the REAL store (which normalises/hardens it).
        function test_buildDoc_applies_through_store() {
            var list = presets.list()
            for (var i = 0; i < list.length; i++) {
                var doc = presets.buildDoc(list[i].id)
                var ok = store.applyExternal(JSON.stringify(doc))
                verify(ok, list[i].id + " applies through the store")
                compare(store.pages().length, doc.pages.length, list[i].id + " page count preserved")
            }
        }

        function test_unknown_id_is_null() {
            compare(presets.def("does-not-exist"), null)
            compare(presets.buildDoc("does-not-exist"), null)
            verify(!presets.has("does-not-exist"))
            verify(presets.has("productivity"), "legacy 'productivity' id is a preset")
        }

        // DashboardStore.seed() routes through the preset library; "blank" stays blank.
        function test_store_seed_uses_presets() {
            store.load("gaming")
            verify(store.pages().length >= 1, "seeding 'gaming' produced a layout")
            store.load("minimal")
            verify(store.pages().length >= 1, "seeding 'minimal' produced a layout")
            store.load("blank")
            compare(store.pages().length, 1, "blank has one page")
            compare(store.pages()[0].tiles.length, 0, "blank page has no tiles")
        }
    }
}
