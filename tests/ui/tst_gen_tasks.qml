import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: schema:hideCompleted, schema:items

// ─────────────────────────────────────────────────────────────────────────
// Comprehensive coverage for area "widget:tasks" (ui/qml/widgets/TasksWidget.qml).
//
// Drives the widget through its real config surface (store.setSetting /
// patchSettings / applyExternal keyed on "test-instance") and asserts on the
// widget's derived properties and functions: items / visibleItems / doneCount /
// status / toggle / remove / add / clearCompleted / celebrate.
//
// Several assertions intentionally document REAL bugs called out in the audit
// (stale/out-of-range storage index, dropped item fields, undefined text,
// empty-state shown while completed tasks exist, celebration re-firing, scroll
// reset). Those failures are the point — they are NOT test mistakes.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 520; height: 940

    // Expanded instance — the interactive editor surface.
    WidgetHarness { id: hTasks;   anchors.fill: parent; widgetFile: "TasksWidget.qml"; expanded: true }
    // Compact instance — tile mode (taps must fall through to the host).
    WidgetHarness { id: hCompact; anchors.fill: parent; widgetFile: "TasksWidget.qml"; expanded: false }

    // Schema is a shared area; instantiate it directly (as the config tests do).
    App.WidgetConfigSchema { id: sc }

    // ── helpers ──────────────────────────────────────────────────────────
    // Recursively find the first descendant whose `text` contains `sub`.
    function findText(node, sub) {
        if (!node || node.children === undefined) return null
        for (var i = 0; i < node.children.length; i++) {
            var c = node.children[i]
            if (c && typeof c.text === "string" && c.text.indexOf(sub) >= 0) return c
            var r = findText(c, sub)
            if (r) return r
        }
        return null
    }
    // Recursively find the first ListView descendant (duck-typed).
    function findListView(node) {
        if (!node || node.children === undefined) return null
        for (var i = 0; i < node.children.length; i++) {
            var c = node.children[i]
            if (c && c.contentY !== undefined && typeof c.positionViewAtEnd === "function") return c
            var r = findListView(c)
            if (r) return r
        }
        return null
    }
    // Find a schema field by key across all sections of a schema.
    function fieldByKey(schema, key) {
        for (var j = 0; j < schema.sections.length; j++) {
            var fs = schema.sections[j].fields || []
            for (var k = 0; k < fs.length; k++)
                if (fs[k].key === key) return fs[k]
        }
        return null
    }

    // ── Main widget behaviour ────────────────────────────────────────────
    TestCase {
        name: "TasksWidget"
        when: windowShown

        function init() {
            tryVerify(function () { return hTasks.ready }, 3000)
            var s = hTasks.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hTasks.storeCtl._touchSettings()
            hTasks.item.celebrateMsg = ""
        }
        function cfg() { return hTasks.storeCtl.settingsFor("test-instance") }
        function setItems(a) { hTasks.storeCtl.setSetting("test-instance", "items", a) }

        // ---- schema-matching defaults ------------------------------------
        function test_defaults_match_schema() {
            var w = hTasks.item
            // With no config the widget uses schema defaults: items [], hideCompleted
            // false, celebrate true.
            compare(w.items.length, 0, "no items by default")
            compare(w.hideCompleted, false, "hideCompleted defaults false")
            compare(w.celebrate, true, "celebrate defaults true")
            compare(w.doneCount, 0)
            compare(w.status, "", "no status string when list empty")

            var s = sc.schemaFor("tasks")
            compare(fieldByKey(s, "hideCompleted").dflt, false, "schema hideCompleted dflt false")
            compare(fieldByKey(s, "celebrate").dflt, true, "schema celebrate dflt true")
            verify(fieldByKey(s, "items") !== null, "schema exposes the tasks items field")
        }

        // ---- add() -------------------------------------------------------
        function test_add_appends_and_persists() {
            var w = hTasks.item
            w.add("Write report")
            w.add("Email team")
            compare(w.items.length, 2)
            compare(cfg().items.length, 2, "add persists through the store")
            compare(w.items[1].text, "Email team")
            compare(w.items[1].done, false, "new tasks start not-done")
        }
        function test_add_rejects_empty_whitespace_null_and_trims() {
            var w = hTasks.item
            w.add(""); w.add("   "); w.add(null)
            compare(w.items.length, 0, "empty/whitespace/null rejected")
            w.add("  spaced  ")
            compare(w.items.length, 1)
            compare(w.items[0].text, "spaced", "surrounding whitespace trimmed")
        }

        // ---- toggle() ----------------------------------------------------
        function test_toggle_flips_only_target_and_persists() {
            var w = hTasks.item
            setItems([{ text: "a", done: false }, { text: "b", done: false }, { text: "c", done: false }])
            w.toggle(1)
            compare(w.items[1].done, true, "target flipped")
            compare(w.items[0].done, false, "sibling untouched")
            compare(w.items[2].done, false, "sibling untouched")
            compare(cfg().items[1].done, true, "toggle persisted via setSetting")
            compare(w.doneCount, 1)
        }

        // ---- remove() ----------------------------------------------------
        function test_remove_deletes_correct_index() {
            var w = hTasks.item
            setItems([{ text: "a", done: false }, { text: "b", done: false }, { text: "c", done: false }])
            w.remove(0)
            compare(w.items.length, 2)
            compare(w.items[0].text, "b")
            compare(w.items[1].text, "c")
        }
        function test_remove_out_of_range_is_safe_noop() {
            var w = hTasks.item
            setItems([{ text: "a", done: false }, { text: "b", done: false }])
            w.remove(5)   // splice(5,1) on len-2 removes nothing
            compare(w.items.length, 2, "out-of-range remove must not delete anything")
            compare(w.items[0].text, "a")
            compare(w.items[1].text, "b")
        }

        // ---- status + reactivity ----------------------------------------
        function test_status_is_done_over_total_and_reactive() {
            var w = hTasks.item
            setItems([{ text: "a", done: true }, { text: "b", done: false }, { text: "c", done: true }])
            compare(w.status, "2/3", "status is doneCount/total")
            w.toggle(1)
            compare(w.status, "3/3", "status updates reactively on revision bump")
        }

        // ---- external (Manager) push updates the tile live ---------------
        function test_external_setUiState_updates_live() {
            var w = hTasks.item
            var doc = {
                version: 1, appearance: {},
                pages: [ { name: "Home", tiles: [ { id: "test-instance", type: "tasks" } ] } ],
                settings: { "test-instance": { items: [ { text: "live", done: false } ] } }
            }
            verify(hTasks.storeCtl.applyExternal(JSON.stringify(doc)), "applyExternal accepts the doc")
            compare(w.items.length, 1, "Manager push reflected live")
            compare(w.items[0].text, "live")
        }

        // ---- hideCompleted + visibleItems idx mapping --------------------
        function test_hidecompleted_false_shows_all() {
            var w = hTasks.item
            hTasks.storeCtl.patchSettings("test-instance", {
                hideCompleted: false,
                items: [{ text: "a", done: true }, { text: "b", done: false }] })
            compare(w.visibleItems.length, 2, "completed tasks visible when hideCompleted off")
        }
        function test_hidecompleted_true_hides_done_but_idx_maps() {
            var w = hTasks.item
            // First item done + hidden; visible list must still map to storage idx.
            hTasks.storeCtl.patchSettings("test-instance", {
                hideCompleted: true,
                items: [{ text: "done0", done: true },
                        { text: "open1", done: false },
                        { text: "open2", done: false }] })
            compare(w.visibleItems.length, 2, "the done item is hidden")
            compare(w.visibleItems[0].text, "open1")
            compare(w.visibleItems[0].idx, 1, "visible row 0 maps to storage index 1")
            compare(w.visibleItems[1].idx, 2, "visible row 1 maps to storage index 2")
            // Toggle the FIRST visible row via its mapped idx → must hit storage[1].
            w.toggle(w.visibleItems[0].idx)
            compare(w.items[1].done, true, "correct storage entry toggled")
            compare(w.items[0].done, true, "the pre-existing done item unchanged")
            compare(w.items[2].done, false, "the other open item unchanged")
        }

        // ---- BUG: stale idx after external shrink -------------------------
        // A row was rendered with idx=1, then the list shrank to length 1
        // (Manager push / config edit). Tapping that row calls toggle(1) with a
        // now out-of-range index. It must be a safe no-op, not a crash or a
        // wrong-entry mutation.  (audit: stale storage-index)
        function test_toggle_stale_idx_after_shrink_is_safe() {
            var w = hTasks.item
            setItems([{ text: "only", done: false }])
            w.toggle(1)   // stale idx from a 2-item render
            compare(w.items.length, 1, "no entry created/destroyed")
            compare(w.items[0].text, "only", "surviving item unchanged")
            compare(w.items[0].done, false, "stale toggle did not flip anything")
        }

        // ---- BUG: extra item fields dropped on toggle --------------------
        // (audit: toggle rebuilds each item as {text,done})
        function test_toggle_preserves_extra_fields() {
            var w = hTasks.item
            setItems([{ text: "x", done: false, id: "u1" }])
            w.toggle(0)
            compare(w.items[0].done, true, "toggle still flips done")
            compare(w.items[0].id, "u1", "external id must survive an on-device toggle")
        }

        // ---- BUG: undefined text propagated ------------------------------
        // (audit: undefined/absent item.text silently propagated)
        function test_toggle_malformed_item_missing_text() {
            var w = hTasks.item
            setItems([{ done: false }])   // no text key
            w.toggle(0)
            verify(w.items[0].text !== undefined,
                   "a malformed item must not be re-persisted with text:undefined")
        }

        // ---- empty-state placeholder -------------------------------------
        function test_empty_state_visible_when_truly_empty() {
            var w = hTasks.item
            setItems([])
            var ph = findText(hTasks.item, "No tasks")
            verify(ph !== null, "placeholder element exists")
            compare(ph.visible, true, "placeholder shows when there are genuinely no tasks")
        }
        // ---- BUG: empty-state shown while completed tasks exist ----------
        // (audit: 'No tasks' empty state shown while completed tasks exist under
        //  hideCompleted=true, contradicting status + Clear button)
        function test_empty_state_hidden_when_completed_tasks_exist() {
            var w = hTasks.item
            hTasks.storeCtl.patchSettings("test-instance", {
                hideCompleted: true,
                items: [{ text: "a", done: true }, { text: "b", done: true }, { text: "c", done: true }] })
            compare(w.status, "3/3", "header still reports 3/3")
            compare(w.doneCount, 3, "Clear-N button would show 3")
            var ph = findText(hTasks.item, "No tasks")
            verify(ph !== null, "placeholder element exists")
            compare(ph.visible, false,
                    "must NOT claim 'no tasks' while 3 completed tasks exist")
        }

        // ---- celebration -------------------------------------------------
        function test_celebrate_fires_when_list_becomes_all_done() {
            var w = hTasks.item
            setItems([{ text: "a", done: false }, { text: "b", done: false }])
            w.celebrateMsg = ""
            w.toggle(0)
            compare(w.celebrateMsg, "", "no celebration until the LAST task is done")
            w.toggle(1)
            compare(w.celebrateMsg, "🎉 All done!", "celebration fires as the list completes")
        }
        function test_celebrate_false_suppresses_burst() {
            var w = hTasks.item
            hTasks.storeCtl.patchSettings("test-instance", {
                celebrate: false,
                items: [{ text: "a", done: false }] })
            w.celebrateMsg = ""
            w.toggle(0)
            compare(w.celebrateMsg, "", "celebrate=false suppresses the burst entirely")
        }
        // ---- BUG: celebration re-fires on re-completing an all-done list --
        // (audit: 'All done' celebration re-fires every time)
        function test_celebrate_does_not_refire_on_recomplete() {
            var w = hTasks.item
            setItems([{ text: "a", done: false }])
            w.toggle(0)                    // completes → fires once (expected)
            w.toggle(0)                    // un-complete
            w.celebrateMsg = ""            // reset our probe
            w.toggle(0)                    // re-complete an already-seen full list
            compare(w.celebrateMsg, "",
                    "re-completing an already-complete list must not re-fire the celebration")
        }

        // ---- clearCompleted ---------------------------------------------
        function test_clear_completed_keeps_only_open_in_order() {
            var w = hTasks.item
            setItems([{ text: "a", done: true }, { text: "b", done: false },
                      { text: "c", done: true }, { text: "d", done: false }])
            w.clearCompleted()
            compare(w.items.length, 2, "only the open tasks remain")
            compare(w.items[0].text, "b", "order preserved")
            compare(w.items[1].text, "d", "order preserved")
        }

        // ---- progress fraction math -------------------------------------
        function test_progress_fraction_and_zero_clamp() {
            var w = hTasks.item
            setItems([{ text: "a", done: true }, { text: "b", done: false },
                      { text: "c", done: false }, { text: "d", done: false }])
            compare(w.doneCount / w.items.length, 0.25, "fraction is doneCount/total")
            setItems([])
            compare(w.items.length, 0, "empty list: no divide-by-zero (guarded)")
            compare(w.doneCount, 0)
        }

        // ---- effAccent recolouring hook ----------------------------------
        // Every accented element (checkbox fill/border, progress bar, flash,
        // celebrate label, input focus ring, Add button) binds to effAccent, so
        // verifying effAccent tracks the per-widget accent preset covers them all.
        function test_effaccent_tracks_accent_preset() {
            var w = hTasks.item
            var base = String(w.effAccent).toLowerCase()
            compare(base, String(hTasks.theme.catProductivity).toLowerCase(),
                    "defaults to the productivity category accent")
            w.accentName = "teal"
            compare(String(w.effAccent).toLowerCase(),
                    String(hTasks.theme.accentPresets["teal"].a).toLowerCase(),
                    "per-widget accent recolours effAccent")
            w.accentName = ""   // restore
        }

        // ---- touch targets ----------------------------------------------
        function test_touch_cells_are_large_enough() {
            verify(hTasks.theme.touchTertiary >= 44,
                   "expanded checkbox/remove cells use touchTertiary (>=44px)")
        }

        // ---- BUG: scroll position resets on every revision bump ----------
        // (audit: ListView scroll resets to top after each add)
        function test_scroll_position_survives_add() {
            var w = hTasks.item
            var big = []
            for (var i = 0; i < 30; i++) big.push({ text: "task " + i, done: false })
            setItems(big)
            var lv = findListView(hTasks.item)
            verify(lv !== null, "found the ListView")
            tryVerify(function () { return lv.contentHeight > lv.height + 50 }, 2000,
                      "list is tall enough to scroll")
            lv.contentY = 150
            tryVerify(function () { return lv.contentY > 100 }, 1000, "scrolled down")
            w.add("appended")
            // The model is rebuilt as a fresh array on the revision bump, which
            // discards contentY. A well-behaved list keeps the user's position.
            verify(lv.contentY > 100,
                   "scroll position should survive an add (was reset to " + lv.contentY + ")")
        }
    }

    // ── Compact tile: taps fall through, list inert ──────────────────────
    TestCase {
        name: "TasksCompact"
        when: windowShown
        function init() {
            tryVerify(function () { return hCompact.ready }, 3000)
            var s = hCompact.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hCompact.storeCtl._touchSettings()
        }

        function test_compact_listview_is_not_interactive() {
            var w = hCompact.item
            hCompact.storeCtl.setSetting("test-instance",
                "items", [{ text: "a", done: false }, { text: "b", done: false }])
            compare(w.expanded, false, "compact instance is not expanded")
            var lv = root.findListView(hCompact.item)
            verify(lv !== null, "found the compact ListView")
            compare(lv.interactive, false,
                    "compact list is inert so a tap reaches the host tapMA and expands the tile")
        }
        function test_compact_status_is_the_only_hint() {
            var w = hCompact.item
            hCompact.storeCtl.setSetting("test-instance",
                "items", [{ text: "a", done: true }, { text: "b", done: false }])
            compare(w.status, "1/2", "compact tile still shows the count summary")
        }
    }

    // ── Per-sizeClass structure (W1 wave 2b) ────────────────────────────────
    // Fixed-size hosts at the real projected cell footprints. tasks declares no
    // 0.5x0.5, so there is no micro case.
    Item { width: 348; height: 819
        WidgetHarness { id: tTall; anchors.fill: parent; widgetFile: "TasksWidget.qml"; expanded: false } }
    Item { id: tWideWrap; width: 696; height: 409
        WidgetHarness { id: tWide; anchors.fill: parent; widgetFile: "TasksWidget.qml"; expanded: false } }
    // 1x3 portrait — the whole panel.
    Item { width: 696; height: 2459
        WidgetHarness { id: tBoard; anchors.fill: parent; widgetFile: "TasksWidget.qml"; expanded: false } }

    TestCase {
        name: "TasksSizes"
        when: windowShown

        function findAll(node, pred, acc) {
            acc = acc || []
            if (!node) return acc
            if (pred(node)) acc.push(node)
            var kids = node.children
            for (var i = 0; kids && i < kids.length; i++) findAll(kids[i], pred, acc)
            return acc
        }
        function seed(host) {
            host.storeCtl.setSetting(host.instanceId, "items", [
                { text: "Renew the domain", done: true },
                { text: "Send the invoice", done: false },
                { text: "Book the dentist", done: false },
                { text: "Water the plants", done: false }])
        }
        function rows(host) {
            return findAll(host.item, function (n) {
                return n.hasOwnProperty("modelData") && n.hasOwnProperty("index") }, [])
        }
        function listOf(host) {
            return findAll(host.item, function (n) {
                return n.hasOwnProperty("contentY") && n.hasOwnProperty("model") }, [])[0]
        }
        function field(host) {
            return findAll(host.item, function (n) {
                return n.hasOwnProperty("placeholderText") }, [])[0]
        }

        // The row AND its checkbox cell are real touch targets at every size.
        // The checkbox cell used to be 18px wide on a tile, in a 24px row.
        function test_checking_a_task_off_is_a_real_touch_target() {
            tryVerify(function () { return tTall.ready }, 3000)
            tryVerify(function () { return tWide.ready }, 3000)
            var hosts = [tTall, tWide]
            var classes = ["tall", "wide"]
            for (var i = 0; i < hosts.length; i++) {
                hosts[i].item.sizeClass = classes[i]
                seed(hosts[i])
                wait(32)
                var rr = rows(hosts[i])
                verify(rr.length > 0, classes[i] + ": rows render")
                var minT = hosts[i].theme.touchTertiary
                for (var j = 0; j < rr.length; j++) {
                    verify(rr[j].height >= minT,
                           classes[i] + " row " + j + " is >= touchTertiary (" + rr[j].height + ")")
                    // The checkbox cell is the first child: it holds the MouseArea.
                    var cell = rr[j].children[0]
                    verify(cell.width >= minT && cell.height >= minT,
                           classes[i] + " row " + j + " checkbox cell is >= touchTertiary ("
                           + cell.width + "x" + cell.height + ") — it was 18x24")
                }
            }
        }

        // The add field is a real target too (it was a fixed 40px on tiles).
        function test_the_add_field_is_a_real_touch_target() {
            tryVerify(function () { return tTall.ready }, 3000)
            tTall.item.sizeClass = "tall"
            seed(tTall)
            wait(32)
            var f = field(tTall)
            verify(f.height >= tTall.theme.touchTertiary,
                   "the add field is >= touchTertiary (" + f.height + ")")
        }

        // 1x3 — the whole panel is just MORE ROWS, not bigger ones.
        function test_the_full_panel_earns_rows_not_bulk() {
            tryVerify(function () { return tBoard.ready }, 3000)
            tryVerify(function () { return tTall.ready }, 3000)
            tTall.item.sizeClass = "tall"; seed(tTall)
            tBoard.item.sizeClass = "large"; seed(tBoard)
            wait(32)
            compare(tBoard.item.rowH, tTall.item.rowH,
                    "a 696x2459 panel uses the SAME row height as a 348x819 sliver")
            verify(listOf(tBoard).height > listOf(tTall).height * 2,
                   "…it just shows far more of them ("
                   + listOf(tBoard).height.toFixed(0) + " vs "
                   + listOf(tTall).height.toFixed(0) + "px of list)")
        }

        // wide — the controls move BESIDE the list.
        function test_wide_puts_the_controls_beside_the_list() {
            tryVerify(function () { return tWide.ready }, 3000)
            var t = tWide.item
            t.sizeClass = "tall"
            seed(tWide)
            wait(32)
            var outer = listOf(tWide).parent.parent
            compare(outer.columns, 1, "a tall box stacks the add row under the list")
            t.sizeClass = "wide"
            wait(32)
            compare(t.horiz, true, "wide is the horizontal shape")
            compare(outer.columns, 2, "wide puts the controls beside the list")
            t.sizeClass = "tall"
        }
    }
}
