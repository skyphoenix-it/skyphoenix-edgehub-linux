import QtQuick
import QtTest

// COVERS: schema:intervalMin, schema:message, schema:showSuggestion

// ─────────────────────────────────────────────────────────────────────────
// Comprehensive coverage for widget:break — ui/qml/widgets/BreakWidget.qml.
//
// Drives the SAME persistent store contract the Dashboard uses (via the
// WidgetHarness). Verifies every config option, the remaining/countdown math,
// the ±5m / reset / take-break / pause-resume actions, interval reseeding,
// accent theming, and the daily-momentum counter.
//
// Some assertions target audited bugs and are EXPECTED to fail until the code
// under test is fixed — those are called out in comments as "REAL BUG".
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 720; height: 900

    // Expanded instance (buttons + full controls exercised through functions).
    WidgetHarness { id: h; anchors.fill: parent; widgetFile: "BreakWidget.qml"; expanded: true }

    function clear(hh) {
        var s = hh.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        hh.storeCtl._touchSettings()
    }
    function cfg() { return h.storeCtl.settingsFor("test-instance") }

    // ── Config options honored ───────────────────────────────────────────
    TestCase {
        name: "BreakConfig"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); root.clear(h) }

        function test_defaults_from_empty_cfg() {
            var w = h.item
            compare(w.intervalMin, 30, "empty cfg → default 30-min interval")
            compare(w.running, true, "auto-running by default")
            compare(w.due, false, "not due by default")
            compare(w.message, "", "no custom message by default")
            compare(w.showSuggestion, true, "suggestions on by default")
        }
        function test_intervalMin_honored() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "intervalMin", 60)
            compare(w.intervalMin, 60)
        }
        function test_running_honored() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "running", false)
            compare(w.running, false)
        }
        function test_due_honored() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "due", true)
            compare(w.due, true)
        }
        function test_message_honored_and_fallback() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "message", "Stretch your legs")
            compare(w.message, "Stretch your legs")
            h.storeCtl.setSetting("test-instance", "message", "")
            compare(w.message, "", "empty message falls back to default wording downstream")
        }
        function test_showSuggestion_honored() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "showSuggestion", false)
            compare(w.showSuggestion, false)
        }
    }

    // ── remaining / countdown math ───────────────────────────────────────
    TestCase {
        name: "BreakRemaining"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); root.clear(h) }

        function test_remaining_from_pausedRemaining_when_paused() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { running: false, due: false, pausedRemaining: 123 })
            w.pulse++
            compare(w.remaining, 123, "paused → reads pausedRemaining")
        }
        function test_remaining_from_endEpoch_when_running() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance",
                { running: true, due: false, endEpoch: Date.now() + 600 * 1000 })
            w.pulse++
            verify(w.remaining >= 598 && w.remaining <= 600, "≈600s from a 10-min endEpoch (got " + w.remaining + ")")
        }
        function test_remaining_zero_when_due() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance",
                { running: true, due: true, endEpoch: Date.now() + 600 * 1000 })
            w.pulse++
            compare(w.remaining, 0, "due forces remaining to 0")
        }
        function test_remaining_clamps_at_zero_after_sleep() {
            // Simulated sleep/resume: wall clock jumped PAST endEpoch.
            var w = h.item
            h.storeCtl.patchSettings("test-instance",
                { running: true, due: false, endEpoch: Date.now() - 5000 })
            w.pulse++
            compare(w.remaining, 0, "past endEpoch never goes negative")
        }
        function test_remaining_fallback_to_interval() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance",
                { running: true, due: false, endEpoch: 0, intervalMin: 30 })
            w.pulse++
            compare(w.remaining, 1800, "running with no endEpoch/pausedRemaining → intervalMin*60")
        }
    }

    // ── fmt() mm:ss formatting ───────────────────────────────────────────
    TestCase {
        name: "BreakFmt"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000) }
        function test_fmt() {
            var w = h.item
            compare(w.fmt(0), "00:00")
            compare(w.fmt(5), "00:05")
            compare(w.fmt(65), "01:05")
            compare(w.fmt(600), "10:00")
            compare(w.fmt(1800), "30:00")
        }
    }

    // ── reset / takeBreak / toggleRun actions ────────────────────────────
    TestCase {
        name: "BreakActions"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); root.clear(h) }

        function test_reset_seeds_and_clears_due() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { due: true, intervalMin: 20 })
            w.reset()
            compare(root.cfg().due, false, "reset clears due")
            compare(root.cfg().running, true, "reset resumes")
            compare(root.cfg().pausedRemaining, 20 * 60, "reset seeds pausedRemaining to full interval")
            verify(root.cfg().endEpoch > Date.now() + 19 * 60 * 1000, "reset seeds a fresh endEpoch")
        }

        function test_takeBreak_increments_and_stamps_today() {
            var w = h.item
            // Baseline: 2 acknowledged breaks already today.
            h.storeCtl.patchSettings("test-instance",
                { due: true, day: w.todayKey, breaksToday: 2, intervalMin: 30 })
            compare(w.breaksToday, 2, "baseline momentum reads from cfg for today")
            w.takeBreak()
            compare(root.cfg().due, false, "acknowledging clears due")
            compare(root.cfg().breaksToday, 3, "acknowledging increments the daily count")
            compare(root.cfg().day, w.todayKey, "the count is stamped with the CURRENT day")
            verify(root.cfg().endEpoch > Date.now(), "the timer restarts after acknowledging")
        }

        function test_pause_preserves_remaining_across_toggle() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance",
                { running: true, due: false, endEpoch: Date.now() + 600 * 1000 })
            w.pulse++
            var before = w.remaining
            verify(before >= 598 && before <= 600, "started ≈600s")
            w.toggleRun()   // pause
            compare(root.cfg().running, false, "paused")
            compare(root.cfg().pausedRemaining, before, "pause snapshots the exact remaining")
            w.toggleRun()   // resume
            compare(root.cfg().running, true, "resumed")
            w.pulse++
            verify(Math.abs(w.remaining - before) <= 2, "remaining survives pause→resume (got " + w.remaining + ")")
        }
    }

    // ── setInterval clamping + seeding ───────────────────────────────────
    TestCase {
        name: "BreakSetInterval"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); root.clear(h) }

        function test_clamp_low() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "intervalMin", 5)
            w.setInterval(w.intervalMin - 5)   // −5m at the floor
            compare(root.cfg().intervalMin, 5, "−5m at 5 stays 5")
        }
        function test_clamp_high() {
            var w = h.item
            h.storeCtl.setSetting("test-instance", "intervalMin", 120)
            w.setInterval(w.intervalMin + 5)   // +5m at the ceiling
            compare(root.cfg().intervalMin, 120, "+5m at 120 stays 120")
        }
        function test_setInterval_seeds_countdown() {
            var w = h.item
            w.setInterval(45)
            compare(root.cfg().intervalMin, 45)
            compare(root.cfg().pausedRemaining, 45 * 60, "seeds pausedRemaining to the new length")
            verify(root.cfg().endEpoch > Date.now(), "seeds a running endEpoch")
        }
    }

    // ── config-side interval change reseeds via onIntervalMinChanged ─────
    TestCase {
        name: "BreakApplyInterval"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); root.clear(h) }

        function test_running_interval_reseeds_preserving_running() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { intervalMin: 30, running: true, due: false })
            h.storeCtl.setSetting("test-instance", "intervalMin", 45)
            tryVerify(function () { return root.cfg().pausedRemaining === 45 * 60 }, 2000,
                      "running interval change reseeds to the new length")
            compare(root.cfg().running, true, "still running after a config interval change")
            verify(root.cfg().endEpoch > Date.now(), "endEpoch re-seeded for the running timer")
        }

        function test_paused_interval_reseeds_but_stays_paused() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance",
                { intervalMin: 30, running: false, pausedRemaining: 1800, endEpoch: 12345 })
            h.storeCtl.setSetting("test-instance", "intervalMin", 60)
            tryVerify(function () { return root.cfg().pausedRemaining === 60 * 60 }, 2000,
                      "paused interval change reseeds pausedRemaining")
            compare(root.cfg().running, false, "stays paused")
            compare(root.cfg().endEpoch, 0, "endEpoch cleared while paused")
        }
    }

    // ── Daily momentum counter ───────────────────────────────────────────
    TestCase {
        name: "BreakMomentum"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); root.clear(h) }

        function test_breaksToday_zero_on_day_mismatch() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { day: "2000-01-01", breaksToday: 5 })
            compare(w.breaksToday, 0, "a stale day resets today's count to 0")
        }
        function test_breaksToday_reads_current_day() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { day: w.todayKey, breaksToday: 4 })
            compare(w.breaksToday, 4, "today's count is honored")
        }
        function test_breakIdeas_present_for_cycling() {
            var w = h.item
            verify(w.breakIdeas.length >= 6, "there are break-activity ideas to cycle through")
            // The suggestion shown is breakIdeas[breaksToday % len]; verify the index math.
            h.storeCtl.patchSettings("test-instance", { day: w.todayKey, breaksToday: 7 })
            compare(w.breaksToday % w.breakIdeas.length, 1, "index wraps around the idea list")
        }
    }

    // ── Accent theming (effAccent) ───────────────────────────────────────
    TestCase {
        name: "BreakAccent"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000) }

        function test_default_accent_is_success() {
            var w = h.item
            w.accentName = ""
            var exp = h.theme.success
            fuzzyCompare(w.effAccent.r, exp.r, 0.02)
            fuzzyCompare(w.effAccent.g, exp.g, 0.02)
            fuzzyCompare(w.effAccent.b, exp.b, 0.02)
        }
        function test_accent_preset_recolours() {
            var w = h.item
            w.accentName = "red"
            var exp = Qt.color(h.theme.accentPresets["red"].a)
            fuzzyCompare(w.effAccent.r, exp.r, 0.02)
            fuzzyCompare(w.effAccent.g, exp.g, 0.02)
            fuzzyCompare(w.effAccent.b, exp.b, 0.02)
            w.accentName = ""   // restore
        }
    }

    // ── AUDITED BUGS — these assertions describe correct behavior and are
    //    expected to FAIL until BreakWidget.qml is fixed. ─────────────────
    TestCase {
        name: "BreakBugs"
        when: windowShown
        function init() { tryVerify(function () { return h.ready }, 3000); root.clear(h) }

        // BUG (high): a freshly-added, auto-running reminder never seeds endEpoch
        // (Component.onCompleted runs before the store is injected), so the
        // countdown is frozen at intervalMin*60 and never fires.
        function test_fresh_instance_seeds_endEpoch() {
            var w = h.item
            compare(w.running, true, "fresh reminder is auto-running")
            compare(w.due, false, "fresh reminder is not due")
            verify(root.cfg().endEpoch > 0,
                   "REAL BUG: a running, non-due reminder must have a live endEpoch to count down")
        }

        // BUG (medium): BreakWidget never declares `property int tick`, so the
        // per-second tick binding is never injected and todayKey/breaksToday
        // never roll over at midnight.
        function test_declares_tick_property() {
            var w = h.item
            compare(w.hasOwnProperty("tick"), true,
                    "REAL BUG: BreakWidget must declare `property int tick` for midnight rollover")
        }

        // BUG (medium): setInterval() unconditionally writes running:true, so
        // tapping −5m / +5m while paused silently resumes the countdown.
        function test_setInterval_while_paused_keeps_paused() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance",
                { running: false, due: false, pausedRemaining: 600, intervalMin: 30 })
            compare(w.running, false, "precondition: paused")
            w.setInterval(w.intervalMin - 5)   // tap −5m
            compare(root.cfg().running, false,
                    "REAL BUG: −5m/+5m while paused must NOT resume the timer")
        }

        // BUG (low): pausing while a break is due snapshots pausedRemaining from
        // `remaining`, which is forced to 0 when due — corrupting the state.
        function test_pause_while_due_does_not_zero_paused() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance",
                { running: true, due: true, endEpoch: Date.now() + 600 * 1000, pausedRemaining: 600 })
            compare(w.due, true, "precondition: due")
            compare(w.remaining, 0, "remaining is forced to 0 while due")
            w.toggleRun()   // pause while due
            verify(root.cfg().pausedRemaining > 0,
                   "REAL BUG: pausing while due must not persist pausedRemaining:0")
        }
    }
}
