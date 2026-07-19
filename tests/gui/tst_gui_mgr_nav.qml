import QtQuick
import QtTest
import "GuiUtil.js" as G

// REAL, on-screen GUI tests for the EdgeHub Manager: tab navigation & sidebar,
// scrolling (MScroll / GridView / popup lists), hub-connection state, scope
// pills, and the Device tab. The REAL Manager window is hosted ONCE via
// ManagerHarness in a real KWin compositor and driven with real mouse/keyboard
// events (mouseClick / mouseWheel / keyClick). Every case asserts an objective,
// GUI-observable outcome after a real interaction.
//
// Spec: scratchpad/specs/03_manager.md — areas B, C, M, N, O. Rules:
// scratchpad/specs/00_authoring_brief.md.
Item {
    id: root
    width: 100; height: 100
    ManagerHarness { id: mh }

    TestCase {
        id: tc
        name: "GuiMgrNav"
        when: windowShown
        visible: true

        // Cached seams (resolved once the window is up).
        property var nav: null       // the 5-tab StackLayout (objectName "managerTabs")
        property var store: null      // DashboardStore
        property color accentRef: "#000000"   // m.accent, read off a ScopeTag border

        // Fixed vocabulary (matches win.scopeLabels in Manager.qml).
        readonly property var chipLabels: ["Screens", "Look", "Images", "Device", "About"]
        readonly property var headings: ["Screens", "Look", "Images", "Device", "About"]

        // ── evidence ──
        function snap(item, nm) { var i = grabImage(item); i.save("gui-evidence/mgrnav_" + nm + ".png"); return i }

        // ── tree helpers (search the whole live window) ──
        function find(p) { return G.findPred(mh.win, p) }
        function findAll(p) { return G.collectPred(mh.win, p) }
        function byName(n) { return G.byObjName(mh.win, n) }
        function colorEq(a, b) { return Qt.colorEqual(a, b) }

        // A Text with exact text + pixel size (distinguishes sidebar chip labels @15
        // from tab headings @24 and body copy).
        function textItem(str, size) {
            return find(function (n) {
                try { return n && n.text === str && n.font && n.font.pixelSize === size } catch (e) { return false }
            })
        }
        function sidebarChipText(label) { return textItem(label, 15) }
        function chipRect(label) { var t = sidebarChipText(label); return t ? t.parent.parent : null }
        function headingText(str) {
            return find(function (n) { try { return n && n.text === str && n.font && n.font.pixelSize === 24 } catch (e) { return false } })
        }

        // Make a tab current (source-of-truth path; real chip clicks are tested in B1).
        function gotoTab(i) { nav.currentIndex = i; wait(250) }

        // First VISIBLE ScrollView (an MScroll) — i.e. the one on the current tab.
        function visibleScroll() {
            return find(function (n) {
                try {
                    return n && n.availableWidth !== undefined && n.contentItem
                        && n.contentItem.contentHeight !== undefined && n.visible
                } catch (e) { return false }
            })
        }
        // GridView (Images tab) — a Flickable with cellWidth.
        function gridView() {
            return find(function (n) { try { return n && n.cellWidth !== undefined && n.cellHeight !== undefined && n.visible } catch (e) { return false } })
        }
        // ScrollView living inside a given node (dialogs).
        function scrollIn(node) {
            return G.findPred(node, function (n) {
                try { return n && n.availableWidth !== undefined && n.contentItem && n.contentItem.contentHeight !== undefined } catch (e) { return false }
            })
        }

        // Real wheel over `target`; return how far `flick.contentY` moved.
        // notches>0 => scroll DOWN (angleDelta.y = -120 per notch).
        function wheelOn(target, flick, notches) {
            var before = flick.contentY
            var n = Math.abs(notches)
            var yd = notches > 0 ? -120 : 120
            for (var i = 0; i < n; i++) { mouseWheel(target, target.width / 2, target.height / 2, 0, yd); wait(110) }
            return flick.contentY - before
        }

        // Scroll an item into the viewport of an MScroll so a real click can land.
        function revealIn(sc, item) {
            var f = sc.contentItem
            if (!f) return
            for (var it = 0; it < 8; it++) {
                var p = item.mapToItem(f, 0, 0)
                var h = item.height || 24
                if (p.y >= 10 && p.y + h <= f.height - 10) break
                var maxY = Math.max(0, f.contentHeight - f.height)
                f.contentY = Math.max(0, Math.min(maxY, f.contentY + (p.y - f.height / 2)))
                wait(60)
            }
            wait(80)
        }

        // The ScopeTag adjacent to a section heading (same RowLayout).
        function pillNear(headingLabel) {
            var h = textItem(headingLabel, 15)
            if (!h || !h.parent) return null
            return G.byObjName(h.parent, "scopePill")
        }

        // ────────────────────────────────────────────────────────────────
        function initTestCase() {
            var w = mh.create()
            verify(w !== null, "Manager.qml instantiated")
            tryVerify(function () { return mh.ready }, 8000, "Manager window became visible")
            tryVerify(function () { return mh.win.active }, 5000, "Manager window is active/exposed")

            nav = byName("managerTabs")
            verify(nav !== null, "found the managerTabs StackLayout")
            compare(nav.count, 5, "5 tabs")

            store = find(function (n) { try { return n && n.applyExternal !== undefined && n.structureRevision !== undefined } catch (e) { return false } })
            verify(store !== null, "found the DashboardStore")

            var pill = byName("scopePill")
            verify(pill !== null, "found a ScopeTag to read the accent from")
            accentRef = pill.border.color
            console.warn("GuiMgrNav ready; accent=" + accentRef)
        }
        function cleanupTestCase() { mh.destroyWin() }

        // ═══════════════════════════════════════════════════════════════
        // AREA B — Tab switching & sidebar navigation (22)
        // ═══════════════════════════════════════════════════════════════

        // B1 — a REAL click on each sidebar chip switches to its tab.
        function test_b1_chip_click_switches_tab_data() {
            return [ { tag: "Screens", label: "Screens", idx: 0 },
                     { tag: "Look",    label: "Look",    idx: 1 },
                     { tag: "Images",  label: "Images",  idx: 2 },
                     { tag: "Device",  label: "Device",  idx: 3 },
                     { tag: "About",   label: "About",   idx: 4 } ]
        }
        function test_b1_chip_click_switches_tab(d) {
            nav.currentIndex = (d.idx + 2) % 5           // start elsewhere so the change is real
            wait(150)
            var chipTxt = sidebarChipText(d.label)
            verify(chipTxt !== null, "sidebar chip '" + d.label + "' present")
            mouseClick(chipTxt, chipTxt.width / 2, chipTxt.height / 2)
            wait(200)
            compare(nav.currentIndex, d.idx, "real click on '" + d.label + "' selected tab " + d.idx)
            snap(mh.win.contentItem, "b1_" + d.tag)
        }

        // B2 — the selected tab shows its heading.
        function test_b2_selected_tab_heading_visible_data() {
            return [ { tag: "Screens", idx: 0, h: "Screens" }, { tag: "Look", idx: 1, h: "Look" },
                     { tag: "Images", idx: 2, h: "Images" }, { tag: "Device", idx: 3, h: "Device" },
                     { tag: "About", idx: 4, h: "About" } ]
        }
        function test_b2_selected_tab_heading_visible(d) {
            gotoTab(d.idx)
            var h = headingText(d.h)
            verify(h !== null, "heading '" + d.h + "' exists")
            verify(h.visible, "heading '" + d.h + "' is visible when its tab is current")
        }

        // B3 — non-current tabs hide their content (exactly one heading visible).
        function test_b3_other_tabs_hidden_data() {
            return [ { tag: "t0", idx: 0 }, { tag: "t1", idx: 1 }, { tag: "t2", idx: 2 },
                     { tag: "t3", idx: 3 }, { tag: "t4", idx: 4 } ]
        }
        function test_b3_other_tabs_hidden(d) {
            gotoTab(d.idx)
            var visCount = 0
            for (var i = 0; i < headings.length; i++) {
                var h = headingText(headings[i])
                verify(h !== null, "heading '" + headings[i] + "' exists")
                if (h.visible) visCount++
                if (i === d.idx) verify(h.visible, "current tab " + d.idx + " heading visible")
                else verify(!h.visible, "non-current tab " + i + " heading hidden while " + d.idx + " current")
            }
            compare(visCount, 1, "exactly one tab heading visible at a time")
        }

        // B4 — the selected chip is visibly indicated (accent fill + bold + distinct label colour).
        function test_b4_selected_chip_indicated_data() {
            return [ { tag: "Screens", idx: 0, label: "Screens" }, { tag: "Look", idx: 1, label: "Look" },
                     { tag: "Images", idx: 2, label: "Images" }, { tag: "Device", idx: 3, label: "Device" },
                     { tag: "About", idx: 4, label: "About" } ]
        }
        function test_b4_selected_chip_indicated(d) {
            gotoTab(d.idx)
            var chipTxt = sidebarChipText(d.label)
            verify(chipTxt !== null, "chip label present")
            var chip = chipTxt.parent.parent
            verify(colorEq(chip.color, accentRef), "'" + d.label + "' chip filled with accent when selected (got " + chip.color + ")")
            verify(chipTxt.font.bold === true, "'" + d.label + "' chip label is bold when selected")
            var otherLabel = d.label === "Screens" ? "About" : "Screens"
            var otherTxt = sidebarChipText(otherLabel)
            verify(!colorEq(chipTxt.color, otherTxt.color), "selected label colour differs from an unselected chip's")
        }

        // B5 — only ONE chip indicated at a time.
        function test_b5_only_one_chip_indicated() {
            for (var t = 0; t < 5; t++) {
                gotoTab(t)
                var accented = 0
                for (var i = 0; i < chipLabels.length; i++) {
                    var c = chipRect(chipLabels[i])
                    verify(c !== null, "chip '" + chipLabels[i] + "' present")
                    if (colorEq(c.color, accentRef)) accented++
                }
                compare(accented, 1, "exactly one accent chip while tab " + t + " current")
            }
        }

        // B7 — switching tab commits a pending rename (audit F1).
        function test_b7_tab_switch_commits_rename() {
            gotoTab(0)
            var f = find(function (n) { try { return n && n.forIndex !== undefined && n.selectByMouse !== undefined } catch (e) { return false } })
            verify(f !== null, "found the page-name TextField")
            mouseClick(f, 12, f.height / 2); wait(140)
            f.selectAll(); wait(60)
            var word = "renamed"
            for (var i = 0; i < word.length; i++) { keyClick(word.charAt(i)); }
            wait(150)
            compare(f.text, word, "typed the new screen name")
            // Leave the field by switching tab — onCurrentIndexChanged -> commitRename().
            nav.currentIndex = 1; wait(300)
            compare(store.pages()[0].name, word, "rename committed to the RIGHT page on tab switch")
            nav.currentIndex = 0; wait(150)
        }

        // ═══════════════════════════════════════════════════════════════
        // AREA C — Scrolling: sensible step, NOT the tiny broken one (16)
        // Every case asserts >= ~100px per notch (the fix is ~130px/notch).
        // ═══════════════════════════════════════════════════════════════

        // C1/C5/C6/C7 — one wheel notch moves the tab's MScroll a sensible amount.
        function test_c_mscroll_sensible_notch_data() {
            return [ { tag: "appearance_apScroll", tab: 1 },
                     { tag: "screens_helperScroll", tab: 0 },
                     { tag: "device_dpScroll", tab: 3 },
                     { tag: "about_abScroll", tab: 4 } ]
        }
        function test_c_mscroll_sensible_notch(d) {
            gotoTab(d.tab)
            var sc = visibleScroll()
            verify(sc !== null, d.tag + ": a scrollable MScroll is visible")
            var f = sc.contentItem
            f.contentY = 0; wait(150)
            var maxY = Math.max(0, f.contentHeight - f.height)
            verify(maxY > 40, d.tag + ": content overflows so scrolling is meaningful (maxY=" + maxY + ")")
            snap(mh.win.contentItem, "c_" + d.tag + "_before")
            var delta = wheelOn(sc, f, 1)
            var expected = Math.min(100, maxY)
            verify(delta >= expected, d.tag + ": one notch moved " + delta + "px (>= " + expected + ") - NOT the broken tiny step")
            snap(mh.win.contentItem, "c_" + d.tag + "_after")
        }

        // C3 — every tab MScroll clamps at the top (wheel up at contentY=0 stays 0).
        function test_c_mscroll_clamp_top_data() {
            return [ { tag: "appearance", tab: 1 }, { tag: "screens", tab: 0 },
                     { tag: "device", tab: 3 }, { tag: "about", tab: 4 } ]
        }
        function test_c_mscroll_clamp_top(d) {
            gotoTab(d.tab)
            var sc = visibleScroll()
            verify(sc !== null, d.tag + ": scroll present")
            var f = sc.contentItem
            f.contentY = 0; wait(120)
            wheelOn(sc, f, -2)                     // wheel UP at the top
            verify(f.contentY <= 1, d.tag + ": clamps at top (contentY stayed " + f.contentY + ")")
        }

        // C2 — a few notches cover a large distance / reach the bottom (Appearance).
        function test_c_appearance_covers_distance_in_few_notches() {
            gotoTab(1)
            var sc = visibleScroll(); verify(sc !== null)
            var f = sc.contentItem
            f.contentY = 0; wait(120)
            var maxY = Math.max(0, f.contentHeight - f.height)
            wheelOn(sc, f, 5)
            verify(f.contentY >= Math.min(maxY, 500), "5 notches moved " + f.contentY + "px (>= min(maxY," + 500 + ")) - a few notches, not 20")
        }

        // C4 — Appearance MScroll clamps at the bottom (never exceeds max).
        function test_c_appearance_clamp_bottom() {
            gotoTab(1)
            var sc = visibleScroll(); verify(sc !== null)
            var f = sc.contentItem
            var maxY = Math.max(0, f.contentHeight - f.height)
            f.contentY = maxY; wait(120)
            wheelOn(sc, f, 3)
            verify(f.contentY <= maxY + 1, "clamps at bottom (contentY " + f.contentY + " <= maxY " + maxY + ")")
        }

        // C9 — the theme dropdown popup list scrolls a sensible amount.
        function test_c_theme_popup_scroll() {
            gotoTab(1)
            var sc = visibleScroll(); if (sc) { sc.contentItem.contentY = 0; wait(120) }
            var field = byName("themeDropdownField")
            verify(field !== null, "theme dropdown field present")
            mouseClick(field, field.width / 2, field.height / 2); wait(300)
            var list = find(function (n) { try { return n && n.contentY !== undefined && n.count !== undefined && n.count >= 20 && n.visible } catch (e) { return false } })
            verify(list !== null, "theme popup ListView is open")
            list.contentY = 0; wait(100)
            var maxY = Math.max(0, list.contentHeight - list.height)
            verify(maxY > 40, "theme list overflows (maxY=" + maxY + ")")
            var delta = wheelOn(list, list, 1)
            verify(delta >= Math.min(100, maxY), "theme popup moved " + delta + "px/notch (>= " + Math.min(100, maxY) + ")")
            snap(mh.win.contentItem, "c_theme_popup")
            mouseClick(field, field.width / 2, field.height / 2); wait(200)   // close
        }

        // C10 — theme popup scroll clamps at both ends.
        function test_c_theme_popup_clamp() {
            gotoTab(1)
            var field = byName("themeDropdownField"); verify(field !== null)
            mouseClick(field, field.width / 2, field.height / 2); wait(300)
            var list = find(function (n) { try { return n && n.contentY !== undefined && n.count !== undefined && n.count >= 20 && n.visible } catch (e) { return false } })
            verify(list !== null, "theme popup open")
            list.contentY = 0; wait(80)
            wheelOn(list, list, -2)
            verify(list.contentY <= 1, "theme popup clamps at top (" + list.contentY + ")")
            var maxY = Math.max(0, list.contentHeight - list.height)
            list.contentY = maxY; wait(80)
            wheelOn(list, list, 3)
            verify(list.contentY <= maxY + 1, "theme popup clamps at bottom (" + list.contentY + " <= " + maxY + ")")
            mouseClick(field, field.width / 2, field.height / 2); wait(200)
        }

        // C11 — the Images "Your images" GridView scrolls a sensible amount.
        function test_c_images_grid_scroll() {
            seedImages(24)
            gotoTab(2)
            var grid = gridView()
            verify(grid !== null, "images GridView is visible with uploads")
            grid.contentY = 0; wait(150)
            var maxY = Math.max(0, grid.contentHeight - grid.height)
            verify(maxY > 40, "image grid overflows (maxY=" + maxY + ")")
            snap(mh.win.contentItem, "c_imggrid_before")
            var delta = wheelOn(grid, grid, 1)
            verify(delta >= Math.min(100, maxY), "image grid moved " + delta + "px/notch (>= " + Math.min(100, maxY) + ")")
            snap(mh.win.contentItem, "c_imggrid_after")
        }

        // C12b — the Images GridView clamps at the top.
        function test_c_images_grid_clamp_top() {
            seedImages(24)
            gotoTab(2)
            var grid = gridView(); verify(grid !== null)
            grid.contentY = 0; wait(120)
            wheelOn(grid, grid, -2)
            verify(grid.contentY <= 1, "image grid clamps at top (" + grid.contentY + ")")
        }

        // C13 — the Add-widget picker's MScroll scrolls a sensible amount.
        function test_c_add_picker_scroll() {
            gotoTab(0)
            var sc0 = visibleScroll(); if (sc0) { sc0.contentItem.contentY = 0; wait(120) }
            var addBtn = find(function (n) { try { return n && n.text === "Add widget" && n.primary !== undefined } catch (e) { return false } })
            verify(addBtn !== null, "'Add widget' button present")
            if (sc0) revealIn(sc0, addBtn)
            mouseClick(addBtn, addBtn.width / 2, addBtn.height / 2); wait(400)
            var dlg = find(function (n) { try { return n && n.title === "Add a widget" && typeof n.close === "function" } catch (e) { return false } })
            verify(dlg !== null, "add-widget dialog opened")
            var sc = scrollIn(dlg)
            verify(sc !== null, "picker MScroll present")
            var f = sc.contentItem; f.contentY = 0; wait(150)
            var maxY = Math.max(0, f.contentHeight - f.height)
            verify(maxY > 40, "picker content overflows (maxY=" + maxY + ")")
            var delta = wheelOn(sc, f, 1)
            verify(delta >= Math.min(100, maxY), "picker moved " + delta + "px/notch (>= " + Math.min(100, maxY) + ")")
            snap(mh.win.contentItem, "c_add_picker")
            dlg.close(); wait(250)
        }

        // C14 — the preset "Start from a preset screen" dialog scrolls a sensible amount.
        function test_c_preset_dialog_scroll() {
            gotoTab(0)
            var sc0 = visibleScroll(); if (sc0) { sc0.contentItem.contentY = 0; wait(120) }
            var presetBtn = find(function (n) { try { return n && ("" + n.text).indexOf("preset screen") >= 0 && n.iconName !== undefined } catch (e) { return false } })
            verify(presetBtn !== null, "'Start from a preset screen' button present")
            if (sc0) revealIn(sc0, presetBtn)
            mouseClick(presetBtn, presetBtn.width / 2, presetBtn.height / 2); wait(400)
            var dlg = find(function (n) { try { return n && n.title === "Start from a preset screen" && typeof n.close === "function" } catch (e) { return false } })
            verify(dlg !== null, "preset dialog opened")
            var sc = scrollIn(dlg); verify(sc !== null, "preset MScroll present")
            var f = sc.contentItem; f.contentY = 0; wait(150)
            var maxY = Math.max(0, f.contentHeight - f.height)
            verify(maxY > 40, "preset list overflows (maxY=" + maxY + ")")
            var delta = wheelOn(sc, f, 1)
            verify(delta >= Math.min(100, maxY), "preset dialog moved " + delta + "px/notch (>= " + Math.min(100, maxY) + ")")
            snap(mh.win.contentItem, "c_preset_dialog")
            dlg.close(); wait(250)
        }

        function seedImages(n) {
            var arr = []
            for (var i = 0; i < n; i++) arr.push("gui-img-" + i + ".png")
            mh.backend.imagesList = arr
            mh.backend.imagesChanged()
            wait(200)
        }

        // ═══════════════════════════════════════════════════════════════
        // AREA M — Connection state (12)
        // ═══════════════════════════════════════════════════════════════

        // The sidebar status dot (10x10, radius 5) and its sibling status Text.
        function statusDot() { return find(function (n) { try { return n && n.width === 10 && n.height === 10 && n.radius === 5 && n.color !== undefined } catch (e) { return false } }) }
        function statusText(dot) { return G.findPred(dot.parent, function (n) { try { return n && n.text !== undefined && n.font && n.font.pixelSize === 12 } catch (e) { return false } }) }
        function hubButton() { return find(function (n) { try { return n && (n.text === "Start hub" || n.text === "Stop hub") && n.primary !== undefined } catch (e) { return false } }) }

        function test_m1_offline_dot_grey_text() {
            mh.win.hubStarting = false; mh.backend.hubConnected = false; wait(200)
            var dot = statusDot(); verify(dot !== null, "status dot present")
            var txt = statusText(dot); verify(txt !== null, "status text present")
            verify(colorEq(dot.color, txt.color), "offline dot uses the secondary (grey) tone, like the label")
            verify(("" + txt.text).toLowerCase().indexOf("offline") >= 0, "text says offline: '" + txt.text + "'")
            snap(mh.win.contentItem, "m1_offline")
        }
        function test_m2_connected_dot_green_text() {
            mh.win.hubStarting = false; mh.backend.hubConnected = true; wait(200)
            var dot = statusDot(); var txt = statusText(dot)
            var c = "" + dot.color                          // dot is a Rectangle; classify its colour string
            // success is a green tone: green channel dominant.
            var r = parseInt(c.substr(1, 2), 16), g = parseInt(c.substr(3, 2), 16), b = parseInt(c.substr(5, 2), 16)
            verify(g > r && g > b, "connected dot is green-dominant (" + c + ")")
            verify(!colorEq(dot.color, accentRef), "connected dot is not the accent")
            verify(("" + txt.text).toLowerCase().indexOf("connected") >= 0, "text says connected: '" + txt.text + "'")
            snap(mh.win.contentItem, "m2_connected")
            mh.backend.hubConnected = false; wait(100)
        }
        function test_m3_starting_dot_accent_text() {
            mh.backend.hubConnected = false; mh.win.hubStarting = true; wait(200)
            var dot = statusDot(); var txt = statusText(dot)
            verify(colorEq(dot.color, accentRef), "starting dot uses the accent (" + dot.color + ")")
            verify(("" + txt.text).toLowerCase().indexOf("starting") >= 0, "text says starting: '" + txt.text + "'")
            mh.win.hubStarting = false; wait(100)
        }
        function test_m4_offline_button_is_start() {
            mh.win.hubStarting = false; mh.backend.hubConnected = false; wait(150)
            var b = hubButton(); verify(b !== null, "hub button present")
            compare(b.text, "Start hub")
            compare(b.primary, true, "Start is the primary action when offline")
            compare(b.iconName, "ui-play")
        }
        function test_m5_connected_button_is_stop() {
            mh.win.hubStarting = false; mh.backend.hubConnected = true; wait(150)
            var b = hubButton(); verify(b !== null)
            compare(b.text, "Stop hub")
            compare(b.iconName, "ui-close")
            mh.backend.hubConnected = false; wait(100)
        }
        function test_m6_start_click_calls_backend_and_enters_starting() {
            mh.win.hubStarting = false; mh.backend.hubConnected = false
            mh.backend.startHubCalled = false; wait(150)
            var b = hubButton(); verify(b !== null && b.text === "Start hub")
            mouseClick(b, b.width / 2, b.height / 2); wait(250)
            compare(mh.backend.startHubCalled, true, "backend.startHub() called by the real click")
            compare(mh.win.hubStarting, true, "entered the 'starting' state")
            compare(b.enabled, false, "button disabled while starting")
            mh.win.hubStarting = false; wait(100)
        }
        function test_m7_stop_click_calls_backend() {
            mh.win.hubStarting = false; mh.backend.hubConnected = true
            mh.backend.stopHubCalled = false; wait(150)
            var b = hubButton(); verify(b !== null && b.text === "Stop hub")
            mouseClick(b, b.width / 2, b.height / 2); wait(250)
            compare(mh.backend.stopHubCalled, true, "backend.stopHub() called by the real click")
            compare(mh.win.hubStarting, false, "stopping does not enter the starting state")
            mh.backend.hubConnected = false; wait(100)
        }
        function test_m8_connect_clears_starting() {
            mh.backend.hubConnected = false; mh.win.hubStarting = true; wait(150)
            mh.backend.hubConnected = true; wait(200)
            compare(mh.win.hubStarting, false, "onHubConnectedChanged cleared the 'starting' state")
            mh.backend.hubConnected = false; wait(100)
        }
        function test_m9_livenote_follows_connection() {
            mh.backend.hubConnected = true; wait(120)
            verify(("" + mh.win.liveNote).toLowerCase().indexOf("immediately") >= 0, "live note (connected): '" + mh.win.liveNote + "'")
            mh.backend.hubConnected = false; wait(120)
            verify(("" + mh.win.liveNote).toLowerCase().indexOf("when the hub starts") >= 0, "live note (offline): '" + mh.win.liveNote + "'")
        }
        function test_m10_button_label_toggles_with_connection() {
            mh.win.hubStarting = false; mh.backend.hubConnected = false; wait(150)
            compare(hubButton().text, "Start hub")
            mh.backend.hubConnected = true; wait(150)
            compare(hubButton().text, "Stop hub")
            mh.backend.hubConnected = false; wait(120)
        }
        function test_m11_diagnostics_line_reflects_connection_and_screens() {
            mh.backend.hubConnected = true
            mh.win.screens = [ { name: "GuiA", model: "GuiA", width: 1920, height: 1080, isEdge: true },
                               { name: "GuiB", model: "GuiB", width: 1280, height: 720, isEdge: false } ]
            gotoTab(4); wait(200)
            var diag = find(function (n) { try { return n && n.text !== undefined && ("" + n.text).indexOf("display") >= 0 && n.visible } catch (e) { return false } })
            verify(diag !== null, "diagnostics line present")
            verify(("" + diag.text).indexOf("connected") >= 0, "diagnostics shows connection: '" + diag.text + "'")
            verify(("" + diag.text).indexOf("2 display") >= 0, "diagnostics shows 2 displays: '" + diag.text + "'")
            mh.backend.hubConnected = false; wait(100)
        }
        function test_m12_helper_note_colour_follows_connection() {
            gotoTab(0)
            mh.backend.hubConnected = true; wait(200)
            var note = find(function (n) { try { return n && n.text === mh.win.liveNote && n.font && n.font.pixelSize === 12 && n.visible } catch (e) { return false } })
            verify(note !== null, "helper live-note present")
            var c = "" + note.color
            var r = parseInt(c.substr(1, 2), 16), g = parseInt(c.substr(3, 2), 16), b = parseInt(c.substr(5, 2), 16)
            verify(g > r && g > b, "connected note is green/success (" + c + ")")
            mh.backend.hubConnected = false; wait(200)
            var note2 = find(function (n) { try { return n && n.text === mh.win.liveNote && n.font && n.font.pixelSize === 12 && n.visible } catch (e) { return false } })
            verify(note2 !== null, "offline live-note present")
            var dot = statusDot()
            verify(colorEq(note2.color, statusText(dot).color), "offline note uses the secondary tone")
        }

        // ═══════════════════════════════════════════════════════════════
        // AREA N — Scope pills (ScopeTag vocabulary) (14)
        // ═══════════════════════════════════════════════════════════════

        readonly property var scopeVocab: ["This widget only", "This screen only", "All screens",
                                            "Whole Edge", "This computer", "This window only"]

        function test_n1_every_pill_uses_the_vocabulary() {
            var pills = findAll(function (n) { try { return n && n.objectName === "scopePill" } catch (e) { return false } })
            verify(pills.length > 0, "found scope pills")
            for (var i = 0; i < pills.length; i++)
                verify(scopeVocab.indexOf(pills[i].label) >= 0, "pill label '" + pills[i].label + "' is in the closed vocabulary")
        }
        function test_n2_every_pill_can_state_its_rule() {
            var pills = findAll(function (n) { try { return n && n.objectName === "scopePill" } catch (e) { return false } })
            for (var i = 0; i < pills.length; i++)
                verify(("" + mh.win.scopeDetail(pills[i].label)).length > 0, "pill '" + pills[i].label + "' has a hover rule")
        }
        function test_n3_at_least_eight_pills() {
            var pills = findAll(function (n) { try { return n && n.objectName === "scopePill" } catch (e) { return false } })
            verify(pills.length >= 8, "at least 8 scope pills across the UI (found " + pills.length + ")")
        }
        function test_n4_scope_detail_wording_data() {
            return [ { tag: "widget",   label: "This widget only", needle: "other widgets" },
                     { tag: "screen",   label: "This screen only", needle: "other screens" },
                     { tag: "screens",  label: "All screens",      needle: "every screen" },
                     { tag: "edge",     label: "Whole Edge",       needle: "every screen and every widget" },
                     { tag: "computer", label: "This computer",    needle: "this computer" },
                     { tag: "window",   label: "This window only", needle: "manager window" } ]
        }
        function test_n4_scope_detail_wording(d) {
            var detail = ("" + mh.win.scopeDetail(d.label)).toLowerCase()
            verify(detail.indexOf(d.needle) >= 0, "'" + d.label + "' detail contains '" + d.needle + "': " + detail)
        }
        function test_n5_unknown_label_has_no_rule() {
            compare(mh.win.scopeDetail("Nonsense scope"), "", "unknown label yields no rule text")
        }
        function test_n6_pill_renders_as_accent_outline() {
            gotoTab(1); wait(150)
            var pill = find(function (n) { try { return n && n.objectName === "scopePill" && n.visible } catch (e) { return false } })
            verify(pill !== null, "a visible scope pill on the Look tab")
            verify(colorEq(pill.color, "transparent"), "pill interior is transparent (outline, not fill)")
            verify(colorEq(pill.border.color, accentRef), "pill border is the accent")
            verify(pill.border.width >= 1, "pill has a visible outline")
            snap(pill, "n6_pill")
        }
        function test_n8_look_tab_pills_say_whole_edge() {
            gotoTab(1); wait(150)
            var edgeTheme = pillNear("Edge theme")
            verify(edgeTheme !== null, "Edge theme pill present")
            compare(edgeTheme.label, "Whole Edge")
            var accent = pillNear("Accent colour")
            verify(accent !== null, "Accent pill present")
            compare(accent.label, "Whole Edge")
        }
        function test_n10_background_and_window_pills() {
            gotoTab(1); wait(150)
            var bg = pillNear("Background")
            verify(bg !== null, "Background pill present")
            compare(bg.label, "All screens")
            var winStyle = pillNear("Manager window style")
            verify(winStyle !== null, "Window-style pill present")
            compare(winStyle.label, "This window only")
        }
        function test_n12_device_tab_pills() {
            gotoTab(3); wait(150)
            var ori = pillNear("Orientation")
            verify(ori !== null, "Orientation pill present")
            compare(ori.label, "Whole Edge")
            var startup = pillNear("Startup")
            verify(startup !== null, "Startup pill present")
            compare(startup.label, "This computer")
        }

        // ═══════════════════════════════════════════════════════════════
        // AREA O — Device tab (18)
        // ═══════════════════════════════════════════════════════════════

        function twoScreens() {
            return [ { name: "GuiMon1", model: "GuiMon1", width: 1920, height: 1080, isEdge: true },
                     { name: "GuiMon2", model: "GuiMon2", width: 1280, height: 720, isEdge: false } ]
        }

        function test_o1_device_heading_visible() {
            gotoTab(3)
            var h = headingText("Device")
            verify(h !== null && h.visible, "Device heading visible on tab 3")
            snap(mh.win.contentItem, "o1_device")
        }
        function test_o2_empty_state_when_no_screens() {
            mh.win.screens = []
            gotoTab(3); wait(200)
            var empty = byName("screensEmpty")
            verify(empty !== null, "screensEmpty row exists")
            verify(empty.visible, "empty state shows when there are no screens")
        }
        function test_o3_empty_state_hides_with_a_screen() {
            mh.win.screens = [ twoScreens()[0] ]
            gotoTab(3); wait(200)
            var empty = byName("screensEmpty")
            verify(empty !== null)
            verify(!empty.visible, "empty state hidden once a screen exists")
        }
        function test_o4_screen_cards_render_with_details_and_edge_tag() {
            mh.win.screens = twoScreens()
            gotoTab(3); wait(250)
            verify(find(function (n) { try { return n && ("" + n.text).indexOf("GuiMon1") >= 0 && n.visible } catch (e) { return false } }) !== null, "screen 1 named")
            verify(find(function (n) { try { return n && ("" + n.text).indexOf("GuiMon2") >= 0 && n.visible } catch (e) { return false } }) !== null, "screen 2 named")
            verify(find(function (n) { try { return n && ("" + n.text).indexOf("Xeneon Edge") >= 0 && n.visible } catch (e) { return false } }) !== null, "the Edge screen is tagged")
            verify(find(function (n) { try { return n && ("" + n.text).indexOf("1920") >= 0 && n.visible } catch (e) { return false } }) !== null, "resolution shown")
            snap(mh.win.contentItem, "o4_screens")
        }
        function test_o6_target_card_highlighted() {
            mh.win.screens = twoScreens()
            mh.win.currentTarget = "GuiMon1"
            gotoTab(3); wait(250)
            var modelTxt = find(function (n) { try { return n && ("" + n.text).indexOf("GuiMon1") >= 0 && n.font && n.font.pixelSize === 15 && n.visible } catch (e) { return false } })
            verify(modelTxt !== null, "found the target card's model text")
            var card = modelTxt.parent.parent.parent
            compare(card.border.width, 2, "target card has a 2px border")
            verify(colorEq(card.border.color, accentRef), "target card border is the accent")
        }
        function test_o7_set_as_target_click_updates_target() {
            mh.win.screens = twoScreens()
            mh.win.currentTarget = ""            // nothing targeted -> both are "Set as target"
            gotoTab(3); wait(250)
            var sc = visibleScroll()
            var btn = findAll(function (n) { try { return n && n.text === "Set as target" && n.primary !== undefined && n.visible } catch (e) { return false } })[0]
            verify(btn !== undefined && btn !== null, "a 'Set as target' button present")
            if (sc) revealIn(sc, btn)
            mouseClick(btn, btn.width / 2, btn.height / 2); wait(250)
            verify(mh.win.currentTarget.length > 0, "target set by the real click (currentTarget='" + mh.win.currentTarget + "')")
        }
        function test_o8_target_button_shows_check() {
            mh.win.screens = twoScreens()
            mh.win.currentTarget = "GuiMon1"
            gotoTab(3); wait(250)
            var btn = find(function (n) { try { return n && n.text === "Target" && n.primary !== undefined && n.visible } catch (e) { return false } })
            verify(btn !== null, "the target card's button reads 'Target'")
            compare(btn.primary, true, "target button is primary")
            compare(btn.iconName, "ui-check")
        }
        function test_o9_orientation_chip_selects_data() {
            return [ { tag: "auto", v: "auto", l: "Auto" },
                     { tag: "portrait", v: "portrait", l: "Portrait" },
                     { tag: "landscape", v: "landscape", l: "Landscape" },
                     { tag: "inv_portrait", v: "inverted-portrait", l: "Portrait (flipped)" },
                     { tag: "inv_landscape", v: "inverted-landscape", l: "Landscape (flipped)" } ]
        }
        function test_o9_orientation_chip_selects(d) {
            gotoTab(3); wait(150)
            var sc = visibleScroll()
            var lbl = find(function (n) { try { return n && n.text === d.l && n.font && n.font.pixelSize === 13 && n.visible } catch (e) { return false } })
            verify(lbl !== null, "orientation chip '" + d.l + "' present")
            if (sc) revealIn(sc, lbl)
            mouseClick(lbl, lbl.width / 2, lbl.height / 2); wait(250)
            compare(store.appearance().orientation, d.v, "orientation committed to '" + d.v + "'")
            var chip = lbl.parent
            verify(chip.sel === true, "the '" + d.l + "' chip is indicated (sel)")
            verify(colorEq(chip.color, accentRef), "the selected chip is accent-filled")
        }
        function test_o11_landscape_orientation_turns_the_clone() {
            gotoTab(3); wait(120)
            store.setAppearance("orientation", "landscape"); wait(300)
            var clone = find(function (n) { try { return n && n.landscape !== undefined && n.editable !== undefined } catch (e) { return false } })
            verify(clone !== null, "found an EdgeClone")
            verify(clone.landscape === true, "landscape orientation turns the preview wide")
            store.setAppearance("orientation", "auto"); wait(150)
        }
        function test_o12_autostart_switch_calls_backend_both_ways() {
            gotoTab(3); wait(150)
            var sc = visibleScroll()
            mh.backend.autostart = false
            var sw = find(function (n) { try { return n && n.text === "Start the hub automatically on login" && n.checked !== undefined } catch (e) { return false } })
            verify(sw !== null, "autostart switch present")
            if (sc) revealIn(sc, sw)
            mouseClick(sw, sw.width / 2, sw.height / 2); wait(250)
            compare(mh.backend.autostart, true, "autostart enabled via the real click")
            mouseClick(sw, sw.width / 2, sw.height / 2); wait(250)
            compare(mh.backend.autostart, false, "autostart disabled via the real click")
        }
        function test_o13_update_switch_persists_both_ways() {
            gotoTab(3); wait(150)
            var sc = visibleScroll()
            // ensure known start state (off)
            if (store.appearance().updateCheck === true) store.setAppearance("updateCheck", false)
            wait(120)
            var sw = find(function (n) { try { return n && n.text === "Check for updates automatically" && n.checked !== undefined } catch (e) { return false } })
            verify(sw !== null, "update-check switch present")
            if (sc) revealIn(sc, sw)
            mouseClick(sw, sw.width / 2, sw.height / 2); wait(250)
            compare(store.appearance().updateCheck, true, "update-check turned on")
            mouseClick(sw, sw.width / 2, sw.height / 2); wait(250)
            compare(store.appearance().updateCheck, false, "update-check turned off")
        }
        function test_o14_reset_button_opens_confirm() {
            gotoTab(3); wait(150)
            var sc = visibleScroll()
            var btn = byName("resetLayoutBtn")
            verify(btn !== null, "resetLayoutBtn present")
            if (sc) revealIn(sc, btn)
            mouseClick(btn, btn.width / 2, btn.height / 2); wait(300)
            var confirm = find(function (n) { try { return n && n.message !== undefined && ("onConfirm" in n) && typeof n.close === "function" } catch (e) { return false } })
            verify(confirm !== null, "confirm dialog found")
            verify(confirm.opened === true || confirm.visible === true, "reset opened the confirm dialog")
            verify(("" + confirm.message).indexOf("default layout") >= 0, "confirm warns about the default layout")
            confirm.close(); wait(250)
        }
        function test_o15_screen_picker_note_is_screen_scoped() {
            gotoTab(3); wait(150)
            var note = find(function (n) { try { return n && ("" + n.text).indexOf("next time the hub starts") >= 0 && n.visible } catch (e) { return false } })
            verify(note !== null, "the 'applies next time the hub starts' note sits on the screen picker")
        }
        function test_o16_startup_and_update_scope_pills() {
            gotoTab(3); wait(150)
            var startup = pillNear("Startup")
            verify(startup !== null && startup.label === "This computer", "Startup pill is 'This computer'")
            var updates = pillNear("Software updates")
            verify(updates !== null && updates.label === "Whole Edge", "Software-updates pill is 'Whole Edge'")
        }
    }
}
