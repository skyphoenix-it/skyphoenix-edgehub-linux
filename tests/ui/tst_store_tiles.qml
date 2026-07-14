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
            // The tile and its expanded overlay share per-widget state THROUGH the
            // store: once a value is set, every reader sees it. (settingsFor is now
            // a non-mutating getter — it no longer creates a persisted bucket as a
            // read side-effect, so we don't assert object identity, only shared value.)
            var id = store.addTile(0, "notes")
            store.setSetting(id, "text", "typed in the overlay")
            var readerA = store.settingsFor(id)
            var readerB = store.settingsFor(id)
            compare(readerA.text, "typed in the overlay")
            compare(readerB.text, "typed in the overlay")
        }

        // Metric sparkline history / peaks are volatile per-session state: they must
        // stay in memory (so the compact tile and its expanded overlay share one
        // sparkline) yet NEVER reach config.toml — otherwise the metric widgets
        // rewrite the config on every ~2s sample (flash wear + a save race with the
        // Manager). The persisted document strips them; a plain setting is kept.
        function test_ephemeral_metric_keys_not_persisted() {
            var id = store.addTile(0, "cpu")
            store.setSetting(id, "hist", [1, 2, 3])
            store.patchSettings(id, { peakRx: 99, peakTx: 42, place: "kept" })
            // In-memory: everything is live (shared with the expanded overlay).
            compare(store.settingsFor(id).hist, [1, 2, 3])
            compare(store.settingsFor(id).peakRx, 99)
            // On disk: the volatile keys are gone, the real setting survives.
            var disk = store._persistableData().settings[id]
            verify(disk.hist === undefined, "hist must not be persisted")
            verify(disk.peakRx === undefined, "peakRx must not be persisted")
            verify(disk.peakTx === undefined, "peakTx must not be persisted")
            compare(disk.place, "kept", "a real setting alongside volatile keys is kept")
        }

        // A write that touches ONLY volatile keys must not schedule a disk save,
        // but must still bump revision so the live sparkline redraws.
        function test_ephemeral_write_bumps_revision_without_save() {
            var id = store.addTile(0, "net")
            var r0 = store.revision
            store.patchSettings(id, { hist: [{ r: 1, t: 2 }], peakRx: 5, peakTx: 6 })
            verify(store.revision > r0, "volatile write still bumps revision for reactivity")
            verify(!store._savePending, "a volatile-only write must not schedule a disk save")
            // A mixed patch (volatile + real) DOES schedule a save.
            store.patchSettings(id, { hist: [{ r: 9, t: 9 }], units: "mbit" })
            verify(store._savePending, "a patch with a real key schedules a save")
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
                "productivity": { pages: ["Focus", "System"] }
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
            // An unknown seed id resolves to the "productivity" preset (whatever
            // that preset's designed layout currently is).
            var unknown = store.seed("nonsense").pages.map(function (p) { return p.name })
            var prod = store.seed("productivity").pages.map(function (p) { return p.name })
            compare(unknown, prod, "unknown seed falls back to the productivity preset")
            verify(prod.length >= 1 && prod.indexOf("Focus") !== -1, "productivity preset has a Focus page")
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
