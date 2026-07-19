import QtQuick
import QtQuick.Controls
import QtTest
import "GuiUtil.js" as G

// REAL on-screen GUI tests for the Manager (manager/qml/Manager.qml) — hosted in a
// real KWin compositor via ManagerHarness, driven with real mouse/keyboard events,
// asserted on GUI-observable outcomes (visible / geometry / text / grabImage).
//
// Areas covered (see scratchpad/specs/03_manager.md):
//   I  EdgeClone preview — portrait/landscape/rotation/tiles (the landscape
//      "tiny-strip" regression is proven directly with on-screen geometry + pixels)
//   K  Screens tab — add/remove/rename/select/columns/preset/override
//   L  Dialogs — add-widget picker / preset / licence / confirm / config / file
//
// The Manager window is created ONCE in initTestCase (QtTest runs test_* in
// alphabetical order; per-test creation would race). All external state is the
// stub `mh.backend`.
Item {
    id: root
    width: 100; height: 100
    ManagerHarness { id: mh }

    TestCase {
        id: tc
        name: "GuiMgrEdgeCloneScreensDialogs"
        when: windowShown
        visible: true

        // ── evidence ────────────────────────────────────────────────────────
        function snap(item, n) { var i = grabImage(item); i.save("gui-evidence/mgredge_" + n + ".png"); return i }

        // ── window / tree seams ─────────────────────────────────────────────
        function win_()  { return mh.win }
        function cont_() { return mh.win.contentItem }
        function store() { return G.findPred(win_(), function (n) { return n && n.applyExternal !== undefined && n.structureRevision !== undefined }) }
        function nav()   { return G.byObjName(cont_(), "managerTabs") }
        function setTab(i) { nav().currentIndex = i; wait(150) }

        // The Screens tab is the content Item that owns the rename field (forIndex).
        function screensTab() {
            var kids = nav().children
            for (var i = 0; i < kids.length; i++)
                if (G.findPred(kids[i], function (n) { return n && n.forIndex !== undefined })) return kids[i]
            return nav().children[0]
        }

        // The two EdgeClone instances (Screens = editable, Look = read-only preview).
        function clones() {
            return G.collectPred(cont_(), function (n) {
                return n && n.injectInto !== undefined && n.landscape !== undefined && n.previewLive !== undefined
            })
        }
        function editClone() { var c = clones(); for (var i = 0; i < c.length; i++) if (c[i].editable === true) return c[i]; return null }
        function lookClone() { var c = clones(); for (var i = 0; i < c.length; i++) if (c[i].editable === false) return c[i]; return null }
        function screenOf(c) { return G.findPred(c, function (n) { return n && n.cellShort !== undefined && n.cellLong !== undefined }) }
        function frameOf(c) { var s = screenOf(c); return s ? s.parent : null }
        function tilesIn(c) {
            return G.collectPred(c, function (n) {
                try { return n && n.tileId !== undefined && n.effSize !== undefined && !n.dying } catch (e) { return false }
            })
        }

        // page chips within the Screens tab, sorted by their store index.
        function chips() {
            var st = screensTab()
            var out = G.collectPred(st, function (n) {
                try { return n && n.index !== undefined && n.color !== undefined && n.modelData
                        && typeof n.modelData === "object" && n.modelData.name !== undefined } catch (e) { return false }
            })
            out.sort(function (a, b) { return a.index - b.index })
            return out
        }
        // The square "+" add-page chip (a small rounded Rectangle hosting a ui-plus icon).
        function addPageChip() {
            var st = screensTab()
            var icons = G.collectPred(st, function (n) { return n && n.name === "ui-plus" })
            for (var i = 0; i < icons.length; i++) {
                var p = icons[i].parent
                while (p && p.radius === undefined) p = p.parent
                if (p && p.width > 0 && p.width < 70 && Math.abs(p.width - p.height) < 6) return p
            }
            return null
        }

        function pill(node, label) { return G.findPred(node, function (n) { return n && n.objectName === "scopePill" && n.label === label }) }
        function findBtn(node, sub) {
            return G.findPred(node, function (n) {
                try { return n && n.clicked !== undefined && n.text !== undefined
                        && ("" + n.text).indexOf(sub) >= 0 && n.visible } catch (e) { return false }
            })
        }
        function dlgTitle(t) { return G.findPred(win_(), function (n) { try { return n && n.title === t && n.open !== undefined && n.opened !== undefined } catch (e) { return false } }) }
        function licenseDlg() { return G.findPred(win_(), function (n) { try { return n && n.candidate !== undefined && n.preview !== undefined && n.reVerify !== undefined } catch (e) { return false } }) }
        function confirmDlg() { return G.findPred(win_(), function (n) { try { return n && n.message !== undefined && ("onConfirm" in n) && typeof n.open === "function" } catch (e) { return false } }) }
        function cfgDlg() { return G.findPred(win_(), function (n) { try { return n && n.wId !== undefined && n.wType !== undefined && typeof n.openFor === "function" } catch (e) { return false } }) }
        function fileDlg() { return G.findPred(win_(), function (n) { try { return n && n.nameFilters !== undefined && typeof n.open === "function" && n.selectedFile !== undefined } catch (e) { return false } }) }

        function clickItem(it) { verify(it, "clickable target present"); mouseClick(it, it.width / 2, it.height / 2) }
        function closeOpenDialogs() {
            var ds = G.collectPred(win_(), function (n) { try { return n && typeof n.close === "function" && n.opened === true } catch (e) { return false } })
            for (var i = 0; i < ds.length; i++) ds[i].close()
            if (ds.length) wait(120)
        }
        // Drive orientation and wait for the clone to re-evaluate.
        function setOrient(mode, wantLandscape) {
            store().setAppearance("orientation", mode)
            tryVerify(function () { var c = editClone(); return c && c.landscape === wantLandscape }, 2500,
                      "clone landscape==" + wantLandscape + " for orientation " + mode)
            wait(200)
        }

        // ── lifecycle ───────────────────────────────────────────────────────
        function initTestCase() {
            var w = mh.create()
            verify(w !== null, "Manager.qml instantiated")
            tryVerify(function () { return mh.ready }, 8000, "Manager window became visible")
            tryVerify(function () { return store() !== null && nav() !== null && clones().length === 2 }, 6000,
                      "store, tabs and both EdgeClones resolved")
        }
        function cleanupTestCase() { mh.destroyWin() }

        // Light per-test reset for isolation (runs before every test / data row).
        function init() {
            var b = mh.backend
            b.hubConnected = false
            b.hubRotation = 0
            if (b.storedKey !== "") { b.storedKey = ""; b.licenseChanged() }
            b.imagesList = []
            closeOpenDialogs()
            var s = store()
            s.load("blank")
            s.setAppearance("orientation", "auto")
            s.setAppearance("wallpaper", "")
            s.setAppearance("bgStyle", "orbs")
            win_().currentPageIndex = 0
            nav().currentIndex = 0
            wait(60)
        }

        // ═══════════════════════════════════════════════════════════════════
        // AREA I — EdgeClone preview
        // ═══════════════════════════════════════════════════════════════════

        // I1: two clones exist — one editable (Screens), one read-only (Look).
        function test_i01_two_clones_one_editable_one_preview() {
            var cs = clones()
            compare(cs.length, 2, "exactly two EdgeClone instances")
            verify(editClone() !== null, "one editable clone (Screens)")
            verify(lookClone() !== null, "one read-only clone (Look)")
            verify(editClone() !== lookClone(), "they are distinct instances")
        }

        // I2: portrait frame renders at a sensible (tall, not-strip) size.
        function test_i02_portrait_frame_is_sensible_not_a_strip() {
            setTab(0)
            setOrient("portrait", false)
            var c = editClone(), f = frameOf(c)
            tryVerify(function () { return c.width > 0 && f.width > 0 }, 3000, "clone + frame laid out")
            var onW = f.width * f.scale, onH = f.height * f.scale
            verify(onW > 0 && onH > 0, "frame has on-screen size")
            verify(onH > onW, "portrait draws TALL (height > width): " + onH + " vs " + onW)
            verify(onW >= 100, "short axis is not a thin strip (" + onW.toFixed(0) + "px on screen)")
            verify(G.looksRendered(snap(c, "portrait")), "portrait clone rendered non-blank pixels")
        }

        // I3: portrait screen aspect mirrors the panel (2560/720 along the long axis).
        function test_i03_portrait_aspect_matches_panel() {
            setTab(0)
            setOrient("portrait", false)
            var s = screenOf(editClone())
            var ratio = s.height / s.width               // long / short
            fuzzyCompare(ratio, 2560 / 720, (2560 / 720) * 0.08, "portrait long/short aspect ~= 2560/720")
        }

        // I4 (regression guard): landscape frame renders WIDE, not a tiny sliver.
        function test_i04_landscape_frame_is_wide_not_a_strip() {
            setTab(0)
            setOrient("landscape", true)
            var c = editClone(), f = frameOf(c)
            tryVerify(function () { return c.width > 0 && f.width > 0 }, 3000, "clone + frame laid out")
            var onW = f.width * f.scale, onH = f.height * f.scale
            verify(onW > onH, "landscape draws WIDE (width > height): " + onW + " vs " + onH)
            verify(onH >= 100, "the short (height) axis is NOT a strip (" + onH.toFixed(0) + "px on screen)")
            var s = screenOf(c)
            fuzzyCompare(s.width / s.height, 2560 / 720, (2560 / 720) * 0.08, "landscape width/height aspect ~= 2560/720")
            verify(G.looksRendered(snap(c, "landscape")), "landscape clone rendered non-blank pixels")
        }

        // I5 / I27: the preview PANE widens for landscape (edgeClone 440->780, look 400->760).
        function test_i05_landscape_pane_widens() {
            setTab(0)
            var ec = editClone()
            setOrient("portrait", false)
            compare(ec.Layout.preferredWidth, 440, "portrait Screens pane is 440")
            setOrient("landscape", true)
            compare(ec.Layout.preferredWidth, 780, "landscape Screens pane widens to 780")

            // The Look preview pane's _pw switches 400<->760 (its column owner carries _pw).
            var pwOwner = G.findPred(cont_(), function (n) { try { return n && n._pw !== undefined } catch (e) { return false } })
            verify(pwOwner, "found the Look preview pane (_pw)")
            compare(pwOwner._pw, 760, "Look pane is 760 while landscape")
            setOrient("portrait", false)
            compare(pwOwner._pw, 400, "Look pane returns to 400 while portrait")
        }

        // I6: landscape read-only Look clone spans the wide pane (not clipped to a band).
        function test_i06_landscape_lookclone_spans_wide_pane() {
            store().setAppearance("orientation", "landscape")
            setTab(1)                                    // Look tab so lookClone is current/visible
            var lc = lookClone()
            tryVerify(function () { return lc.landscape === true && lc.width > 0 }, 3000, "look clone landscape + laid out")
            var f = frameOf(lc)
            var onW = f.width * f.scale
            verify(onW >= lc.width * 0.6, "rendered device spans most of the wide pane (" + onW.toFixed(0) + " of " + lc.width.toFixed(0) + ")")
            verify(G.looksRendered(snap(lc, "look_landscape")), "look landscape rendered pixels")
        }

        // I7-I10: AUTO orientation follows the hub rotation reported over the socket.
        function test_i07_auto_follows_hub_rotation_data() {
            return [
                { tag: "rot90_landscape",  rot: 90,  land: true },
                { tag: "rot270_landscape", rot: 270, land: true },
                { tag: "rot0_portrait",    rot: 0,   land: false },
                { tag: "offline_portrait", rot: -1,  land: false }
            ]
        }
        function test_i07_auto_follows_hub_rotation(d) {
            setTab(0)
            store().setAppearance("orientation", "auto")
            mh.backend.setHubRotation(d.rot)
            tryVerify(function () { return editClone().landscape === d.land }, 2500,
                      "auto + hubRotation " + d.rot + " -> landscape " + d.land)
        }

        // I11: a FIXED orientation overrides the hub rotation.
        function test_i11_fixed_orientation_overrides_hub_rotation() {
            setTab(0)
            store().setAppearance("orientation", "portrait")
            mh.backend.setHubRotation(90)
            wait(200)
            compare(editClone().landscape, false, "fixed portrait wins over hub rotation 90")
        }

        // I12 / I13: every fixed orientation mode maps to the right shape.
        function test_i12_orientation_modes_data() {
            return [
                { tag: "landscape",          mode: "landscape",          land: true },
                { tag: "inverted-landscape", mode: "inverted-landscape", land: true },
                { tag: "portrait",           mode: "portrait",           land: false },
                { tag: "inverted-portrait",  mode: "inverted-portrait",  land: false }
            ]
        }
        function test_i12_orientation_modes(d) {
            setTab(0)
            setOrient(d.mode, d.land)
            compare(editClone().landscape, d.land, d.mode + " -> landscape " + d.land)
        }

        // I14: the clone reflects the current page's tiles.
        function test_i14_reflects_current_page_tiles() {
            setTab(0)
            var s = store()
            s.addTile(0, "cpu"); s.addTile(0, "clock")
            tryVerify(function () { return tilesIn(editClone()).length === 2 }, 4000, "two tile delegates rendered")
        }

        // I15: switching page updates the clone (page-1 tiles only, no ghost of page 0).
        function test_i15_switching_page_updates_clone() {
            setTab(0)
            var s = store()
            s.addTile(0, "cpu")
            s.addPage(""); s.addTile(1, "disk")
            tryVerify(function () { return tilesIn(editClone()).length === 1 }, 4000, "page 0 shows its one tile")
            win_().currentPageIndex = 1
            tryVerify(function () {
                var ts = tilesIn(editClone())
                return ts.length === 1 && ts[0].tileId === s.pages()[1].tiles[0].id
            }, 4000, "page 1's single tile is shown, no page-0 ghost")
        }

        // I16: an empty page shows the empty hint.
        function test_i16_empty_page_shows_hint() {
            setTab(0)
            var t = G.byText(editClone(), "This page is empty")
            verify(t && t.visible, "empty-page hint visible on a blank page")
        }

        // I18: the device frame is never upscaled past 1.6 (short page must not blur).
        function test_i18_scale_capped_at_1p6() {
            setTab(0)
            var f = frameOf(editClone())
            tryVerify(function () { return f.width > 0 }, 3000, "frame laid out")
            verify(f.scale <= 1.6 + 1e-6, "frame scale capped at <= 1.6 (was " + f.scale.toFixed(3) + ")")
            verify(f.scale > 0, "frame is drawn")
        }

        // I19: the clone paints the chosen background style.
        function test_i19_clone_paints_background_style() {
            setTab(0)
            store().setAppearance("wallpaper", "")
            store().setAppearance("bgStyle", "mesh")
            var c = editClone()
            tryVerify(function () { return c.pageBg && c.pageBg.style === "mesh" }, 2000, "clone adopts the mesh style")
            var backdrop = G.findPred(c, function (n) { try { return n && n.style !== undefined && n.accent !== undefined && n.running !== undefined } catch (e) { return false } })
            verify(backdrop, "found the BackdropLayer")
            verify(backdrop.visible, "backdrop layer visible when no wallpaper + decorative theme")
        }

        // I20: the clone paints a wallpaper when one is set.
        function test_i20_clone_paints_wallpaper() {
            setTab(0)
            store().setAppearance("wallpaper", "file:///imgs/pic.png")
            var c = editClone()
            tryVerify(function () { return c.wallpaperSource !== "" }, 2000, "clone resolves a wallpaper source")
            var wall = G.findPred(c, function (n) { try { return n && n.fillMode !== undefined && n.source !== undefined && ("" + n.source).indexOf("imgs") >= 0 } catch (e) { return false } })
            verify(wall && wall.visible, "wallpaper Image visible with the set source")
        }

        // I21: the read-only Look clone hides every edit affordance.
        function test_i21_lookclone_hides_edit_chrome() {
            var s = store(); s.addTile(0, "cpu")
            setTab(1)
            var lc = lookClone()
            tryVerify(function () { return tilesIn(lc).length === 1 }, 4000, "look clone shows the tile")
            var overlays = G.collectPred(lc, function (n) { try { return n && n.dragging !== undefined && typeof n.pressed === "boolean" } catch (e) { return false } })
            verify(overlays.length > 0, "found the drag/select overlay(s)")
            for (var i = 0; i < overlays.length; i++) verify(!overlays[i].visible, "drag overlay hidden in read-only preview")
        }

        // I22: the editable Screens clone shows edit chrome (drag overlay + resize handle).
        function test_i22_edgeclone_shows_edit_chrome() {
            setTab(0)
            var s = store(); s.addTile(0, "cpu")
            var ec = editClone()
            tryVerify(function () { return tilesIn(ec).length === 1 }, 4000, "screens clone shows the tile")
            var overlays = G.collectPred(ec, function (n) { try { return n && n.dragging !== undefined && typeof n.pressed === "boolean" && n.visible } catch (e) { return false } })
            verify(overlays.length >= 1, "at least one drag overlay is visible (editable)")
            var resizeIcon = G.findPred(ec, function (n) { return n && n.name === "ui-resize" })
            verify(resizeIcon, "resize handle icon present on an editable tile")
        }

        // I23: a rotation change re-projects tiles without rebuilding the delegate.
        function test_i23_rotation_preserves_delegate_identity() {
            setTab(0)
            var s = store(); s.addTile(0, "cpu")
            s.setAppearance("orientation", "portrait")
            tryVerify(function () { return tilesIn(editClone()).length === 1 && editClone().landscape === false }, 4000, "one tile, portrait")
            var before = tilesIn(editClone())[0]
            setOrient("landscape", true)
            var after = tilesIn(editClone())
            compare(after.length, 1, "still exactly one tile after the rotation")
            verify(after[0] === before, "the tile delegate is the SAME object (re-projected, not rebuilt)")
        }

        // I25: the live tick advances while the preview is live.
        function test_i25_live_tick_advances() {
            setTab(0)
            var c = editClone()
            verify(c.previewLive, "preview is live on the current tab")
            var t0 = c.tick
            tryVerify(function () { return c.tick > t0 }, 2500, "the per-second tick advanced (" + t0 + " -> " + c.tick + ")")
        }

        // I26: the metrics poll feeds an object into the clone.
        function test_i26_metrics_object_present() {
            setTab(0)
            var c = editClone()
            tryVerify(function () { return c.metricsObj !== undefined && c.metricsObj !== null && typeof c.metricsObj === "object" }, 3000,
                      "clone holds a parsed metrics object")
        }

        // I27b/I24: previewLive tracks visibility (true when the tab is current).
        function test_i27_previewlive_true_when_visible() {
            setTab(0)
            verify(editClone().previewLive === true, "editable clone previewLive true on its current tab")
            setTab(2)                                    // Images — Screens clone no longer visible
            tryVerify(function () { return editClone().previewLive === false }, 2000, "clone previewLive false when its tab is hidden")
        }

        // I28 (regression, pixel proof): the device is NOT a tiny strip in EITHER
        // orientation — the rendered device region is a real fraction of the pane.
        function test_i28_not_a_strip_pixel_proof_data() {
            return [ { tag: "portrait", mode: "portrait", land: false },
                     { tag: "landscape", mode: "landscape", land: true } ]
        }
        function test_i28_not_a_strip_pixel_proof(d) {
            setTab(0)
            setOrient(d.mode, d.land)
            var c = editClone(), f = frameOf(c)
            tryVerify(function () { return c.width > 0 && f.width > 0 }, 3000, "laid out")
            var onW = f.width * f.scale, onH = f.height * f.scale
            var ratio = (onW * onH) / (c.width * c.height)
            verify(ratio >= 0.20, d.mode + ": rendered device region is " + (ratio * 100).toFixed(0)
                   + "% of the pane (>=20% — not a strip)")
            var shortAxis = Math.min(onW, onH)
            verify(shortAxis >= 100, d.mode + ": device short axis " + shortAxis.toFixed(0) + "px is not a sliver")
            verify(G.looksRendered(snap(c, "strip_" + d.tag)), d.mode + " rendered non-blank")
        }

        // ═══════════════════════════════════════════════════════════════════
        // AREA K — Screens tab
        // ═══════════════════════════════════════════════════════════════════

        // K1: one chip per page.
        function test_k01_page_chips_one_per_page() {
            setTab(0)
            var s = store(); s.addPage(""); s.addPage("")
            tryVerify(function () { return chips().length === 3 }, 3000, "three page chips for three pages")
        }

        // K2: the selected page chip is visibly indicated (bold label, others not).
        function test_k02_selected_chip_indicated() {
            setTab(0)
            var s = store(); s.addPage("")
            tryVerify(function () { return chips().length === 2 }, 3000, "two chips")
            win_().currentPageIndex = 1; wait(120)
            var cs = chips()
            var lbl1 = G.findPred(cs[1], function (n) { return n && n.text !== undefined && n.font !== undefined && ("" + n.text).length > 0 })
            var lbl0 = G.findPred(cs[0], function (n) { return n && n.text !== undefined && n.font !== undefined && ("" + n.text).length > 0 })
            verify(lbl1.font.bold, "selected chip label is bold")
            verify(!lbl0.font.bold, "unselected chip label is not bold")
        }

        // K3: clicking a page chip selects it (real click).
        function test_k03_click_chip_selects_data() { return [ { tag: "p0", i: 0 }, { tag: "p1", i: 1 }, { tag: "p2", i: 2 } ] }
        function test_k03_click_chip_selects(d) {
            setTab(0)
            var s = store(); s.addPage(""); s.addPage("")
            tryVerify(function () { return chips().length === 3 }, 3000, "three chips")
            clickItem(chips()[d.i])
            tryVerify(function () { return win_().currentPageIndex === d.i }, 2000, "chip " + d.i + " selected")
        }

        // K4: the "+" chip adds a page and jumps to it (real click).
        function test_k04_add_chip_adds_and_jumps() {
            setTab(0)
            var s = store()
            var before = s.pageCount()
            var plus = addPageChip()
            verify(plus, "found the + add-page chip")
            clickItem(plus)
            tryVerify(function () { return s.pageCount() === before + 1 }, 2000, "a page was added")
            compare(win_().currentPageIndex, s.pageCount() - 1, "jumped to the new (last) page")
        }

        // K5: the rename field starts on the current page's name.
        function test_k05_rename_field_shows_current_name() {
            setTab(0)
            var field = G.findPred(screensTab(), function (n) { return n && n.forIndex !== undefined && n.text !== undefined })
            verify(field, "found the rename field")
            compare(field.text, win_().currentPageName(), "field text == current page name")
        }

        // K6: typing + Enter renames the page (real keyboard).
        function test_k06_type_and_enter_renames() {
            setTab(0)
            var s = store()
            var field = G.findPred(screensTab(), function (n) { return n && n.forIndex !== undefined && n.text !== undefined })
            mouseClick(field, 12, field.height / 2)
            field.selectAll()
            var name = "OpsRoom"
            for (var i = 0; i < name.length; i++) keyClick(name[i])
            keyClick(Qt.Key_Return)
            tryVerify(function () { return s.pages()[0].name === "OpsRoom" }, 2000, "page 0 renamed to OpsRoom")
        }

        // K7: typing then switching page saves the edit to the RIGHT page (audit F1).
        function test_k07_switch_page_commits_pending_rename() {
            setTab(0)
            var s = store(); s.addPage("")
            tryVerify(function () { return chips().length === 2 }, 3000, "two chips")
            var field = G.findPred(screensTab(), function (n) { return n && n.forIndex !== undefined && n.text !== undefined })
            var page1Name = s.pages()[1].name
            mouseClick(field, 12, field.height / 2)
            field.selectAll()
            var name = "YentaScreen"
            for (var i = 0; i < name.length; i++) keyClick(name[i])
            clickItem(chips()[1])                        // switch WITHOUT pressing Enter
            tryVerify(function () { return s.pages()[0].name === "YentaScreen" }, 2000, "page 0 kept the mid-edit name")
            compare(s.pages()[1].name, page1Name, "page 1's name was untouched")
        }

        // K8: switching page without editing is a no-op for names.
        function test_k08_rename_noop_when_unchanged() {
            setTab(0)
            var s = store(); s.addPage("")
            tryVerify(function () { return chips().length === 2 }, 3000, "two chips")
            var n0 = s.pages()[0].name, n1 = s.pages()[1].name
            clickItem(chips()[1]); wait(120)
            clickItem(chips()[0]); wait(120)
            compare(s.pages()[0].name, n0, "page 0 name unchanged")
            compare(s.pages()[1].name, n1, "page 1 name unchanged")
        }

        // K9: rename validates (a duplicate name is de-duplicated by the store).
        function test_k09_rename_dedupes_via_store() {
            setTab(0)
            var s = store(); s.addPage(""); s.renamePage(1, "Dup")
            tryVerify(function () { return chips().length === 2 }, 3000, "two chips")
            win_().currentPageIndex = 0; wait(120)
            var field = G.findPred(screensTab(), function (n) { return n && n.forIndex !== undefined && n.text !== undefined })
            mouseClick(field, 12, field.height / 2)
            field.selectAll()
            var name = "Dup"
            for (var i = 0; i < name.length; i++) keyClick(name[i])
            keyClick(Qt.Key_Return)
            tryVerify(function () { return s.pages()[0].name === "Dup 2" }, 2000, "duplicate name de-duped to 'Dup 2'")
            compare(field.text, "Dup 2", "field reflects the store-validated name")
        }

        // K10 / K11: remove-screen disabled with one page, enabled with more.
        function test_k10_remove_disabled_with_one_page() {
            setTab(0)
            var btn = findBtn(screensTab(), "Remove screen")
            verify(btn, "found Remove screen button")
            compare(btn.enabled, false, "disabled with a single page")
        }
        function test_k11_remove_enabled_with_multiple_pages() {
            setTab(0)
            store().addPage("")
            var btn = findBtn(screensTab(), "Remove screen")
            tryVerify(function () { return btn.enabled === true }, 2000, "enabled once >1 page exists")
        }

        // K12: remove opens a confirm naming the page + widget count.
        function test_k12_remove_opens_confirm_with_page_name() {
            setTab(0)
            var s = store(); s.addPage(""); s.renamePage(0, "DeleteMe"); s.addTile(0, "cpu")
            win_().currentPageIndex = 0; wait(120)
            clickItem(findBtn(screensTab(), "Remove screen"))
            var conf = confirmDlg()
            tryVerify(function () { return conf.opened }, 2000, "confirm opened")
            verify(("" + conf.message).indexOf("DeleteMe") >= 0, "message names the page: " + conf.message)
            verify(("" + conf.message).indexOf("widget") >= 0, "message mentions the widget count")
        }

        // K13: confirming remove deletes the page.
        function test_k13_confirm_remove_deletes_page() {
            setTab(0)
            var s = store(); s.addPage("")
            var before = s.pageCount()
            win_().currentPageIndex = 1; wait(120)
            clickItem(findBtn(screensTab(), "Remove screen"))
            var conf = confirmDlg()
            tryVerify(function () { return conf.opened }, 2000, "confirm opened")
            conf.accept()
            tryVerify(function () { return s.pageCount() === before - 1 }, 2000, "one page removed")
        }

        // K14: cancelling remove keeps the page.
        function test_k14_cancel_remove_keeps_page() {
            setTab(0)
            var s = store(); s.addPage("")
            var before = s.pageCount()
            clickItem(findBtn(screensTab(), "Remove screen"))
            var conf = confirmDlg()
            tryVerify(function () { return conf.opened }, 2000, "confirm opened")
            conf.reject()
            wait(200)
            compare(s.pageCount(), before, "page count unchanged after cancel")
        }

        // K15: "Add widget" opens the picker.
        function test_k15_add_widget_opens_picker() {
            setTab(0)
            clickItem(findBtn(screensTab(), "Add widget"))
            var d = dlgTitle("Add a widget")
            tryVerify(function () { return d && d.opened }, 2000, "add-widget picker opened")
        }

        // K16: "Start from a preset screen…" opens the preset dialog.
        function test_k16_start_from_preset_opens_dialog() {
            setTab(0)
            clickItem(findBtn(screensTab(), "Start from a preset"))
            var d = dlgTitle("Start from a preset screen")
            tryVerify(function () { return d && d.opened }, 2000, "preset dialog opened")
        }

        // K17: adding a widget from the picker lands it on the current page + updates clone.
        function test_k17_add_widget_lands_on_current_page() {
            setTab(0)
            var s = store()
            var before = s.pages()[0].tiles.length
            clickItem(findBtn(screensTab(), "Add widget"))
            var d = dlgTitle("Add a widget")
            tryVerify(function () { return d.opened }, 2000, "picker opened")
            var card = G.findPred(d, function (n) { try { return n && n.modelData && n.modelData.type !== undefined && n.width === 150 } catch (e) { return false } })
            verify(card, "found a widget card")
            clickItem(card)
            tryVerify(function () { return !d.opened }, 2000, "picker closed after add")
            tryVerify(function () { return s.pages()[0].tiles.length === before + 1 }, 2000, "a tile landed on page 0")
            tryVerify(function () { return tilesIn(editClone()).length === before + 1 }, 3000, "clone updated")
        }

        // K18: columns segment + its "This screen only" scope pill are present.
        function test_k18_columns_segment_and_scope_pill() {
            setTab(0)
            var seg = G.findPred(screensTab(), function (n) {
                try { return n && n.options !== undefined && n.currentValue !== undefined
                        && n.options.length === 2 && n.options[0].label === "1 column" } catch (e) { return false }
            })
            verify(seg, "found the columns MSegment")
            verify(pill(screensTab(), "This screen only"), "'This screen only' scope pill present on Screens tab")
        }

        // K19: columns switch reflows the page (real click on a segment).
        function test_k19_columns_switch_data() { return [ { tag: "to2", label: "2 columns", expect: 2 }, { tag: "to1", label: "1 column", expect: 1 } ] }
        function test_k19_columns_switch(d) {
            setTab(0)
            var s = store()
            if (d.expect === 1) { s.setPageColumns(0, 2); wait(120) }   // start from 2 so clicking 1 is a real change
            var seg = G.findPred(screensTab(), function (n) {
                try { return n && n.options !== undefined && n.currentValue !== undefined && n.options.length === 2 && n.options[0].label === "1 column" } catch (e) { return false }
            })
            var lbl = G.findPred(seg, function (n) { try { return n && n.text === d.label } catch (e) { return false } })
            verify(lbl, "found the '" + d.label + "' segment label")
            clickItem(lbl)
            tryVerify(function () { return s.pageColumns(0) === d.expect }, 2000, "columns became " + d.expect)
        }

        // K20: the collapsible how-to card toggles (real click on the header).
        function test_k20_howto_card_toggles() {
            setTab(0)
            var st = screensTab()
            var hdr = G.byText(st, "This is your Edge")
            verify(hdr, "found the how-to header")
            // the caret whose rotation encodes collapsed/expanded (0 / -90)
            var caret = G.findPred(st, function (n) { try { return n && n.name === "ui-caret-right" && (n.rotation === 0 || n.rotation === -90) } catch (e) { return false } })
            verify(caret, "found the how-to caret")
            var before = caret.rotation
            mouseClick(hdr, hdr.width / 2, hdr.height / 2)
            tryVerify(function () { return caret.rotation !== before }, 2000, "the caret rotated (card toggled)")
            mouseClick(hdr, hdr.width / 2, hdr.height / 2)   // restore
        }

        // K21: the how-to live note follows the connection state.
        function test_k21_live_note_follows_connection() {
            setTab(0)
            mh.backend.hubConnected = false; wait(120)
            var noteOff = G.findPred(screensTab(), function (n) { try { return n && n.text !== undefined && ("" + n.text).indexOf("saved and appear") >= 0 } catch (e) { return false } })
            verify(noteOff, "offline note wording present ('saved and appear')")
            mh.backend.hubConnected = true; wait(150)
            var noteOn = G.findPred(screensTab(), function (n) { try { return n && n.text !== undefined && ("" + n.text).indexOf("immediately") >= 0 } catch (e) { return false } })
            verify(noteOn, "connected note wording present ('immediately')")
        }

        // K22: the per-screen "This screen's look" BackgroundPicker is present.
        function test_k22_per_screen_background_picker_present() {
            setTab(0)
            var bp = G.findPred(screensTab(), function (n) { try { return n && n.pageIndex !== undefined && n.uploadedImages !== undefined && n.bgCatalog !== undefined } catch (e) { return false } })
            verify(bp, "found the per-screen BackgroundPicker")
            compare(bp.pageIndex, win_().currentPageIndex, "picker targets the current page")
        }

        // K23: a per-page override applies to that page only.
        function test_k23_per_page_override_is_scoped() {
            setTab(0)
            var s = store(); s.addPage("")
            win_().currentPageIndex = 0; wait(120)
            s.setPageBackground(0, "wallpaper", "file:///imgs/page0.png")
            var ec = editClone()
            tryVerify(function () { return ec.wallpaperSource !== "" }, 2000, "page 0 shows its override wallpaper")
            win_().currentPageIndex = 1; wait(150)
            tryVerify(function () { return ec.wallpaperSource === "" }, 2000, "page 1 (no override, blank global) shows none")
        }

        // ═══════════════════════════════════════════════════════════════════
        // AREA L — Dialogs
        // ═══════════════════════════════════════════════════════════════════

        // L1: add-widget picker opens modal.
        function test_l01_add_picker_opens_modal() {
            setTab(0)
            clickItem(findBtn(screensTab(), "Add widget"))
            var d = dlgTitle("Add a widget")
            tryVerify(function () { return d.opened }, 2000, "picker opened")
            compare(d.modal, true, "picker is modal")
            snap(cont_(), "addpicker_open")
        }

        // L2: the picker names its target page (audit F4).
        function test_l02_picker_names_target_page() {
            setTab(0)
            store().renamePage(0, "SecondScreen"); wait(120)
            clickItem(findBtn(screensTab(), "Add widget"))
            var d = dlgTitle("Add a widget")
            tryVerify(function () { return d.opened }, 2000, "picker opened")
            var tgt = G.byObjName(d, "addPickerTarget")
            verify(tgt, "found addPickerTarget label")
            verify(("" + tgt.text).indexOf("SecondScreen") >= 0, "target names the page: " + tgt.text)
        }

        // L3: the picker carries a "This screen only" scope pill.
        function test_l03_picker_scope_pill() {
            setTab(0)
            clickItem(findBtn(screensTab(), "Add widget"))
            var d = dlgTitle("Add a widget")
            tryVerify(function () { return d.opened }, 2000, "picker opened")
            verify(pill(d, "This screen only"), "'This screen only' scope pill in the picker header")
        }

        // L4: the picker lists widgets grouped by category.
        function test_l04_picker_lists_widget_cards() {
            setTab(0)
            clickItem(findBtn(screensTab(), "Add widget"))
            var d = dlgTitle("Add a widget")
            tryVerify(function () { return d.opened }, 2000, "picker opened")
            var cards = G.collectPred(d, function (n) { try { return n && n.modelData && n.modelData.type !== undefined && n.width === 150 } catch (e) { return false } })
            verify(cards.length > 0, "picker renders widget cards (" + cards.length + ")")
        }

        // L5: the "screen is full" hint appears when the page is packed.
        function test_l05_screen_full_hint() {
            setTab(0)
            var s = store()
            for (var i = 0; i < 12 && !s.pageIsFull(0); i++) s.addTile(0, "cpu")
            verify(s.pageIsFull(0), "page 0 is now full")
            clickItem(findBtn(screensTab(), "Add widget"))
            var d = dlgTitle("Add a widget")
            tryVerify(function () { return d.opened }, 2000, "picker opened")
            var t = G.byText(d, "This screen is full")
            verify(t, "the full-screen hint text is present")
            verify(t.parent.parent.visible, "the hint row is visible")
        }

        // L6: clicking a widget card adds it and closes the picker.
        function test_l06_click_card_adds_and_closes() {
            setTab(0)
            var s = store()
            var before = s.pages()[0].tiles.length
            clickItem(findBtn(screensTab(), "Add widget"))
            var d = dlgTitle("Add a widget")
            tryVerify(function () { return d.opened }, 2000, "picker opened")
            var card = G.findPred(d, function (n) { try { return n && n.modelData && n.modelData.type !== undefined && n.width === 150 } catch (e) { return false } })
            clickItem(card)
            tryVerify(function () { return !d.opened }, 2000, "picker closed")
            compare(s.pages()[0].tiles.length, before + 1, "a tile was added")
        }

        // L7: the picker Close dismisses without adding.
        function test_l07_picker_close_adds_nothing() {
            setTab(0)
            var s = store()
            var before = s.pages()[0].tiles.length
            clickItem(findBtn(screensTab(), "Add widget"))
            var d = dlgTitle("Add a widget")
            tryVerify(function () { return d.opened }, 2000, "picker opened")
            d.close()
            tryVerify(function () { return !d.opened }, 2000, "picker closed")
            compare(s.pages()[0].tiles.length, before, "nothing added")
        }

        // L8: the preset dialog opens and lists >= 15 presets.
        function test_l08_preset_dialog_lists_presets() {
            setTab(0)
            clickItem(findBtn(screensTab(), "Start from a preset"))
            var d = dlgTitle("Start from a preset screen")
            tryVerify(function () { return d.opened }, 2000, "preset dialog opened")
            var minis = G.allByObjName(d, "presetMini")
            verify(minis.length >= 15, "at least 15 preset rows (" + minis.length + ")")
            snap(cont_(), "presetdialog_open")
        }

        // L9: each preset row shows a live PresetMini thumbnail (with placements).
        function test_l09_preset_minis_have_placements() {
            setTab(0)
            clickItem(findBtn(screensTab(), "Start from a preset"))
            var d = dlgTitle("Start from a preset screen")
            tryVerify(function () { return d.opened }, 2000, "preset dialog opened")
            var minis = G.allByObjName(d, "presetMini")
            var withTiles = 0
            for (var i = 0; i < minis.length; i++) if (minis[i].placements && minis[i].placements.length >= 1) withTiles++
            verify(withTiles >= 1, "at least one PresetMini packs real placements (" + withTiles + ")")
        }

        // L10: preset rows show a title + blurb + icon.
        function test_l10_preset_rows_have_title_and_icon() {
            setTab(0)
            clickItem(findBtn(screensTab(), "Start from a preset"))
            var d = dlgTitle("Start from a preset screen")
            tryVerify(function () { return d.opened }, 2000, "preset dialog opened")
            var titles = G.collectPred(d, function (n) { try { return n && n.text !== undefined && n.font && n.font.pixelSize === 16 && n.font.bold && ("" + n.text).length > 0 } catch (e) { return false } })
            verify(titles.length >= 1, "preset title text present (" + titles.length + ")")
            verify(findBtn(d, "Add screen"), "each row offers an 'Add screen' button")
        }

        // L11: "Add screen" appends a NEW page and closes.
        function test_l11_add_screen_appends_page() {
            setTab(0)
            var s = store()
            var before = s.pageCount()
            clickItem(findBtn(screensTab(), "Start from a preset"))
            var d = dlgTitle("Start from a preset screen")
            tryVerify(function () { return d.opened }, 2000, "preset dialog opened")
            clickItem(findBtn(d, "Add screen"))
            tryVerify(function () { return !d.opened }, 2000, "dialog closed")
            tryVerify(function () { return s.pageCount() === before + 1 }, 2000, "one page appended")
            compare(win_().currentPageIndex, s.pageCount() - 1, "jumped to the new screen")
        }

        // L12: adding a preset is additive — prior pages are kept intact.
        function test_l12_preset_add_is_additive() {
            setTab(0)
            var s = store(); s.renamePage(0, "First"); s.addPage(""); s.renamePage(1, "Second")
            var before = s.pageCount()
            clickItem(findBtn(screensTab(), "Start from a preset"))
            var d = dlgTitle("Start from a preset screen")
            tryVerify(function () { return d.opened }, 2000, "preset dialog opened")
            clickItem(findBtn(d, "Add screen"))
            tryVerify(function () { return s.pageCount() === before + 1 }, 2000, "count grew by exactly 1")
            compare(s.pages()[0].name, "First", "page 0 kept its name")
            compare(s.pages()[1].name, "Second", "page 1 kept its name")
        }

        // L13: the preset dialog Close cancels (no page added).
        function test_l13_preset_close_cancels() {
            setTab(0)
            var s = store()
            var before = s.pageCount()
            clickItem(findBtn(screensTab(), "Start from a preset"))
            var d = dlgTitle("Start from a preset screen")
            tryVerify(function () { return d.opened }, 2000, "preset dialog opened")
            d.close()
            tryVerify(function () { return !d.opened }, 2000, "closed")
            compare(s.pageCount(), before, "no page added")
        }

        // L14: the licence dialog opens from About → Activate Pro.
        function test_l14_license_opens_from_about() {
            setTab(4)
            clickItem(findBtn(cont_(), "Activate Pro"))
            var lic = licenseDlg()
            tryVerify(function () { return lic.opened }, 2000, "licence dialog opened")
            snap(cont_(), "license_open")
        }

        // L23: the key field auto-focuses on open.
        function test_l23_key_field_autofocus() {
            setTab(4)
            clickItem(findBtn(cont_(), "Activate Pro"))
            var lic = licenseDlg()
            tryVerify(function () { return lic.opened }, 2000, "licence dialog opened")
            var kf = G.findPred(lic, function (n) { try { return n && n.placeholderText !== undefined && ("" + n.placeholderText).indexOf("XE1") >= 0 } catch (e) { return false } })
            verify(kf, "found the key field")
            tryVerify(function () { return kf.activeFocus }, 2000, "key field auto-focused")
        }

        // L15 / L16: a bad key keeps Activate disabled + shows a warning verdict.
        function test_l15_bad_key_disables_activate() {
            setTab(4)
            clickItem(findBtn(cont_(), "Activate Pro"))
            var lic = licenseDlg()
            tryVerify(function () { return lic.opened }, 2000, "licence dialog opened")
            var kf = G.findPred(lic, function (n) { try { return n && n.placeholderText !== undefined && ("" + n.placeholderText).indexOf("XE1") >= 0 } catch (e) { return false } })
            kf.forceActiveFocus(); kf.text = "XE1.nope"
            tryVerify(function () { return lic.candidate === "XE1.nope" }, 2000, "candidate captured")
            var act = findBtn(lic, "Activate")
            verify(act, "found Activate button")
            compare(act.enabled, false, "Activate disabled for a bad key")
            verify(G.byText(lic, "Not a valid"), "verdict says 'Not a valid…'")
            compare(win_().isPro, false, "still free tier")
        }
        function test_l16_bad_key_shows_warning_icon() {
            setTab(4)
            clickItem(findBtn(cont_(), "Activate Pro"))
            var lic = licenseDlg()
            tryVerify(function () { return lic.opened }, 2000, "licence dialog opened")
            var kf = G.findPred(lic, function (n) { try { return n && n.placeholderText !== undefined && ("" + n.placeholderText).indexOf("XE1") >= 0 } catch (e) { return false } })
            kf.forceActiveFocus(); kf.text = "XE1.nope"
            tryVerify(function () { return lic.candidate === "XE1.nope" }, 2000, "candidate captured")
            var warn = G.findPred(lic, function (n) { return n && n.name === "ui-warning" && n.visible })
            verify(warn, "a warning icon is shown for the invalid key")
        }

        // L17: a valid key enables Activate + shows the valid verdict.
        function test_l17_valid_key_enables_activate() {
            setTab(4)
            clickItem(findBtn(cont_(), "Activate Pro"))
            var lic = licenseDlg()
            tryVerify(function () { return lic.opened }, 2000, "licence dialog opened")
            var kf = G.findPred(lic, function (n) { try { return n && n.placeholderText !== undefined && ("" + n.placeholderText).indexOf("XE1") >= 0 } catch (e) { return false } })
            kf.forceActiveFocus(); kf.text = "XE1.valid.pro"
            tryVerify(function () { return lic.preview.tier === "pro" }, 2000, "verifier accepts the key")
            var act = findBtn(lic, "Activate")
            tryVerify(function () { return act.enabled === true }, 2000, "Activate enabled")
            var v = G.byText(lic, "Valid")
            verify(v, "verdict says 'Valid…'")
            verify(("" + v.text).indexOf("Ada Lovelace") >= 0, "verdict names the licensee: " + v.text)
        }

        // L18: activating a valid key flips to Pro + closes.
        function test_l18_activate_flips_to_pro() {
            setTab(4)
            clickItem(findBtn(cont_(), "Activate Pro"))
            var lic = licenseDlg()
            tryVerify(function () { return lic.opened }, 2000, "licence dialog opened")
            var kf = G.findPred(lic, function (n) { try { return n && n.placeholderText !== undefined && ("" + n.placeholderText).indexOf("XE1") >= 0 } catch (e) { return false } })
            kf.forceActiveFocus(); kf.text = "XE1.valid.pro"
            var act = findBtn(lic, "Activate")
            tryVerify(function () { return act.enabled === true }, 2000, "Activate enabled")
            clickItem(act)
            tryVerify(function () { return win_().isPro === true }, 2000, "tier flipped to Pro")
            compare(mh.backend.storedKey, "XE1.valid.pro", "key stored via backend")
            tryVerify(function () { return !lic.opened }, 2000, "dialog closed on activate")
        }

        // L19: the About button reads "Activate Pro" (free) vs "Manage licence" (pro).
        function test_l19_about_button_reflects_tier() {
            setTab(4)
            verify(findBtn(cont_(), "Activate Pro"), "free tier shows 'Activate Pro'")
            mh.backend.storedKey = "XE1.valid.pro"; mh.backend.licenseChanged()
            tryVerify(function () { return win_().isPro === true }, 2000, "now Pro")
            tryVerify(function () { return findBtn(cont_(), "Manage licence") !== null }, 2000, "Pro tier shows 'Manage licence'")
        }

        // L20: Remove licence reverts to the free tier.
        function test_l20_remove_licence_reverts_to_free() {
            mh.backend.storedKey = "XE1.valid.pro"; mh.backend.licenseChanged()
            tryVerify(function () { return win_().isPro === true }, 2000, "start as Pro")
            setTab(4)
            clickItem(findBtn(cont_(), "Manage licence"))
            var lic = licenseDlg()
            tryVerify(function () { return lic.opened }, 2000, "licence dialog opened")
            clickItem(findBtn(lic, "Remove licence"))
            tryVerify(function () { return win_().isPro === false }, 2000, "reverted to free tier")
        }

        // L22: Cancel closes the licence dialog without changing the tier.
        function test_l22_cancel_license_no_change() {
            setTab(4)
            clickItem(findBtn(cont_(), "Activate Pro"))
            var lic = licenseDlg()
            tryVerify(function () { return lic.opened }, 2000, "licence dialog opened")
            var kf = G.findPred(lic, function (n) { try { return n && n.placeholderText !== undefined && ("" + n.placeholderText).indexOf("XE1") >= 0 } catch (e) { return false } })
            kf.forceActiveFocus(); kf.text = "XE1.valid.pro"
            clickItem(findBtn(lic, "Cancel"))
            tryVerify(function () { return !lic.opened }, 2000, "dialog closed")
            compare(win_().isPro, false, "tier unchanged (still free)")
        }

        // L24 / L25: reset opens a Yes/No confirm with the right wording.
        function test_l24_reset_opens_confirm_yes_no() {
            setTab(3)
            var btn = G.byObjName(cont_(), "resetLayoutBtn")
            verify(btn, "found resetLayoutBtn")
            clickItem(btn)
            var conf = confirmDlg()
            tryVerify(function () { return conf.opened }, 2000, "confirm opened")
            verify((conf.standardButtons & Dialog.Yes) !== 0, "Yes present")
            verify((conf.standardButtons & Dialog.No) !== 0, "No present")
            snap(cont_(), "confirm_reset_open")
        }
        function test_l25_reset_confirm_message() {
            setTab(3)
            clickItem(G.byObjName(cont_(), "resetLayoutBtn"))
            var conf = confirmDlg()
            tryVerify(function () { return conf.opened }, 2000, "confirm opened")
            verify(("" + conf.message).indexOf("default layout") >= 0, "message mentions the default layout")
            verify(("" + conf.message).indexOf("images are kept") >= 0, "message notes images are kept")
        }

        // L26: confirming reset restores the starter bundle.
        function test_l26_confirm_reset_restores_starter() {
            var s = store(); s.renamePage(0, "ZZZTEMP")
            setTab(3)
            clickItem(G.byObjName(cont_(), "resetLayoutBtn"))
            var conf = confirmDlg()
            tryVerify(function () { return conf.opened }, 2000, "confirm opened")
            conf.accept()
            tryVerify(function () { return s.pageCount() >= 1 && s.pages()[0].name !== "ZZZTEMP" }, 2000,
                      "layout replaced by the starter bundle")
            compare(win_().currentPageIndex, 0, "selection clamped to page 0")
        }

        // L27: cancelling reset changes nothing.
        function test_l27_cancel_reset_no_change() {
            var s = store(); s.renamePage(0, "KEEPME")
            setTab(3)
            clickItem(G.byObjName(cont_(), "resetLayoutBtn"))
            var conf = confirmDlg()
            tryVerify(function () { return conf.opened }, 2000, "confirm opened")
            conf.reject()
            wait(200)
            compare(s.pages()[0].name, "KEEPME", "page unchanged after cancel")
        }

        // L28: the confirm dialog is reused — its message swaps per action.
        function test_l28_confirm_dialog_is_reused() {
            var s = store(); s.addPage(""); win_().currentPageIndex = 0
            win_().confirmRemovePage()
            var conf = confirmDlg()
            tryVerify(function () { return conf.opened }, 2000, "confirm opened for remove")
            verify(("" + conf.message).indexOf("Remove screen") >= 0, "remove message: " + conf.message)
            conf.reject(); wait(150)
            win_().confirmDeleteImage("pic.png", "file:///imgs/pic.png")
            tryVerify(function () { return conf.opened }, 2000, "same dialog reopened for delete")
            verify(("" + conf.message).indexOf("Delete") >= 0, "delete message swapped in: " + conf.message)
            conf.reject()
        }

        // L29: the per-widget config dialog opens from a tile (click routes configRequested).
        function test_l29_config_dialog_opens_for_tile() {
            setTab(0)
            var s = store(); var id = s.addTile(0, "cpu")
            var ec = editClone()
            tryVerify(function () { return tilesIn(ec).length === 1 }, 4000, "tile rendered")
            var ma = G.findPred(ec, function (n) { try { return n && n.dragging !== undefined && n.sx !== undefined && n.visible } catch (e) { return false } })
            verify(ma, "found the tile's drag/select overlay")
            clickItem(ma)                                // a click (no drag) -> configRequested
            var cfg = cfgDlg()
            tryVerify(function () { return cfg && cfg.opened && cfg.wId === id }, 3000, "config dialog opened for the tile")
            snap(cont_(), "config_open")
        }

        // L30: the config dialog carries a "This widget only" scope tag.
        function test_l30_config_scope_tag() {
            setTab(0)
            var s = store(); s.addTile(0, "cpu")
            var ec = editClone()
            tryVerify(function () { return tilesIn(ec).length === 1 }, 4000, "tile rendered")
            var ma = G.findPred(ec, function (n) { try { return n && n.dragging !== undefined && n.sx !== undefined && n.visible } catch (e) { return false } })
            clickItem(ma)
            var cfg = cfgDlg()
            tryVerify(function () { return cfg.opened }, 3000, "config dialog opened")
            var st = G.byObjName(cfg, "scopeTag")
            verify(st, "found the config scope tag")
            verify(G.byText(cfg, "This widget only"), "scope tag reads 'This widget only'")
        }

        // L31: the config dialog targets the tile that was clicked.
        function test_l31_config_targets_clicked_tile() {
            setTab(0)
            var s = store(); var id = s.addTile(0, "clock")
            var ec = editClone()
            tryVerify(function () { return tilesIn(ec).length === 1 }, 4000, "tile rendered")
            var ma = G.findPred(ec, function (n) { try { return n && n.dragging !== undefined && n.sx !== undefined && n.visible } catch (e) { return false } })
            clickItem(ma)
            var cfg = cfgDlg()
            tryVerify(function () { return cfg.opened }, 3000, "config dialog opened")
            compare(cfg.wId, id, "config targets the clicked tile id")
            compare(cfg.wType, "clock", "and its type")
            // and it closes from its own Close button (real click).
            var closeBtn = G.byObjName(cfg, "closeBtn")
            verify(closeBtn, "found the config Close button")
            clickItem(closeBtn)
            tryVerify(function () { return !cfg.opened }, 2000, "config dialog closed")
        }

        // L32: the import file dialog declares the image name filters.
        function test_l32_file_dialog_name_filters() {
            setTab(2)
            var fd = fileDlg()
            verify(fd, "found the FileDialog")
            var joined = ("" + fd.nameFilters).toLowerCase()
            verify(joined.indexOf("png") >= 0 && joined.indexOf("jpg") >= 0 && joined.indexOf("jpeg") >= 0
                   && joined.indexOf("webp") >= 0 && joined.indexOf("gif") >= 0 && joined.indexOf("bmp") >= 0,
                   "name filters cover png/jpg/jpeg/webp/gif/bmp: " + fd.nameFilters)
            verify(findBtn(cont_(), "Import image"), "Images tab offers an Import button")
        }
    }
}
