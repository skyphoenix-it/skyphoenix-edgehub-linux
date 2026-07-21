import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as W

// BackgroundPicker - the unified control that replaced the scattered background/
// wallpaper settings. Verifies the mutually-exclusive "style OR wallpaper" choice
// and the global vs per-page precedence ("Use global" drops a page override).
Item {
    width: 500; height: 400
    property var col: ({ textPrimary: "#fff", textSecondary: "#aaa", panel: "#161B22",
        panelAlt: "#1C222B", border: "#333", accent: "#58A6FF", radius: 10 })

    App.DashboardStore { id: store }
    App.BackgroundCatalog { id: bgc }
    App.WallpaperCatalog { id: wpc }

    W.BackgroundPicker { id: gp; st: store; pageIndex: -1; col: parent.col; bgCatalog: bgc; wpCatalog: wpc }
    W.BackgroundPicker { id: pp; st: store; pageIndex: 0;  col: parent.col; bgCatalog: bgc; wpCatalog: wpc }

    TestCase {
        name: "BackgroundPicker"
        when: windowShown
        function init() { store.load("blank") }

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
            verify(pp.selGlobal(), "Use global drops the page override")
            verify(!store.pageBackground(0).style && !store.pageBackground(0).wallpaper)
        }
    }
}
