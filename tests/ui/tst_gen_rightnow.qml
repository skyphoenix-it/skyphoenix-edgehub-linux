import QtQuick
import QtTest

// ─────────────────────────────────────────────────────────────────────────
// Comprehensive coverage for widget:rightnow (ui/qml/widgets/RightNowWidget.qml)
//
// Drives config through the store (setSetting / patchSettings) exactly the way
// the Manager/Dashboard do, and asserts on the widget's derived state and its
// rendered content. Two harnesses are used because a couple of behaviours only
// exist in one mode: the expanded editor (TextField, Save/Done pills, the
// "finished today" label) and the compact hero display.
//
// Some assertions intentionally encode the DESIGN CONTRACT / INTENDED behaviour
// and therefore fail against the current code — those pin the audit's bugs
// (frozen todayKey, dead pluralization ternary, un-accented hero text, Done!
// discarding unsaved edits). Test-side mistakes are fixed; genuine code defects
// are left failing on purpose.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 480; height: 900

    WidgetHarness { id: hRN;      anchors.fill: parent; widgetFile: "RightNowWidget.qml"; expanded: true  }
    WidgetHarness { id: hCompact; anchors.fill: parent; widgetFile: "RightNowWidget.qml"; expanded: false }

    // ── traversal helpers (mirrors tst_touch_targets / tst_clicks) ──────────
    function findAll(node, pred, acc) {
        if (!node) return acc
        if (pred(node)) acc.push(node)
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) findAll(kids[i], pred, acc)
        return acc
    }
    // Plain Text items expose `elide`; TextField/TextInput/TextArea do not.
    function isText(n) { return n.hasOwnProperty("elide") && n.hasOwnProperty("text") && n.hasOwnProperty("wrapMode") }
    function texts(node) { return findAll(node, isText, []) }
    function textWith(node, needle) {
        var ts = texts(node)
        for (var i = 0; i < ts.length; i++)
            if (typeof ts[i].text === "string" && ts[i].text.indexOf(needle) !== -1) return ts[i]
        return null
    }
    function textEq(node, exact) {
        var ts = texts(node)
        for (var i = 0; i < ts.length; i++)
            if (ts[i].text === exact) return ts[i]
        return null
    }
    function findByProp(node, prop, val) {
        if (!node) return null
        if (node[prop] !== undefined && node[prop] === val) return node
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) {
            var r = findByProp(kids[i], prop, val); if (r) return r
        }
        return null
    }
    function findTextField(node) {
        if (!node) return null
        if (node.hasOwnProperty("placeholderText") && node.hasOwnProperty("text")) return node
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) {
            var r = findTextField(kids[i]); if (r) return r
        }
        return null
    }
    // Collect QtQuick animation objects (have both `easing` and `property`).
    function collectAnims(node, acc, seen) {
        if (!node) return acc
        for (var s = 0; s < seen.length; s++) if (seen[s] === node) return acc
        seen.push(node)
        if (node.hasOwnProperty && node.hasOwnProperty("easing") && node.hasOwnProperty("property"))
            acc.push(node)
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) collectAnims(kids[i], acc, seen)
        try { var d = node.data; for (var j = 0; d && j < d.length; j++) collectAnims(d[j], acc, seen) } catch (e) {}
        try { var a = node.animations; for (var k = 0; a && k < a.length; k++) collectAnims(a[k], acc, seen) } catch (e2) {}
        return acc
    }

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function keyOf(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
    function clear(h) {
        var s = h.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        h.storeCtl._touchSettings()
    }

    // ── Expanded editor: config, logic, reactivity ─────────────────────────
    TestCase {
        name: "RightNowExpanded"
        when: windowShown
        function initTestCase() { tryVerify(function () { return hRN.ready }, 3000) }
        function init() { clear(hRN); hRN.item.celebrateMsg = "" }
        function set(k, v) { hRN.storeCtl.setSetting("test-instance", k, v) }
        function patch(o) { hRN.storeCtl.patchSettings("test-instance", o) }
        function cfg() { return hRN.storeCtl.settingsFor("test-instance") }

        // setText persists and w.current tracks store.revision bumps.
        function test_setText_persists_and_reactive() {
            var w = hRN.item
            w.setText("Finish the report")
            compare(cfg().text, "Finish the report", "setText writes the config")
            compare(w.current, "Finish the report", "current reflects the saved value")
            // External write (as the Manager would do) must flow through via revision.
            patch({ text: "External focus" })
            compare(w.current, "External focus", "current reacts to an external setSetting")
        }

        // finish() counts a win, clears the text and fires the celebration.
        function test_finish_counts_clears_celebrates() {
            var w = hRN.item
            set("text", "Ship the build")
            compare(w.finishedToday, 0, "starts at 0")
            w.finish()
            compare(w.finishedToday, 1, "finishing increments today's counter")
            compare(w.current, "", "the focus is cleared after finishing")
            compare(cfg().day, w.todayKey, "the day bucket is stamped with today")
            verify(w.celebrateMsg.length > 0, "a celebration message is shown")
        }

        // finish() is a no-op when there is no real focus (empty / whitespace).
        function test_finish_noop_when_empty_or_whitespace() {
            var w = hRN.item
            w.finish()
            compare(w.finishedToday, 0, "empty focus: nothing counted")
            compare(w.celebrateMsg, "", "empty focus: no celebration")
            set("text", "   ")
            w.finish()
            compare(w.finishedToday, 0, "whitespace-only focus: nothing counted")
            compare(w.celebrateMsg, "", "whitespace-only focus: no celebration")
        }

        // Day-comparison rollover: a stale bucket from another calendar day reads 0.
        function test_counter_resets_for_a_different_stored_day() {
            var w = hRN.item
            patch({ day: "2000-01-01", finishedToday: 7 })
            compare(w.finishedToday, 0, "a bucket from another day does not count as today")
            patch({ day: w.todayKey, finishedToday: 4 })
            compare(w.finishedToday, 4, "today's bucket is preserved")
        }

        // BUG (frozen todayKey): after midnight, with the widget still alive, the
        // 'today' bucket must reset. todayKey is a plain, non-reactive property set
        // once at load, so a widget created 'yesterday' keeps a stale key. We
        // emulate that stale-at-load state and assert the count resets for the real
        // current day — a correct widget would recompute todayKey and read 0.
        function test_frozen_todayKey_never_rolls_over_midnight() {
            var w = hRN.item
            var yesterday = keyOf(new Date(Date.now() - 86400000))
            w.todayKey = yesterday                       // widget was loaded 'yesterday'
            patch({ day: yesterday, finishedToday: 3 })  // 3 finished yesterday
            // It is now really a new day; the count for 'today' should be 0.
            compare(w.finishedToday, 0,
                    "count must reset on the new calendar day (frozen todayKey stays " + w.todayKey + ")")
            w.todayKey = keyOf(new Date())               // restore for later tests
        }

        // BUG (dead pluralization ternary): the '✓ N finished today' label uses a
        // ternary whose branches are identical, so 1 vs N never differ in wording.
        function test_finished_label_pluralizes_for_one_vs_many() {
            var w = hRN.item
            patch({ day: w.todayKey, finishedToday: 1 })
            var one = textWith(w, "finished today")
            verify(one !== null, "found the finished-today label")
            var s1 = one.text.replace(/[0-9✓\s]/g, "")   // strip count + tick + spaces
            patch({ day: w.todayKey, finishedToday: 3 })
            var many = textWith(w, "finished today")
            var s3 = many.text.replace(/[0-9✓\s]/g, "")
            verify(s1 !== s3, "singular and plural wording must differ (1='" + one.text + "' N='" + many.text + "')")
        }

        // A custom title from config is shown in the expanded header.
        function test_custom_title_shown_in_header() {
            var w = hRN.item
            w.titleOverride = "My One Thing"             // Dashboard injects this from cfg.title
            var t = textEq(w, "My One Thing")
            verify(t !== null, "the expanded header shows the custom title")
            w.titleOverride = ""
        }

        // An external write updates the (unfocused) TextField, not just w.current.
        function test_external_write_updates_unfocused_field() {
            var w = hRN.item
            var field = findTextField(w)
            verify(field !== null, "found the editor field")
            field.focus = false                          // a prior test may have focused it
            verify(!field.activeFocus, "field is not focused")
            patch({ text: "From the Manager" })
            compare(w.current, "From the Manager", "current updated")
            compare(field.text, "From the Manager", "the unfocused field resynced to the new value")
        }

        // A single Save should be exactly one store write (one revision bump).
        // Audit bug: Save also blurs the field (onEditingFinished) → two writes.
        function test_single_save_is_one_write() {
            var w = hRN.item
            var field = findTextField(w)
            var save = findByProp(w, "label", "Save")
            verify(save !== null, "found the Save pill")
            mouseClick(field)
            field.text = "Save exactly once"
            var before = hRN.storeCtl.revision
            mouseClick(save)
            var delta = hRN.storeCtl.revision - before
            compare(w.current, "Save exactly once", "the value is saved")
            compare(delta, 1, "one Save = one revision bump (got " + delta + ")")
        }

        // BUG (Done! discards unsaved edits): Done! completes the previously-saved
        // focus (w.current) while any text typed but not yet saved is thrown away.
        function test_done_operates_on_visible_text_not_stale_saved() {
            var w = hRN.item
            // Original assertion (w.current === field.text with no Done! click) was
            // self-contradictory with its own prior compare; drive Done! and assert the
            // real contract: it completes the visible/typed focus, not the saved value.
            var field = findTextField(w)
            var done = findByProp(w, "label", "Done!")
            verify(done !== null, "found the Done pill")
            mouseClick(field)                            // focus so the resync won't overwrite
            field.text = "Focus B (unsaved)"             // user edits without pressing Save
            compare(w.current, "", "nothing has been saved yet")
            mouseClick(done)                             // complete the visible focus
            compare(w.finishedToday, 1,
                    "Done! counted the visible focus, not the empty saved value")
            compare(w.current, "", "the focus is cleared after finishing")
        }
    }

    // ── Compact hero display: accent, placeholder, whitespace, tap handling ──
    TestCase {
        name: "RightNowCompact"
        when: windowShown
        function initTestCase() { tryVerify(function () { return hCompact.ready }, 3000) }
        function init() { clear(hCompact); hCompact.item.accentName = "" }
        function set(k, v) { hCompact.storeCtl.setSetting("test-instance", k, v) }

        // Placeholder prompt when no focus is set.
        function test_placeholder_when_no_focus() {
            var w = hCompact.item
            var t = textEq(w, "Tap to set your one focus")
            verify(t !== null, "placeholder prompt is shown when empty")
            verify(t.visible, "placeholder is visible")
        }

        // BUG (hero text ignores per-instance accent): the most prominent content
        // stays theme.textPrimary even when the instance accent is set.
        function test_hero_text_honours_accent() {
            var w = hCompact.item
            w.accentName = "red"
            set("text", "Recolour me")
            var hero = textEq(w, "Recolour me")
            verify(hero !== null, "found the hero focus text")
            compare(String(w.effAccent).toLowerCase(), String(hCompact.theme.accentPresets["red"].a).toLowerCase(),
                    "effAccent resolved to red")
            compare(String(hero.color).toLowerCase(), String(w.effAccent).toLowerCase(),
                    "the hero focus text should adopt the per-instance accent (is " + hero.color + ")")
        }

        // Whitespace-only text should read as 'no focus' (placeholder), matching the
        // trim() logic Done!/finish() already use. Currently the raw whitespace is
        // shown as bold content instead.
        function test_whitespace_reads_as_no_focus() {
            var w = hCompact.item
            set("text", "     ")
            var placeholder = textEq(w, "Tap to set your one focus")
            verify(placeholder !== null && placeholder.visible,
                   "whitespace-only focus should fall back to the placeholder")
        }

        // No full-tile MouseArea should swallow the tap that opens the editor (the
        // tile host handles the tap). The only widget-fill MouseArea is the chrome
        // hover ring, which accepts Qt.NoButton.
        function test_no_full_tile_mousearea_swallows_taps() {
            var w = hCompact.item
            var areas = findAll(w, function (n) {
                return n.hasOwnProperty("pressed") && n.hasOwnProperty("containsMouse")
            }, [])
            for (var i = 0; i < areas.length; i++) {
                var a = areas[i]
                var fillsTile = a.width >= w.width * 0.9 && a.height >= w.height * 0.9
                if (fillsTile)
                    compare(a.acceptedButtons, Qt.NoButton,
                            "a tile-filling MouseArea must not accept taps (would swallow the open gesture)")
            }
            verify(true, "checked " + areas.length + " mouse areas")
        }

        // Celebration honours reduceMotion: the scale pop drops the OutBack overshoot
        // for a linear ease.
        function test_celebration_honours_reduce_motion() {
            var w = hCompact.item
            var anims = collectAnims(w, [], [])
            var scaleAnim = null
            for (var i = 0; i < anims.length; i++)
                if (anims[i].property === "scale") { scaleAnim = anims[i]; break }
            verify(scaleAnim !== null, "found the celebration scale animation")
            hCompact.theme.reduceMotion = false
            compare(scaleAnim.easing.type, Easing.OutBack, "full motion uses OutBack overshoot")
            hCompact.theme.reduceMotion = true
            compare(scaleAnim.easing.type, Easing.Linear, "reduced motion uses a linear ease")
            hCompact.theme.reduceMotion = false
        }
    }
}
