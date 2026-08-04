import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as W

// BackgroundPicker - the unified control that replaced the scattered background/
// wallpaper settings. Verifies the mutually-exclusive "style OR wallpaper" choice
// and the global vs per-page precedence ("Use Edge-wide" drops a page override).
Item {
    width: 500; height: 400
    property var col: ({ textPrimary: "#fff", textSecondary: "#aaa", panel: "#161B22",
        panelAlt: "#1C222B", border: "#333", accent: "#58A6FF", radius: 10 })

    App.DashboardStore { id: store }
    App.BackgroundCatalog { id: bgc }
    App.WallpaperCatalog { id: wpc }
    App.Theme { id: theme }

    W.BackgroundPicker { id: gp; st: store; pageIndex: -1; col: parent.col; bgCatalog: bgc; wpCatalog: wpc
        themeKey: "nord"; themeLabel: "Nord" }
    W.BackgroundPicker { id: pp; st: store; pageIndex: 0;  col: parent.col; bgCatalog: bgc; wpCatalog: wpc
        themeKey: "nord"; themeLabel: "Nord" }

    TestCase {
        name: "BackgroundPicker"
        when: windowShown
        function init() { store.load("blank"); gp.showAllWallpapers = false; pp.showAllWallpapers = false }

        function test_recommendations_pair_wallpapers_with_the_active_theme() {
            compare(gp.recommendedWallpapers.length, 1)
            compare(gp.recommendedWallpapers[0].name, "slate",
                    "Nord leads with its deliberately paired wallpaper")
            compare(gp.visibleWallpapers.length, 1,
                    "the default view is recommendations, not all 18 choices")

            gp.showAllWallpapers = true
            compare(gp.visibleWallpapers.length, wpc.items.length,
                    "Browse all reveals the complete catalogue without changing selection")
        }

        function test_every_theme_has_a_deliberate_valid_pairing() {
            var knownThemes = ({})
            for (var i = 0; i < theme.themeCatalog.length; i++)
                knownThemes[theme.themeCatalog[i].k] = 0

            for (var j = 0; j < wpc.items.length; j++) {
                var item = wpc.items[j]
                verify(item.recommendedThemes && item.recommendedThemes.length > 0,
                       item.name + " declares at least one paired theme")
                for (var k = 0; k < item.recommendedThemes.length; k++) {
                    var key = item.recommendedThemes[k]
                    verify(knownThemes[key] !== undefined,
                           item.name + " does not reference unknown theme " + key)
                    knownThemes[key]++
                }
            }

            for (var themeKey in knownThemes)
                verify(knownThemes[themeKey] > 0,
                       themeKey + " has at least one explicitly paired wallpaper")
        }

        function test_current_nonrecommended_wallpaper_stays_visible() {
            gp.pickWallpaper("qrc:/wallpapers/sunset.png")
            compare(gp.visibleWallpapers.length, 2)
            verify(gp.visibleWallpapers.some(function (entry) { return entry.name === "sunset" }),
                   "the current choice remains visible beside the recommendation")
        }

        function test_global_style_clears_wallpaper() {
            store.setAppearance("wallpaper", "qrc:/wallpapers/nebula.png")
            gp.pickStyle("waves")
            compare(store.appearance().bgStyle, "waves")
            compare(store.appearance().wallpaper, "", "picking a style clears the wallpaper")
            verify(gp.selStyle("waves"))
            verify(!gp.selWall("qrc:/wallpapers/nebula.png"))
        }

        function test_global_wallpaper_wins() {
            gp.pickWallpaper("qrc:/wallpapers/ocean.png")
            compare(store.appearance().wallpaper, "qrc:/wallpapers/ocean.png")
            verify(gp.selWall("qrc:/wallpapers/ocean.png"))
            // A style is no longer the active selection while a wallpaper is set.
            verify(!gp.selStyle(store.appearance().bgStyle || "orbs"))
        }

        function test_page_override_then_use_global() {
            verify(pp.selGlobal(), "a fresh page inherits the global default")
            pp.pickStyle("stars")
            verify(!pp.selGlobal(), "page now has its own override")
            verify(pp.selStyle("stars"))
            compare(store.pageBackground(0).style, "stars")
            pp.pickWallpaper("qrc:/wallpapers/sunset.png")
            compare(store.pageBackground(0).wallpaper, "qrc:/wallpapers/sunset.png")
            verify(!pp.selStyle("stars"), "wallpaper supersedes the page style")
            pp.useGlobal()
            verify(pp.selGlobal(), "Use Edge-wide drops the page override")
            verify(!store.pageBackground(0).style && !store.pageBackground(0).wallpaper)
        }
    }
}
