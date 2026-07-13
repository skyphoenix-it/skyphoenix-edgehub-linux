import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: fn:DashboardStore._isPlainObject
//
// Robustness (Phase 3a): `_normaliseDoc` is a real VALIDATOR. A corrupt or hostile
// UI-state document — pushed over the control socket (applyExternal) or read from a
// clobbered config.toml (load) — must SELF-HEAL into a well-formed structure rather
// than reaching the page/tile Repeater and `addTile` as a number/string/id-less
// object → TypeError → blank dashboard. Both entry points share `_normaliseDoc`, so
// each malformed shape is exercised end-to-end through applyExternal AND directly
// through _normaliseDoc (the coercion the load path applies to the parsed object).
Item {
    width: 100; height: 100
    App.DashboardStore { id: store }

    TestCase {
        name: "StoreValidation"
        when: windowShown
        function init() { store.load("blank") }

        // "pages":5 — a non-array pages field is discarded to an empty array.
        function test_pages_number_self_heals() {
            var ok = store.applyExternal('{"pages":5}')
            verify(ok, "applyExternal accepted (truthy pages) and did not throw")
            verify(Array.isArray(store.pages()), "pages() is an array")
            compare(store.pageCount(), 0, "junk pages coerced to []")
        }

        // "pages":{} — an object (not an array) is likewise discarded.
        function test_pages_object_self_heals() {
            var ok = store.applyExternal('{"pages":{}}')
            verify(ok, "did not throw")
            verify(Array.isArray(store.pages()), "pages() is an array")
            compare(store.pageCount(), 0, "object pages coerced to []")
        }

        // A page whose `tiles` is a string → tiles reset to [], the page survives.
        function test_page_tiles_non_array_reset() {
            var ok = store.applyExternal('{"pages":[{"name":"A","tiles":"x"}]}')
            verify(ok, "did not throw")
            compare(store.pageCount(), 1, "page kept")
            compare(store.pages()[0].name, "A", "name preserved")
            verify(Array.isArray(store.pages()[0].tiles), "tiles coerced to array")
            compare(store.pages()[0].tiles.length, 0, "non-array tiles reset to []")
        }

        // Mixed tile array: a bare string and a number are dropped; the only valid
        // tile (a plain object with a non-empty string id) survives.
        function test_bad_tiles_dropped_valid_survives() {
            var ok = store.applyExternal('{"pages":[{"tiles":["bad",3,{"id":"ok","type":"cpu"}]}]}')
            verify(ok, "did not throw")
            compare(store.pageCount(), 1, "page kept")
            var tiles = store.pages()[0].tiles
            compare(tiles.length, 1, "only the valid tile survived")
            compare(tiles[0].id, "ok", "the valid tile is the one kept")
            compare(tiles[0].type, "cpu", "its fields are intact")
            // A nameless page gets a synthesised default name (never undefined).
            compare(typeof store.pages()[0].name, "string", "page has a string name")
            verify(store.pages()[0].name.length > 0, "default page name is non-empty")
        }

        // The `_isPlainObject` predicate underpins every heal above: it is the exact
        // gate that decides whether appearance/settings/a page/a tile is a usable
        // object or junk to drop. Assert it across every branch (null / non-object /
        // array / plain object) so a regression in the predicate is caught here.
        function test_isPlainObject_predicate() {
            verify(store._isPlainObject({}), "an empty object is a plain object")
            verify(store._isPlainObject({ a: 1 }), "a populated object is a plain object")
            verify(!store._isPlainObject(null), "null is not a plain object")
            verify(!store._isPlainObject([]), "an array is not a plain object")
            verify(!store._isPlainObject(5), "a number is not a plain object")
            verify(!store._isPlainObject("x"), "a string is not a plain object")
            verify(!store._isPlainObject(undefined), "undefined is not a plain object")
        }

        // Id-less / empty-id tile objects are dropped (they'd poison settings keys).
        function test_idless_tiles_dropped() {
            var doc = store._normaliseDoc({ pages: [ { name: "P", tiles: [
                { type: "cpu" },        // no id
                { id: "", type: "gpu" },// empty id
                { id: "keep", type: "ram" }
            ] } ] })
            compare(doc.pages[0].tiles.length, 1, "only the id-bearing tile kept")
            compare(doc.pages[0].tiles[0].id, "keep")
        }

        // Missing `settings` — the doc is accepted and settings becomes an object,
        // so settingsFor() / mutations don't throw.
        function test_missing_settings_becomes_object() {
            var ok = store.applyExternal('{"pages":[{"name":"A","tiles":[{"id":"t1","type":"cpu"}]}]}')
            verify(ok, "did not throw")
            compare(typeof store.data.settings, "object", "settings is an object")
            verify(store.data.settings !== null, "settings not null")
            // Round-trips a normal read/write without exception.
            compare(store.settingsFor("t1").anything, undefined)
            store.setSetting("t1", "k", 1)
            compare(store.settingsFor("t1").k, 1)
        }

        // A non-object `settings` (e.g. a number) is coerced to {}.
        function test_settings_non_object_coerced() {
            var doc = store._normaliseDoc({ pages: [], settings: 5 })
            compare(typeof doc.settings, "object")
            verify(!Array.isArray(doc.settings), "settings is a plain object, not an array")
        }

        // Non-object pages inside the array are dropped entirely.
        function test_non_object_pages_dropped() {
            var doc = store._normaliseDoc({ pages: [ 5, "x", null, { name: "Real", tiles: [] } ] })
            compare(doc.pages.length, 1, "only the real page survived")
            compare(doc.pages[0].name, "Real")
        }

        // A well-formed document is passed through UNCHANGED (no false positives).
        function test_normal_doc_unchanged() {
            var good = {
                version: 1,
                appearance: { themeMode: "dark", accent: "cyan" },
                pages: [
                    { name: "System", tiles: [ { id: "cpu-1", type: "cpu" }, { id: "ram-1", type: "ram" } ] },
                    { name: "Life", tiles: [ { id: "clk-1", type: "clock" } ] }
                ],
                settings: { "cpu-1": { title: "CPU" } }
            }
            var ok = store.applyExternal(JSON.stringify(good))
            verify(ok, "accepted")
            compare(store.pageCount(), 2, "both pages kept")
            compare(store.pages()[0].name, "System")
            compare(store.pages()[0].tiles.length, 2)
            compare(store.pages()[0].tiles[0].id, "cpu-1")
            compare(store.pages()[1].tiles[0].type, "clock")
            compare(store.settingsFor("cpu-1").title, "CPU", "live settings preserved")
        }

        // Duplicate page names are still de-duplicated (existing behaviour intact).
        function test_duplicate_page_names_disambiguated() {
            var doc = store._normaliseDoc({ pages: [
                { name: "Work", tiles: [] }, { name: "Work", tiles: [] }
            ] })
            compare(doc.pages[0].name, "Work")
            verify(doc.pages[1].name !== "Work", "second duplicate renamed, got " + doc.pages[1].name)
        }
    }
}
