import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Wg

// COVERS: bg:*, wallpaper:*

// BackgroundCatalog + WallpaperCatalog (ui/qml/*Catalog.qml) — the shared style /
// wallpaper registries. Assert expected counts, unique keys, required fields, and
// non-empty asset paths, plus that every background style has a real backdrop
// component (catalog ↔ BackdropLayer map parity).
Item {
    id: root
    width: 100; height: 100
    App.Theme { id: theme }
    App.BackgroundCatalog { id: bg }
    App.WallpaperCatalog { id: wp }

    TestCase {
        name: "BackgroundCatalog"
        when: windowShown

        function test_expected_count() {
            compare(bg.styles.length, 8, "eight background styles")
        }

        function test_unique_keys_and_required_fields() {
            var seen = {}
            for (var i = 0; i < bg.styles.length; i++) {
                var s = bg.styles[i]
                verify(s.v !== undefined && s.v.length > 0, "style has a non-empty value key")
                verify(s.l !== undefined && s.l.length > 0, "style '" + s.v + "' has a label")
                verify(seen[s.v] === undefined, "duplicate style key: " + s.v)
                seen[s.v] = true
            }
        }

        function test_first_is_plain_gradient() {
            compare(bg.styles[0].v, "none", "the first option is the plain gradient (none)")
        }

        // Every animated style (all but 'none') must map to a real component in
        // BackdropLayer — the catalog and the style→component map must not drift.
        function test_every_animated_style_loads_a_backdrop() {
            var bl = Qt.createQmlObject(
                'import "../../ui/qml/widgets" as W; W.BackdropLayer { width: 80; height: 80; running: false; visible: true }',
                root, "bl")
            for (var i = 0; i < bg.styles.length; i++) {
                var v = bg.styles[i].v
                if (v === "none") continue
                bl.style = v
                verify(bl.active, "style '" + v + "' activates the loader")
                verify(bl.item !== null, "style '" + v + "' loads a real backdrop component")
            }
            bl.style = "none"
            verify(!bl.active, "the 'none' style loads nothing")
            bl.destroy()
        }
    }

    TestCase {
        name: "WallpaperCatalog"
        when: windowShown

        function test_expected_count() {
            compare(wp.items.length, 12, "twelve bundled wallpapers")
        }

        function test_unique_names_required_fields_and_paths() {
            var seen = {}
            for (var i = 0; i < wp.items.length; i++) {
                var w = wp.items[i]
                verify(w.name !== undefined && w.name.length > 0, "wallpaper has a name")
                verify(w.label !== undefined && w.label.length > 0, "wallpaper '" + w.name + "' has a label")
                verify(w.source !== undefined && w.source.length > 0, "wallpaper '" + w.name + "' has a source")
                verify(w.source.indexOf("qrc:/wallpapers/") === 0,
                       "wallpaper '" + w.name + "' source is a bundled asset path")
                verify(seen[w.name] === undefined, "duplicate wallpaper name: " + w.name)
                seen[w.name] = true
            }
        }
    }
}
