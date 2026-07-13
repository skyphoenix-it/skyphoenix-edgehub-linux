import QtQuick
import QtTest
import "../../ui/qml" as App

// Gate for the duplicate page-name reconciliation added to _normaliseDoc.
// renamePage/addPage reject NEW collisions, but a config that already carried
// two identical page names (the real "two Page 5 tabs" bug) was never fixed on
// load. Loading such a document must now disambiguate later duplicates while
// leaving order + tiles intact, and must leave an all-unique document unchanged.
Item {
    width: 100; height: 100
    App.DashboardStore { id: store }

    TestCase {
        name: "StoreDedup"
        when: windowShown

        // Push a doc through the load path (applyExternal reuses _normaliseDoc too).
        function applyDoc(doc) {
            return store.applyExternal(JSON.stringify(doc))
        }

        function names() {
            return store.pages().map(function (p) { return p.name })
        }

        // Two identical "Page 5" pages → names become unique, tiles preserved.
        function test_duplicate_names_deduped_on_load() {
            var ok = applyDoc({
                version: 1, appearance: {}, settings: {},
                pages: [
                    { name: "Page 5", tiles: [ { id: "a", type: "cpu" } ] },
                    { name: "Page 5", tiles: [ { id: "b", type: "ram" } ] }
                ]
            })
            verify(ok, "applyExternal accepted the doc")

            var nm = names()
            compare(nm.length, 2, "still two pages")
            compare(nm[0], "Page 5", "first occurrence keeps its name")
            compare(nm[1], "Page 5 2", "later duplicate is disambiguated deterministically")
            verify(nm[0] !== nm[1], "names are now unique")

            // Order + tiles are untouched.
            compare(store.pages()[0].tiles[0].id, "a", "first page keeps its tile")
            compare(store.pages()[1].tiles[0].id, "b", "second page keeps its tile")
        }

        // Three-way collision cascades " 2", " 3".
        function test_triple_duplicate_cascades() {
            applyDoc({
                version: 1, appearance: {}, settings: {},
                pages: [
                    { name: "Sys", tiles: [] },
                    { name: "Sys", tiles: [] },
                    { name: "Sys", tiles: [] }
                ]
            })
            var nm = names()
            compare(nm[0], "Sys")
            compare(nm[1], "Sys 2")
            compare(nm[2], "Sys 3")
        }

        // A disambiguated suffix must not itself collide with an existing name.
        function test_dedup_skips_existing_suffix() {
            applyDoc({
                version: 1, appearance: {}, settings: {},
                pages: [
                    { name: "Home", tiles: [] },
                    { name: "Home 2", tiles: [] },
                    { name: "Home", tiles: [] }
                ]
            })
            var nm = names()
            compare(nm[0], "Home")
            compare(nm[1], "Home 2")
            compare(nm[2], "Home 3", "the third 'Home' skips the already-present 'Home 2'")
        }

        // An all-unique document is left exactly as-is.
        function test_unique_names_unchanged() {
            applyDoc({
                version: 1, appearance: {}, settings: {},
                pages: [
                    { name: "Focus", tiles: [] },
                    { name: "System", tiles: [] },
                    { name: "Life", tiles: [] }
                ]
            })
            var nm = names()
            compare(nm[0], "Focus")
            compare(nm[1], "System")
            compare(nm[2], "Life")
        }
    }
}
