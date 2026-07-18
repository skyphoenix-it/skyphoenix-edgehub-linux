import QtQuick
import QtTest
import "../../ui/qml" as App

// Coverage for the page-level store functions added for per-page backgrounds,
// per-page columns, and unique page naming.
//
// COVERS: fn:DashboardStore.appendPreset, fn:DashboardStore._dedupPageName
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

        function test_appearance_roundtrips() {
            store.setAppearance("orientation", "landscape")
            compare(store.appearance().orientation, "landscape")
        }

        function test_bounds_guarded() {
            // Out-of-range page indices must not throw.
            store.setPageBackground(99, "style", "orbs")
            compare(store.pageBackground(99).style, undefined)
            verify(true)
        }

        // renamePage validation: blank input keeps the existing name (never yields
        // a zero-width, unclickable tab).
        function test_rename_rejects_blank() {
            var was = store.pages()[0].name
            store.renamePage(0, "   ")
            compare(store.pages()[0].name, was, "blank rename keeps the old name")
            store.renamePage(0, "Dashboard")
            compare(store.pages()[0].name, "Dashboard", "a real name is accepted")
        }

        // renamePage de-duplicates against OTHER pages so two tabs can't collide
        // (the real "two identical Page 5 tabs" bug).
        function test_rename_dedupes_against_others() {
            store.addPage("")                 // 2 pages: page0, "Page 2"
            store.renamePage(0, "Work")
            store.renamePage(1, "Work")       // collides with page0 → must be disambiguated
            compare(store.pages()[0].name, "Work")
            verify(store.pages()[1].name !== "Work", "duplicate renamed away, got " + store.pages()[1].name)
        }

        // resetSettings replaces settings with a DEEP COPY of the defaults: two
        // instances reset from the same defaults must NOT share the array instance
        // (mutating one must not leak into the other) — the B9 aliasing hazard.
        function test_reset_settings_deep_clones_defaults() {
            var defaults = { tasks: [], count: 0 }
            store.resetSettings("a", defaults)
            store.resetSettings("b", defaults)
            store.settingsFor("a").tasks.push("only-a")
            compare(store.settingsFor("a").tasks.length, 1, "a got its item")
            compare(store.settingsFor("b").tasks.length, 0, "b's array is independent")
            // And independent from the defaults object itself.
            compare(defaults.tasks.length, 0, "the defaults object is untouched")
        }

        // resetSettings drops stale keys not present in the defaults.
        function test_reset_settings_drops_stale_keys() {
            store.setSetting("c", "leftover", 42)
            store.resetSettings("c", { fresh: 1 })
            compare(store.settingsFor("c").fresh, 1)
            compare(store.settingsFor("c").leftover, undefined, "stale key removed")
        }

        // ── appendPreset: add a single-page "screen" as ONE new page, additive ──
        function test_appendPreset_adds_one_page_and_leaves_appearance() {
            var before = store.pageCount()               // blank = one "Home" page
            var themeBefore = store.appearance().themeMode
            var idx = store.appendPreset("calm-focus")
            compare(idx, before, "appendPreset returns the new page index")
            compare(store.pageCount(), before + 1, "exactly one page was added")
            var pages = store.pages()
            compare(pages[idx].name, "Focus", "the added page is the screen's single page")
            verify(pages[idx].tiles.length >= 1, "the added page carries the screen's tiles")
            verify(pages[idx].bg && pages[idx].bg.style !== undefined,
                   "the screen's character rides on the page (per-page background)")
            compare(store.appearance().themeMode, themeBefore,
                    "appendPreset does NOT touch the global appearance")
            compare(pages[0].name, "Home", "the user's existing page is untouched")
        }

        function test_appendPreset_rekeys_ids_no_collision() {
            store.appendPreset("system-monitor")         // cpu/gpu/ram
            store.appendPreset("system-monitor")         // again → ids must not collide
            var ids = ({})
            var pages = store.pages()
            for (var p = 0; p < pages.length; p++)
                for (var t = 0; t < pages[p].tiles.length; t++) {
                    var id = pages[p].tiles[t].id
                    verify(ids[id] === undefined, "appendPreset re-keys tile ids uniquely: " + id)
                    ids[id] = true
                }
        }

        function test_appendPreset_unknown_id_is_refused() {
            var before = store.pageCount()
            compare(store.appendPreset("does-not-exist"), -1, "appendPreset refuses an unknown id")
            compare(store.pageCount(), before, "nothing was added")
        }

        function test_dedupPageName_avoids_collision() {
            store.appendPreset("system-monitor")         // adds a "Core" page
            var names = store.pages().map(function (p) { return p.name })
            verify(names.indexOf("Core") >= 0, "the screen added its 'Core' page")
            compare(store._dedupPageName("Core"), "Core 2", "_dedupPageName avoids the existing name")
            compare(store._dedupPageName("Brand New"), "Brand New", "a free name is returned unchanged")
        }
    }
}
