import QtQuick
import QtTest

// FocusWidget — verifies the timer logic and the audited fixes:
//  * reset()/applyPreset() clear the REAL persisted key (doneToday), not the
//    derived read-only completedWork.
//  * "+5" never drives the ring fill negative.
//  * start/pause/skip persist correctly and phases advance.
Item {
    width: 420; height: 820
    WidgetHarness { id: h; anchors.fill: parent; widgetFile: "FocusWidget.qml"; expanded: true }

    TestCase {
        name: "FocusWidget"
        when: windowShown

        function init() {
            tryVerify(function () { return h.ready }, 3000)
            // Clean slate per test — settings would otherwise leak between tests
            // (they run in alphabetical order and share one instance).
            var s = h.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            h.storeCtl._touchSettings()
        }

        function cfg() { return h.storeCtl.settingsFor("test-instance") }

        function test_reset_clears_done_today() {
            var w = h.item
            // Simulate sessions completed today.
            h.storeCtl.patchSettings("test-instance", { doneToday: 3, day: w.today() })
            compare(w.completedWork, 3)
            w.reset()
            compare(cfg().doneToday, 0, "doneToday persisted key reset")
            compare(w.completedWork, 0, "derived counter reflects reset")
            // Must NOT have written the bogus derived key.
            verify(cfg().completedWork === undefined, "no stray completedWork key written")
        }

        function test_applypreset_resets_and_switches() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { doneToday: 2, day: w.today() })
            w.applyPreset("deep")
            compare(cfg().preset, "deep")
            compare(w.presetName, "deep")
            compare(cfg().doneToday, 0)
            compare(w.phase, "work", "preset switch returns to work phase")
        }

        function test_start_pause_persist() {
            var w = h.item
            w.reset()
            verify(!w.running)
            w.toggle()  // start
            verify(cfg().running === true)
            verify(cfg().endEpoch > 0, "start sets an absolute end epoch")
            w.toggle()  // pause
            verify(cfg().running === false)
            verify(cfg().pausedRemaining !== undefined, "pause captures remaining")
        }

        function test_plus5_ring_never_negative() {
            var w = h.item
            w.reset()
            w.toggle() // running
            for (var i = 0; i < 20; i++) w.addFive()  // push remaining far past phaseTotal
            verify(w.ringValue >= 0, "ring fill fraction stays >= 0 (was underflowing)")
            verify(w.ringValue <= 1, "ring fill fraction stays <= 1")
        }

        function test_skip_advances_phase_and_counts() {
            var w = h.item
            w.reset()  // phase = work, doneToday = 0
            w.skip()
            compare(cfg().doneToday, 1, "finishing a work phase counts a session")
            verify(w.phase === "short" || w.phase === "long", "advanced to a break phase")
        }

        function test_remaining_never_negative() {
            var w = h.item
            w.reset()
            w.toggle()
            // Force an end epoch in the past; remaining must clamp to 0.
            h.storeCtl.patchSettings("test-instance", { running: true, endEpoch: 1 })
            w.pulse++  // re-evaluate
            verify(w.remaining >= 0)
        }

        // The reported bug: choose a preset, then the timer won't start / the ring
        // doesn't reflect the new duration.
        function test_preset_then_start() {
            var w = h.item
            w.applyPreset("deep")
            compare(w.presetName, "deep")
            compare(w.p.work, 50)
            tryVerify(function () { return w.remaining === 3000 }, 1000,
                      "idle clock shows Deep's 50:00 (3000s)")
            compare(w.ringValue, 0, "ring empty (full time) on a fresh preset")
            verify(!w.running)
            w.toggle()   // START
            verify(w.running, "timer starts after choosing a preset")
            verify(cfg().running === true)
            verify(cfg().endEpoch > 0, "start sets an end epoch after a preset change")
        }

        // Changing the custom length (as the config panel does) resets the idle clock.
        function test_custom_length_change_resets_idle_clock() {
            var w = h.item
            w.applyPreset("custom")
            tryVerify(function () { return w.remaining === w.workMin * 60 }, 1000)
            h.storeCtl.patchSettings("test-instance", { workMin: 40 })
            tryVerify(function () { return w.remaining === 2400 }, 1000,
                      "idle clock follows a custom-length change (40:00)")
        }

        // ADHD momentum: points accrue per session with a bonus on hitting the goal.
        function test_reward_points_and_goal_bonus() {
            var w = h.item
            w.reset()
            h.storeCtl.patchSettings("test-instance", { points: 0, dailyGoal: 2 })
            w.skip()                     // work #1 → +10, done=1, → break
            compare(cfg().doneToday, 1)
            compare(cfg().points, 10, "10 points per completed session")
            w.skip()                     // break → work (no points)
            compare(cfg().doneToday, 1)
            w.skip()                     // work #2 hits the goal → +10 +50
            compare(cfg().doneToday, 2)
            compare(cfg().points, 70, "goal bonus (+50) awarded on hitting the daily goal")
        }

        function test_celebrate_message_on_session() {
            var w = h.item
            w.reset()
            w.celebrateMsg = ""
            w.skip()                     // completes a work session (celebrate dflt on)
            verify(w.celebrateMsg.length > 0, "a celebration message pops on a completed session")
        }

        function test_points_off_when_disabled() {
            var w = h.item
            w.reset()
            h.storeCtl.patchSettings("test-instance", { points: 0, rewardPoints: false })
            w.skip()
            compare(cfg().points, 0, "no points accrue when rewards are disabled")
        }
    }
}
