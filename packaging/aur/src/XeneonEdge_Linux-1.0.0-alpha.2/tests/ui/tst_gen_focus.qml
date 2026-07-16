import QtQuick
import QtTest

// COVERS: schema:autoStartBreak, schema:breakMin, schema:breakSuggestions, schema:celebrate, schema:dailyGoal, schema:rewardPoints
// COVERS: schema:showNudges, schema:workMin

// ─────────────────────────────────────────────────────────────────────────
// Comprehensive tests for widget:focus — ui/qml/widgets/FocusWidget.qml
// (the Focus / Pomodoro timer).
//
// Drives config through the shared DashboardStore (setSetting/patchSettings on
// "test-instance") exactly the way the live dashboard does, and asserts on the
// widget's derived properties + functions (cfg, phase, completedWork, remaining,
// ringValue, points, effAccent, advance()/skip()/reset()/applyPreset()/addFive()).
//
// Everything lives in ONE TestCase: this widget draws a per-second Canvas ring
// and restarts flash/celebration animations on every completion, and the
// offscreen scenegraph crashes at a TestCase boundary once enough of that state
// has accumulated — a single TestCase has no mid-run boundaries. active:false
// also keeps the widget's 1-second driving Timer OFF so it never auto-advances
// between assertions; every completion is driven by calling advance()/skip()
// directly, and `remaining` is derived from the absolute endEpoch (read on
// demand), so results stay correct.
//
// Some assertions encode the INTENDED behaviour and currently FAIL because of
// real bugs in the widget (skip counting as a completed session, Reset/preset
// wiping the daily count, custom accent not reaching the content, addFive NaN).
// Those failures are the point — they are left in. (The former ">= goal"
// re-celebration bug is now fixed: the bonus fires once, on the crossing session.)
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 480; height: 820

    WidgetHarness {
        id: hFocus; anchors.fill: parent
        widgetFile: "FocusWidget.qml"; expanded: true; active: false
    }

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function dayString(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
    function todayStr() { return dayString(new Date()) }
    function offsetDay(n) { var d = new Date(); d.setDate(d.getDate() + n); return dayString(d) }

    TestCase {
        name: "Focus"
        when: windowShown

        function initTestCase() { tryVerify(function () { return hFocus.ready }, 3000) }

        // Fresh, known state before every test.
        function init() {
            var s = hFocus.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hFocus.storeCtl._touchSettings()
            hFocus.item.accentName = ""
            hFocus.item.celebrateMsg = ""
        }

        function patch(o) { hFocus.storeCtl.patchSettings("test-instance", o) }
        function cfg() { return hFocus.storeCtl.settingsFor("test-instance") }

        // ── Pure helpers / formatting ──────────────────────────────────────
        function test_fmt_pads_minutes_seconds() {
            var w = hFocus.item
            compare(w.fmt(0), "00:00")
            compare(w.fmt(90), "01:30")
            compare(w.fmt(1500), "25:00")
            compare(w.fmt(5), "00:05")
        }
        function test_phase_labels() {
            var w = hFocus.item
            patch({ phase: "work" });  compare(w.phaseLabel(), "Focus")
            patch({ phase: "short" }); compare(w.phaseLabel(), "Short Break")
            patch({ phase: "long" });  compare(w.phaseLabel(), "Long Break")
        }
        function test_classic_preset_durations() {
            var w = hFocus.item
            patch({ preset: "classic" })
            compare(w.phaseSeconds("work"), 25 * 60)
            compare(w.phaseSeconds("short"), 5 * 60)
            compare(w.phaseSeconds("long"), 15 * 60)
        }
        function test_today_matches_local_date() {
            compare(hFocus.item.today(), todayStr())
        }

        // ── Skip vs natural completion (advance's `natural` flag) ──────────
        // BUG (high): skip() during a focus phase counts as a completed session.
        function test_skip_focus_does_not_count_or_reward() {
            var w = hFocus.item
            patch({ phase: "work", day: todayStr(), doneToday: 0, points: 0,
                    celebrate: true, rewardPoints: true })
            w.celebrateMsg = ""
            w.skip()
            compare(cfg().doneToday, 0, "Skip must NOT increment the completed-session count")
            compare(cfg().points || 0, 0, "Skip must NOT award points")
            compare(w.celebrateMsg, "", "Skip must NOT fire a celebration")
        }
        // Natural completion of a focus phase (advance(true)) is the correct path.
        function test_natural_focus_completion_counts_once() {
            var w = hFocus.item
            patch({ phase: "work", day: todayStr(), doneToday: 0, points: 0,
                    rewardPoints: true })
            w.advance(true)
            compare(cfg().doneToday, 1, "one natural completion → exactly +1")
            compare(cfg().points, 10, "one natural completion → +10 points")
        }
        // Skip during a break must move to work WITHOUT awarding points.
        function test_skip_break_advances_without_reward() {
            var w = hFocus.item
            patch({ phase: "short", day: todayStr(), doneToday: 2, points: 20,
                    rewardPoints: true })
            w.skip()
            compare(cfg().phase, "work", "break → work")
            compare(cfg().points, 20, "no points for leaving a break")
            compare(cfg().doneToday, 2, "count unchanged leaving a break")
        }

        // ── Reset / preset switch must preserve the daily count ────────────
        // BUG (medium): Reset zeroes doneToday.
        function test_reset_keeps_daily_count() {
            var w = hFocus.item
            patch({ phase: "work", day: todayStr(), doneToday: 3, points: 30 })
            w.reset()
            compare(cfg().doneToday, 3, "Reset restarts the timer, not the day's session count")
        }
        function test_reset_restarts_timer_to_work() {
            var w = hFocus.item
            patch({ phase: "short", day: todayStr(), running: true,
                    endEpoch: Date.now() + 100000 })
            w.reset()
            compare(cfg().phase, "work", "Reset returns to a work phase")
            compare(cfg().running, false, "Reset leaves the timer paused")
        }
        // BUG (medium): switching preset zeroes doneToday.
        function test_preset_switch_keeps_daily_count() {
            var w = hFocus.item
            patch({ phase: "work", day: todayStr(), doneToday: 2 })
            w.applyPreset("deep")
            compare(cfg().preset, "deep", "preset was applied")
            compare(cfg().doneToday, 2, "changing preset must preserve today's count")
        }
        // BUG (low): reset() zeroes doneToday but leaves points → inconsistent
        // momentum state. If doneToday is reset, points should be too.
        function test_reset_leaves_points_and_count_consistent() {
            var w = hFocus.item
            patch({ phase: "work", day: todayStr(), doneToday: 3, points: 30 })
            w.reset()
            if ((cfg().doneToday || 0) === 0)
                compare(cfg().points || 0, 0,
                        "if Reset clears the count it must also clear points")
        }

        // ── Date / midnight math ────────────────────────────────────────────
        function test_completedWork_zero_on_stale_day() {
            var w = hFocus.item
            patch({ day: offsetDay(-1), doneToday: 4 })
            compare(w.completedWork, 0, "yesterday's count does not count as today's")
        }
        function test_completedWork_reflects_today() {
            var w = hFocus.item
            patch({ day: todayStr(), doneToday: 3 })
            compare(w.completedWork, 3)
        }
        // Completing after the day has rolled restarts the count at 1, not +1.
        function test_new_day_completion_resets_to_one() {
            var w = hFocus.item
            patch({ phase: "work", day: offsetDay(-1), doneToday: 4, points: 0,
                    rewardPoints: true, celebrate: false })
            w.advance(true)
            compare(cfg().doneToday, 1, "post-midnight completion restarts at 1")
            compare(cfg().day, todayStr(), "day rolls forward to today")
        }

        // ── Reward points + goal celebration ────────────────────────────────
        function test_reaching_goal_awards_bonus() {
            var w = hFocus.item
            // doneToday 3, goal 4 → this completion is #4, exactly the goal.
            patch({ phase: "work", day: todayStr(), doneToday: 3, points: 0,
                    dailyGoal: 4, rewardPoints: true, celebrate: true })
            w.celebrateMsg = ""
            w.advance(true)
            compare(cfg().points, 60, "goal session awards +10 and +50 bonus")
            verify(w.celebrateMsg.indexOf("Goal") >= 0, "goal celebration fired")
        }
        // The goal bonus/celebration is ONE-TIME: it fires only on the session
        // that crosses the goal (done === dailyGoal). A session that merely
        // exceeds an already-reached goal earns the ordinary +10, no second +50
        // and no "Goal reached!" re-celebration.
        function test_goal_bonus_does_not_refire_when_exceeding() {
            var w = hFocus.item
            patch({ phase: "work", day: todayStr(), doneToday: 4, points: 0,
                    dailyGoal: 3, rewardPoints: true, celebrate: true })
            w.celebrateMsg = ""
            w.advance(true)   // done becomes 5 (already past goal 3) → +10 only
            compare(cfg().points, 10, "a session past the goal earns +10, not another +50")
            verify(w.celebrateMsg.indexOf("Goal") < 0, "no goal re-celebration past the goal")
        }
        // rewardPoints=false → no accumulation.
        function test_reward_points_off_stops_accumulation() {
            var w = hFocus.item
            patch({ phase: "work", day: todayStr(), doneToday: 0, points: 0,
                    rewardPoints: false })
            w.advance(true)
            compare(cfg().points || 0, 0, "no points accrue when rewards are disabled")
            compare(w.rewardPoints, false, "points display is gated off too")
        }
        // celebrate=false → no celebration message on completion.
        function test_celebrate_off_suppresses_message() {
            var w = hFocus.item
            patch({ phase: "work", day: todayStr(), doneToday: 0, celebrate: false })
            w.celebrateMsg = ""
            w.advance(true)
            compare(w.celebrateMsg, "", "no celebration when celebrate is disabled")
        }

        // ── Per-instance accent override reaches the content ────────────────
        // BUG (medium): the highlight content (ring/digits/label/Start) is
        // coloured by phaseColor()==catProductivity, NOT effAccent, so a custom
        // per-instance accent recolours only the chrome header.
        function test_custom_accent_recolours_focus_content() {
            var w = hFocus.item
            patch({ phase: "work" })
            w.accentName = "pink"
            compare(w.effAccent.toString().toLowerCase(),
                    hFocus.theme.accentPresets["pink"].a.toString().toLowerCase(),
                    "effAccent picks up the custom preset")
            compare(w.phaseColor().toString().toLowerCase(), w.effAccent.toString().toLowerCase(),
                    "focus highlight content should follow the custom accent")
        }

        // ── addFive: paused vs running, NaN guard, ring underflow ───────────
        function test_addfive_paused_extends_by_300() {
            var w = hFocus.item
            patch({ preset: "classic", phase: "work", running: false })
            wait(60)   // let any idle-duration sync settle
            patch({ pausedRemaining: 600 })
            compare(w.remaining, 600)
            w.addFive()
            compare(w.remaining, 900, "paused +5 extends remaining by exactly 300s")
        }
        function test_addfive_running_extends_by_300() {
            var w = hFocus.item
            patch({ preset: "classic", phase: "work", running: true,
                    endEpoch: Date.now() + 600 * 1000 })
            var before = w.remaining
            w.addFive()
            var delta = w.remaining - before
            verify(delta >= 298 && delta <= 302,
                   "running +5 extends remaining by ~300s (got " + delta + ")")
        }
        // BUG (low): addFive while running with a missing endEpoch → NaN/null.
        function test_addfive_running_without_endEpoch_no_nan() {
            var w = hFocus.item
            patch({ preset: "classic", phase: "work", running: true, pausedRemaining: 600 })
            delete hFocus.storeCtl.settingsFor("test-instance").endEpoch
            hFocus.storeCtl._touchSettings()
            w.addFive()
            var e = cfg().endEpoch
            verify(e !== null && e !== undefined && !isNaN(e),
                   "endEpoch stays a valid number after +5 (got " + e + ")")
        }
        // ringValue must never go below 0 even when +5 pushes remaining past the
        // phase's nominal length (denominator grows via Math.max).
        function test_ringvalue_never_underflows() {
            var w = hFocus.item
            patch({ preset: "custom", workMin: 1, phase: "work", running: false })
            wait(60)   // idle sync sets pausedRemaining to the 60s phase length
            compare(w.phaseTotal, 60)
            compare(w.remaining, 60)
            w.addFive()
            compare(w.remaining, 360, "+5 pushes remaining well past the 60s phase")
            verify(w.ringValue >= 0, "ringValue is clamped at/above 0 (got " + w.ringValue + ")")
            compare(w.ringValue, 0, "ring reads full-remaining (0 elapsed), not negative")
        }

        // ── autoStartBreak + phase progression ──────────────────────────────
        function test_autostart_break_off_pauses_at_break() {
            var w = hFocus.item
            patch({ preset: "classic", phase: "work", day: todayStr(),
                    doneToday: 0, autoStartBreak: false })
            w.advance(true)
            compare(cfg().phase, "short", "1st completion → short break")
            compare(cfg().running, false, "break waits to be started")
        }
        function test_autostart_break_on_runs_break() {
            var w = hFocus.item
            patch({ preset: "classic", phase: "work", day: todayStr(),
                    doneToday: 0, autoStartBreak: true })
            w.advance(true)
            compare(cfg().phase, "short", "1st completion → short break")
            compare(cfg().running, true, "break auto-starts")
        }
        function test_every_fourth_is_long_break() {
            var w = hFocus.item
            // classic every=4: 4th completed work session → long break.
            patch({ preset: "classic", phase: "work", day: todayStr(),
                    doneToday: 3, autoStartBreak: false })
            w.advance(true)
            compare(cfg().phase, "long", "4th session leads into a long break")
        }
        function test_break_completion_returns_to_work_paused() {
            var w = hFocus.item
            patch({ preset: "classic", phase: "short", day: todayStr(),
                    doneToday: 1, autoStartBreak: true })
            w.advance(true)
            compare(cfg().phase, "work", "break → work")
            compare(cfg().running, false, "work phase never auto-starts after a break")
        }

        // ── Every schema key changes observable behaviour ───────────────────
        function test_workMin_drives_custom_focus_length() {
            var w = hFocus.item
            patch({ preset: "custom", workMin: 30, breakMin: 5 })
            compare(w.phaseSeconds("work"), 30 * 60)
        }
        function test_breakMin_drives_both_breaks() {
            var w = hFocus.item
            patch({ preset: "custom", workMin: 40, breakMin: 8 })
            compare(w.phaseSeconds("short"), 8 * 60, "short break uses breakMin")
            compare(w.phaseSeconds("long"), 8 * 60, "long break also uses breakMin")
            compare(w.phaseSeconds("work"), 40 * 60, "focus uses workMin")
        }
        function test_dailyGoal_honored() {
            var w = hFocus.item
            patch({ dailyGoal: 7 })
            compare(w.dailyGoal, 7)
        }
        function test_showNudges_honored() {
            var w = hFocus.item
            patch({ showNudges: false })
            compare(w.showNudges, false)
            patch({ showNudges: true })
            compare(w.showNudges, true)
        }
        function test_breakSuggestions_honored() {
            var w = hFocus.item
            patch({ breakSuggestions: false })
            compare(w.breakSuggestions, false)
        }
        function test_autoStartBreak_honored() {
            var w = hFocus.item
            patch({ autoStartBreak: true })
            compare(w.autoStartBreak, true)
        }
        function test_preset_selection_changes_durations() {
            var w = hFocus.item
            patch({ preset: "deep" })
            compare(w.p.work, 50, "deep focus is 50 min")
            compare(w.phaseSeconds("work"), 50 * 60)
            patch({ preset: "sprint" })
            compare(w.p.work, 15, "sprint focus is 15 min")
        }

        // ── Persistence / reactivity of the running timer ───────────────────
        // remaining is derived from an absolute endEpoch, so it is correct across
        // a long background gap (past-due session reads 0, not negative).
        function test_remaining_from_absolute_endEpoch() {
            var w = hFocus.item
            patch({ phase: "work", running: true, endEpoch: Date.now() + 100 * 1000 })
            verify(w.remaining >= 98 && w.remaining <= 100,
                   "remaining tracks endEpoch (got " + w.remaining + ")")
        }
        function test_remaining_clamps_to_zero_after_gap() {
            var w = hFocus.item
            patch({ phase: "work", running: true, endEpoch: Date.now() - 5000 })
            compare(w.remaining, 0, "a session whose end is in the past reads 0, never negative")
        }
        function test_running_state_survives_expand_toggle() {
            var w = hFocus.item
            patch({ phase: "work", running: true, endEpoch: Date.now() + 200 * 1000 })
            var before = w.remaining
            hFocus.expanded = false
            hFocus.expanded = true
            verify(Math.abs(w.remaining - before) <= 2,
                   "collapsing/expanding does not disturb the running timer")
            compare(cfg().running, true)
        }
        function test_start_pause_toggle() {
            var w = hFocus.item
            patch({ phase: "work", running: false, pausedRemaining: 300 })
            w.toggle()   // start
            compare(cfg().running, true, "toggle from paused starts")
            verify(cfg().endEpoch > Date.now(), "start sets an endEpoch in the future")
            w.toggle()   // pause
            compare(cfg().running, false, "toggle again pauses")
            verify(cfg().pausedRemaining > 0, "pause snapshots remaining")
        }
    }
}
