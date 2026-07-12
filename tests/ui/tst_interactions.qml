import QtQuick
import QtTest

// Interaction + boundary coverage for the remaining stateful widgets. Each
// exercises the exact operations its buttons/inputs invoke, plus edge cases
// (empty/whitespace/duplicate/out-of-range/clamping).
Item {
    id: root
    width: 460; height: 860

    WidgetHarness { id: hTasks;     anchors.fill: parent; widgetFile: "TasksWidget.qml";     expanded: true }
    WidgetHarness { id: hHydration; anchors.fill: parent; widgetFile: "HydrationWidget.qml"; expanded: true }
    WidgetHarness { id: hCountdown; anchors.fill: parent; widgetFile: "CountdownWidget.qml"; expanded: true }
    WidgetHarness { id: hHabit;     anchors.fill: parent; widgetFile: "HabitWidget.qml";     expanded: true }
    WidgetHarness { id: hRightNow;  anchors.fill: parent; widgetFile: "RightNowWidget.qml";  expanded: true }
    WidgetHarness { id: hNotes;     anchors.fill: parent; widgetFile: "NotesWidget.qml";     expanded: true }

    TestCase {
        name: "Tasks"
        when: windowShown
        function init() { tryVerify(function () { return hTasks.ready }, 3000) }
        function cfg() { return hTasks.storeCtl.settingsFor("test-instance") }

        function test_add_toggle_remove() {
            var w = hTasks.item
            w.add("Write report")
            w.add("Email team")
            compare(w.items.length, 2)
            compare(w.doneCount, 0)
            w.toggle(0)
            compare(w.items[0].done, true)
            compare(w.doneCount, 1)
            w.remove(0)
            compare(w.items.length, 1)
            compare(w.items[0].text, "Email team")
        }
        function test_add_rejects_empty_and_whitespace() {
            var w = hTasks.item
            var before = w.items.length
            w.add("")
            w.add("   ")
            w.add(null)
            compare(w.items.length, before, "empty/whitespace/null not added")
        }
        function test_add_trims() {
            var w = hTasks.item
            w.add("  spaced  ")
            compare(w.items[w.items.length - 1].text, "spaced")
        }
    }

    TestCase {
        name: "Hydration"
        when: windowShown
        function init() { tryVerify(function () { return hHydration.ready }, 3000) }

        function test_count_clamps_to_goal() {
            var w = hHydration.item
            w.setGoal(8)
            w.set(100)
            compare(w.count, 8, "count cannot exceed goal")
            w.set(-5)
            compare(w.count, 0, "count cannot go below 0")
        }
        function test_goal_clamps() {
            var w = hHydration.item
            w.setGoal(0)
            compare(w.goal, 1, "goal min 1")
            w.setGoal(99)
            compare(w.goal, 16, "goal max 16")
        }
        function test_increment_decrement() {
            var w = hHydration.item
            w.setGoal(8); w.set(0)
            w.set(w.count + 1); w.set(w.count + 1)
            compare(w.count, 2)
            w.set(w.count - 1)
            compare(w.count, 1)
        }
    }

    TestCase {
        name: "Countdown"
        when: windowShown
        function init() { tryVerify(function () { return hCountdown.ready }, 3000) }

        function test_invalid_date_is_not_valid() {
            var w = hCountdown.item
            hCountdown.storeCtl.patchSettings("test-instance", { date: "", label: "" })
            w.tick++
            compare(w.valid, false)
            hCountdown.storeCtl.patchSettings("test-instance", { date: "not-a-date" })
            w.tick++
            compare(w.valid, false)
        }
        function test_future_date_positive_days() {
            var w = hCountdown.item
            var d = new Date(new Date().getTime() + 10 * 86400000)
            var ds = Qt.formatDate(d, "yyyy-MM-dd")
            hCountdown.storeCtl.patchSettings("test-instance", { date: ds, label: "Trip" })
            w.tick++
            verify(w.valid)
            verify(w.days >= 9 && w.days <= 11, "roughly 10 days (got " + w.days + ")")
        }
        function test_past_date_negative_days() {
            var w = hCountdown.item
            var d = new Date(new Date().getTime() - 5 * 86400000)
            hCountdown.storeCtl.patchSettings("test-instance", { date: Qt.formatDate(d, "yyyy-MM-dd") })
            w.tick++
            verify(w.days < 0)
        }
    }

    TestCase {
        name: "Habit"
        when: windowShown
        function init() { tryVerify(function () { return hHabit.ready }, 3000) }

        function test_checkin_toggles_and_streak() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: [] })
            w.tick++
            compare(w.doneToday, false)
            compare(w.streak, 0)
            w.toggleToday()
            compare(w.doneToday, true)
            compare(w.streak, 1)
            w.toggleToday()
            compare(w.doneToday, false, "toggles off")
        }
        function test_streak_counts_consecutive() {
            var w = hHabit.item
            var days = []
            for (var i = 0; i < 5; i++)
                days.push(w.key(new Date(new Date().getTime() - i * 86400000)))
            hHabit.storeCtl.patchSettings("test-instance", { checkins: days })
            w.tick++
            compare(w.streak, 5, "5 consecutive days incl today")
        }
        function test_streak_breaks_on_gap() {
            var w = hHabit.item
            var today = w.key(new Date())
            var threeAgo = w.key(new Date(new Date().getTime() - 3 * 86400000))
            hHabit.storeCtl.patchSettings("test-instance", { checkins: [today, threeAgo] })
            w.tick++
            compare(w.streak, 1, "gap breaks the streak")
        }
    }

    TestCase {
        name: "RightNow"
        when: windowShown
        function init() { tryVerify(function () { return hRightNow.ready }, 3000) }

        function test_set_and_clear() {
            var w = hRightNow.item
            w.setText("Finish the report")
            compare(w.current, "Finish the report")
            w.setText("")
            compare(w.current, "")
        }
    }

    TestCase {
        name: "Notes"
        when: windowShown
        function init() { tryVerify(function () { return hNotes.ready }, 3000) }

        function test_persist_note() {
            var w = hNotes.item
            w.save("remember the milk")
            compare(w.current, "remember the milk")
            w.save("")
            compare(w.current, "")
        }
    }
}
