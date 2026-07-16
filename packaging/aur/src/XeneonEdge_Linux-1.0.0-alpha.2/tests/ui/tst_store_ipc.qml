import QtQuick
import QtTest
import "../../ui/qml" as App

// DashboardStore.applyExternal — the live-reload path used when the companion
// Manager app pushes a new layout over the hub's control socket.
Item {
    width: 100; height: 100
    App.DashboardStore { id: store }

    TestCase {
        name: "StoreIPC"
        when: windowShown

        function init() { store.load("blank") }

        function test_apply_external_replaces_layout() {
            var doc = {
                version: 1,
                appearance: { themeMode: "oled", accent: "purple" },
                pages: [ { name: "Pushed", tiles: [ { id: "cpu-1", type: "cpu" },
                                                    { id: "clock-1", type: "clock" } ] } ],
                settings: { "cpu-1": {} }
            }
            var before = store.revision
            var ok = store.applyExternal(JSON.stringify(doc))
            verify(ok, "applyExternal accepted a valid document")
            compare(store.pages().length, 1)
            compare(store.pages()[0].name, "Pushed")
            compare(store.pages()[0].tiles.length, 2)
            compare(store.appearance().themeMode, "oled")
            verify(store.revision > before, "revision bumped for reactivity")
        }

        function test_apply_external_rejects_garbage() {
            verify(!store.applyExternal("not json"), "rejects invalid JSON")
            verify(!store.applyExternal('{"no":"pages"}'), "rejects doc without pages")
        }

        function test_apply_external_backfills_missing_maps() {
            var doc = { version: 1, pages: [ { name: "P", tiles: [] } ] }
            verify(store.applyExternal(JSON.stringify(doc)))
            verify(store.appearance() !== undefined)
            // settingsFor must not throw on the backfilled settings map.
            var s = store.settingsFor("whatever")
            verify(s !== undefined)
        }
    }
}
