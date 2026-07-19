import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: schema:text

// ─────────────────────────────────────────────────────────────────────────
// Comprehensive coverage for area "widget:notes" (ui/qml/widgets/NotesWidget.qml).
//
// Exercises: the `text` config option + reactivity, the debounce/flush save
// path, close/destroy semantics, external (Manager) update handling, the
// compact-preview placeholder, the char/word counter, per-widget chrome
// (title/accent/backdrop), cursor-follow on long notes, tap-fallthrough, and
// reset-to-defaults isolation.
//
// Several assertions here intentionally fail because they document REAL bugs
// flagged in the audit (save-on-close loss, external-overwrite, no cursor
// follow, whitespace placeholder, revision churn). Those failures are the
// point — do not "fix" the test to make them pass.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 480; height: 900

    // Expanded editor instance.
    WidgetHarness { id: hNotes;   anchors.fill: parent; widgetFile: "NotesWidget.qml"; expanded: true }
    // Compact-tile instance (preview + placeholder logic).
    WidgetHarness { id: hCompact; anchors.fill: parent; widgetFile: "NotesWidget.qml"; expanded: false }

    // A NotesWidget hosted in a Loader WE control, so a test can DESTROY the
    // widget item exactly the way Dashboard.closeExpanded() destroys the shared
    // overlay Loader item (active → false). The store lives OUTSIDE the Loader,
    // so it survives the destruction and can be inspected afterwards.
    Item {
        id: destroyHost
        anchors.fill: parent
        property alias theme: dTheme
        App.Theme { id: dTheme }
        App.DashboardStore { id: dStore }
        property bool hostActive: true
        Component.onCompleted: dStore.load("blank")
        Loader {
            id: dLoader
            anchors.fill: parent
            active: destroyHost.hostActive
            source: "../../ui/qml/widgets/NotesWidget.qml"
            onLoaded: {
                if (!item) return
                dStore.ensureSettings("dnote", {})
                item.instanceId = "dnote"
                item.store = dStore
                item.expanded = true
            }
        }
    }

    // ── Visual-tree helpers ──────────────────────────────────────────────────
    // Recurse over children AND a Flickable's contentItem (which is where its
    // declared children — e.g. the editor — actually live).
    // The `seen` set is a correctness requirement, not an optimisation: a
    // Control's `contentItem` is ALSO one of its `children`, so every
    // contentItem subtree is reachable by two paths. Without memoing, each such
    // subtree is re-walked once per path — 2^k for k nested contentItem-bearing
    // ancestors (Pane > ScrollView > Flickable > TextArea nests several here).
    // Two sibling copies of this bug reached 18.8 GB and 20 GB RSS and caused a
    // system-wide OOM on 2026-07-19. It also inflated collect() results, so any
    // count assertion below was measuring duplicates. Keep the set.
    function walk(node, fn) { _walkSeen(node, fn, new Set()) }
    function _walkSeen(node, fn, seen) {
        if (!node || seen.has(node)) return
        seen.add(node)
        fn(node)
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) _walkSeen(kids[i], fn, seen)
        if (node.contentItem && node.contentItem !== node) {
            var ck = node.contentItem.children
            for (var j = 0; ck && j < ck.length; j++) _walkSeen(ck[j], fn, seen)
        }
    }
    function findOne(node, test) {
        var found = null
        walk(node, function (n) { if (!found && test(n)) found = n })
        return found
    }
    function collect(node, test) {
        var out = []
        walk(node, function (n) { if (test(n)) out.push(n) })
        return out
    }
    // TextEdit has persistentSelection; Text does not.
    function findEditor(w) {
        return findOne(w, function (n) {
            return n.hasOwnProperty("persistentSelection") && n.hasOwnProperty("wrapMode")
        })
    }
    // Flickable has contentY + flicking.
    function findFlickable(w) {
        return findOne(w, function (n) {
            return n.hasOwnProperty("contentY") && n.hasOwnProperty("flicking")
        })
    }
    // All Text nodes (have elide; TextEdit does not).
    function texts(w) {
        return collect(w, function (n) {
            return n.hasOwnProperty("elide") && n.hasOwnProperty("text") && !n.hasOwnProperty("persistentSelection")
        })
    }
    function hasTextEqual(w, s) {
        return texts(w).some(function (t) { return t.text === s })
    }
    // MouseAreas have containsMouse + acceptedButtons.
    function mouseAreas(w) {
        return collect(w, function (n) {
            return n.hasOwnProperty("containsMouse") && n.hasOwnProperty("acceptedButtons")
        })
    }
    function clearStore(h) {
        var s = h.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        h.storeCtl._touchSettings()
    }

    // ── Config: the `text` option + reactivity ───────────────────────────────
    TestCase {
        name: "NotesConfig"
        when: windowShown
        function init() { tryVerify(function () { return hNotes.ready }, 3000); clearStore(hNotes) }

        function test_default_is_empty() {
            var w = hNotes.item
            compare(w.current, "", "a fresh note is empty")
            compare(w.title, "Quick Note", "default title")
            compare(w.iconName, "notes", "notes icon")
        }
        function test_text_config_honored() {
            var w = hNotes.item
            hNotes.storeCtl.patchSettings("test-instance", { text: "hello world" })
            compare(w.current, "hello world", "current reflects settings.text")
        }
        function test_current_reacts_to_setSetting() {
            var w = hNotes.item
            hNotes.storeCtl.setSetting("test-instance", "text", "first")
            compare(w.current, "first")
            hNotes.storeCtl.setSetting("test-instance", "text", "second")
            compare(w.current, "second", "current re-reads on revision bump")
        }
        function test_cfg_is_defensive_clone() {
            var w = hNotes.item
            hNotes.storeCtl.setSetting("test-instance", "text", "orig")
            var c = w.cfg
            c.text = "mutated"   // mutating the returned clone must not affect the store
            compare(hNotes.storeCtl.settingsFor("test-instance").text, "orig",
                    "cfg is a defensive JSON clone, not the live settings object")
        }
    }

    // ── Public save/flush API ────────────────────────────────────────────────
    TestCase {
        name: "NotesSaveApi"
        when: windowShown
        function init() { tryVerify(function () { return hNotes.ready }, 3000); clearStore(hNotes) }

        function test_save_roundtrip() {
            var w = hNotes.item
            w.save("remember the milk")
            compare(w.current, "remember the milk")
            w.save("")
            compare(w.current, "", "saving empty clears the note")
        }
        function test_flush_persists_pending_immediately() {
            var w = hNotes.item
            var ed = findEditor(w)
            verify(ed !== null, "found the TextEdit")
            ed.text = "typed but not idle yet"     // starts the 400ms debounce
            compare(w.current, "", "debounced write has NOT landed yet")
            w.flush()                                // simulate an explicit flush
            compare(w.current, "typed but not idle yet", "flush persists the pending text now")
        }
        function test_debounce_eventually_saves() {
            var w = hNotes.item
            var ed = findEditor(w)
            ed.text = "idle save"
            tryVerify(function () { return w.current === "idle save" }, 2000,
                      "the 400ms debounce eventually persists the text")
        }
    }

    // ── Close/destroy semantics (audit critical bug) ─────────────────────────
    // Reproduces Dashboard.closeExpanded(): the overlay Loader item is destroyed
    // outright — `expanded` never transitions true→false — so nothing relying on
    // onExpandedChanged runs. Any un-flushed (still-debouncing) text is lost.
    TestCase {
        name: "NotesCloseFlush"
        when: windowShown
        // Force a clean, freshly-loaded item for every destroy test: tear the
        // current one down, clear state, then reload. This makes the destroy
        // observable and independent of what the previous test left behind.
        function init() {
            destroyHost.hostActive = false
            tryVerify(function () { return dLoader.item === null }, 3000)
            var s = dStore.settingsFor("dnote")
            for (var k in s) delete s[k]
            dStore._touchSettings()
            destroyHost.hostActive = true
            tryVerify(function () { return dLoader.item !== null }, 3000)
        }

        function test_destroy_flushes_short_note() {
            var w = dLoader.item
            var ed = findEditor(w)
            ed.text = "buy milk"                 // typed within 400ms of "Done"
            destroyHost.hostActive = false       // closeExpanded → destroy the overlay item
            tryVerify(function () { return dLoader.item === null }, 2000, "widget item destroyed")
            compare(dStore.settingsFor("dnote").text, "buy milk",
                    "closing the overlay must persist the in-progress note")
        }
        function test_destroy_flushes_full_sentence() {
            var w = dLoader.item
            var ed = findEditor(w)
            ed.text = "pick up the dry cleaning and call the dentist"
            destroyHost.hostActive = false
            tryVerify(function () { return dLoader.item === null }, 2000)
            compare(dStore.settingsFor("dnote").text, "pick up the dry cleaning and call the dentist",
                    "a whole note typed with no pause survives a bottom-bar Done close")
        }
    }

    // ── External (Manager) updates while the editor is open (audit high bug) ──
    TestCase {
        name: "NotesExternalUpdate"
        when: windowShown
        function init() { tryVerify(function () { return hNotes.ready }, 3000); clearStore(hNotes) }

        // Re-open sync works via onExpandedChanged when expanded toggles.
        function test_reopen_syncs_editor() {
            var w = hNotes.item
            hNotes.storeCtl.setSetting("test-instance", "text", "stored")
            hNotes.expanded = false
            hNotes.expanded = true
            var ed = findEditor(w)
            compare(ed.text, "stored", "re-opening the editor loads the stored text")
        }
        function test_open_editor_resyncs_on_external_push() {
            var w = hNotes.item
            var ed = findEditor(w)
            ed.text = "aaa"                          // local edit breaks the text binding
            // Manager pushes a new value (applyExternal bumps revision).
            hNotes.storeCtl.settingsFor("test-instance").text = "server text"
            hNotes.storeCtl.revision++
            compare(ed.text, "server text",
                    "an open editor should re-sync to an external update (not keep stale local text)")
        }
        function test_pending_flush_does_not_clobber_external() {
            var w = hNotes.item
            var ed = findEditor(w)
            ed.text = "aaa"
            hNotes.storeCtl.settingsFor("test-instance").text = "server text"
            hNotes.storeCtl.revision++
            w.flush()                                // the still-pending local write lands
            compare(hNotes.storeCtl.settingsFor("test-instance").text, "server text",
                    "a stale local edit must not overwrite the Manager's pushed value")
        }
        // Compact preview DOES react to external revision bumps — this passes.
        function test_compact_reacts_to_external_bump() {
            var w = hCompact.item
            clearStore(hCompact)
            hCompact.storeCtl.setSetting("test-instance", "text", "first")
            compare(w.current, "first")
            hCompact.storeCtl.settingsFor("test-instance").text = "server text"
            hCompact.storeCtl.revision++
            compare(w.current, "server text", "compact preview reflects the external update")
        }
    }

    // ── Compact preview + placeholder + counter (audit low/medium bugs) ──────
    TestCase {
        name: "NotesPreview"
        when: windowShown
        function init() { tryVerify(function () { return hCompact.ready }, 3000); clearStore(hCompact) }

        function test_empty_shows_placeholder() {
            var w = hCompact.item
            verify(hasTextEqual(w, "Tap to jot a note…"), "empty note shows the compact placeholder")
        }
        function test_text_shows_in_preview() {
            var w = hCompact.item
            hCompact.storeCtl.setSetting("test-instance", "text", "groceries list")
            verify(hasTextEqual(w, "groceries list"), "preview renders the stored note")
        }
        function test_whitespace_only_shows_placeholder() {
            var w = hCompact.item
            hCompact.storeCtl.setSetting("test-instance", "text", "   ")
            verify(hasTextEqual(w, "Tap to jot a note…"),
                   "a whitespace-only note should still show the placeholder prompt")
        }
    }

    // ── Char/word counter (audit low bug) ────────────────────────────────────
    TestCase {
        name: "NotesCounter"
        when: windowShown
        function init() { tryVerify(function () { return hNotes.ready }, 3000); clearStore(hNotes) }
        // The counter Text contains the word "chars".
        function counter(w) {
            return findOne(w, function (n) {
                return n.hasOwnProperty("elide") && typeof n.text === "string" && n.text.indexOf("chars") >= 0
            })
        }

        function test_counter_reports_words() {
            var w = hNotes.item
            var ed = findEditor(w)
            ed.text = "one two three"
            var c = counter(w)
            verify(c !== null && c.visible, "counter is visible with content")
            compare(c.text, "13 chars · 3 words", "reports chars and words")
        }
        function test_counter_hidden_for_whitespace_only() {
            var w = hNotes.item
            var ed = findEditor(w)
            ed.text = "   "
            var c = counter(w)
            // A whitespace-only note has 0 words; the counter should not claim content.
            verify(!c || !c.visible,
                   "the counter should be hidden for a whitespace-only note (0 words)")
        }
    }

    // ── No-op typing should not churn the store (audit low bug) ──────────────
    TestCase {
        name: "NotesNoChurn"
        when: windowShown
        function init() { tryVerify(function () { return hNotes.ready }, 3000); clearStore(hNotes) }

        function test_type_and_delete_no_net_write() {
            var w = hNotes.item
            var ed = findEditor(w)
            hNotes.storeCtl.setSetting("test-instance", "text", "base")
            ed.text = "base"                 // sync editor to the saved base
            var rev0 = hNotes.storeCtl.revision
            ed.text = "basex"                // type a char
            ed.text = "base"                 // delete it — net unchanged
            w.flush()                        // land the debounced write
            compare(hNotes.storeCtl.settingsFor("test-instance").text, "base", "text unchanged")
            compare(hNotes.storeCtl.revision, rev0,
                    "a net no-op edit must not bump revision / re-persist / re-broadcast")
        }
    }

    // ── Cursor follow on long notes (audit medium bug) ───────────────────────
    TestCase {
        name: "NotesCursorFollow"
        when: windowShown
        function init() { tryVerify(function () { return hNotes.ready }, 3000); clearStore(hNotes) }

        function test_flickable_scrolls_to_caret() {
            var w = hNotes.item
            var ed = findEditor(w)
            var flick = findFlickable(w)
            verify(ed !== null && flick !== null, "found editor + flickable")
            var lines = ""
            for (var i = 0; i < 80; i++) lines += "line number " + i + "\n"
            ed.text = lines
            ed.cursorPosition = ed.text.length          // caret at the very end
            if (flick.contentHeight <= flick.height) {
                skip("viewport is tall enough that the caret never leaves it")
                return
            }
            var caretBottom = ed.cursorRectangle.y + ed.cursorRectangle.height
            verify(caretBottom - flick.contentY <= flick.height + 2,
                   "the Flickable should scroll so the caret stays visible (caretBottom=" +
                   caretBottom + " contentY=" + flick.contentY + " h=" + flick.height + ")")
        }

        // Environment note: the on-screen-keyboard lift in main.qml relies on
        // Qt.inputMethod.cursorRectangle, which is only meaningful with a real
        // InputPanel + main.qml scene — not reproducible in this isolated harness.
        function test_onscreen_keyboard_lift_env() {
            skip("requires main.qml InputPanel scene; not exercisable in the widget harness")
        }
    }

    // ── Per-widget chrome: title / accent / backdrop (audit testCases) ───────
    TestCase {
        name: "NotesChrome"
        when: windowShown
        function init() { tryVerify(function () { return hNotes.ready }, 3000); clearStore(hNotes) }

        function test_custom_title_overrides_default() {
            var w = hNotes.item
            w.titleOverride = "Groceries"        // Dashboard binds this from settings.title
            verify(hasTextEqual(w, "Groceries"), "header shows the custom title")
            verify(!hasTextEqual(w, "Quick Note"), "the default title is replaced")
            w.titleOverride = ""                 // reset
        }
        function test_accent_preset_honored() {
            var w = hNotes.item
            compare(String(w.effAccent), String(w.accentColor),
                    "no override → the widget's category accent (catInfo)")
            w.accentName = "red"
            compare(String(w.effAccent).toLowerCase(), String(hNotes.theme.accentPresets["red"].a).toLowerCase(),
                    "a per-widget accent preset overrides the category accent")
            w.accentName = ""
        }
        function test_card_backdrop_honored() {
            var w = hNotes.item
            compare(w.cardBackdrop, "none", "default is no backdrop")
            w.cardBackdrop = "aurora"
            compare(w.cardBackdrop, "aurora", "per-widget card backdrop is applied")
            var layer = findOne(w, function (n) {
                return n.hasOwnProperty("style") && n.hasOwnProperty("running") && n.hasOwnProperty("visible")
            })
            verify(layer !== null && layer.style === "aurora", "BackdropLayer picks up the backdrop style")
            w.cardBackdrop = "none"
        }
    }

    // ── Tap fallthrough on the compact tile (audit testCase) ─────────────────
    TestCase {
        name: "NotesTapFallthrough"
        when: windowShown
        function init() { tryVerify(function () { return hCompact.ready }, 3000); clearStore(hCompact) }

        function test_no_mousearea_swallows_taps() {
            var w = hCompact.item
            var mas = mouseAreas(w)
            // The widget must not host a tap-eating MouseArea; the only chrome
            // MouseArea is a hover ring with acceptedButtons: Qt.NoButton, so
            // taps fall through to the Dashboard's tapMA to expand the tile.
            for (var i = 0; i < mas.length; i++)
                compare(mas[i].acceptedButtons, Qt.NoButton,
                        "compact notes tile has no tap-swallowing MouseArea")
        }
    }

    // ── Reset to defaults is isolated per instance (audit testCase) ──────────
    TestCase {
        name: "NotesReset"
        when: windowShown
        function init() { tryVerify(function () { return hNotes.ready }, 3000); clearStore(hNotes) }

        function test_reset_clears_text_without_leaking() {
            var st = hNotes.storeCtl
            st.setSetting("test-instance", "text", "abc")
            st.setSetting("other-note", "text", "keep me")
            st.resetSettings("test-instance", { text: "" })
            compare(st.settingsFor("test-instance").text, "", "reset clears the note to empty")
            compare(st.settingsFor("other-note").text, "keep me",
                    "reset does not leak/clear another instance's note")
        }
    }

    // ── Per-sizeClass structure (W1 wave 2b) ────────────────────────────────
    // Fixed-size hosts at the real projected cell footprints.
    Item { width: 348; height: 409
        WidgetHarness { id: qMicro; anchors.fill: parent; widgetFile: "NotesWidget.qml"; expanded: false } }
    Item { width: 696; height: 819
        WidgetHarness { id: qBase; anchors.fill: parent; widgetFile: "NotesWidget.qml"; expanded: false } }
    // 1x3 portrait — the whole panel.
    Item { width: 696; height: 2459
        WidgetHarness { id: qBoard; anchors.fill: parent; widgetFile: "NotesWidget.qml"; expanded: false } }

    TestCase {
        name: "NotesSizes"
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
            host.storeCtl.setSetting(host.instanceId, "text",
                "Pick up the dry cleaning before six, and ask Ana whether the "
                + "invoice for March ever went out. Also: the boiler service is due.")
        }
        // Every Text has a wrapMode property (the chrome header's title matches a
        // naive predicate), so identify the preview by the note it is showing.
        function preview(host) {
            return findAll(host.item, function (n) {
                return n.hasOwnProperty("wrapMode") && n.hasOwnProperty("elide")
                       && n.visible && String(n.text).indexOf("Pick up the dry") === 0 }, [])[0]
        }

        // 0.5x0.5 — the note IS the tile; 36px of chrome is a line you cannot spare.
        function test_micro_drops_the_header_for_a_line_of_note() {
            tryVerify(function () { return qMicro.ready }, 3000)
            var q = qMicro.item
            q.sizeClass = "compact"
            seed(qMicro)
            wait(32)
            compare(q.micro, true, "a 348x409 compact box is the micro tile")
            compare(q.showHeader, false, "micro drops the chrome header")
            verify(preview(qMicro) !== null, "the note still renders")
        }

        // The preview is sized off the BOX, not off `expanded` — the wave-2b bug.
        function test_the_preview_scales_with_the_tile() {
            tryVerify(function () { return qBase.ready }, 3000)
            tryVerify(function () { return qMicro.ready }, 3000)
            qMicro.item.sizeClass = "compact"; seed(qMicro)
            var q = qBase.item
            q.sizeClass = "compact"
            seed(qBase)
            wait(32)
            verify(q.previewPx > 13,
                   "a 696x819 tile reads past the old flat 13px (" + q.previewPx.toFixed(0) + ")")
            verify(q.previewPx > qMicro.item.previewPx,
                   "…and bigger than a 348x409 tile's (" + q.previewPx.toFixed(0)
                   + " vs " + qMicro.item.previewPx.toFixed(0) + ")")
        }

        // 1x3 earns more LINES, not bigger type: a note is one body of text.
        function test_the_full_panel_earns_lines_not_bigger_type() {
            tryVerify(function () { return qBoard.ready }, 3000)
            tryVerify(function () { return qBase.ready }, 3000)
            qBase.item.sizeClass = "compact"; seed(qBase)
            var q = qBoard.item
            q.sizeClass = "large"
            seed(qBoard)
            wait(32)
            compare(q.previewPx, qBase.item.previewPx,
                    "a 696x2459 panel uses the SAME type size as a 696x819 tile — "
                    + "the same column width carries the same line length")
            verify(preview(qBoard).height > preview(qBase).height * 2,
                   "…it just has room for far more lines")
        }
    }
}
