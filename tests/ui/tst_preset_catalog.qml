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
    App.WidgetConfigSchema { id: sc }
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

        // A preset ships per-tile `settings`, but nothing at runtime validates them:
        // an unknown key is silently ignored, so a typo (`listmax`) would ship a tile
        // that quietly doesn't do what the preset intends. Every key must therefore be
        // either universal (honoured by WidgetChrome for ANY widget, see
        // Dashboard.injectWidget) or declared in that type's config schema.
        function test_preset_settings_keys_are_real() {
            var universal = { "title": 1, "accent": 1, "cardBackdrop": 1 }
            var list = presets.list()
            for (var i = 0; i < list.length; i++) {
                var p = list[i]
                for (var pg = 0; pg < p.pages.length; pg++) {
                    var tiles = p.pages[pg].tiles
                    for (var t = 0; t < tiles.length; t++) {
                        if (!tiles[t].settings) continue
                        var known = ({})
                        var schema = sc.schemaFor(tiles[t].type)
                        for (var s = 0; s < schema.sections.length; s++) {
                            var fields = schema.sections[s].fields || []
                            for (var f = 0; f < fields.length; f++) known[fields[f].key] = 1
                        }
                        for (var k in tiles[t].settings)
                            verify(universal[k] === 1 || known[k] === 1,
                                   p.id + ": tile '" + tiles[t].type + "' setting '" + k +
                                   "' is a real config key (universal or in its schema)")
                    }
                }
            }
        }

        // The data-connected presets are the payoff of the primitive widgets (E1):
        // they must actually carry a data tile, and must ship it UNCONFIGURED — the
        // endpoint is the user's to supply, so a preset must never guess a URL (which
        // would poll a stranger's host on first run). A blank url/filePath also means
        // the widget's own polling stays off until the user connects it.
        function test_data_presets_ship_labelled_but_unconnected_tiles() {
            var expected = ["developer", "homelab", "trading-desk", "analyst", "enterprise"]
            for (var i = 0; i < expected.length; i++) {
                var p = presets.def(expected[i])
                verify(p !== null, expected[i] + " exists")
                var dataTiles = 0
                for (var pg = 0; pg < p.pages.length; pg++) {
                    var tiles = p.pages[pg].tiles
                    for (var t = 0; t < tiles.length; t++) {
                        var ty = tiles[t].type
                        if (ty !== "httpjson" && ty !== "kpi") continue
                        dataTiles++
                        var st = tiles[t].settings || {}
                        verify(st.title && st.title.length,
                               expected[i] + ": data tile is labelled (a named slot, not a bare 'HTTP / JSON')")
                        verify(!st.url, expected[i] + ": data tile ships with NO url — the user connects it")
                        verify(!st.filePath, expected[i] + ": data tile ships with NO filePath")
                    }
                }
                verify(dataTiles >= 1, expected[i] + " carries at least one HTTP/JSON or KPI tile")
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
