import QtQuick
import QtTest

// COVERS: schema:name

// ─────────────────────────────────────────────────────────────────────────
// Comprehensive coverage for the Habit streak widget
// (ui/qml/widgets/HabitWidget.qml).
//
// Exercises: streak maths (grace day, gaps, DST-spanning consecutive runs),
// the 28-day heatmap mapping, check-in toggling, milestone celebration
// (including the "re-check re-fires" bug), pluralisation, best-streak
// persistence, checkins-array growth, reactivity through store.revision,
// per-instance accent, custom name / title override, compact-tile layout,
// and the store==null no-op path.
//
// Several assertions encode CORRECT behaviour the audit flags as broken; those
// are expected to FAIL against the current code and are the point of the file.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 480; height: 900

    // Non-overlapping layout so mouseClick() hit-testing reaches each harness's
    // own widget (a topmost sibling at the same origin would swallow the click).
    WidgetHarness { id: hHabit;   anchors.fill: parent; widgetFile: "HabitWidget.qml"; expanded: true }
    // A 1x1-sized compact tile to reproduce the clipped check-in button.
    WidgetHarness { id: hCompact; x: 280; y: 0;   width: 150; height: 150; widgetFile: "HabitWidget.qml"; expanded: false }
    // A widget whose store is forcibly nulled to test the guard path.
    WidgetHarness { id: hNull;    x: 280; y: 200; width: 200; height: 200; widgetFile: "HabitWidget.qml"; expanded: false }

    // Recursively collect nodes matching a predicate.
    function findAll(node, pred, acc) {
        if (!node) return acc
        if (pred(node)) acc.push(node)
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) findAll(kids[i], pred, acc)
        return acc
    }
    function findPill(item) {
        return findAll(item, function (n) {
            return n.hasOwnProperty("label") && n.hasOwnProperty("primary") && n.hasOwnProperty("glyph")
        }, [])[0] || null
    }
    function findCells(item) {
        return findAll(item, function (n) {
            return n.hasOwnProperty("dk") && n.hasOwnProperty("on")
        }, [])
    }

    // A run of `count` calendar-consecutive local dates ending `endOffset` days
    // before today. Built with setDate() (true calendar stepping) so the TEST
    // DATA is DST-correct even where the widget's fixed-ms stepping is not.
    function consecutiveDays(w, count, endOffset) {
        var arr = []
        var d = new Date(); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() - (endOffset || 0))
        for (var i = 0; i < count; i++) { arr.push(w.key(d)); d.setDate(d.getDate() - 1) }
        return arr
    }
    function clearSettings(h) {
        var s = h.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        h.storeCtl._touchSettings()
    }
    function occurrences(arr, val) {
        var n = 0
        for (var i = 0; i < arr.length; i++) if (arr[i] === val) n++
        return n
    }

    // ── Core streak + check-in logic ───────────────────────────────────────
    TestCase {
        name: "HabitCore"
        when: windowShown
        function init() {
            tryVerify(function () { return hHabit.ready }, 3000)
            clearSettings(hHabit)
        }
        function cfg() { return hHabit.storeCtl.settingsFor("test-instance") }

        function test_streak_of_basics() {
            var w = hHabit.item
            compare(w.streakOf([]), 0, "empty list → 0")
            var today = w.key(new Date())
            var yest = w.key(new Date(Date.now() - 86400000))
            var three = w.key(new Date(Date.now() - 3 * 86400000))
            compare(w.streakOf([today]), 1, "today only → 1")
            compare(w.streakOf([today, yest]), 2, "today+yesterday → 2")
            compare(w.streakOf([today, three]), 1, "a gap breaks the streak")
        }

        function test_grace_day_counts_run_ending_yesterday() {
            var w = hHabit.item
            // Two consecutive days ending yesterday; today NOT checked in.
            hHabit.storeCtl.patchSettings("test-instance", { checkins: consecutiveDays(w, 2, 1) })
            compare(w.doneToday, false, "today is not checked")
            compare(w.streak, 2, "grace day: a run ending yesterday still counts")
        }
        function test_streak_zero_when_today_and_yesterday_missing() {
            var w = hHabit.item
            // A single check-in 3 days ago; both today and yesterday missing.
            hHabit.storeCtl.patchSettings("test-instance", { checkins: consecutiveDays(w, 1, 3) })
            compare(w.streak, 0, "no run touching today/yesterday → 0")
        }

        function test_checkin_adds_today_once() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: [] })
            compare(w.doneToday, false)
            w.toggleToday()
            compare(w.doneToday, true, "checked in")
            compare(w.streak, 1)
            compare(occurrences(cfg().checkins, w.todayKey), 1, "today's key stored exactly once")
        }
        function test_uncheck_removes_and_lowers_streak_but_keeps_best() {
            var w = hHabit.item
            // 3-day run incl today, with a stored best of 3.
            hHabit.storeCtl.patchSettings("test-instance",
                { checkins: consecutiveDays(w, 3, 0), bestStreak: 3 })
            compare(w.streak, 3)
            w.toggleToday()   // uncheck today
            compare(w.doneToday, false, "today removed")
            compare(w.streak, 2, "streak drops (grace day keeps the ending-yesterday run)")
            compare(w.bestStreak, 3, "best streak stays at prior max")
            compare(occurrences(cfg().checkins, w.todayKey), 0, "today's key gone from storage")
        }

        function test_status_compact_shows_streak_flames() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: consecutiveDays(w, 4, 0) })
            // In expanded mode status is blank; drive the compact instance.
            compare(hCompact.item.status, hCompact.item.streak + "🔥", "compact status = N🔥")
        }
    }

    // ── Milestones + celebration ───────────────────────────────────────────
    TestCase {
        name: "HabitMilestones"
        when: windowShown
        function init() {
            tryVerify(function () { return hHabit.ready }, 3000)
            clearSettings(hHabit)
            hHabit.item.celebrateMsg = ""
        }

        function test_milestone_message_formatting() {
            var w = hHabit.item
            compare(w.milestoneMsg(7), "🏆 7-day milestone!", "7 is a milestone")
            compare(w.milestoneMsg(365), "🏆 365-day milestone!", "365 is a milestone")
            compare(w.milestoneMsg(1), "🔥 1 day!", "singular day")
            compare(w.milestoneMsg(2), "🔥 2 days!", "plural days")
            compare(w.milestoneMsg(8), "🔥 8 days!", "non-milestone plural")
        }

        function test_checkin_fires_singular_message() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: [] })
            w.celebrateMsg = ""
            w.toggleToday()
            compare(w.celebrateMsg, "🔥 1 day!", "first check-in → singular")
        }
        function test_checkin_fires_plural_message() {
            var w = hHabit.item
            // One day ending yesterday; checking in today → ns == 2.
            hHabit.storeCtl.patchSettings("test-instance", { checkins: consecutiveDays(w, 1, 1) })
            w.celebrateMsg = ""
            w.toggleToday()
            compare(w.celebrateMsg, "🔥 2 days!", "second consecutive day → plural")
        }
        function test_milestone_fires_on_crossing_seven() {
            var w = hHabit.item
            // 6 consecutive ending yesterday; checking in today → ns == 7.
            hHabit.storeCtl.patchSettings("test-instance", { checkins: consecutiveDays(w, 6, 1) })
            w.celebrateMsg = ""
            w.toggleToday()
            compare(w.streak, 7, "crossed into a 7-day run")
            compare(w.celebrateMsg, "🏆 7-day milestone!", "milestone popup on crossing 7")
        }

        // BUG (audit line 58): re-checking the same already-milestone day
        // re-fires the milestone celebration. Correct behaviour: no milestone
        // message on a plain re-check. This assertion is expected to FAIL.
        function test_recheck_same_day_should_not_refire_milestone() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: consecutiveDays(w, 7, 0) })
            compare(w.streak, 7, "already at a 7-day milestone (today included)")
            w.toggleToday()          // uncheck today → streak 6, no celebration
            w.celebrateMsg = ""      // clear before the re-check
            w.toggleToday()          // re-check today → streak back to 7
            verify(w.celebrateMsg.indexOf("milestone") < 0,
                   "re-checking an already-reached milestone should NOT re-announce it (got '"
                   + w.celebrateMsg + "')")
        }
    }

    // ── Best streak + reactivity ───────────────────────────────────────────
    TestCase {
        name: "HabitReactivity"
        when: windowShown
        function init() {
            tryVerify(function () { return hHabit.ready }, 3000)
            clearSettings(hHabit)
        }
        function cfg() { return hHabit.storeCtl.settingsFor("test-instance") }

        function test_best_streak_never_below_current() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: [], bestStreak: 5 })
            compare(w.bestStreak, 5, "persisted best survives a lapsed current streak")
            hHabit.storeCtl.patchSettings("test-instance",
                { checkins: consecutiveDays(w, 9, 0), bestStreak: 5 })
            compare(w.bestStreak, 9, "live max wins when current run exceeds stored best")
        }

        function test_reactive_to_store_revision() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { name: "Read", checkins: [] })
            compare(w.name, "Read", "name reads through revision")
            compare(w.streak, 0)
            // External patch (mirrors a Manager setUiState → revision bump).
            hHabit.storeCtl.patchSettings("test-instance",
                { name: "Run", checkins: consecutiveDays(w, 3, 0), bestStreak: 12 })
            compare(w.name, "Run", "name updates reactively")
            compare(w.streak, 3, "streak recomputes reactively")
            compare(w.bestStreak, 12, "bestStreak updates reactively")
            compare(w.doneToday, true, "doneToday updates reactively")
        }

        function test_tick_drives_today_recompute() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: [w.key(new Date())] })
            var before = w.todayKey
            w.tick++
            compare(w.todayKey, before, "todayKey stable across tick (same wall day)")
            compare(w.doneToday, true, "doneToday still reflects today's check-in after tick")
        }

        // BUG (audit line 55): checkins is never pruned, so long-term use bloats
        // the persisted array (only 28 days are ever displayed). Correct
        // behaviour: bounded storage. This assertion is expected to FAIL.
        function test_checkins_storage_is_bounded() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: consecutiveDays(w, 40, 1) })
            w.toggleToday()   // add today → 41 entries and counting
            verify(cfg().checkins.length <= 30,
                   "checkins should be pruned to the displayable window (got "
                   + cfg().checkins.length + ")")
        }
    }

    // ── DST-spanning streak + heatmap mapping ──────────────────────────────
    TestCase {
        name: "HabitDST"
        when: windowShown
        function init() {
            tryVerify(function () { return hHabit.ready }, 3000)
            clearSettings(hHabit)
        }

        // BUG (audit line 37): streakOf() steps days with a fixed 86400000ms,
        // which skips/duplicates a calendar date across a DST boundary when the
        // walk crosses one near local midnight. A fully-consecutive run must
        // count to its exact length. (Passes in non-DST zones / away from
        // midnight; fails when the DST skip lands inside the run.)
        function test_consecutive_run_counts_across_dst() {
            var w = hHabit.item
            // 400 days spans at least one spring-forward and one fall-back.
            var run = consecutiveDays(w, 400, 0)
            compare(w.streakOf(run), run.length,
                    "an unbroken daily run must count every calendar day (DST-safe)")
        }

        // BUG (audit line 122): the heatmap cells use (27-index)*86400000 and can
        // collapse two cells onto one calendar date across a DST boundary. All
        // 28 cells must map to distinct consecutive dates, and exactly one cell
        // (todayKey) carries the "today" border.
        function test_heatmap_28_distinct_days_and_one_today() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: [] })
            wait(0)
            var cells = findCells(w)
            compare(cells.length, 28, "28 heatmap cells rendered")
            var seen = {}, distinct = 0, todayBorders = 0
            for (var i = 0; i < cells.length; i++) {
                if (!seen[cells[i].dk]) { seen[cells[i].dk] = true; distinct++ }
                if (cells[i].dk === w.todayKey && cells[i].border.width >= 2) todayBorders++
            }
            compare(distinct, 28, "all 28 cells map to distinct calendar dates (no DST collision)")
            compare(todayBorders, 1, "exactly one cell carries the today border")
        }

        function test_heatmap_today_cell_reflects_checkin() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: [w.key(new Date())] })
            wait(0)
            var cells = findCells(w)
            var todayCell = null
            for (var i = 0; i < cells.length; i++)
                if (cells[i].dk === w.todayKey) todayCell = cells[i]
            verify(todayCell !== null, "today's cell exists in the grid")
            compare(todayCell.on, true, "today's cell is filled after a check-in")
        }
    }

    // ── Appearance, name, title override ───────────────────────────────────
    TestCase {
        name: "HabitAppearance"
        when: windowShown
        function init() {
            tryVerify(function () { return hHabit.ready }, 3000)
            clearSettings(hHabit)
            hHabit.item.accentName = ""
            hHabit.item.titleOverride = ""
        }

        function test_accent_name_recolors() {
            var w = hHabit.item
            verify(Qt.colorEqual(w.effAccent, hHabit.theme.catProductivity),
                   "defaults to the productivity category accent")
            w.accentName = "green"
            verify(Qt.colorEqual(w.effAccent, hHabit.theme.accentPresets["green"].a),
                   "accentName overrides the effective accent")
            verify(!Qt.colorEqual(w.effAccent, hHabit.theme.catProductivity),
                   "no longer the default accent")
        }

        function test_custom_name_in_header() {
            var w = hHabit.item
            hHabit.storeCtl.setSetting("test-instance", "name", "Meditate")
            compare(w.name, "Meditate")
            compare(w.title, "Meditate", "custom name becomes the header title")
        }
        function test_empty_name_falls_back() {
            var w = hHabit.item
            hHabit.storeCtl.setSetting("test-instance", "name", "")
            compare(w.name, "")
            compare(w.title, "Habit", "empty name falls back to 'Habit'")
        }
        function test_title_override_wins() {
            var w = hHabit.item
            hHabit.storeCtl.setSetting("test-instance", "name", "Meditate")
            w.titleOverride = "Morning Ritual"
            compare(w.title, "Meditate", "widget title still tracks the name")
            // WidgetChrome renders titleOverride when present.
            var texts = root.findAll(w, function (n) {
                return n.hasOwnProperty("text") && String(n.text) === "Morning Ritual"
            }, [])
            verify(texts.length >= 1, "the override string is what actually renders in the header")
        }
    }

    // ── Compact-tile layout (1x1) ──────────────────────────────────────────
    TestCase {
        name: "HabitCompactTile"
        when: windowShown
        function init() {
            tryVerify(function () { return hCompact.ready }, 3000)
            var s = hCompact.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hCompact.storeCtl._touchSettings()
        }

        // BUG (audit line 96): compact content is centerIn:parent inside a
        // clipped body, so on a 1x1 tile the check-in PillButton overflows and is
        // clipped/untappable. It should stay fully within the tile and be
        // touch-sized. This assertion is expected to FAIL on a 150px tile.
        function test_checkin_button_visible_and_tappable() {
            var w = hCompact.item
            var pill = root.findPill(w)
            verify(pill !== null, "check-in pill exists")
            verify(pill.height >= 44, "pill meets the 44px touch minimum (" + pill.height + ")")
            var p = pill.mapToItem(w, 0, 0)
            verify(p.y >= 0 && (p.y + pill.height) <= w.height,
                   "pill fits within the tile (top=" + p.y.toFixed(1)
                   + " bottom=" + (p.y + pill.height).toFixed(1) + " tileH=" + w.height + ")")
        }

        function test_pill_click_checks_in() {
            var w = hCompact.item
            hCompact.storeCtl.patchSettings("test-instance", { checkins: [] })
            compare(w.doneToday, false)
            var pill = root.findPill(w)
            verify(pill !== null)
            mouseClick(pill)
            compare(w.doneToday, true, "tapping the pill records a check-in")
        }
    }

    // ── P1: streak persists past the 28-day heatmap window ─────────────────
    // The streak is a stored NUMBER, decoupled from the pruned `checkins` array,
    // so long runs report their true length and milestones past 14 can fire.
    TestCase {
        name: "HabitLongStreak"
        when: windowShown
        function init() {
            tryVerify(function () { return hHabit.ready }, 3000)
            clearSettings(hHabit)
            hHabit.item.celebrateMsg = ""
            // Reset any overridden today key from a prior test (rebind to now).
            hHabit.item.todayKey = Qt.binding(function () {
                return (hHabit.item.tick, hHabit.item.key(new Date()))
            })
        }
        function cfg() { return hHabit.storeCtl.settingsFor("test-instance") }

        // (a) A 40-consecutive-day streak, accrued via daily check-ins, reports
        // 40 (NOT capped at 28) while the heatmap array stays pruned; best ≥ 40.
        // Days are advanced deterministically by overriding todayKey, never the
        // wall clock.
        function test_forty_day_streak_reports_40_not_28() {
            var w = hHabit.item
            hHabit.storeCtl.patchSettings("test-instance", { checkins: [] })
            // Walk from 39 days ago up to today, checking in each calendar day.
            var d = new Date(); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() - 39)
            for (var i = 0; i < 40; i++) {
                w.todayKey = w.key(d)
                w.toggleToday()
                d.setDate(d.getDate() + 1)
            }
            compare(w.streak, 40, "40 consecutive check-ins report a 40-day streak")
            verify(w.bestStreak >= 40, "bestStreak tracks the full run (got " + w.bestStreak + ")")
            verify(cfg().checkins.length <= 28,
                   "heatmap array is still pruned to its window (got " + cfg().checkins.length + ")")
            compare(cfg().streak, 40, "the streak number is persisted independently")
        }

        // (b) A milestone past 14 (30) is reachable — impossible while the streak
        // was capped at ~28.
        function test_milestone_30_is_reachable() {
            var w = hHabit.item
            var today = w.key(new Date())
            var yesterday = w.prevDayKey(today)
            // Seed a maintained 29-run ending yesterday; today not yet checked.
            hHabit.storeCtl.patchSettings("test-instance",
                { checkins: [], streak: 29, lastCheckinDay: yesterday, bestStreak: 29 })
            compare(w.streak, 29, "grace day: a 29-run ending yesterday still counts")
            w.celebrateMsg = ""
            w.toggleToday()   // check in today → 30
            compare(w.streak, 30, "crossed into a 30-day run")
            compare(w.celebrateMsg, "🏆 30-day milestone!", "30-day milestone celebration fires")
        }

        // (c) A gap (last check-in older than the grace day) resets the streak to
        // 1 on the next check-in, while the best-ever is preserved.
        function test_gap_resets_streak_to_one() {
            var w = hHabit.item
            var d = new Date(); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() - 3)
            var threeAgo = w.key(d)
            hHabit.storeCtl.patchSettings("test-instance",
                { checkins: [threeAgo], streak: 20, lastCheckinDay: threeAgo, bestStreak: 20 })
            compare(w.streak, 0, "a lapsed streak (gap beyond the grace day) reads 0")
            w.celebrateMsg = ""
            w.toggleToday()   // check in today after the gap
            compare(w.streak, 1, "the gap starts a fresh 1-day streak")
            compare(w.bestStreak, 20, "the best-ever streak is preserved across the gap")
            compare(w.celebrateMsg, "🔥 1 day!", "no false milestone on the reset")
        }

        // (d) Checking in when today is already counted is idempotent — it must
        // not double-increment the stored number.
        function test_same_day_checkin_is_idempotent() {
            var w = hHabit.item
            var today = w.key(new Date())
            // Defensive state: streak recorded for today, but today's key absent
            // from the (pruned) array — the check-in branch must still not bump.
            hHabit.storeCtl.patchSettings("test-instance",
                { checkins: [], streak: 5, lastCheckinDay: today, bestStreak: 5 })
            w.toggleToday()   // check-in branch, but today is already the last day
            compare(w.streak, 5, "re-checking the same day does not double-increment")
            compare(w.bestStreak, 5, "best-ever unchanged by an idempotent check-in")
            compare(cfg().streak, 5, "persisted number unchanged")
        }

        // (e) A legacy config that only has a long `checkins` array (no stored
        // streak/lastCheckinDay) derives a sensible initial streak and then keeps
        // maintaining the number forward — no crash, no reset.
        function test_legacy_config_derives_then_maintains() {
            var w = hHabit.item
            // 25-day consecutive run ending today; ONLY the array is stored.
            hHabit.storeCtl.patchSettings("test-instance", { checkins: consecutiveDays(w, 25, 0) })
            verify(cfg().streak === undefined, "legacy: no stored streak number yet")
            compare(w.streak, 25, "legacy streak is derived from the check-in array")
            // Un-check then re-check today: the number is maintained forward.
            w.toggleToday()   // uncheck today → 24
            compare(w.streak, 24, "maintained down to 24 after un-checking today")
            w.toggleToday()   // recheck today → 25
            compare(w.streak, 25, "maintained back to 25, no legacy-derivation reset")
            compare(cfg().streak, 25, "the number is now persisted")
        }
    }

    // ── store == null guard ────────────────────────────────────────────────
    TestCase {
        name: "HabitNullStore"
        when: windowShown
        function init() { tryVerify(function () { return hNull.ready }, 3000) }

        function test_toggle_is_safe_noop_without_store() {
            var w = hNull.item
            w.store = null
            w.celebrateMsg = ""
            compare(w.streak, 0, "no store → empty streak")
            compare(w.doneToday, false)
            w.toggleToday()   // must not throw and must not celebrate
            compare(w.celebrateMsg, "", "no celebration fired without a store")
            compare(w.doneToday, false, "nothing persisted")
            verify(true, "toggleToday did not crash without a store")
        }
    }
}
