import QtQuick
import QtTest
import "GuiUtil.js" as G

// Visible GUI tests for the Manager "Look" tab Appearance section:
//   Area D — Edge THEME dropdown (open/apply/hover-preview/Pro-gate)
//   Area E — ACCENT swatches (14 house + 8 Okabe–Ito, incl. black), rings, hover
//
// Hosts the REAL manager/qml/Manager.qml window ONCE in a real KWin compositor
// via ManagerHarness, drives real mouse/keyboard events, and asserts objective,
// GUI-observable outcomes: store settings reflected in the live theme, the
// preview EdgeClone backdrop repainting (grabImage pixel diff), and the accent
// selection ring / black-swatch visibility proven by grabImage. Every case saves
// a PNG frame under gui-evidence/ for the morning video.
Item {
    id: root
    width: 100; height: 100
    ManagerHarness { id: mh }

    TestCase {
        name: "GuiMgrThemeAccent"
        when: windowShown
        visible: true

        property var _store: null
        property var _theme: null

        function snap(item, name) {
            if (!item) return null
            var img = grabImage(item); img.save("gui-evidence/mgrta_" + name + ".png"); return img
        }

        // ── one-time hosting ────────────────────────────────────────────────
        function initTestCase() {
            var w = mh.create()
            verify(w !== null, "Manager.qml instantiated")
            tryVerify(function () { return mh.ready }, 8000, "Manager window visible")
            tryVerify(function () { return mh.win.active }, 5000, "Manager window active (mapped)")

            _store = G.findPred(mh.win, function (x) {
                try { return x && x.applyExternal !== undefined && x.structureRevision !== undefined } catch (e) { return false } })
            _theme = G.findPred(mh.win, function (x) {
                try { return x && x.themeCatalog !== undefined && typeof x.applyTheme === "function" } catch (e) { return false } })
            verify(_store !== null, "found the DashboardStore")
            verify(_theme !== null, "found the Theme")

            tabs().currentIndex = 1               // Look / Appearance tab
            wait(300)
        }
        function cleanupTestCase() { mh.destroyWin() }

        // Reset to a clean, isolated baseline before EVERY test row (QtTest runs
        // test_* alphabetically; each data row also gets init/cleanup).
        function init() {
            closePopupIfOpen()
            var dlg = licenseDlg(); if (dlg && dlg.opened) { dlg.close(); wait(80) }
            if (mh.win.isPro) { mh.backend.clearLicenseKey(); wait(80) }
            tabs().currentIndex = 1
            _store.setAppearance("themeMode", "dark")
            _store.setAppearance("accent", "blue")
            mouseMove(mh.win.contentItem, 3, 3)   // clear any residual hover
            wait(60)
        }
        function cleanup() {
            closePopupIfOpen()
            var dlg = licenseDlg(); if (dlg && dlg.opened) { dlg.close(); wait(60) }
            mouseMove(mh.win.contentItem, 3, 3)
        }

        // ── seam finders ────────────────────────────────────────────────────
        function tabs() { return G.byObjName(mh.win.contentItem, "managerTabs") }
        function field() { return G.byObjName(mh.win.contentItem, "themeDropdownField") }
        function lookClone() {
            return G.findPred(mh.win.contentItem, function (n) {
                try { return n && n.editable === false && n.landscape !== undefined } catch (e) { return false } })
        }
        function themeList() {
            return G.findPred(mh.win.contentItem, function (n) {
                try { return n && typeof n.positionViewAtIndex === "function"
                       && n.count === _theme.themeCatalog.length } catch (e) { return false } })
        }
        function licenseDlg() {
            return G.findPred(mh.win.contentItem, function (n) {
                try { return n && n.candidate !== undefined && n.preview !== undefined
                       && typeof n.open === "function" } catch (e) { return false } })
        }
        function accentSwatches() {
            return G.collectPred(mh.win.contentItem, function (n) {
                try { return n && n.radius === 23 && n.modelData && n.modelData.c !== undefined
                       && n.modelData.name !== undefined && n.sel !== undefined } catch (e) { return false } })
        }
        function swatchByName(nm) {
            var all = accentSwatches()
            for (var i = 0; i < all.length; i++) if (all[i].modelData.name === nm) return all[i]
            return null
        }
        function themeIndex(k) {
            var cat = _theme.themeCatalog
            for (var i = 0; i < cat.length; i++) if (cat[i].k === k) return i
            return -1
        }

        // ── helpers ─────────────────────────────────────────────────────────
        // Scroll the Look-tab MScroll so `item` is inside the viewport (real
        // clicks only land on on-screen pixels). Walks to the nearest Flickable.
        function ensureVisible(item) {
            var f = item ? item.parent : null
            while (f) {
                if (f.contentY !== undefined && f.contentHeight !== undefined
                    && typeof f.returnToBounds === "function") break
                f = f.parent
            }
            if (!f) return
            var pos = item.mapToItem(f.contentItem, 0, 0)
            var top = pos.y, bottom = top + item.height, view = f.height
            var maxY = Math.max(0, f.contentHeight - view)
            if (top < f.contentY) f.contentY = Math.max(0, top - 24)
            else if (bottom > f.contentY + view) f.contentY = Math.min(maxY, bottom - view + 24)
            wait(90)
        }
        function openThemePopup() {
            var lv = themeList()
            if (lv && lv.visible) return
            var f = field(); ensureVisible(f)
            mouseClick(f, Math.floor(f.width / 2), Math.floor(f.height / 2))
            tryVerify(function () { var l = themeList(); return l && l.visible && l.height > 0 }, 3000, "theme popup open")
            wait(120)
        }
        function closePopupIfOpen() {
            var lv = themeList()
            if (lv && lv.visible) { keyClick(Qt.Key_Escape); wait(140) }
        }
        function themeRow(k) {
            var lv = themeList(); var idx = themeIndex(k)
            lv.positionViewAtIndex(idx, ListView.Contain); wait(120)
            return lv.itemAtIndex(idx)
        }
        function clickThemeRow(k) {
            var row = themeRow(k); verify(row, "row realized for " + k)
            mouseClick(row, Math.floor(row.width / 2), Math.floor(row.height / 2))
        }
        function hoverThemeRow(k) {
            var row = themeRow(k); verify(row, "row realized for " + k)
            mouseMove(row, Math.floor(row.width / 2), Math.floor(row.height / 2))
        }
        // Max per-pixel channel distance over a sampled grid (two same-size grabs).
        function maxChDist(a, b) {
            var w = Math.min(a.width, b.width), h = Math.min(a.height, b.height), mx = 0
            for (var yi = 1; yi < 6; yi++) for (var xi = 1; xi < 6; xi++) {
                var x = Math.floor(w * xi / 6), y = Math.floor(h * yi / 6)
                var dr = a.red(x, y) - b.red(x, y), dg = a.green(x, y) - b.green(x, y), db = a.blue(x, y) - b.blue(x, y)
                var d = Math.sqrt(dr * dr + dg * dg + db * db); if (d > mx) mx = d
            }
            return mx
        }
        function hasNearWhite(img, x0, y0, x1, y1) {
            for (var y = y0; y < y1; y += 2) for (var x = x0; x < x1; x += 2)
                if (img.red(x, y) > 200 && img.green(x, y) > 200 && img.blue(x, y) > 200) return true
            return false
        }

        // ════════════════════════════ AREA D — THEME ════════════════════════

        function test_D1_field_present() {
            var f = field()
            verify(f !== null, "themeDropdownField found")
            verify(f.visible && f.width > 0 && f.height > 0, "field visible & sized on Look tab")
            snap(f, "field_present")
        }

        function test_D2_field_shows_committed_theme() {
            _store.setAppearance("themeMode", "nord"); wait(120)
            var f = field()
            compare(f.curKey, "nord", "field curKey reflects committed theme")
            var t = G.findPred(f, function (n) { try { return n && n.text === "Nord" && n.visible } catch (e) { return false } })
            verify(t !== null, "field shows the theme's display name 'Nord'")
            snap(f, "field_nord")
        }

        function test_D3_click_opens_popup() {
            var lv0 = themeList()
            verify(!(lv0 && lv0.visible), "popup starts closed")
            openThemePopup()
            verify(themeList().visible, "popup opened on field click")
            snap(mh.win.contentItem, "popup_open")
        }

        function test_D4_click_closes_popup() {
            openThemePopup()
            verify(themeList().visible, "popup open")
            var f = field()
            mouseClick(f, Math.floor(f.width / 2), Math.floor(f.height / 2))   // toggle closed
            tryVerify(function () { var l = themeList(); return !(l && l.visible) }, 3000, "popup closed on second click")
            snap(mh.win.contentItem, "popup_closed")
        }

        function test_D5_popup_lists_all_themes() {
            openThemePopup()
            compare(themeList().count, _theme.themeCatalog.length, "popup lists ALL themes (== catalogue)")
            compare(themeList().count, 29, "catalogue is the expected 29 themes")
            snap(mh.win.contentItem, "popup_all")
        }

        function test_D6_free_theme_applies_data() {
            return [
                { tag: "dark", k: "dark" }, { tag: "midnight", k: "midnight" }, { tag: "aurora", k: "aurora" },
                { tag: "sunset", k: "sunset" }, { tag: "nebula", k: "nebula" }, { tag: "deep_forest", k: "deep_forest" },
                { tag: "deep_ocean", k: "deep_ocean" }, { tag: "ember", k: "ember" }, { tag: "rose_gold", k: "rose_gold" },
                { tag: "nord", k: "nord" }, { tag: "dracula", k: "dracula" }, { tag: "solarized", k: "solarized" },
                { tag: "gruvbox", k: "gruvbox" }, { tag: "catppuccin", k: "catppuccin" }, { tag: "tokyonight", k: "tokyonight" },
                { tag: "aubergine", k: "aubergine" }, { tag: "crimson", k: "crimson" }, { tag: "oled", k: "oled" },
                { tag: "light", k: "light" }, { tag: "high_contrast", k: "high_contrast" }
            ]
        }
        function test_D6_free_theme_applies(d) {
            var baseline = (d.k === "light") ? "dark" : "light"
            _store.setAppearance("themeMode", baseline); wait(120)
            var before = grabImage(lookClone())
            openThemePopup()
            clickThemeRow(d.k)                                   // commits + closes popup
            wait(220)
            compare(_store.appearance().themeMode, d.k, "themeMode committed to " + d.k)
            var after = grabImage(lookClone())
            verify(maxChDist(before, after) > 20, "preview backdrop repainted for " + d.k)
            var img = snap(lookClone(), "theme_" + d.k)
            verify(G.looksRendered(img), "preview rendered non-blank")
        }

        function test_D7_applied_theme_shows_check_and_bold() {
            _store.setAppearance("themeMode", "nord"); wait(120)
            openThemePopup()
            var row = themeRow("nord"); verify(row, "nord row realized")
            verify(row.sel === true, "applied row marked selected")
            var chk = G.findPred(row, function (n) { try { return n && n.name === "ui-check" } catch (e) { return false } })
            verify(chk && chk.visible, "applied row shows the ui-check")
            var lbl = G.findPred(row, function (n) { try { return n && n.text === "Nord" && n.font !== undefined } catch (e) { return false } })
            verify(lbl !== null, "applied row has its name label")
            verify(lbl.font.bold === true, "applied row name is bold")
            snap(mh.win.contentItem, "theme_check_nord")
        }

        function test_D8_pro_theme_locked_free_data() {
            return [
                { tag: "synthwave", k: "synthwave" }, { tag: "cyberpunk", k: "cyberpunk" },
                { tag: "vaporwave", k: "vaporwave" }, { tag: "matrix", k: "matrix" },
                { tag: "arch", k: "arch" }, { tag: "cachyos", k: "cachyos" },
                { tag: "debian", k: "debian" }, { tag: "fedora", k: "fedora" }, { tag: "popos", k: "popos" }
            ]
        }
        function test_D8_pro_theme_locked_free(d) {
            verify(!mh.win.isPro, "free tier")
            _store.setAppearance("themeMode", "dark"); wait(80)
            openThemePopup()
            clickThemeRow(d.k)
            wait(200)
            compare(_store.appearance().themeMode, "dark", "locked Pro theme " + d.k + " NOT applied on free tier")
            var dlg = licenseDlg()
            verify(dlg && dlg.opened, "licence dialog opened instead of committing " + d.k)
            snap(mh.win.contentItem, "pro_locked_" + d.k)
            dlg.close(); wait(100)
        }

        function test_D9_pro_row_shows_badge_when_locked() {
            verify(!mh.win.isPro, "free tier")
            openThemePopup()
            var row = themeRow("synthwave"); verify(row, "synthwave row realized")
            verify(row.locked === true, "pro row locked on free tier")
            var badge = G.findPred(row, function (n) { try { return n && n.text === "PRO" && n.visible } catch (e) { return false } })
            verify(badge !== null, "PRO badge visible on locked row")
            snap(mh.win.contentItem, "pro_badge")
        }

        function test_D10_pro_theme_applies_when_pro() {
            mh.backend.storedKey = "XE1.valid.pro"; mh.backend.licenseChanged(); wait(120)
            verify(mh.win.isPro, "Pro tier active")
            _store.setAppearance("themeMode", "dark"); wait(80)
            openThemePopup()
            clickThemeRow("matrix")
            wait(200)
            compare(_store.appearance().themeMode, "matrix", "Pro theme applies once Pro is active")
            var dlg = licenseDlg()
            verify(!(dlg && dlg.opened), "no licence dialog when Pro is active")
            snap(lookClone(), "pro_applied_matrix")
        }

        function test_D11_hover_previews_theme_data() {
            return [
                { tag: "midnight", k: "midnight" }, { tag: "nord", k: "nord" }, { tag: "dracula", k: "dracula" },
                { tag: "gruvbox", k: "gruvbox" }, { tag: "deep_ocean", k: "deep_ocean" }, { tag: "matrix", k: "matrix" }
            ]
        }
        function test_D11_hover_previews_theme(d) {
            _store.setAppearance("themeMode", "light"); wait(120)   // committed = light
            var committedBg = "" + _theme.backgroundColor
            openThemePopup()
            hoverThemeRow(d.k); wait(170)                            // debounce ~45ms
            var previewBg = "" + _theme.backgroundColor
            verify(G.colorDist(committedBg, previewBg) > 12,
                   "hover previewed a different bg (" + committedBg + " -> " + previewBg + ")")
            compare(_store.appearance().themeMode, "light", "store NOT committed by hover")
            snap(lookClone(), "hover_theme_" + d.k)
        }

        function test_D12_hover_preview_reverts_on_close() {
            _store.setAppearance("themeMode", "light"); wait(120)
            var committedBg = "" + _theme.backgroundColor
            openThemePopup()
            hoverThemeRow("midnight"); wait(170)
            verify(G.colorDist(committedBg, "" + _theme.backgroundColor) > 12, "midnight previewed")
            closePopupIfOpen(); wait(250)                            // onClosed -> endThemePreview
            verify(G.colorDist(committedBg, "" + _theme.backgroundColor) < 6,
                   "preview reverted to committed bg on close")
            snap(lookClone(), "hover_revert")
        }

        // ════════════════════════════ AREA E — ACCENT ═══════════════════════

        function test_E1_all_swatches_render() {
            var all = accentSwatches()
            compare(all.length, 22, "14 house + 8 Okabe–Ito swatch delegates render")
            var heading = G.byText(mh.win.contentItem, "Okabe")
            verify(heading !== null, "Okabe–Ito group heading present")
            snap(mh.win.contentItem, "swatches_all")
        }

        function test_E2_house_accent_applies_data() {
            return [
                { tag: "blue", n: "blue", c: "#58A6FF" }, { tag: "purple", n: "purple", c: "#A371F7" },
                { tag: "green", n: "green", c: "#3FB950" }, { tag: "orange", n: "orange", c: "#F0883E" },
                { tag: "pink", n: "pink", c: "#F778BA" }, { tag: "teal", n: "teal", c: "#56D4DD" },
                { tag: "red", n: "red", c: "#F85149" }, { tag: "gold", n: "gold", c: "#E3B341" },
                { tag: "cyan", n: "cyan", c: "#22D3EE" }, { tag: "indigo", n: "indigo", c: "#818CF8" },
                { tag: "mint", n: "mint", c: "#34D399" }, { tag: "coral", n: "coral", c: "#FB7185" },
                { tag: "amber", n: "amber", c: "#FBBF24" }, { tag: "magenta", n: "magenta", c: "#E879F9" }
            ]
        }
        function test_E2_house_accent_applies(d) {
            _store.setAppearance("accent", d.n === "blue" ? "green" : "blue"); wait(80)
            var sw = swatchByName(d.n); verify(sw, "swatch " + d.n + " found")
            ensureVisible(sw)
            mouseClick(sw, Math.floor(sw.width / 2), Math.floor(sw.height / 2)); wait(150)
            compare(_store.appearance().accent, d.n, "accent committed to " + d.n)
            compare(("" + _theme.accent).toLowerCase(), d.c.toLowerCase(), "theme.accent == " + d.c)
            verify(sw.sel === true, "swatch marked selected")
            compare(sw.border.width, 3, "selection ring is 3px")
            snap(sw, "accent_" + d.n)
        }

        function test_E3_a11y_accent_applies_data() {
            return [
                { tag: "oi_blue", n: "oi_blue", c: "#0072B2" }, { tag: "oi_sky_blue", n: "oi_sky_blue", c: "#56B4E9" },
                { tag: "oi_bluish_green", n: "oi_bluish_green", c: "#009E73" }, { tag: "oi_yellow", n: "oi_yellow", c: "#F0E442" },
                { tag: "oi_orange", n: "oi_orange", c: "#E69F00" }, { tag: "oi_vermillion", n: "oi_vermillion", c: "#D55E00" },
                { tag: "oi_reddish_purple", n: "oi_reddish_purple", c: "#CC79A7" }, { tag: "oi_black", n: "oi_black", c: "#000000" }
            ]
        }
        function test_E3_a11y_accent_applies(d) {
            _store.setAppearance("accent", "blue"); wait(80)
            var sw = swatchByName(d.n); verify(sw, "a11y swatch " + d.n + " found")
            ensureVisible(sw)
            mouseClick(sw, Math.floor(sw.width / 2), Math.floor(sw.height / 2)); wait(150)
            compare(_store.appearance().accent, d.n, "accent committed to " + d.n)
            compare(("" + _theme.accent).toLowerCase(), d.c.toLowerCase(), "theme.accent == " + d.c)
            verify(sw.sel === true, "swatch marked selected")
            compare(sw.border.width, 3, "selection ring is 3px")
            snap(sw, "accent_" + d.n)
        }

        function test_E4_ring_shows_on_active_data() {
            return [
                { tag: "blue", n: "blue" }, { tag: "green", n: "green" }, { tag: "red", n: "red" },
                { tag: "teal", n: "teal" }, { tag: "oi_black", n: "oi_black" }
            ]
        }
        function test_E4_ring_shows_on_active(d) {
            _store.setAppearance("accent", d.n); wait(120)
            var sw = swatchByName(d.n); verify(sw, "swatch " + d.n)
            ensureVisible(sw)
            compare(sw.border.width, 3, "3px ring on active swatch")
            var chk = G.findPred(sw, function (n) { try { return n && n.name === "ui-check" } catch (e) { return false } })
            verify(chk && chk.visible, "white ui-check visible on active swatch")
            snap(sw, "ring_" + d.n)
        }

        function test_E5_exactly_one_ring() {
            _store.setAppearance("accent", "purple"); wait(120)
            var all = accentSwatches()
            var selCount = 0, ringCount = 0
            for (var i = 0; i < all.length; i++) {
                if (all[i].sel === true) selCount++
                if (all[i].border.width === 3) ringCount++
            }
            compare(selCount, 1, "exactly one swatch selected")
            compare(ringCount, 1, "exactly one swatch shows the 3px ring")
            snap(mh.win.contentItem, "one_ring")
        }

        function test_E6_default_fallback_marked() {
            _store.setAppearance("accent", "green"); wait(80)     // theme.accentName -> green
            _store.setAppearance("accent", ""); wait(120)          // no explicit key -> fall back
            var sw = swatchByName("green"); verify(sw, "green swatch")
            verify(sw.sel === true, "effective-default accent reads as selected with no explicit key")
            var all = accentSwatches(); var selCount = 0
            for (var i = 0; i < all.length; i++) if (all[i].sel === true) selCount++
            compare(selCount, 1, "still exactly one swatch marked on fallback")
            snap(sw, "fallback_marked")
        }

        function test_E7_black_swatch_visible_on_panel() {
            _store.setAppearance("accent", "blue"); wait(120)      // keep oi_black UN-selected
            var sw = swatchByName("oi_black"); verify(sw, "oi_black swatch")
            ensureVisible(sw)
            compare(("" + sw.color).toLowerCase(), "#000000", "swatch fill is pure black")
            var img = grabImage(sw)
            var cx = Math.floor(sw.width / 2), cy = Math.floor(sw.height / 2)
            verify(img.red(cx, cy) < 40 && img.green(cx, cy) < 40 && img.blue(cx, cy) < 40, "centre pixel is black")
            // A distinct (non-black) border ring around the circle proves the swatch
            // is not invisible against the panel. Sample the edge midpoints.
            var edges = [[cx, 1], [cx, sw.height - 2], [1, cy], [sw.width - 2, cy]]
            var lit = false
            for (var i = 0; i < edges.length; i++) {
                var e = edges[i]
                if (img.red(e[0], e[1]) > 90 || img.green(e[0], e[1]) > 90 || img.blue(e[0], e[1]) > 90) lit = true
            }
            verify(lit, "a lighter border ring surrounds the black fill (swatch is visible)")
            img.save("gui-evidence/mgrta_black_visible.png")
        }

        function test_E8_black_swatch_selected_legible() {
            _store.setAppearance("accent", "oi_black"); wait(150)
            var sw = swatchByName("oi_black"); verify(sw, "oi_black swatch")
            ensureVisible(sw)
            verify(sw.sel === true, "oi_black selected")
            compare(sw.border.width, 3, "3px ring even for the black swatch")
            var img = grabImage(sw)
            verify(hasNearWhite(img, 8, 8, img.width - 8, img.height - 8),
                   "white ui-check pixels legible over the black fill")
            img.save("gui-evidence/mgrta_black_selected.png")
        }

        function test_E9_hover_previews_accent_data() {
            return [
                { tag: "green", n: "green", c: "#3FB950" }, { tag: "orange", n: "orange", c: "#F0883E" },
                { tag: "magenta", n: "magenta", c: "#E879F9" }, { tag: "oi_orange", n: "oi_orange", c: "#E69F00" },
                { tag: "oi_bluish_green", n: "oi_bluish_green", c: "#009E73" }, { tag: "oi_black", n: "oi_black", c: "#000000" }
            ]
        }
        function test_E9_hover_previews_accent(d) {
            _store.setAppearance("accent", d.n === "blue" ? "green" : "blue"); wait(100)
            var committed = _store.appearance().accent
            var sw = swatchByName(d.n); verify(sw, "swatch " + d.n)
            ensureVisible(sw)
            mouseMove(sw, Math.floor(sw.width / 2), Math.floor(sw.height / 2)); wait(170)   // debounce
            compare(("" + _theme.accent).toLowerCase(), d.c.toLowerCase(), "hover previewed theme.accent == " + d.c)
            compare(_store.appearance().accent, committed, "store accent UNCHANGED by hover")
            snap(sw, "hover_accent_" + d.n)
            mouseMove(mh.win.contentItem, 3, 3); wait(150)                                    // leave -> revert
        }

        function test_E10_hover_accent_reverts_on_exit() {
            _store.setAppearance("accent", "blue"); wait(100)      // committed blue -> #58A6FF
            var committed = ("" + _theme.accent).toLowerCase()
            var sw = swatchByName("red"); verify(sw, "red swatch")
            ensureVisible(sw)
            mouseMove(sw, Math.floor(sw.width / 2), Math.floor(sw.height / 2)); wait(170)
            verify(("" + _theme.accent).toLowerCase() !== committed, "accent previewed away from committed")
            mouseMove(mh.win.contentItem, 3, 3); wait(200)         // exit -> endThemePreview
            compare(("" + _theme.accent).toLowerCase(), committed, "accent reverted to committed on exit")
            snap(mh.win.contentItem, "accent_revert")
        }

        function test_E11_hover_grows_border_and_previews() {
            _store.setAppearance("accent", "blue"); wait(100)      // green is NOT selected
            var sw = swatchByName("green"); verify(sw, "green swatch")
            ensureVisible(sw)
            compare(sw.border.width, 1, "un-hovered non-selected swatch has 1px edge")
            mouseMove(sw, Math.floor(sw.width / 2), Math.floor(sw.height / 2)); wait(60)
            compare(sw.border.width, 2, "hovered non-selected swatch grows to a 2px edge")
            wait(150)
            compare(("" + _theme.accent).toLowerCase(), "#3fb950", "hover also previews the accent live")
            snap(sw, "hover_border")
            mouseMove(mh.win.contentItem, 3, 3); wait(120)
        }
    }
}
