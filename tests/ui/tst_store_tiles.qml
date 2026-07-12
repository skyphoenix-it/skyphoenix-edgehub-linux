import QtQuick
import QtTest
import "../../ui/qml" as App

// Coverage for the core editable paths the dashboard is built on: tile add /
// remove / move / resize, per-instance settings lifecycle, the shared-state
// contract (one settings object backs both the tile and its expanded overlay),
// and the named starter layouts. These are the most-used mutation paths and
// were previously only exercised indirectly.
Item {
    width: 100; height: 100
    App.DashboardStore { id: store }

    TestCase {
        name: "StoreTiles"
        when: windowShown
        function init() { store.load("blank") }   // one empty "Home" page

        function tiles() { return store.pages()[0].tiles }

        // ── add / remove ───────────────────────────────────────────────────
        function test_add_tile_returns_unique_ids() {
            var a = store.addTile(0, "cpu")
            var b = store.addTile(0, "cpu")
            verify(a && b && a !== b, "ids must be non-empty and distinct")
            compare(tiles().length, 2)
            compare(tiles()[0].type, "cpu")
        }

        function test_add_tile_out_of_range_is_noop() {
            store.addTile(5, "cpu")
            store.addTile(-1, "cpu")
            compare(tiles().length, 0)
        }

        function test_remove_tile_also_drops_its_settings() {
            var id = store.addTile(0, "notes")
            store.setSetting(id, "text", "hello")
            compare(store.settingsFor(id).text, "hello")
            store.removeTile(0, id)
            compare(tiles().length, 0)
            // settingsFor lazily recreates, so assert the map no longer carried it
            verify(store.data.settings[id] === undefined || Object.keys(store.data.settings[id]).length === 0)
        }

        function test_remove_unknown_tile_is_noop() {
            store.addTile(0, "cpu")
            store.removeTile(0, "does-not-exist")
            compare(tiles().length, 1)
        }

        // ── resize cycle (1x1 → 2x1 → 1x2 → 2x2 → 1x1) ─────────────────────
        function test_resize_cycle() {
            var id = store.addTile(0, "cpu")
            var seq = [[2, 1], [1, 2], [2, 2], [1, 1]]
            for (var i = 0; i < seq.length; i++) {
                store.setTileSize(0, id, seq[i][0], seq[i][1])
                compare(tiles()[0].w, seq[i][0])
                compare(tiles()[0].h, seq[i][1])
            }
        }

        function test_resize_out_of_range_is_noop() {
            var id = store.addTile(0, "cpu")
            store.setTileSize(9, id, 2, 2)   // bad page index
            compare(tiles()[0].w, undefined)
        }

        // ── move / reorder with clamping ───────────────────────────────────
        function test_move_reorders() {
            var a = store.addTile(0, "cpu")
            var b = store.addTile(0, "gpu")
            var c = store.addTile(0, "ram")
            store.moveTile(0, 0, 2)          // cpu to the end
            var order = tiles().map(function (t) { return t.id })
            compare(order, [b, c, a])
        }

        function test_move_clamps_target_index() {
            var a = store.addTile(0, "cpu")
            var b = store.addTile(0, "gpu")
            store.moveTile(0, 0, 99)         // clamps to last
            compare(tiles()[tiles().length - 1].id, a)
        }

        function test_move_invalid_from_is_noop() {
            store.addTile(0, "cpu")
            store.moveTile(0, 5, 0)
            store.moveTile(0, -1, 0)
            compare(tiles().length, 1)
        }

        // ── settings lifecycle ─────────────────────────────────────────────
        function test_ensure_settings_no_clobber() {
            var id = store.addTile(0, "focus")
            store.setSetting(id, "phase", "break")
            store.ensureSettings(id, { phase: "work", running: false })
            compare(store.settingsFor(id).phase, "break")   // existing kept
            compare(store.settingsFor(id).running, false)   // missing seeded
        }

        function test_patch_settings_merges() {
            var id = store.addTile(0, "weather")
            store.patchSettings(id, { lat: 1.5, lon: 2.5, place: "X" })
            store.patchSettings(id, { place: "Y" })
            var s = store.settingsFor(id)
            compare(s.lat, 1.5)
            compare(s.place, "Y")
        }

        // The design contract: a tile and its expanded overlay are two separate
        // widget instances that share ONE live settings object via the store.
        function test_shared_state_between_two_readers() {
            var id = store.addTile(0, "notes")
            var readerA = store.settingsFor(id)
            store.setSetting(id, "text", "typed in the overlay")
            var readerB = store.settingsFor(id)
            compare(readerB.text, "typed in the overlay")
            compare(readerA.text, "typed in the overlay")   // same object
            verify(readerA === readerB)
        }

        function test_mutations_bump_revision() {
            var r0 = store.revision
            store.addTile(0, "cpu")
            verify(store.revision > r0, "structural edit bumps revision")
            var r1 = store.revision
            store.setSetting(store.pages()[0].tiles[0].id, "k", 1)
            verify(store.revision > r1, "settings edit bumps revision")
        }
    }

    // ── Starter layouts ────────────────────────────────────────────────────
    TestCase {
        name: "StoreSeeds"
        when: windowShown

        function test_seed_shapes_data() {
            var cases = {
                "blank":        { pages: ["Home"], firstTileCount: 0 },
                "minimal":      { pages: ["Home"] },
                "gaming":       { pages: ["System", "Play"] },
                "productivity": { pages: ["Focus", "System", "Life"] }
            }
            for (var which in cases) {
                var doc = store.seed(which)
                var names = doc.pages.map(function (p) { return p.name })
                compare(names, cases[which].pages, which + " page names")
                // Every tile has an id + type.
                for (var i = 0; i < doc.pages.length; i++)
                    for (var j = 0; j < doc.pages[i].tiles.length; j++) {
                        verify(doc.pages[i].tiles[j].id, which + " tile has id")
                        verify(doc.pages[i].tiles[j].type, which + " tile has type")
                    }
            }
            compare(store.seed("blank").pages[0].tiles.length, 0)
        }

        function test_unknown_seed_falls_back_to_productivity() {
            var doc = store.seed("nonsense")
            compare(doc.pages.map(function (p) { return p.name }), ["Focus", "System", "Life"])
        }

        function test_reset_to_replaces_layout() {
            store.load("blank")
            store.addTile(0, "cpu")
            store.resetTo("minimal")
            compare(store.pages().length, 1)
            compare(store.pages()[0].name, "Home")
            verify(store.pages()[0].tiles.length > 0)
        }
    }
}
