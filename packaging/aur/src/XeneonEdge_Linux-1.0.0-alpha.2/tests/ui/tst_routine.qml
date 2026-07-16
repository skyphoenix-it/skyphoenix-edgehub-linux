import QtQuick
import QtTest

// COVERS: schema:steps

// ─────────────────────────────────────────────────────────────────────────
// tst_routine — ui/qml/widgets/RoutineWidget.qml.
//
// Two requirements, both asserted rather than reviewed:
//   1. It resets each day. Yesterday's ticks must not read as today's, and the
//      reset must need no timer (it is a read-time decision, so a device that was
//      asleep at midnight still wakes up to a clean list).
//   2. It does not punish. The "no shaming" rule is enforced STRUCTURALLY: the
//      widget must persist no cross-day state at all, so there is nothing a bad
//      day can decrement. That is a stronger, testable claim than "we picked calm
//      colours" — so the test asserts the absence of streak-shaped keys on disk,
//      not just the absence of red.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 1000; height: 720

    WidgetHarness {
        id: h; x: 0; y: 0; width: 620; height: parent.height
        widgetFile: "RoutineWidget.qml"; expanded: true
    }
    WidgetHarness {
        id: hc; x: 640; y: 0; width: 340; height: 420
        widgetFile: "RoutineWidget.qml"; expanded: false
    }

    function clearSettings(harness) {
        var s = harness.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        harness.storeCtl._touchSettings()
    }
    function todayKey() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }
    // A round-trip must go through a doc that OWNS the settings bucket: the store
    // prunes settings whose id no tile claims (an orphan bucket is a leak), so a
    // harness instance with no tile is dropped on reload — correctly. Give the
    // document the tile a real config.toml would have, then reload it.
    function reloadWith(harness, doc, type) {
        doc.pages = [ { name: "Test", tiles: [ { id: "test-instance", type: type, size: "1x1" } ] } ]
        return harness.storeCtl.applyExternal(JSON.stringify(doc))
    }
    function findAll(node, pred, acc) {
        acc = acc || []
        if (!node) return acc
        if (pred(node)) acc.push(node)
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) findAll(kids[i], pred, acc)
        return acc
    }

    // ── Steps ────────────────────────────────────────────────────────────
    TestCase {
        name: "RoutineSteps"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); clearSettings(h) }

        function test_steps_parse_one_per_line_in_order() {
            h.storeCtl.patchSettings("test-instance", { steps: "Meds\nBrush teeth\nPack bag" })
            compare(h.item.steps, "Meds\nBrush teeth\nPack bag",
                    "the steps setting is read back off the store")
            var s = h.item.stepList
            compare(s.length, 3)
            compare(s[0], "Meds"); compare(s[1], "Brush teeth"); compare(s[2], "Pack bag")
        }

        function test_blank_lines_and_padding_are_ignored() {
            h.storeCtl.patchSettings("test-instance", { steps: "\n  Meds  \n\n\nPack bag\n  \n" })
            var s = h.item.stepList
            compare(s.length, 2, "blank lines never become empty steps")
            compare(s[0], "Meds"); compare(s[1], "Pack bag")
        }

        function test_no_steps_means_no_progress_and_not_allDone() {
            h.storeCtl.patchSettings("test-instance", { steps: "" })
            compare(h.item.stepList.length, 0)
            compare(h.item.doneCount, 0)
            compare(h.item.allDone, false, "an empty routine is not 'all done'")
        }
    }

    // ── Ticking ──────────────────────────────────────────────────────────
    TestCase {
        name: "RoutineTicking"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); clearSettings(h) }

        function test_toggle_marks_and_persists_with_todays_day() {
            h.storeCtl.patchSettings("test-instance", { steps: "Meds\nPack bag" })
            h.item.toggle("Meds")
            compare(h.item.isDone("Meds"), true)
            compare(h.item.isDone("Pack bag"), false)
            compare(h.item.doneCount, 1)
            var saved = h.storeCtl.settingsFor("test-instance")
            compare(saved.day, root.todayKey(), "the day is stamped")
            compare(saved.done.length, 1); compare(saved.done[0], "Meds")
        }

        function test_toggle_is_reversible() {
            h.storeCtl.patchSettings("test-instance", { steps: "Meds" })
            h.item.toggle("Meds"); compare(h.item.isDone("Meds"), true)
            h.item.toggle("Meds"); compare(h.item.isDone("Meds"), false, "un-ticking works")
            compare(h.item.doneCount, 0)
        }

        function test_allDone_when_every_step_is_ticked() {
            h.storeCtl.patchSettings("test-instance", { steps: "A\nB" })
            h.item.toggle("A")
            compare(h.item.allDone, false)
            h.item.toggle("B")
            compare(h.item.allDone, true)
            compare(h.item.doneCount, 2)
        }

        function test_ticks_survive_a_store_round_trip() {
            h.storeCtl.patchSettings("test-instance", { steps: "Meds\nPack bag" })
            h.item.toggle("Meds")
            var onDisk = JSON.parse(JSON.stringify(h.storeCtl._persistableData()))
            compare(onDisk.settings["test-instance"].done[0], "Meds", "persistable, not ephemeral")
            // applyExternal() is the real reload path — the same one the hub and the
            // Manager push a document through — and it forces the doc back through
            // JSON, so this exercises the serialization config.toml actually uses.
            compare(root.reloadWith(h, onDisk, "routine"), true, "the document reloads")
            compare(h.item.isDone("Meds"), true, "still ticked after a reload")
        }

        // Identity is the step text, not the index — inserting a line above must
        // not silently move a tick onto a different step.
        function test_ticks_survive_inserting_a_step_above() {
            h.storeCtl.patchSettings("test-instance", { steps: "Pack bag" })
            h.item.toggle("Pack bag")
            h.storeCtl.patchSettings("test-instance", { steps: "Meds\nPack bag" })
            compare(h.item.stepList[0], "Meds")
            compare(h.item.isDone("Meds"), false, "the newly inserted step is NOT ticked")
            compare(h.item.isDone("Pack bag"), true, "the originally ticked step still is")
            compare(h.item.doneCount, 1)
        }
    }

    // ── The daily reset ──────────────────────────────────────────────────
    TestCase {
        name: "RoutineReset"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); clearSettings(h) }

        function test_a_previous_days_ticks_do_not_count_today() {
            h.storeCtl.patchSettings("test-instance",
                { steps: "Meds\nPack bag", day: "2020-01-01", done: ["Meds", "Pack bag"] })
            var w = h.item
            compare(w.doneToday.length, 0, "yesterday's ticks read as nothing")
            compare(w.isDone("Meds"), false)
            compare(w.doneCount, 0)
            compare(w.allDone, false, "the day starts clean, not finished")
        }

        // No timer, no midnight write: the rollover is decided when read, so a
        // device asleep at midnight still wakes to a clean list.
        function test_the_reset_needs_no_timer_and_writes_nothing() {
            h.storeCtl.patchSettings("test-instance",
                { steps: "Meds", day: "2020-01-01", done: ["Meds"] })
            compare(h.item.isDone("Meds"), false, "already reset on read alone")
            var saved = h.storeCtl.settingsFor("test-instance")
            compare(saved.day, "2020-01-01", "reading did not rewrite the stored day…")
            compare(saved.done.length, 1, "…nor the stored list")
        }

        function test_ticking_after_a_rollover_restamps_the_day() {
            h.storeCtl.patchSettings("test-instance",
                { steps: "Meds\nPack bag", day: "2020-01-01", done: ["Meds", "Pack bag"] })
            h.item.toggle("Meds")
            var saved = h.storeCtl.settingsFor("test-instance")
            compare(saved.day, root.todayKey(), "the day is re-stamped")
            compare(saved.done.length, 1, "yesterday's list is replaced, not appended to")
            compare(saved.done[0], "Meds")
            compare(h.item.doneCount, 1, "and only today's tick counts")
        }
    }

    // ── No shaming ───────────────────────────────────────────────────────
    TestCase {
        name: "RoutineDoesNotPunish"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); clearSettings(h) }

        // The structural guarantee. If someone adds a streak later, this fails.
        function test_nothing_is_remembered_across_days() {
            h.storeCtl.patchSettings("test-instance", { steps: "A\nB" })
            h.item.toggle("A"); h.item.toggle("B")
            compare(h.item.allDone, true)
            var saved = JSON.parse(JSON.stringify(h.storeCtl._persistableData()))
                            .settings["test-instance"]
            // Only today's ticks + the day stamp + config may be stored.
            var allowed = ["steps", "day", "done"]
            for (var k in saved)
                verify(allowed.indexOf(k) >= 0,
                       "routine persists no '" + k + "' — nothing to lose by skipping a day")
            verify(saved.streak === undefined, "no streak is kept")
            verify(saved.bestStreak === undefined, "no personal best to fall short of")
            verify(saved.history === undefined, "no history of bad days")
            verify(saved.lastCompletedDay === undefined, "no record of when you last managed it")
        }

        // A skipped day must cost nothing: state after a gap is identical to state
        // after a fresh start.
        function test_a_skipped_day_costs_nothing() {
            h.storeCtl.patchSettings("test-instance",
                { steps: "A\nB", day: "2019-05-05", done: ["A", "B"] })
            var afterGap = { done: h.item.doneCount, all: h.item.allDone }
            clearSettings(h)
            h.storeCtl.patchSettings("test-instance", { steps: "A\nB" })
            compare(afterGap.done, h.item.doneCount,
                    "a 5-year gap leaves you exactly where a brand-new routine does")
            compare(afterGap.all, h.item.allDone)
        }

        // An unticked step is a normal thing you might do — not an error.
        function test_an_unticked_step_is_not_rendered_as_an_error() {
            h.storeCtl.patchSettings("test-instance", { steps: "Meds\nPack bag" })
            h.item.toggle("Meds")
            var labels = root.findAll(h.item, function (n) {
                return n.hasOwnProperty("text") && n.hasOwnProperty("color")
                       && (n.text === "Meds" || n.text === "Pack bag")
            }, [])
            verify(labels.length >= 2, "both step labels are rendered")
            for (var i = 0; i < labels.length; i++) {
                var c = String(labels[i].color)
                verify(c !== String(h.theme.error), labels[i].text + " is not error-coloured")
                verify(c !== String(h.theme.warning), labels[i].text + " is not warning-coloured")
            }
            var undone = null
            for (var j = 0; j < labels.length; j++) if (labels[j].text === "Pack bag") undone = labels[j]
            verify(undone !== null)
            compare(String(undone.color), String(h.theme.textPrimary),
                    "an undone step is just normal text")
        }

        // The visible progress copy must never scold.
        function test_progress_copy_states_a_fact_and_nothing_more() {
            h.storeCtl.patchSettings("test-instance", { steps: "A\nB\nC" })
            h.item.toggle("A")
            var texts = root.findAll(h.item, function (n) {
                return n.hasOwnProperty("text") && n.visible && String(n.text).length > 0
            }, []).map(function (n) { return String(n.text).toLowerCase() }).join(" | ")
            compare(texts.indexOf("1 of 3") >= 0, true, "it says where you are")
            var banned = ["missed", "failed", "fail", "behind", "streak", "lost",
                          "don't break", "overdue", "you should", "again!"]
            for (var i = 0; i < banned.length; i++)
                verify(texts.indexOf(banned[i]) < 0, "never says '" + banned[i] + "'")
        }
    }

    // ── Real input on the tile ───────────────────────────────────────────
    TestCase {
        name: "RoutineTileInput"
        when: windowShown
        function init() { tryVerify(function () { return hc.ready }, 3000); clearSettings(hc) }

        function test_tapping_a_row_ticks_it_and_persists() {
            hc.storeCtl.patchSettings("test-instance", { steps: "Meds\nPack bag" })
            wait(32)
            var rows = root.findAll(hc.item, function (n) {
                return n.hasOwnProperty("done") && n.hasOwnProperty("modelData")
            }, [])
            verify(rows.length >= 1, "step rows are rendered on the tile (" + rows.length + ")")
            mouseClick(rows[0])
            compare(hc.item.isDone("Meds"), true, "a tap on the row ticks the step")
            compare(hc.storeCtl.settingsFor("test-instance").done[0], "Meds", "and it persisted")
        }
    }
}
