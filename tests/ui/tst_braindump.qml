import QtQuick
import QtTest

// COVERS: schema:showTimes

// ─────────────────────────────────────────────────────────────────────────
// tst_braindump — ui/qml/widgets/BraindumpWidget.qml.
//
// What must hold: capture is one line and one key, the newest entry is the one
// you see, entries survive a store round-trip, and the list cannot grow the
// config without bound. The ordering assertion is not cosmetic — an entry that
// lands off-screen is an entry the user believes was lost.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 1000; height: 720

    WidgetHarness {
        id: h; x: 0; y: 0; width: 620; height: parent.height
        widgetFile: "BraindumpWidget.qml"; expanded: true
    }
    WidgetHarness {
        id: hc; x: 640; y: 0; width: 340; height: 380
        widgetFile: "BraindumpWidget.qml"; expanded: false
    }

    function clearSettings(harness) {
        var s = harness.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        harness.storeCtl._touchSettings()
    }
    function findAll(node, pred, acc) {
        acc = acc || []
        if (!node) return acc
        if (pred(node)) acc.push(node)
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) findAll(kids[i], pred, acc)
        return acc
    }
    // A round-trip must go through a doc that OWNS the settings bucket: the store
    // prunes settings whose id no tile claims (an orphan bucket is a leak), so a
    // harness instance with no tile is dropped on reload — correctly. Give the
    // document the tile a real config.toml would have, then reload it.
    function reloadWith(harness, doc, type) {
        doc.pages = [ { name: "Test", tiles: [ { id: "test-instance", type: type, size: "1x1" } ] } ]
        return harness.storeCtl.applyExternal(JSON.stringify(doc))
    }
    function fieldIn(w) {
        // The TextField is the one editable input in the tree.
        var f = root.findAll(w, function (n) {
            return n.hasOwnProperty("placeholderText") && n.hasOwnProperty("text")
        }, [])
        return f.length ? f[0] : null
    }

    // ── Capture ──────────────────────────────────────────────────────────
    TestCase {
        name: "BraindumpCapture"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); clearSettings(h) }

        function test_add_stores_text_and_a_timestamp() {
            var before = Date.now()
            h.item.add("call the dentist")
            var e = h.item.entries
            compare(e.length, 1)
            compare(e[0].text, "call the dentist")
            verify(e[0].at >= before && e[0].at <= Date.now(), "stamped with the time it arrived")
        }

        function test_add_trims_and_ignores_empty() {
            h.item.add("   spaced out   ")
            compare(h.item.entries.length, 1)
            compare(h.item.entries[0].text, "spaced out", "leading/trailing space is trimmed")
            h.item.add("")
            h.item.add("    ")
            h.item.add(null)
            compare(h.item.entries.length, 1, "blank captures are ignored, not stored as empty rows")
        }

        // Newest first: the thing you just typed must be the thing you can see.
        function test_newest_entry_is_first() {
            h.item.add("first")
            h.item.add("second")
            h.item.add("third")
            var e = h.item.entries
            compare(e.length, 3)
            compare(e[0].text, "third", "the newest capture leads the list")
            compare(e[1].text, "second")
            compare(e[2].text, "first")
        }

        function test_remove_takes_out_the_right_entry() {
            h.item.add("a"); h.item.add("b"); h.item.add("c")   // → c, b, a
            h.item.remove(1)
            var e = h.item.entries
            compare(e.length, 2)
            compare(e[0].text, "c"); compare(e[1].text, "a", "'b' is the one that went")
        }

        function test_remove_ignores_an_out_of_range_index() {
            h.item.add("only")
            h.item.remove(5); h.item.remove(-1)
            compare(h.item.entries.length, 1, "a stale index is ignored, not a crash or a wrong delete")
        }

        function test_clear_all_empties_the_list() {
            h.item.add("a"); h.item.add("b")
            h.item.clearAll()
            compare(h.item.entries.length, 0)
            compare(h.storeCtl.settingsFor("test-instance").entries.length, 0, "and it persisted")
        }

        // An unbounded array here would grow config.toml forever — this is the
        // widget you dump into without thinking.
        function test_list_is_capped_and_drops_the_oldest() {
            var w = h.item
            for (var i = 0; i < w.maxEntries + 10; i++) w.add("entry " + i)
            compare(w.entries.length, w.maxEntries, "the list is capped")
            compare(w.entries[0].text, "entry " + (w.maxEntries + 9), "newest kept")
            compare(w.entries[w.entries.length - 1].text, "entry 10", "the oldest were dropped")
        }
    }

    // ── Persistence ──────────────────────────────────────────────────────
    TestCase {
        name: "BraindumpPersistence"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); clearSettings(h) }

        function test_entries_survive_a_store_round_trip() {
            h.item.add("remember the milk")
            h.item.add("email Dana")
            var onDisk = JSON.parse(JSON.stringify(h.storeCtl._persistableData()))
            var saved = onDisk.settings["test-instance"]
            verify(saved !== undefined, "the instance reaches disk")
            compare(saved.entries.length, 2, "entries are persistable, not ephemeral")
            compare(saved.entries[0].text, "email Dana")
            verify(saved.entries[0].at > 0, "the timestamp is persisted too")
            // applyExternal() is the real reload path — the same one the hub and the
            // Manager push a document through — and it forces the doc back through
            // JSON, so this exercises the serialization config.toml actually uses.
            compare(root.reloadWith(h, onDisk, "braindump"), true, "the document reloads")
            var e = h.item.entries
            compare(e.length, 2, "the dump is still there after a reload")
            compare(e[0].text, "email Dana")
            compare(e[1].text, "remember the milk")
        }
    }

    // ── Timestamp rendering ──────────────────────────────────────────────
    TestCase {
        name: "BraindumpStamps"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); clearSettings(h) }

        function test_todays_stamp_is_just_a_time() {
            var now = new Date()
            compare(h.item.stampOf({ text: "x", at: now.getTime() }),
                    Qt.formatTime(now, "HH:mm"), "today → time only")
        }

        function test_an_older_stamp_carries_the_weekday() {
            var then = new Date(Date.now() - 3 * 86400000)
            compare(h.item.stampOf({ text: "x", at: then.getTime() }),
                    Qt.formatDateTime(then, "ddd HH:mm"), "older → weekday + time")
        }

        // A hand-edited config must not render "Invalid Date" next to real text.
        function test_a_missing_or_broken_stamp_renders_blank() {
            compare(h.item.stampOf({ text: "x" }), "", "no stamp → blank, not 'Invalid Date'")
            compare(h.item.stampOf({ text: "x", at: "nonsense" }), "")
            compare(h.item.stampOf(null), "")
        }

        function test_showTimes_hides_the_stamp_column() {
            h.item.add("a thought")
            compare(h.item.showTimes, true, "stamps show by default")
            var stamp = Qt.formatTime(new Date(), "HH:mm")
            var shown = root.findAll(h.item, function (n) {
                return n.hasOwnProperty("text") && n.text === stamp && n.hasOwnProperty("font")
            }, [])
            verify(shown.length > 0 && shown[0].visible, "the stamp is rendered")
            h.storeCtl.patchSettings("test-instance", { showTimes: false })
            compare(h.item.showTimes, false)
            verify(!shown[0].visible, "turning showTimes off actually hides it")
        }
    }

    // ── Real typing on the tile ──────────────────────────────────────────
    TestCase {
        name: "BraindumpTileInput"
        when: windowShown
        function init() { tryVerify(function () { return hc.ready }, 3000); clearSettings(hc) }

        // Capture has to work from the tile itself, with Enter — that IS the widget.
        function test_typing_and_pressing_enter_captures_from_the_tile() {
            var f = root.fieldIn(hc.item)
            verify(f !== null, "the tile carries the capture field")
            f.forceActiveFocus()
            keyClick(Qt.Key_B); keyClick(Qt.Key_U); keyClick(Qt.Key_Y)
            keyClick(Qt.Key_Return)
            compare(hc.item.entries.length, 1, "Enter commits the capture")
            compare(hc.item.entries[0].text, "buy")
            compare(f.text, "", "and the field is cleared, ready for the next thought")
            compare(hc.storeCtl.settingsFor("test-instance").entries[0].text, "buy", "persisted")
        }
    }
}
