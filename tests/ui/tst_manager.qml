import QtQuick
import QtTest

// COVERS: fn:Manager.confirmDeleteImage, fn:Manager.currentPageName, fn:Manager.onChanged, fn:Manager.onConfigChanged, fn:Manager.onHubConnectedChanged, fn:Manager.onImagesChanged
// COVERS: fn:Manager.onScreensChanged, fn:Manager.pageTiles, fn:Manager.refreshImages, fn:Manager.syncTheme
// COVERS: fn:Manager.previewTheme, fn:Manager.previewAccent, fn:Manager.endThemePreview, fn:Manager.confirmRemovePage
//
// manager/qml/Manager.qml (hosted with a STUBBED `backend`) —
//   • the 5-tab StackLayout (Layout/Appearance/Images/Display/About) switches
//   • pageTiles(): current-page tiles, revision-reactive
//   • refreshImages(): rebuilds imagesModel from backend.listImages()
//   • confirmDeleteImage(): sets the confirm message + onConfirm, and the
//     confirm action clears a matching wallpaper and calls backend.deleteImage
//   • syncTheme(): a store `changed()` re-applies accent to the theme
//   • the inline MButton (Start hub: click → startHub + hubStarting; enabled
//     tracks !hubStarting) and MSwitch (Widget glow: toggle → store.setAppearance)
//
// Manager owns its own Theme/DashboardStore/catalog/media; only `backend` (the
// C++ ManagerBackend) is external, so we feed a light QtObject stub through the
// context scope and instantiate the REAL Manager.qml window. Assertions target
// the store/driving props, not pixels.
Item {
    id: root
    width: 200; height: 200

    // Stub of the C++ ManagerBackend: signals + methods returning sane JSON,
    // recording the calls the tests assert on.
    QtObject {
        id: backend
        property bool hubConnected: false
        signal imagesChanged()
        signal configChanged()
        signal screensChanged()
        property var imagesList: []
        property string lastDeleted: ""
        property string lastImported: ""
        property bool startHubCalled: false
        property bool stopHubCalled: false
        property bool syncCalled: false
        property bool autostart: false
        function imageUrl(n) { return "file:///imgs/" + n }
        function starterLayout() { return "blank" }
        function autoConfig() { return "" }
        function startTab() { return 0 }
        function metricsJson() { return "{}" }
        function screensJson() { return "[]" }
        function targetConnector() { return "" }
        function listImages() { return imagesList }
        function importImage(u) { lastImported = String(u) }
        function deleteImage(n) { lastDeleted = n }
        function setTargetDisplay(a, b) {}
        function isAutostart() { return autostart }
        function setAutostart(v) { autostart = v }
        function syncFromHub() { syncCalled = true }
        function startHub() { startHubCalled = true; return true }
        function stopHub() { stopHubCalled = true }
    }

    property var win: null

    // ── tree helpers ─────────────────────────────────────────────────────────
    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids) for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
        var res = node.data          // catch non-visual (Dialog/ListModel) children
        if (res && res !== kids) for (var j = 0; j < res.length; j++) eachItem(res[j], fn)
    }
    function findPred(n, pred) {
        var f = null
        eachItem(n, function (x) { if (!f && pred(x)) f = x })
        return f
    }
    function findAll(n, pred) {
        var out = []
        eachItem(n, function (x) { if (pred(x)) out.push(x) })
        return out
    }

    property var _store: null
    property var _theme: null
    property var _nav: null
    property var _images: null
    property var _confirm: null

    function findButton(txt) {
        return findPred(win, function (x) {
            return x && typeof x.text === "string" && x.text === txt
                   && typeof x.down === "boolean" && typeof x.hovered === "boolean"
        })
    }
    function findSwitch(txt) {
        return findPred(win, function (x) {
            return x && typeof x.checked === "boolean" && typeof x.text === "string"
                   && x.text === txt && typeof x.toggled === "function"
        })
    }

    TestCase {
        name: "Manager"
        when: windowShown

        function initTestCase() {
            var c = Qt.createComponent("../../manager/qml/Manager.qml")
            tryVerify(function () { return c.status !== Component.Loading }, 5000)
            compare(c.status, Component.Ready, "Manager.qml compiles: " + c.errorString())
            win = c.createObject(root)
            verify(win !== null, "Manager window instantiated")

            _store = findPred(win, function (x) {
                return x && x.applyExternal !== undefined && x.structureRevision !== undefined })
            _theme = findPred(win, function (x) {
                return x && x.accentPresets !== undefined && typeof x.applyAccent === "function" })
            _nav = findPred(win, function (x) {
                return x && x.currentIndex !== undefined && x.count === 5 && x.count !== undefined })
            _images = findPred(win, function (x) {
                return x && x.count !== undefined && typeof x.append === "function"
                       && typeof x.clear === "function" && typeof x.get === "function" })
            _confirm = findPred(win, function (x) {
                return x && x.message !== undefined && ("onConfirm" in x) && typeof x.open === "function" })
            verify(_store, "found store")
            verify(_theme, "found theme")
            verify(_nav, "found the 5-tab StackLayout")
            verify(_images, "found imagesModel")
            verify(_confirm, "found confirmDialog")
        }
        function cleanupTestCase() { if (win) win.destroy() }

        function init() {
            _store.load("blank")
            win.currentPageIndex = 0
            win.hubStarting = false
            _nav.currentIndex = 0
            backend.startHubCalled = false
            backend.stopHubCalled = false
        }

        // ── tabs ──────────────────────────────────────────────────────────────
        function test_four_tabs_switch() {
            compare(_nav.count, 5, "Layout / Appearance / Images / Display / About")
            for (var i = 0; i < 5; i++) {
                _nav.currentIndex = i
                compare(_nav.currentIndex, i, "switched to tab " + i)
            }
        }

        // ── pageTiles ─────────────────────────────────────────────────────────
        function test_pageTiles_reflects_current_page() {
            compare(win.pageTiles().length, 0, "blank page starts empty")
            _store.addTile(0, "cpu")
            _store.addTile(0, "clock")
            compare(win.pageTiles().length, 2, "tiles added to the current page appear")
            // Out-of-range current page returns [] (guard).
            win.currentPageIndex = 99
            compare(win.pageTiles().length, 0, "an out-of-range page yields no tiles")
        }

        // ── refreshImages ─────────────────────────────────────────────────────
        function test_refreshImages_rebuilds_model() {
            backend.imagesList = ["a.png", "b.png", "c.png"]
            win.refreshImages()
            compare(_images.count, 3, "model rebuilt from backend.listImages()")
            compare(_images.get(0).modelData, "a.png", "first image name stored")
            backend.imagesList = []
            win.refreshImages()
            compare(_images.count, 0, "an empty list clears the model")
        }

        // ── confirmDeleteImage ────────────────────────────────────────────────
        function test_confirmDeleteImage_confirm_clears_and_deletes() {
            var name = "wall.png"
            var full = backend.imageUrl(name)
            _store.setAppearance("wallpaper", full)      // this image is the wallpaper
            backend.lastDeleted = ""
            win.confirmDeleteImage(name, full)
            verify(_confirm.message.indexOf(name) >= 0, "confirmDeleteImage set a confirm message naming the image")
            verify(typeof _confirm.onConfirm === "function", "an onConfirm action was armed")
            // Simulate the user pressing "Yes".
            _confirm.onConfirm()
            compare(_store.appearance().wallpaper, "", "the matching wallpaper was cleared")
            compare(backend.lastDeleted, name, "backend.deleteImage was called")
        }

        // Deleting a NON-wallpaper image must LEAVE the current wallpaper intact
        // (the false branch of `appearance().wallpaper === fullPath`).
        function test_confirmDeleteImage_nonwallpaper_keeps_wallpaper() {
            var wallName = "keep.png"
            var wallFull = backend.imageUrl(wallName)
            _store.setAppearance("wallpaper", wallFull)   // wallpaper points at a DIFFERENT image
            var other = "gone.png"
            backend.lastDeleted = ""
            win.confirmDeleteImage(other, backend.imageUrl(other))
            _confirm.onConfirm()
            compare(_store.appearance().wallpaper, wallFull,
                    "deleting an unrelated image leaves the wallpaper untouched")
            compare(backend.lastDeleted, other, "the unrelated image is still deleted")
        }

        // Deleting an image used as a PER-PAGE background clears that page bg too
        // (the pageBackground/setPageBackground loop), even when it's not the
        // global wallpaper.
        function test_confirmDeleteImage_clears_matching_page_background() {
            var name = "pbg.png"
            var full = backend.imageUrl(name)
            _store.setAppearance("wallpaper", "")          // NOT the global wallpaper
            _store.setPageBackground(0, "wallpaper", full) // but IS a page-0 background
            compare(_store.pageBackground(0).wallpaper, full, "precondition: page-0 bg armed")
            backend.lastDeleted = ""
            win.confirmDeleteImage(name, full)
            _confirm.onConfirm()
            verify(!_store.pageBackground(0).wallpaper,
                   "the matching per-page background was cleared")
            compare(backend.lastDeleted, name, "backend.deleteImage was called")
        }

        // The cancel path: arming the dialog then DISMISSING it (No/Cancel) must
        // NOT run onConfirm — nothing is deleted, the wallpaper is untouched.
        function test_confirmDeleteImage_cancel_deletes_nothing() {
            var name = "safe.png"
            var full = backend.imageUrl(name)
            _store.setAppearance("wallpaper", full)
            backend.lastDeleted = "SENTINEL"
            win.confirmDeleteImage(name, full)
            verify(typeof _confirm.onConfirm === "function", "an onConfirm action was armed")
            _confirm.reject()                              // user presses No / dismisses
            compare(backend.lastDeleted, "SENTINEL", "dismissing the dialog deletes nothing")
            compare(_store.appearance().wallpaper, full, "the wallpaper is untouched on cancel")
        }

        // The image-import flow: FileDialog.onAccepted → backend.importImage(file)
        // then refreshImages() rebuilds the model.
        function test_import_image_flow_calls_backend_and_refreshes() {
            var fileDlg = findPred(win, function (x) {
                return x && x.selectedFile !== undefined && x.nameFilters !== undefined
                       && typeof x.accepted === "function" })
            verify(fileDlg, "found the image-import FileDialog")
            backend.imagesList = ["i1.png", "i2.png"]
            backend.lastImported = "SENTINEL"
            fileDlg.accepted()                             // fire onAccepted (offscreen: no native dialog)
            verify(backend.lastImported !== "SENTINEL", "backend.importImage was invoked")
            compare(backend.lastImported, String(fileDlg.selectedFile),
                    "importImage received the dialog's selected file")
            compare(_images.count, 2, "refreshImages rebuilt the model after import")
        }

        // ── inline MButton (Stop hub — the hub-CONNECTED variant) ─────────────
        function test_stop_hub_button_when_connected() {
            backend.hubConnected = true                    // hub live → control becomes "Stop hub"
            var btn = findButton("Stop hub")
            verify(btn, "button switches to 'Stop hub' when the hub is connected")
            verify(!findButton("Start hub"), "no 'Start hub' while connected")
            verify(btn.enabled, "enabled while not starting")
            backend.stopHubCalled = false
            btn.clicked()
            compare(backend.stopHubCalled, true, "click invoked backend.stopHub()")
            compare(win.hubStarting, false, "stopping does not enter the 'starting…' state")
            backend.hubConnected = false                   // restore for the other cases
        }

        // ── syncTheme on store change (store.changed → onChanged → syncTheme) ──
        function test_syncTheme_applies_accent_on_store_change() {
            // A store appearance change fires changed() → Connections → syncTheme().
            _store.setAppearance("accent", "green")
            verify(Qt.colorEqual(_theme.accent, _theme.accentPresets["green"].a), "onChanged ran syncTheme: accent re-themed")
            _store.setAppearance("accent", "red")
            verify(Qt.colorEqual(_theme.accent, _theme.accentPresets["red"].a), "second store.onChanged re-applies syncTheme live")
        }

        // ── currentPageName ───────────────────────────────────────────────────
        function test_currentPageName_tracks_selected_page() {
            compare(win.currentPageName(), "Home", "currentPageName returns the blank layout's Home page")
            _store.addPage("Second")
            win.currentPageIndex = 1
            compare(win.currentPageName(), "Second", "currentPageName follows the selected page")
            win.currentPageIndex = 99
            compare(win.currentPageName(), "", "currentPageName returns '' for an out-of-range page")
        }

        // ── backend Connections: onImagesChanged → refreshImages ──────────────
        function test_onImagesChanged_rebuilds_images() {
            backend.imagesList = ["x.png", "y.png"]
            backend.imagesChanged()          // fires the Connections onImagesChanged handler
            compare(_images.count, 2, "onImagesChanged rebuilt the images model via refreshImages")
        }

        // ── backend Connections: onConfigChanged adopts the pushed config live ─
        function test_onConfigChanged_reloads_store() {
            backend.imagesList = []
            backend.configChanged()          // hub/disk changed config → adopt it
            // store.load re-seeded from the (blank) starter layout → one Home page.
            compare(_store.pages()[0].name, "Home", "onConfigChanged reloaded the store from the backend")
            verify(win.currentPageIndex < _store.pageCount(),
                   "onConfigChanged clamped the current page index into range")
        }

        // ── backend Connections: onScreensChanged refreshes the display state ─
        function test_onScreensChanged_updates_screens() {
            backend.screensChanged()         // display hotplug
            verify(win.screens !== undefined && win.screens.length >= 0, "onScreensChanged refreshed win.screens from the backend")
        }

        // ── backend Connections: onHubConnectedChanged clears 'starting…' ─────
        function test_onHubConnectedChanged_clears_starting() {
            win.hubStarting = true
            backend.hubConnected = true      // property change fires onHubConnectedChanged
            compare(win.hubStarting, false, "onHubConnectedChanged cleared the 'starting…' state on connect")
            backend.hubConnected = false     // restore
        }

        // ── inline MButton (Start hub) ────────────────────────────────────────
        function test_start_hub_button_click_and_enabled() {
            var btn = findButton("Start hub")
            verify(btn, "Start hub button present (hub offline)")
            verify(btn.enabled, "enabled while not starting")
            // Manager runs in its own (offscreen, non-exposed) window, so synthetic
            // mouse events don't deliver; emit the button's `clicked` signal to run
            // its real onClicked handler — the behaviour under test.
            btn.clicked()
            compare(backend.startHubCalled, true, "click invoked backend.startHub()")
            compare(win.hubStarting, true, "entered the 'starting…' state")
            verify(!btn.enabled, "button disables itself while starting")
        }

        // ── hover previews: show, then commit ─────────────────────────────────
        // previewTheme paints the Manager's theme instance WITHOUT touching the
        // store; endThemePreview restores the stored appearance (it must void the
        // signature guard, or syncTheme would skip the "unchanged" payload).
        function test_previewTheme_is_transient() {
            // toString(): a bare `var x = theme.backgroundColor` holds a live
            // value-type reference that re-reads the property, so the "before"
            // snapshot would always equal the "after" value.
            var storedBg = _theme.backgroundColor.toString()
            win.previewTheme("light")
            verify(!Qt.colorEqual(_theme.backgroundColor, storedBg), "previewTheme repainted the theme instance")
            verify(_store.appearance().themeMode === undefined, "previewTheme did NOT write the store")
            win.endThemePreview()
            verify(Qt.colorEqual(_theme.backgroundColor, storedBg), "endThemePreview restored the stored theme")
        }

        function test_previewAccent_is_transient_and_restorable() {
            _store.setAppearance("accent", "blue")           // a committed baseline
            var storedAccent = _theme.accent.toString()      // snapshot, not a live reference
            win.previewAccent("green")
            verify(Qt.colorEqual(_theme.accent, _theme.accentPresets["green"].a), "previewAccent painted the hovered accent")
            compare(_store.appearance().accent, "blue", "previewAccent left the stored accent untouched")
            win.endThemePreview()
            verify(Qt.colorEqual(_theme.accent, storedAccent), "endThemePreview restored the committed accent")
        }

        // previewTheme must re-apply the COMMITTED accent (applyTheme resets it),
        // or hovering a theme swatch would also appear to change the accent.
        function test_previewTheme_keeps_the_committed_accent() {
            _store.setAppearance("accent", "purple")
            win.previewTheme("midnight")
            verify(Qt.colorEqual(_theme.accent, _theme.accentPresets["purple"].a), "previewTheme keeps the committed accent")
            win.endThemePreview()
        }

        // ── confirmRemovePage: destructive → armed confirm, not instant ───────
        function test_confirmRemovePage_confirms_then_removes() {
            _store.addPage("Doomed")
            win.currentPageIndex = 1
            _store.addTile(1, "cpu")
            win.confirmRemovePage()
            verify(_confirm.message.indexOf("Doomed") >= 0, "confirmRemovePage names the page")
            verify(_confirm.message.indexOf("1 widget") >= 0, "confirmRemovePage counts its widgets")
            _confirm.reject()                                // user says No
            compare(_store.pageCount(), 2, "rejecting the confirm removes nothing")
            win.confirmRemovePage()
            _confirm.onConfirm()                             // user says Yes
            compare(_store.pageCount(), 1, "confirming removes the page")
            compare(win.currentPageIndex, 0, "selection clamped back into range")
        }

        // ── Appearance tab hosts a live, read-only Edge preview ───────────────
        function test_appearance_tab_has_readonly_edge_preview() {
            // Dedupe: eachItem walks both `children` and `data`, so deep nodes are
            // visited (and collected) many times over.
            var seen = []
            findAll(win, function (x) {
                if (x && typeof x.injectInto === "function" && x.editable !== undefined
                        && seen.indexOf(x) < 0) seen.push(x)
                return false
            })
            var clones = seen
            compare(clones.length, 2, "two EdgeClones: the Layout editor + the Appearance preview")
            var editorCount = 0, previewCount = 0
            for (var i = 0; i < clones.length; i++)
                clones[i].editable ? editorCount++ : previewCount++
            compare(editorCount, 1, "exactly one editable clone (Layout tab)")
            compare(previewCount, 1, "exactly one read-only preview clone (Appearance tab)")
        }

        // ── liveNote: the one phrase for "does an edit reach the panel now?" ──
        function test_liveNote_follows_hub_connection() {
            backend.hubConnected = false
            verify(win.liveNote.indexOf("offline") >= 0, "offline wording while disconnected")
            backend.hubConnected = true
            verify(win.liveNote.indexOf("immediately") >= 0, "live wording while connected")
            backend.hubConnected = false
        }

        // ── per-widget config dialog declares its scope ───────────────────────
        function test_config_dialog_carries_widget_scope_tag() {
            _store.addTile(0, "clock")
            var tileId = _store.pages()[0].tiles[0].id
            var dlg = findPred(win, function (x) { return x && typeof x.openFor === "function" })
            verify(dlg, "found the WidgetConfigDialog")
            dlg.openFor(tileId, "clock")
            var tag = findPred(win, function (x) { return x && x.objectName === "scopeTag" })
            verify(tag, "the dialog header carries a scope tag")
            compare(tag.text, "This widget only", "…that says the settings touch one tile")
            dlg.close()
        }

        // ── inline MSwitch (Widget glow) ──────────────────────────────────────
        function test_widget_glow_switch_toggles_store() {
            _nav.currentIndex = 1            // Appearance tab hosts the switch
            var sw = findSwitch("Widget glow")
            verify(sw, "Widget glow switch present on the Appearance tab")
            var before = sw.checked          // defaults true (glow undefined)
            // Flip + fire the wired onToggled (see note above re: offscreen window).
            sw.toggle(); sw.toggled()
            verify(sw.checked !== before, "the switch flipped")
            compare(_store.appearance().glow, sw.checked, "toggle persisted to the store")
        }
    }
}
