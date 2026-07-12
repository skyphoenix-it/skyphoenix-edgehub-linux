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

        function init() { tryVerify(function () { return h.ready }, 3000) }

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
    }
}
