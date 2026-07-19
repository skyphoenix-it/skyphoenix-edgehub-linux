import QtQuick
import QtTest
import "GuiUtil.js" as G

// ─────────────────────────────────────────────────────────────────────────────
// REAL, visible GUI tests for the Manager's Appearance surface:
//   F  Background style + wallpaper (BackgroundPicker, global pageIndex -1)
//   G  The GLASS SLIDER — the snap-back regression (real drag + churny revision)
//   H  Switches (glow / animated-bg / reduce-motion) + segmented controls
//   J  Images tab (18 bundled backgrounds gallery + your-images + upload stub)
//
// Hosted via ManagerHarness (REAL manager/qml/Manager.qml in a real KWin
// compositor), created ONCE in initTestCase. Every case asserts an OBJECTIVE,
// GUI-observable outcome after a real mouse interaction (store fact reflected in
// the visible control + geometry/visibility/pixel evidence). See
// scratchpad/specs/00_authoring_brief.md and 03_manager.md.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 100; height: 100
    ManagerHarness { id: mh }

    TestCase {
        id: tc
        name: "GuiMgrBgGlassImages"
        when: windowShown
        visible: true

        // Cached seams (found once).
        property var _store: null
        property var _theme: null
        property var _nav: null
        property var _picker: null      // the GLOBAL BackgroundPicker (pageIndex -1)
        property var _glass: null       // the glass Slider

        function snap(item, name) {
            var img = grabImage(item)
            img.save("gui-evidence/mgrbg_" + name + ".png")
            return img
        }

        // ── tree helpers ──────────────────────────────────────────────────────
        function winObj() { return mh.win }

        function collect(pred) { return G.collectPred(mh.win, pred) }
        function find(pred) { return G.findPred(mh.win, pred) }

        // The Flickable ancestor of an item (a QQC2 ScrollView reparents its
        // content into an internal Flickable). Used to scroll a control on-screen.
        function flickAncestor(item) {
            var p = item ? item.parent : null
            while (p) {
                try { if (p.contentY !== undefined && p.contentHeight !== undefined
                          && p.maximumFlickVelocity !== undefined) return p } catch (e) {}
                p = p.parent
            }
            return null
        }
        // Scroll `item` into the middle of its scroll viewport so a real click/drag
        // lands on it. No-op when it has no Flickable ancestor.
        function scrollIntoView(item) {
            var f = flickAncestor(item)
            if (!f) return
            var pos = item.mapToItem(f, 0, 0)
            var target = f.contentY + pos.y - f.height / 2 + item.height / 2
            var maxY = Math.max(0, f.contentHeight - f.height)
            f.contentY = Math.max(0, Math.min(maxY, target))
            wait(120)
        }

        // Make a tab current, wait for its content to lay out.
        function goTab(i) {
            _nav.currentIndex = i
            wait(250)
            compare(_nav.currentIndex, i, "tab " + i + " current")
        }

        // ── control finders ───────────────────────────────────────────────────
        function styleChips() {
            // Style chips of the GLOBAL picker: a Rectangle with `sel` + modelData.v.
            return G.collectPred(_picker, function (n) {
                try { return n && n.sel !== undefined && n.modelData !== undefined
                          && n.modelData.v !== undefined } catch (e) { return false }
            })
        }
        function pickerWalls() {
            // Wallpaper thumbnails of the GLOBAL picker: `sel` + modelData.source.
            return G.collectPred(_picker, function (n) {
                try { return n && n.sel !== undefined && n.modelData !== undefined
                          && n.modelData.source !== undefined } catch (e) { return false }
            })
        }
        function bundledCards() {
            // Images-tab bundled gallery delegates: `bw` + modelData.source.
            return collect(function (n) {
                try { return n && n.bw !== undefined && n.modelData !== undefined
                          && n.modelData.source !== undefined } catch (e) { return false }
            })
        }
        function uploadedCards() {
            return collect(function (n) {
                try { return n && n.isWall !== undefined && n.modelData !== undefined } catch (e) { return false }
            })
        }
        function switchByText(t) {
            return find(function (n) {
                try { return n && n.checked !== undefined && typeof n.toggle === "function"
                          && n.text === t } catch (e) { return false }
            })
        }
        function segments() {
            return collect(function (n) {
                try { return n && n.options !== undefined && n.currentValue !== undefined
                          && typeof n.selected === "function" } catch (e) { return false }
            })
        }
        function windowStyleSegment() {
            var s = segments()
            for (var i = 0; i < s.length; i++) {
                try { if (s[i].options.length && s[i].options[0].value === "dark") return s[i] } catch (e) {}
            }
            return null
        }
        function columnsSegment() {
            var s = segments()
            for (var i = 0; i < s.length; i++) {
                try { if (s[i].options.length && s[i].options[0].value === 1) return s[i] } catch (e) {}
            }
            return null
        }
        function segDelegate(seg, val) {
            return G.findPred(seg, function (n) {
                try { return n && n.active !== undefined && n.modelData !== undefined
                          && n.modelData.value === val } catch (e) { return false }
            })
        }

        // Real click on the centre of an item (scrolled on-screen first).
        function clickItem(item) {
            scrollIntoView(item)
            mouseClick(item, item.width / 2, item.height / 2)
            wait(150)
        }

        // ── slider helpers ────────────────────────────────────────────────────
        function xForValue(sl, frac) {
            var hw = (sl.handle ? sl.handle.width : 20)
            return sl.leftPadding + hw / 2 + frac * (sl.availableWidth - hw)
        }
        function setGlass(v) {
            // Establish a known handle position via the store (syncTheme → theme.
            // glassOpacity → the slider's bound value).
            _store.setAppearance("glass", v)
            wait(120)
        }

        // ─────────────────────────────────────────────────────────────────────
        function initTestCase() {
            var w = mh.create()
            verify(w !== null, "Manager.qml instantiated")
            tryVerify(function () { return mh.ready }, 8000, "Manager window visible")

            _store = find(function (n) {
                try { return n && n.applyExternal !== undefined && n.structureRevision !== undefined } catch (e) { return false } })
            _theme = find(function (n) {
                try { return n && typeof n.applyAccent === "function" && n.glassOpacity !== undefined
                          && n.previewBgStyle !== undefined } catch (e) { return false } })
            _nav = G.byObjName(mh.win.contentItem, "managerTabs")
            _picker = find(function (n) {
                try { return n && typeof n.pickStyle === "function" && n.pageIndex === -1 } catch (e) { return false } })
            _glass = find(function (n) {
                try { return n && n.from !== undefined && n.to !== undefined
                          && n.visualPosition !== undefined && n.handle !== undefined } catch (e) { return false } })

            verify(_store !== null, "found DashboardStore")
            verify(_theme !== null, "found Theme")
            verify(_nav !== null && _nav.count === 5, "found 5-tab managerTabs")
            verify(_picker !== null, "found the global BackgroundPicker (pageIndex -1)")
            verify(_glass !== null, "found the glass Slider")
        }
        function cleanupTestCase() { mh.destroyWin() }

        // ════════════════════════════════════════════════════════════════════
        // AREA F — Background style + wallpaper
        // ════════════════════════════════════════════════════════════════════

        function test_f01_picker_present() {
            goTab(1)
            scrollIntoView(_picker)
            verify(_picker.visible, "global background picker visible on Look tab")
            verify(_picker.width > 0 && _picker.height > 0, "picker has real geometry")
            var chips = styleChips()
            compare(chips.length, 11, "11 animated style chips present")
            snap(mh.win.contentItem, "f01_look_picker")
        }

        // Each of the 11 animated styles commits on a REAL click and clears any
        // wallpaper (mutually exclusive).
        function test_f_style_commits_data() {
            var out = []
            for (var i = 0; i < 11; i++) out.push({ tag: "style" + i, i: i })
            return out
        }
        function test_f_style_commits(d) {
            goTab(1)
            _store.setAppearance("wallpaper", "qrc:/wallpapers/nebula.png")  // set a wallpaper first
            wait(80)
            var chips = styleChips()
            verify(d.i < chips.length, "chip index in range")
            var chip = chips[d.i]
            var v = chip.modelData.v
            clickItem(chip)
            compare(_store.appearance().bgStyle, v, "bgStyle committed to " + v)
            compare(_store.appearance().wallpaper, "", "picking a style cleared the wallpaper")
            verify(chip.sel === true, "clicked style chip reads as selected")
        }

        // A sample of style chips render as SELECTED after picking (accent fill +
        // 2px border) — the app's fill rule for a text/segment selection.
        function test_f_selected_style_data() {
            return [ { tag: "orbs", v: "orbs" }, { tag: "waves", v: "waves" },
                     { tag: "grid", v: "grid" }, { tag: "aubergine", v: "aubergine" } ]
        }
        function test_f_selected_style(d) {
            goTab(1)
            var chips = styleChips(), target = null
            for (var i = 0; i < chips.length; i++) if (chips[i].modelData.v === d.v) target = chips[i]
            verify(target !== null, "found style chip " + d.v)
            clickItem(target)
            verify(target.sel === true, d.v + " chip selected")
            compare(target.border.width, 2, "selected chip has a 2px border")
            // exactly one style chip selected at a time
            var selCount = 0
            for (var j = 0; j < chips.length; j++) if (chips[j].sel === true) selCount++
            compare(selCount, 1, "exactly one style chip indicated")
        }

        // All bundled wallpaper thumbnails are browsable in the picker. qrc: images
        // don't load under qmltestrunner, so assert the delegate renders (geometry +
        // model source), not the image pixels.
        function test_f_wallpaper_renders_data() {
            return [ { tag: "wp0", i: 0 }, { tag: "wp3", i: 3 }, { tag: "wp6", i: 6 },
                     { tag: "wp9", i: 9 }, { tag: "wp12", i: 12 }, { tag: "wp17", i: 17 } ]
        }
        function test_f_wallpaper_renders(d) {
            goTab(1)
            var walls = pickerWalls()
            verify(walls.length >= 18, "at least 18 wallpaper thumbnails (" + walls.length + ")")
            var wp = walls[d.i]
            verify(wp !== undefined, "wallpaper thumbnail " + d.i + " present")
            compare(wp.width, 64, "thumbnail width")
            compare(wp.height, 88, "thumbnail height")
            verify(("" + wp.modelData.source).length > 0, "thumbnail has a source")
        }

        // Sample wallpapers commit on a REAL click in the picker (wallpaper wins
        // over any animated style — current() prioritises wallpaper).
        function test_f_wallpaper_click_data() {
            return [ { tag: "w0", i: 0 }, { tag: "w5", i: 5 }, { tag: "w17", i: 17 } ]
        }
        function test_f_wallpaper_click(d) {
            goTab(1)
            var wp = pickerWalls()[d.i]
            var src = wp.modelData.source
            clickItem(wp)
            compare(_store.appearance().wallpaper, src, "wallpaper committed to " + src)
            verify(wp.sel === true, "clicked wallpaper reads as selected")
            compare(wp.border.width, 3, "selected wallpaper has a 3px border")
        }

        function test_f_style_then_wallpaper_switches_kind() {
            goTab(1)
            // pick a style
            var chips = styleChips()
            clickItem(chips[1])
            compare(_picker.current().kind, "style", "kind is style after picking a style")
            // now pick a wallpaper — kind flips to wallpaper, style value retained but overridden
            var wp = pickerWalls()[2]
            clickItem(wp)
            compare(_picker.current().kind, "wallpaper", "kind flips to wallpaper")
            compare(_store.appearance().wallpaper, wp.modelData.source, "wallpaper set")
        }

        function test_f_wallpaper_then_style_clears_wallpaper() {
            goTab(1)
            var wp = pickerWalls()[4]
            clickItem(wp)
            compare(_store.appearance().wallpaper, wp.modelData.source, "wallpaper set")
            var chips = styleChips()
            clickItem(chips[3])
            compare(_store.appearance().wallpaper, "", "picking a style cleared the wallpaper")
            compare(_store.appearance().bgStyle, chips[3].modelData.v, "style committed")
        }

        // ════════════════════════════════════════════════════════════════════
        // AREA G — the GLASS SLIDER (snap-back regression)
        // ════════════════════════════════════════════════════════════════════

        function test_g01_slider_pressable() {
            goTab(1); scrollIntoView(_glass)
            verify(_glass.visible, "glass slider visible")
            verify(_glass.height >= 16, "slider has a pressable height (" + _glass.height + ")")
            verify(_glass.handle.width >= 16 && _glass.handle.height >= 16, "handle has a real hit size")
        }

        function test_g02_handle_tracks_glassopacity() {
            goTab(1); scrollIntoView(_glass)
            _theme.glassOpacity = 0.77
            wait(150)
            verify(Math.abs(_glass.value - 0.77) < 0.01, "value tracks theme.glassOpacity (" + _glass.value + ")")
            verify(Math.abs(_glass.visualPosition - 0.77) < 0.02, "visualPosition reflects the value")
            verify(_glass.handle.x > _glass.leftPadding + (_glass.availableWidth - _glass.handle.width) * 0.5,
                   "handle sits past the midpoint at 77%")
        }

        // THE regression, part 1: a REAL drag moves the handle and it does NOT snap
        // back after settling (value bound to the stable theme.glassOpacity).
        function test_g03_real_drag_no_snapback() {
            goTab(1); scrollIntoView(_glass)
            setGlass(0.55)
            var y = _glass.height / 2
            var startX = xForValue(_glass, _glass.value)
            var targetX = xForValue(_glass, 0.20)
            snap(_glass, "g03_before")
            mousePress(_glass, startX, y)
            mouseMove(_glass, startX - 15, y)      // cross the drag threshold
            mouseMove(_glass, targetX, y)
            mouseRelease(_glass, targetX, y)
            wait(120)
            verify(_glass.value < 0.40, "handle moved left toward ~0.20 (value=" + _glass.value + ")")
            var afterDrag = _glass.value
            snap(_glass, "g03_after")
            wait(400)                               // outlast any deferred re-eval
            verify(Math.abs(_glass.value - afterDrag) < 0.02,
                   "value did NOT snap back after settling (" + afterDrag + " -> " + _glass.value + ")")
        }

        // THE regression, part 2: a churny store-revision bump (a volatile setSetting
        // that does NOT touch glass) must NOT move the handle. This is the exact bug
        // — the old slider bound to store.revision and snapped to the stale stored
        // value whenever the preview's cpu/gpu/ram widgets wrote sparkline history.
        function test_g04_churn_revision_no_snapback() {
            goTab(1); scrollIntoView(_glass)
            setGlass(0.55)
            var y = _glass.height / 2
            var startX = xForValue(_glass, _glass.value)
            var targetX = xForValue(_glass, 0.30)
            mousePress(_glass, startX, y)
            mouseMove(_glass, startX - 15, y)
            mouseMove(_glass, targetX, y)
            mouseRelease(_glass, targetX, y)
            wait(220)                               // let the 180ms commit fire
            var dragged = _glass.value
            verify(Math.abs(dragged - 0.30) < 0.10, "dragged to ~0.30 (" + dragged + ")")
            // Bump store.revision repeatedly WITHOUT changing glass (mimics metric churn).
            var revBefore = _store.revision
            for (var i = 0; i < 6; i++) _store.setSetting("glass-churn-probe", "hist", Math.random())
            wait(120)
            verify(_store.revision > revBefore, "store.revision actually churned")
            verify(Math.abs(_glass.value - dragged) < 0.02,
                   "handle STILL at " + dragged + " after churn (=" + _glass.value + ") — no snap-back")
            snap(_glass, "g04_after_churn")
        }

        // Handle x is monotonic with the drag direction (no jump back to origin).
        function test_g05_handle_monotonic_during_drag() {
            goTab(1); scrollIntoView(_glass)
            setGlass(0.80)
            var y = _glass.height / 2
            var startX = xForValue(_glass, _glass.value)
            mousePress(_glass, startX, y)
            mouseMove(_glass, startX - 15, y)
            mouseMove(_glass, xForValue(_glass, 0.60), y); wait(60); var x1 = _glass.handle.x
            mouseMove(_glass, xForValue(_glass, 0.40), y); wait(60); var x2 = _glass.handle.x
            mouseMove(_glass, xForValue(_glass, 0.15), y); wait(60); var x3 = _glass.handle.x
            mouseRelease(_glass, xForValue(_glass, 0.15), y)
            verify(x1 > x2 && x2 > x3, "handle.x decreased monotonically: " + x1 + " > " + x2 + " > " + x3)
        }

        // The drag updates the live theme immediately (onMoved writes glassOpacity).
        function test_g06_drag_updates_theme_live() {
            goTab(1); scrollIntoView(_glass)
            setGlass(0.55)
            var y = _glass.height / 2
            var startX = xForValue(_glass, _glass.value)
            var targetX = xForValue(_glass, 0.25)
            mousePress(_glass, startX, y)
            mouseMove(_glass, startX - 15, y)
            mouseMove(_glass, targetX, y)
            verify(Math.abs(_theme.glassOpacity - _glass.value) < 0.01,
                   "theme.glassOpacity tracks the slider mid-drag")
            mouseRelease(_glass, targetX, y)
        }

        // Releasing debounce-commits to the store (~180ms).
        function test_g07_debounce_commit_to_store() {
            goTab(1); scrollIntoView(_glass)
            setGlass(0.55)
            var y = _glass.height / 2
            var startX = xForValue(_glass, _glass.value)
            var targetX = xForValue(_glass, 0.35)
            mousePress(_glass, startX, y)
            mouseMove(_glass, startX - 15, y)
            mouseMove(_glass, targetX, y)
            mouseRelease(_glass, targetX, y)
            var v = _glass.value
            tryVerify(function () { return Math.abs(_store.appearance().glass - v) < 0.02 }, 2000,
                      "released value persisted to the store")
        }

        // The "NN%" label follows the handle.
        function test_g08_percent_label_data() {
            return [ { tag: "p20", frac: 0.20 }, { tag: "p50", frac: 0.50 }, { tag: "p85", frac: 0.85 } ]
        }
        function test_g08_percent_label(d) {
            goTab(1); scrollIntoView(_glass)
            _theme.glassOpacity = d.frac
            wait(120)
            var expect = Math.round(_glass.value * 100) + "%"
            var lbl = find(function (n) {
                try { return n && n.text !== undefined && ("" + n.text) === expect
                          && n.font && n.font.pixelSize === 13 } catch (e) { return false } })
            verify(lbl !== null && lbl.visible, "percentage label shows " + expect)
        }

        // External/hub push still moves the handle after a drag (binding re-asserted).
        function test_g09_external_push_moves_handle() {
            goTab(1); scrollIntoView(_glass)
            // do a drag first to sever/re-assert the binding
            var y = _glass.height / 2
            mousePress(_glass, xForValue(_glass, _glass.value), y)
            mouseMove(_glass, xForValue(_glass, _glass.value) - 15, y)
            mouseMove(_glass, xForValue(_glass, 0.70), y)
            mouseRelease(_glass, xForValue(_glass, 0.70), y)
            wait(220)
            _store.setAppearance("glass", 0.15)     // external push
            tryVerify(function () { return Math.abs(_glass.value - 0.15) < 0.01 }, 2000,
                      "handle followed an external store push to 0.15")
        }

        // Press-and-release without moving does not change the value.
        function test_g10_press_hold_no_change() {
            goTab(1); scrollIntoView(_glass)
            setGlass(0.42)
            var before = _glass.value
            var y = _glass.height / 2, x = xForValue(_glass, before)
            mousePress(_glass, x, y)
            mouseRelease(_glass, x, y)
            wait(120)
            verify(Math.abs(_glass.value - before) < 0.02, "value unchanged by a no-move press")
        }

        // Extremes are reachable by a full-left / full-right drag.
        function test_g11_extremes_data() {
            return [ { tag: "min", frac: 0.0, txt: "0%" }, { tag: "max", frac: 1.0, txt: "100%" } ]
        }
        function test_g11_extremes(d) {
            goTab(1); scrollIntoView(_glass)
            setGlass(0.5)
            var y = _glass.height / 2
            var startX = xForValue(_glass, 0.5)
            // aim well past the end so it clamps at the extreme
            var targetX = d.frac < 0.5 ? _glass.leftPadding - 40
                                       : _glass.leftPadding + _glass.availableWidth + 40
            mousePress(_glass, startX, y)
            mouseMove(_glass, startX + (targetX > startX ? 15 : -15), y)
            mouseMove(_glass, targetX, y)
            mouseRelease(_glass, targetX, y)
            wait(120)
            verify(Math.abs(_glass.value - d.frac) < 0.02, "reached " + d.frac + " (=" + _glass.value + ")")
        }

        function test_g12_preview_pixels_evidence() {
            goTab(1); scrollIntoView(_glass)
            var look = find(function (n) {
                try { return n && n.editable === false && n.pageIndex !== undefined
                          && n.landscape !== undefined } catch (e) { return false } })
            verify(look !== null, "found the read-only look preview clone")
            setGlass(0.0); wait(200)
            var a = snap(look, "g12_glass0")
            setGlass(1.0); wait(200)
            var b = snap(look, "g12_glass100")
            verify(G.looksRendered(a) && G.looksRendered(b), "preview renders at both glass extremes")
        }

        // ════════════════════════════════════════════════════════════════════
        // AREA H — switches & segmented controls
        // ════════════════════════════════════════════════════════════════════

        // Each Look-tab switch toggles on a REAL click and persists to the store.
        function test_h_toggle_persist_data() {
            return [ { tag: "glow", txt: "Widget glow", key: "glow" },
                     { tag: "animbg", txt: "Animated background", key: "animatedBg" },
                     { tag: "reduce", txt: "Reduce motion", key: "reduceMotion" } ]
        }
        function test_h_toggle_persist(d) {
            goTab(1)
            var sw = switchByText(d.txt)
            verify(sw !== null, "found switch: " + d.txt)
            scrollIntoView(sw)
            var before = sw.checked
            mouseClick(sw, sw.width * 0.15, sw.height / 2)
            wait(200)
            compare(sw.checked, !before, d.txt + " toggled")
            compare(_store.appearance()[d.key], sw.checked, d.txt + " persisted to store")
        }

        // A switch re-binds after an EXTERNAL store push (a Switch severs its
        // `checked:` binding on toggle; the handler re-asserts it).
        function test_h_external_rebind_data() {
            return [ { tag: "glow", txt: "Widget glow", key: "glow" },
                     { tag: "animbg", txt: "Animated background", key: "animatedBg" },
                     { tag: "reduce", txt: "Reduce motion", key: "reduceMotion" } ]
        }
        function test_h_external_rebind(d) {
            goTab(1)
            var sw = switchByText(d.txt); scrollIntoView(sw)
            _store.setAppearance(d.key, true); wait(120)
            compare(sw.checked, true, d.txt + " follows store→true")
            _store.setAppearance(d.key, false); wait(120)
            compare(sw.checked, false, d.txt + " follows store→false")
        }

        // The knob position animates to the toggled state (0=left, 1=right).
        function test_h_knob_position_data() {
            return [ { tag: "glow", txt: "Widget glow", key: "glow" },
                     { tag: "reduce", txt: "Reduce motion", key: "reduceMotion" } ]
        }
        function test_h_knob_position(d) {
            goTab(1)
            var sw = switchByText(d.txt); scrollIntoView(sw)
            _store.setAppearance(d.key, false); wait(150)
            compare(sw.position, 0, d.txt + " knob left when off")
            mouseClick(sw, sw.width * 0.15, sw.height / 2); wait(250)
            compare(sw.position, 1, d.txt + " knob moved right when on")
        }

        // The window-style segment recolours the Manager chrome (window.color = m.bg
        // for the chosen palette). Order ends on "default" to restore the OOB look.
        function test_h_windowstyle_data() {
            return [ { tag: "dark", v: "dark", bg: "#0D1117" },
                     { tag: "light", v: "light", bg: "#F6F8FA" },
                     { tag: "default", v: "default", bg: "#FAF4EC" } ]
        }
        function test_h_windowstyle(d) {
            goTab(1)
            var seg = windowStyleSegment()
            verify(seg !== null, "found window-style segment")
            var del = segDelegate(seg, d.v)
            verify(del !== null, "found segment '" + d.v + "'")
            clickItem(del)
            verify(del.active === true, "segment '" + d.v + "' is active")
            verify(Qt.colorEqual(mh.win.color, d.bg), "window recoloured to " + d.bg + " (=" + mh.win.color + ")")
            snap(mh.win.contentItem, "h_windowstyle_" + d.tag)
        }

        function test_h01_windowstyle_one_active() {
            goTab(1)
            var seg = windowStyleSegment()
            clickItem(segDelegate(seg, "dark"))
            var dels = G.collectPred(seg, function (n) {
                try { return n && n.active !== undefined && n.modelData !== undefined
                          && n.modelData.value !== undefined } catch (e) { return false } })
            var act = 0
            for (var i = 0; i < dels.length; i++) if (dels[i].active) act++
            compare(act, 1, "exactly one window-style segment active")
            clickItem(segDelegate(seg, "default"))   // restore
        }

        function test_h02_segment_selected_label_bold() {
            goTab(1)
            var seg = windowStyleSegment()
            var del = segDelegate(seg, "light")
            clickItem(del)
            var lbl = G.findPred(del, function (n) {
                try { return n && n.text === "Light" && n.font !== undefined } catch (e) { return false } })
            verify(lbl !== null && lbl.font.bold === true, "active segment label is bold")
            clickItem(segDelegate(seg, "default"))   // restore
        }

        // Columns segment (Screens tab) reflows the current page.
        function test_h_columns_data() {
            return [ { tag: "two", v: 2 }, { tag: "one", v: 1 } ]
        }
        function test_h_columns(d) {
            goTab(0)
            var seg = columnsSegment()
            verify(seg !== null, "found columns segment")
            var del = segDelegate(seg, d.v)
            verify(del !== null, "found columns segment '" + d.v + "'")
            clickItem(del)
            compare(_store.pageColumns(0), d.v, "page 0 columns set to " + d.v)
            compare(seg.currentValue, d.v, "segment currentValue reflects " + d.v)
        }

        function test_h03_reducemotion_theme() {
            goTab(1)
            var sw = switchByText("Reduce motion"); scrollIntoView(sw)
            _store.setAppearance("reduceMotion", false); wait(120)
            if (!sw.checked) { mouseClick(sw, sw.width * 0.15, sw.height / 2); wait(200) }
            compare(sw.checked, true, "reduce-motion on")
            verify(_theme.reduceMotion === true, "theme.reduceMotion reflects the switch")
            _store.setAppearance("reduceMotion", false); wait(120)   // restore
        }

        function test_h04_indicator_colour() {
            goTab(1)
            var sw = switchByText("Widget glow"); scrollIntoView(sw)
            _store.setAppearance("glow", true); wait(150)
            var indOn = grabImage(sw.indicator)
            _store.setAppearance("glow", false); wait(150)
            var indOff = grabImage(sw.indicator)
            // The indicator fill differs between checked (accent) and unchecked (panelAlt).
            var cOn = "" + indOn.pixel(indOn.width - 6, indOn.height / 2)
            var cOff = "" + indOff.pixel(indOff.width - 6, indOff.height / 2)
            verify(G.colorDist(cOn, cOff) > 20, "indicator fill differs on/off (" + cOn + " vs " + cOff + ")")
        }

        // ════════════════════════════════════════════════════════════════════
        // AREA J — Images tab
        // ════════════════════════════════════════════════════════════════════

        function _clearUploads() {
            mh.backend.imagesList = []
            mh.backend.imagesChanged()
            wait(120)
        }

        function test_j01_heading_visible() {
            goTab(2)
            var h = find(function (n) {
                try { return n && n.text === "Images" && n.font && n.font.pixelSize === 24 && n.visible } catch (e) { return false } })
            verify(h !== null, "Images heading (24px) visible")
            var imp = find(function (n) {
                try { return n && n.text !== undefined && ("" + n.text).indexOf("Import") >= 0 && n.visible } catch (e) { return false } })
            verify(imp !== null, "Import button visible")
            snap(mh.win.contentItem, "j01_images_tab")
        }

        function test_j02_bundled_section_pill() {
            goTab(2)
            var sec = find(function (n) {
                try { return n && n.text === "Bundled backgrounds" && n.visible } catch (e) { return false } })
            verify(sec !== null, "'Bundled backgrounds' section label visible")
            var pill = find(function (n) {
                try { return n && n.objectName === "scopePill" && n.label === "All screens" && n.visible } catch (e) { return false } })
            verify(pill !== null, "'All screens' scope pill present")
        }

        // All 18 bundled thumbnails render as cards (geometry + label + model).
        function test_j_bundled_render_data() {
            var out = []
            for (var i = 0; i < 18; i++) out.push({ tag: "b" + i, i: i })
            return out
        }
        function test_j_bundled_render(d) {
            goTab(2); _clearUploads()
            var cards = bundledCards()
            compare(cards.length, 18, "18 bundled thumbnail cards")
            var c = cards[d.i]
            verify(c.visible, "card " + d.i + " visible")
            compare(c.width, 128, "card width")
            compare(c.height, 76, "card height")
            var lbl = G.findPred(c, function (n) {
                try { return n && n.text !== undefined && ("" + n.text) === c.modelData.label } catch (e) { return false } })
            verify(lbl !== null, "card shows its label '" + c.modelData.label + "'")
        }

        // Clicking each bundled thumbnail sets it as the Edge-wide wallpaper and
        // shows the selected check. (Selecting each of the 18 wallpapers.)
        function test_j_bundled_click_data() {
            var out = []
            for (var i = 0; i < 18; i++) out.push({ tag: "c" + i, i: i })
            return out
        }
        function test_j_bundled_click(d) {
            goTab(2); _clearUploads()
            var c = bundledCards()[d.i]
            var src = c.modelData.source
            clickItem(c)
            compare(_store.appearance().wallpaper, src, "wallpaper set to bundled #" + d.i)
            verify(c.bw === true, "selected bundled card reads bw=true")
            compare(c.border.width, 2, "selected card has a 2px accent border")
        }

        function test_j03_selected_check_shows() {
            goTab(2); _clearUploads()
            var c = bundledCards()[7]
            clickItem(c)
            var badge = G.findPred(c, function (n) {
                try { return n && n.name === "ui-check" && n.visible } catch (e) { return false } })
            verify(badge !== null, "check badge visible on the selected card")
            snap(c, "j03_selected_card")
        }

        function test_j04_exactly_one_marked() {
            goTab(2); _clearUploads()
            var cards = bundledCards()
            clickItem(cards[3])
            var marked = 0
            for (var i = 0; i < cards.length; i++) if (cards[i].bw === true) marked++
            compare(marked, 1, "exactly one bundled thumbnail marked")
        }

        function test_j05_your_images_empty_state() {
            goTab(2); _clearUploads()
            var empty = find(function (n) {
                try { return n && n.text !== undefined && ("" + n.text).indexOf("No images yet") >= 0 } catch (e) { return false } })
            verify(empty !== null && empty.visible, "'No images yet' empty state visible")
            var grid = find(function (n) {
                try { return n && n.cellWidth !== undefined && n.cellHeight !== undefined && n.model !== undefined } catch (e) { return false } })
            verify(grid !== null, "found the your-images GridView")
            compare(grid.visible, false, "grid hidden while there are no uploads")
        }

        function test_j06_grid_appears_with_images() {
            goTab(2)
            mh.backend.imagesList = ["up1.png", "up2.png", "up3.png"]
            mh.backend.imagesChanged()
            wait(200)
            var model = find(function (n) {
                try { return n && n.objectName === "imagesModel" } catch (e) { return false } })
            verify(model !== null, "found imagesModel")
            compare(model.count, 3, "imagesModel rebuilt to 3")
            var grid = find(function (n) {
                try { return n && n.cellWidth !== undefined && n.model !== undefined } catch (e) { return false } })
            verify(grid.visible, "your-images grid visible once uploads exist")
            _clearUploads()
        }

        function test_j07_import_button_and_filedialog() {
            goTab(2)
            var imp = find(function (n) {
                try { return n && n.text !== undefined && ("" + n.text).indexOf("Import") >= 0 } catch (e) { return false } })
            verify(imp !== null && imp.visible && imp.enabled, "Import button is present and hittable")
            // Assert the file dialog is wired with the expected image filters (do NOT
            // click — a native dialog would block the runner).
            var fd = find(function (n) {
                try { return n && n.nameFilters !== undefined && typeof n.open === "function"
                          && ("" + n.nameFilters).toLowerCase().indexOf("png") >= 0 } catch (e) { return false } })
            verify(fd !== null, "FileDialog present with image nameFilters (" + (fd ? fd.nameFilters : "?") + ")")
            var nf = "" + fd.nameFilters
            verify(nf.indexOf("jpg") >= 0 && nf.indexOf("jpeg") >= 0 && nf.indexOf("webp") >= 0,
                   "filters include jpg/jpeg/webp")
        }

        function test_j08_upload_path_backend_stub() {
            goTab(2)
            mh.backend.imagesList = ["fresh.png"]
            mh.backend.importImage("file:///imgs/fresh.png")   // stub records + emits imagesChanged
            wait(200)
            compare(mh.backend.lastImported, "file:///imgs/fresh.png", "backend.importImage recorded the file")
            var model = find(function (n) { try { return n && n.objectName === "imagesModel" } catch (e) { return false } })
            compare(model.count, 1, "imagesModel rebuilt after import")
            var cards = uploadedCards()
            verify(cards.length === 1 && cards[0].modelData === "fresh.png", "uploaded card appears for the imported file")
            _clearUploads()
        }

        function test_j09_uploaded_click_sets_wallpaper() {
            goTab(2)
            mh.backend.imagesList = ["pick.png"]; mh.backend.imagesChanged(); wait(200)
            var card = uploadedCards()[0]
            verify(card !== undefined, "uploaded card present")
            clickItem(card)
            compare(_store.appearance().wallpaper, mh.backend.imageUrl("pick.png"),
                    "clicking the uploaded card set it as wallpaper")
            _store.setAppearance("wallpaper", ""); _clearUploads()
        }

        function test_j10_uploaded_selected_label() {
            goTab(2)
            mh.backend.imagesList = ["chosen.png"]; mh.backend.imagesChanged(); wait(200)
            var card = uploadedCards()[0]
            clickItem(card)
            verify(card.isWall === true, "uploaded card marked isWall")
            compare(card.border.width, 3, "selected uploaded card has a 3px ring")
            var lbl = G.findPred(card, function (n) {
                try { return n && n.text === "wallpaper" && n.visible } catch (e) { return false } })
            verify(lbl !== null, "selected uploaded card label reads 'wallpaper'")
            _store.setAppearance("wallpaper", ""); _clearUploads()
        }

        function test_j11_delete_opens_confirm() {
            goTab(2)
            mh.backend.imagesList = ["del1.png"]; mh.backend.imagesChanged(); wait(200)
            var card = uploadedCards()[0]
            var trash = G.findPred(card, function (n) {
                try { return n && n.name === "ui-trash" } catch (e) { return false } })
            verify(trash !== null, "found the trash icon on the card")
            scrollIntoView(card)
            mouseClick(trash.parent, trash.parent.width / 2, trash.parent.height / 2)
            wait(200)
            var confirm = find(function (n) {
                try { return n && n.message !== undefined && ("onConfirm" in n) && typeof n.open === "function" } catch (e) { return false } })
            verify(confirm !== null, "found the confirm dialog")
            verify(confirm.opened === true, "confirm dialog opened")
            verify(("" + confirm.message).indexOf("del1.png") >= 0, "confirm message names the image")
            confirm.reject(); wait(120)
            compare(mh.backend.lastDeleted, "", "cancelling did NOT delete")
            _clearUploads()
        }

        function test_j12_delete_confirm_calls_backend() {
            goTab(2)
            mh.backend.lastDeleted = ""
            mh.backend.imagesList = ["del2.png"]; mh.backend.imagesChanged(); wait(200)
            mh.win.confirmDeleteImage("del2.png", mh.backend.imageUrl("del2.png"))
            wait(150)
            var confirm = find(function (n) {
                try { return n && n.message !== undefined && ("onConfirm" in n) && typeof n.open === "function" } catch (e) { return false } })
            verify(confirm.opened === true, "confirm dialog armed")
            confirm.accept(); wait(200)
            compare(mh.backend.lastDeleted, "del2.png", "confirming delete called backend.deleteImage")
            _clearUploads()
        }
    }
}
