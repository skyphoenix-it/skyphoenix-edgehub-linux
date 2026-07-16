import QtQuick
import QtTest

// Regression tests for the trickier per-widget logic added in the widgets pass:
// Calendar ICS recurrence/all-day parsing, Countdown yearly-repeat + local date
// parsing, End-of-Day work-window guard, and Clock half-hour UTC offsets.
Item {
    width: 480; height: 320
    WidgetHarness { id: hCal;   anchors.fill: parent; widgetFile: "CalendarWidget.qml"  }
    WidgetHarness { id: hCount; anchors.fill: parent; widgetFile: "CountdownWidget.qml" }
    WidgetHarness { id: hEod;   anchors.fill: parent; widgetFile: "EndOfDayWidget.qml"  }
    WidgetHarness { id: hClock; anchors.fill: parent; widgetFile: "ClockWidget.qml"     }
    WidgetHarness { id: hBreak; anchors.fill: parent; widgetFile: "BreakWidget.qml"     }
    WidgetHarness { id: hHabit; anchors.fill: parent; widgetFile: "HabitWidget.qml"     }
    WidgetHarness { id: hTasks; anchors.fill: parent; widgetFile: "TasksWidget.qml"     }

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function icsDay(d) { return d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) }
    function icsDateTime(d) {
        return icsDay(d) + "T" + pad(d.getHours()) + pad(d.getMinutes()) + "00"
    }
    function daysFromNow(n) { var d = new Date(); d.setHours(9, 0, 0, 0); d.setDate(d.getDate() + n); return d }

    // ── Calendar ───────────────────────────────────────────────────────────
    TestCase {
        name: "CalendarLogic"
        when: windowShown
        function init() { tryVerify(function () { return hCal.ready }, 3000) }

        function test_weekday_nums() {
            var w = hCal.item
            compare(w.weekdayNums("MO,WE,FR"), [1, 3, 5], "MO,WE,FR → 1,3,5")
            compare(w.weekdayNums("SU,SA"), [0, 6], "SU,SA → 0,6")
            // Tolerates BYDAY ordinal prefixes like "2MO".
            compare(w.weekdayNums("2MO"), [1], "ordinal prefix stripped")
        }

        function test_value_date_vs_date_time() {
            var w = hCal.item
            var timed = daysFromNow(1)      // tomorrow 09:00
            var ics =
                "BEGIN:VCALENDAR\n" +
                "BEGIN:VEVENT\nSUMMARY:Timed\nDTSTART;VALUE=DATE-TIME:" + icsDateTime(timed) + "\nEND:VEVENT\n" +
                "BEGIN:VEVENT\nSUMMARY:Allday\nDTSTART;VALUE=DATE:" + icsDay(timed) + "\nEND:VEVENT\n" +
                "END:VCALENDAR"
            var evs = w.parseICS(ics)
            var timedEv = null, allEv = null
            for (var i = 0; i < evs.length; i++) {
                if (evs[i].title === "Timed") timedEv = evs[i]
                if (evs[i].title === "Allday") allEv = evs[i]
            }
            verify(timedEv !== null && allEv !== null, "both events parsed")
            compare(timedEv.allDay, false, "VALUE=DATE-TIME is NOT all-day")
            compare(allEv.allDay, true, "VALUE=DATE is all-day")
        }

        function test_weekly_byday_expands() {
            var w = hCal.item
            var start = daysFromNow(-1)   // started yesterday so weeks are active now
            var ics =
                "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Standup\n" +
                "DTSTART;VALUE=DATE-TIME:" + icsDateTime(start) + "\n" +
                "RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR\nEND:VEVENT\nEND:VCALENDAR"
            var evs = w.parseICS(ics).filter(function (e) { return e.title === "Standup" })
            verify(evs.length > 1, "BYDAY yields multiple weekly occurrences (got " + evs.length + ")")
            for (var i = 0; i < evs.length; i++) {
                var dow = evs[i].start.getDay()
                verify(dow === 1 || dow === 3 || dow === 5, "every occurrence is Mon/Wed/Fri")
            }
        }

        function test_exdate_excludes_occurrence() {
            var w = hCal.item
            var start = daysFromNow(1)
            var skip = daysFromNow(2)     // exclude the second daily occurrence
            var ics =
                "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Daily\n" +
                "DTSTART;VALUE=DATE-TIME:" + icsDateTime(start) + "\n" +
                "RRULE:FREQ=DAILY;COUNT=4\n" +
                "EXDATE:" + icsDateTime(skip) + "\nEND:VEVENT\nEND:VCALENDAR"
            var evs = w.parseICS(ics).filter(function (e) { return e.title === "Daily" })
            for (var i = 0; i < evs.length; i++)
                verify(icsDay(evs[i].start) !== icsDay(skip), "the EXDATE occurrence is removed")
        }
    }

    // ── Countdown ──────────────────────────────────────────────────────────
    TestCase {
        name: "CountdownLogic"
        when: windowShown
        function init() {
            tryVerify(function () { return hCount.ready }, 3000)
            var s = hCount.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hCount.storeCtl._touchSettings()
        }
        function set(k, v) { hCount.storeCtl.setSetting("test-instance", k, v) }

        function test_local_date_parse_today_is_zero() {
            var w = hCount.item
            var t = new Date()
            set("date", t.getFullYear() + "-" + pad(t.getMonth() + 1) + "-" + pad(t.getDate()))
            compare(w.days, 0, "today parses to 0 days (no UTC off-by-one)")
        }
        function test_future_date_positive() {
            var w = hCount.item
            var f = new Date(); f.setDate(f.getDate() + 10)
            set("date", f.getFullYear() + "-" + pad(f.getMonth() + 1) + "-" + pad(f.getDate()))
            compare(w.days, 10, "a date 10 days out reads 10")
        }
        function test_past_date_negative_without_repeat() {
            var w = hCount.item
            set("repeatYearly", false)
            var p = new Date(); p.setDate(p.getDate() - 3)
            set("date", p.getFullYear() + "-" + pad(p.getMonth() + 1) + "-" + pad(p.getDate()))
            compare(w.days, -3, "a past date reads negative")
        }
        function test_yearly_repeat_never_passes() {
            var w = hCount.item
            set("repeatYearly", true)
            var p = new Date(); p.setDate(p.getDate() - 3)   // 3 days ago
            set("date", p.getFullYear() + "-" + pad(p.getMonth() + 1) + "-" + pad(p.getDate()))
            verify(w.days > 300, "a passed anniversary rolls to next year (got " + w.days + ")")
        }
    }

    // ── End of Day ─────────────────────────────────────────────────────────
    TestCase {
        name: "EndOfDayLogic"
        when: windowShown
        function init() {
            tryVerify(function () { return hEod.ready }, 3000)
            var s = hEod.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hEod.storeCtl._touchSettings()
        }
        function test_work_window_cannot_invert() {
            var w = hEod.item
            hEod.storeCtl.patchSettings("test-instance", { startHour: 9, endHour: 17 })
            // Try to push start past end — the guard keeps a ≥1h window.
            w.setHours(20, 17)
            verify(w.endHour > w.startHour, "end stays after start (start=" + w.startHour + " end=" + w.endHour + ")")
            // Try to pull end below start.
            w.setHours(w.startHour, w.startHour - 2)
            verify(w.endHour > w.startHour, "end can't drop to/under start")
        }
        function test_valid_hours_flag() {
            var w = hEod.item
            hEod.storeCtl.patchSettings("test-instance", { startHour: 9, endHour: 17 })
            compare(w.validHours, true, "9→17 is valid")
        }
    }

    // ── Clock half-hour offset ─────────────────────────────────────────────
    TestCase {
        name: "ClockOffset"
        when: windowShown
        function init() {
            tryVerify(function () { return hClock.ready }, 3000)
            var s = hClock.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hClock.storeCtl._touchSettings()
        }
        function set(k, v) { hClock.storeCtl.setSetting("test-instance", k, v) }

        function test_half_hour_offset_label() {
            var w = hClock.item
            set("utcOffset", 5.5)
            compare(w.offsetLabel(), "UTC+5:30", "India +5:30")
            set("utcOffset", -3.5)
            compare(w.offsetLabel(), "UTC-3:30", "negative half-hour")
            set("utcOffset", 0)
            compare(w.offsetLabel(), "UTC+0", "zero offset")
            set("utcOffset", 9)
            compare(w.offsetLabel(), "UTC+9", "whole-hour has no minutes")
        }
    }

    // ── Break: config interval must reseed the countdown ───────────────────
    TestCase {
        name: "BreakLogic"
        when: windowShown
        function init() {
            tryVerify(function () { return hBreak.ready }, 3000)
            var s = hBreak.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hBreak.storeCtl._touchSettings()
        }
        function test_interval_reseeds_on_config_change() {
            var w = hBreak.item
            hBreak.storeCtl.patchSettings("test-instance", { intervalMin: 30, running: true, due: false })
            // Changing the interval via config (not the ±5m buttons) must reseed.
            hBreak.storeCtl.setSetting("test-instance", "intervalMin", 45)
            tryVerify(function () {
                return hBreak.storeCtl.settingsFor("test-instance").pausedRemaining === 45 * 60
            }, 2000, "interval change reseeds the countdown to the new length")
        }
    }

    // ── Habit: streak maths + best-streak persistence ──────────────────────
    TestCase {
        name: "HabitLogic"
        when: windowShown
        function init() {
            tryVerify(function () { return hHabit.ready }, 3000)
            var s = hHabit.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hHabit.storeCtl._touchSettings()
        }
        function test_streak_of() {
            var w = hHabit.item
            compare(w.streakOf([]), 0, "empty list → 0")
            var today = w.key(new Date())
            var yest = w.key(new Date(Date.now() - 86400000))
            var three = w.key(new Date(Date.now() - 3 * 86400000))
            compare(w.streakOf([today]), 1, "today only → 1")
            compare(w.streakOf([today, yest]), 2, "today+yesterday → 2")
            compare(w.streakOf([today, three]), 1, "a gap breaks the streak")
        }
        function test_best_streak_persists() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: [], bestStreak: 5 })
            compare(w.bestStreak, 5, "best streak survives a lapsed current streak")
        }
    }

    // ── Tasks: clear-completed keeps only unfinished items ─────────────────
    TestCase {
        name: "TasksLogic"
        when: windowShown
        function init() {
            tryVerify(function () { return hTasks.ready }, 3000)
            var s = hTasks.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hTasks.storeCtl._touchSettings()
        }
        function test_clear_completed() {
            var w = hTasks.item
            hTasks.storeCtl.setSetting("test-instance", "items",
                [{ text: "a", done: true }, { text: "b", done: false }, { text: "c", done: true }])
            w.clearCompleted()
            var items = hTasks.storeCtl.settingsFor("test-instance").items
            compare(items.length, 1, "only the unfinished task remains")
            compare(items[0].text, "b", "and it's the right one")
        }
    }
}
