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
    }
}
