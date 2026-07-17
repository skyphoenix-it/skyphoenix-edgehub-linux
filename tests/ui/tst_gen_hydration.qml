import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: schema:glassMl, schema:goal

// Comprehensive coverage for area "widget:hydration" — HydrationWidget.qml.
//
// Exercises every config knob (goal, glassMl), the daily reset / midnight
// projection, streak + goal-crossing maths, celebration replay, colour reward
// logic, clamping, reactivity to store.revision (Manager round-trip), and the
// hydration config schema. Some assertions intentionally encode the CORRECT
// behaviour and therefore FAIL on real bugs flagged in the widget audit
// (streak not credited when the goal is lowered; celebration replays on
// re-cross; the goal-reached colour is invisible with the default accent).
Item {
    id: root
    width: 640; height: 900

    WidgetHarness { id: h; anchors.fill: parent; widgetFile: "HydrationWidget.qml"; expanded: true }

    // Direct schema instance for the shared config-schema area.
    App.WidgetConfigSchema { id: schema }

    // Date helpers, mirroring the widget's yyyy-MM-dd keying.
    function dayKey(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
    function daysAgoKey(n) { var d = new Date(); d.setDate(d.getDate() - n); return dayKey(d) }

    // ── Widget behaviour ─────────────────────────────────────────────────────
    TestCase {
        name: "HydrationWidget"
        when: windowShown

        function cfg() { return h.storeCtl.settingsFor("test-instance") }

        function init() {
            tryVerify(function () { return h.ready }, 3000)
            // Reset accent override + reduceMotion left over from prior tests.
            h.item.accentName = ""
            h.theme.reduceMotion = false
            // Clear all persisted settings for a clean slate.
            var s = cfg()
            for (var k in s) delete s[k]
            h.storeCtl._touchSettings()
        }

        // Convenience: seed a fresh "today, N glasses, goal G" starting state.
        function seed(count, goal) {
            var patch = { day: h.item.todayKey, count: count }
            if (goal !== undefined) patch.goal = goal
            h.storeCtl.patchSettings("test-instance", patch)
        }

        // — Defaults ————————————————————————————————————————————————————
        function test_defaults() {
            var w = h.item
            compare(w.goal, 8, "default goal 8")
            compare(w.glassMl, 250, "default glass size 250 ml")
            compare(w.count, 0, "no settings → 0 glasses today")
            compare(w.streakDisplay, 0, "no streak yet")
        }

        // — Config option: goal honoured + reactive ————————————————————————
        function test_goal_config_honored_and_reactive() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { goal: 12 })
            compare(w.goal, 12, "goal config applied")
            // Manager setUiState round-trip: bumping revision re-reads live.
            h.storeCtl.patchSettings("test-instance", { goal: 5 })
            compare(w.goal, 5, "goal re-applies live on revision bump")
        }

        // — Config option: glassMl honoured in volumeText ————————————————————
        function test_glassml_config_honored() {
            var w = h.item
            seed(6)
            h.storeCtl.patchSettings("test-instance", { glassMl: 300 })
            compare(w.glassMl, 300, "glassMl config applied")
            compare(w.volumeText(), "1.8 L", "6 × 300 ml → 1.8 L")
        }

        // — volumeText ml↔L boundary at 1000 ml ——————————————————————————
        function test_volume_text_liter_boundary() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { glassMl: 250 })
            seed(3)
            compare(w.volumeText(), "750 ml", "750 ml stays ml (< 1000)")
            seed(4)
            compare(w.volumeText(), "1.0 L", "exactly 1000 ml switches to L")
            seed(6)
            compare(w.volumeText(), "1.5 L", "1500 ml → 1.5 L")
        }

        function test_glassml_reactive() {
            var w = h.item
            seed(4)
            h.storeCtl.patchSettings("test-instance", { glassMl: 500 })
            compare(w.volumeText(), "2.0 L", "glassMl change re-applies live")
        }

        // — status string —————————————————————————————————————————————————
        function test_status_string() {
            var w = h.item
            seed(3, 8)
            compare(w.status, "3/8", "status is count/goal")
        }

        // — Clamping ————————————————————————————————————————————————————
        function test_count_clamped_0_to_50() {
            var w = h.item
            w.set(100)
            compare(w.count, 50, "count capped at 50")
            w.set(-5)
            compare(w.count, 0, "count floored at 0")
        }
        function test_goal_clamped_1_to_20() {
            var w = h.item
            w.setGoal(0)
            compare(w.goal, 1, "goal min 1")
            w.setGoal(99)
            compare(w.goal, 20, "goal max 20")
        }

        // — Increment / decrement via set() ————————————————————————————————
        function test_increment_decrement() {
            var w = h.item
            seed(0, 8)
            w.set(w.count + 1); w.set(w.count + 1); w.set(w.count + 1)
            compare(w.count, 3)
            w.set(w.count - 1)
            compare(w.count, 2)
        }

        // — Daily reset: displayed count resets at midnight, stored stays ——————
        function test_midnight_display_reset_keeps_stored() {
            var w = h.item
            // Yesterday's document: 5 glasses on the previous day key.
            h.storeCtl.patchSettings("test-instance", { day: daysAgoKey(1), count: 5, goal: 8 })
            compare(w.count, 0, "displayed count resets when stored day ≠ today")
            // Stored raw settings still hold yesterday's values (display-only reset).
            compare(cfg().count, 5, "stored count still 5 until next interaction")
            compare(cfg().day, daysAgoKey(1), "stored day still yesterday")
        }

        // — First tap after midnight writes today/1, not stored+1 ————————————
        function test_first_tap_after_midnight() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { day: daysAgoKey(1), count: 5, goal: 8 })
            compare(w.count, 0, "starts projected at 0")
            w.set(w.count + 1)   // +1 glass tap
            compare(cfg().count, 1, "first glass writes count=1, not 6")
            compare(cfg().day, w.todayKey, "day rewritten to today")
            compare(w.count, 1)
        }

        // — Streak: fresh goal hit bumps to 1 + sets lastGoalDay ————————————
        function test_fresh_goal_hit_bumps_streak() {
            var w = h.item
            seed(0, 8)
            w.set(8)
            compare(cfg().streak, 1, "fresh goal hit → streak 1")
            compare(cfg().lastGoalDay, w.todayKey, "lastGoalDay set to today")
            compare(w.streakDisplay, 1, "streakDisplay reflects it")
        }

        // — Streak: re-crossing same day does NOT double-increment ——————————
        function test_recross_same_day_no_double_increment() {
            var w = h.item
            seed(0, 8)
            w.set(8)
            compare(cfg().streak, 1)
            w.set(7)   // drop below goal
            w.set(8)   // re-cross
            compare(cfg().streak, 1, "streak stays 1 on same-day re-cross")
        }

        // — Streak: consecutive-day (lastGoalDay===yesterday) increments ——————
        function test_consecutive_day_increments_streak() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance",
                { day: w.todayKey, count: 0, goal: 8, streak: 3, lastGoalDay: w._yesterdayKey() })
            w.set(8)
            compare(cfg().streak, 4, "yesterday+today → streak 3→4")
            compare(cfg().lastGoalDay, w.todayKey)
        }

        // — Streak: a one-day gap resets to 1 ————————————————————————————
        function test_gap_resets_streak_to_1() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance",
                { day: w.todayKey, count: 0, goal: 8, streak: 5, lastGoalDay: daysAgoKey(2) })
            w.set(8)
            compare(cfg().streak, 1, "gap (2 days ago) resets streak to 1")
        }

        // — streakDisplay lapses to 0 when lastGoalDay is stale ————————————
        function test_streak_display_lapses() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { streak: 9, lastGoalDay: daysAgoKey(3) })
            compare(w.streakDisplay, 0, "stale-high streak shows 0 when lapsed")
            // But raw stored streak is unchanged.
            compare(cfg().streak, 9, "stored streak untouched by the display projection")
        }
        function test_streak_display_valid_yesterday() {
            var w = h.item
            h.storeCtl.patchSettings("test-instance", { streak: 4, lastGoalDay: w._yesterdayKey() })
            compare(w.streakDisplay, 4, "yesterday counts as still-alive streak")
        }

        // — set(count) on the highest-filled glass is a no-op (dead tap) ————————
        function test_tapping_highest_glass_is_noop() {
            var w = h.item
            seed(5, 8)
            w.set(5)   // tapping the 5th (index 4) glass → set(index+1)=set(5)
            compare(w.count, 5, "re-setting to the current count changes nothing")
        }

        // — Expanded glass grid: set(i+1) sets count to i+1 ————————————————
        function test_glass_tap_sets_count() {
            var w = h.item
            seed(2, 8)
            w.set(3 + 1)   // tapping the 4th glass (index 3)
            compare(w.count, 4, "tapping glass index i sets count=i+1")
        }

        // — Overfill allowed past goal ————————————————————————————————————
        function test_overfill_allowed() {
            var w = h.item
            seed(0, 8)
            w.set(12)
            compare(w.count, 12, "overfilling past goal is allowed (extra credit)")
        }

        // — accentName override recolours effAccent ————————————————————————
        function test_accent_name_override() {
            var w = h.item
            w.accentName = "purple"
            compare(String(w.effAccent).toLowerCase(),
                    String(h.theme.accentPresets["purple"].a).toLowerCase(),
                    "accentName override drives effAccent")
            w.accentName = ""
        }

        // — With an accent override, goal-reached colour is visibly different ——
        function test_goal_color_change_visible_with_override() {
            var w = h.item
            w.accentName = "red"
            verify(String(w.effAccent) !== String(h.theme.success),
                   "below goal (effAccent) differs from at-goal (success) with a red accent")
            w.accentName = ""
        }

        // — BUG (audit #4): default accent makes the goal-reached colour invisible.
        //   Correct behaviour is that effAccent and success differ so the reward
        //   colour change is perceptible. With the default accent they are the
        //   same byte value, so this fails.
        function test_goal_color_change_visible_by_default() {
            var w = h.item
            verify(String(w.effAccent) !== String(h.theme.success),
                   "default accent must differ from success so hitting the goal recolours the count")
        }

        // — BUG (audit line 49/58): lowering the goal below the current count
        //   should credit the streak / mark the goal reached, but setGoal() only
        //   writes goal and never re-evaluates attainment.
        function test_lowering_goal_credits_streak() {
            var w = h.item
            seed(6, 8)          // 6 glasses, goal 8 (not yet reached, no streak)
            compare(w.streakDisplay, 0, "precondition: no streak yet")
            w.setGoal(5)        // now 6 >= 5 — the goal is met by lowering it
            compare(w.count, 6, "count unchanged")
            compare(w.goal, 5, "goal lowered")
            compare(cfg().lastGoalDay, w.todayKey,
                    "meeting the goal by lowering it should credit lastGoalDay=today")
            compare(w.streakDisplay, 1, "and bump the streak")
        }

        // — BUG (audit line 54): re-crossing the goal the same day replays the
        //   celebration. Correct behaviour: the celebration should not re-fire
        //   (the streak is correctly guarded, but the flash/label are not).
        function test_recross_does_not_replay_celebration() {
            var w = h.item
            seed(0, 8)
            w.set(8)                    // first cross → celebration fires
            w.celebrateMsg = ""         // clear so we can detect a re-fire
            w.set(7)                    // drop below goal (no celebrate)
            w.set(8)                    // re-cross same day
            compare(w.celebrateMsg, "", "re-crossing the goal should not replay the celebration")
        }

        // — reduceMotion path does not break goal crossing (smoke) ————————————
        function test_reduce_motion_smoke() {
            var w = h.item
            h.theme.reduceMotion = true
            seed(0, 8)
            w.set(8)
            compare(cfg().streak, 1, "goal crossing still works with reduceMotion on")
            h.theme.reduceMotion = false
        }

        // — _yesterdayKey is exactly one calendar day before today —————————————
        function test_yesterday_key() {
            var w = h.item
            compare(w._yesterdayKey(), daysAgoKey(1), "yesterday key = today − 1 day")
            verify(w._yesterdayKey() !== w.todayKey, "yesterday differs from today")
            // Well-formed yyyy-MM-dd.
            verify(/^\d{4}-\d{2}-\d{2}$/.test(w._yesterdayKey()), "yesterday key is yyyy-MM-dd")
        }

        // — resetSettings restores catalog defaults + clears streak/glassMl ————
        function test_reset_settings_restores_defaults() {
            var w = h.item
            // Dirty everything.
            h.storeCtl.patchSettings("test-instance",
                { goal: 15, count: 12, day: w.todayKey, glassMl: 500, streak: 7, lastGoalDay: w.todayKey })
            // Reset to the catalog defaults for hydration.
            h.storeCtl.resetSettings("test-instance", { goal: 8, count: 0, day: "" })
            compare(cfg().goal, 8, "goal reset to 8")
            compare(cfg().count, 0, "count reset to 0")
            compare(cfg().day, "", "day reset to empty")
            verify(cfg().streak === undefined, "stale streak dropped")
            verify(cfg().lastGoalDay === undefined, "stale lastGoalDay dropped")
            verify(cfg().glassMl === undefined, "stale glassMl dropped")
            compare(w.goal, 8, "widget reflects reset goal")
            compare(w.glassMl, 250, "glassMl falls back to default 250")
            compare(w.count, 0, "widget reflects reset count (day empty → 0)")
            compare(w.streakDisplay, 0, "streak display cleared")
        }
    }

    // ── Hydration config schema (shared config area, instantiated directly) ────
    TestCase {
        name: "HydrationSchema"
        when: windowShown

        function test_hydration_schema_fields() {
            var s = schema.schemaFor("hydration")
            verify(s && s.sections && s.sections.length > 0, "hydration has sections")
            var goal = null, glassMl = null
            for (var i = 0; i < s.sections.length; i++)
                for (var j = 0; j < (s.sections[i].fields || []).length; j++) {
                    var f = s.sections[i].fields[j]
                    if (f.key === "goal") goal = f
                    if (f.key === "glassMl") glassMl = f
                }
            verify(goal !== null, "schema exposes a goal field")
            compare(goal.type, "number", "goal is a number field")
            compare(goal.min, 1, "goal min 1 matches setGoal clamp")
            compare(goal.max, 20, "goal max 20 matches setGoal clamp")
            compare(goal.dflt, 8, "goal default 8 matches widget default")

            verify(glassMl !== null, "schema exposes a glassMl field")
            compare(glassMl.type, "number", "glassMl is a number field")
            compare(glassMl.dflt, 250, "glassMl default 250 matches widget default")
        }
    }

    // ── Per-sizeClass structure (W1 wave 2b) ────────────────────────────────
    // Fixed-size hosts at the real projected cell footprints.
    Item { width: 348; height: 409
        WidgetHarness { id: yMicro; anchors.fill: parent; widgetFile: "HydrationWidget.qml"; expanded: false } }
    Item { width: 696; height: 819
        WidgetHarness { id: yBase; anchors.fill: parent; widgetFile: "HydrationWidget.qml"; expanded: false } }
    Item { id: yWideWrap; width: 696; height: 409
        WidgetHarness { id: yWide; anchors.fill: parent; widgetFile: "HydrationWidget.qml"; expanded: false } }

    TestCase {
        name: "HydrationSizes"
        when: windowShown

        function seed(host) {
            host.storeCtl.patchSettings(host.instanceId,
                { goal: 8, count: 3, day: Qt.formatDate(new Date(), "yyyy-MM-dd") })
        }
        function findAll(node, pred, acc) {
            if (!node) return acc
            if (pred(node)) acc.push(node)
            var kids = node.children
            for (var i = 0; kids && i < kids.length; i++) findAll(kids[i], pred, acc)
            return acc
        }
        // Every PillButton holds exactly one MouseArea; the button is its parent.
        function pills(host) {
            return findAll(host.item, function (n) {
                return n.hasOwnProperty("label") && n.hasOwnProperty("glyph")
                       && n.hasOwnProperty("primary") && n.visible
            }, [])
        }

        // 0.5x0.5 — the count, and the one tap that matters. Nothing else.
        function test_micro_is_count_plus_one_tap() {
            tryVerify(function () { return yMicro.ready }, 3000)
            var y = yMicro.item
            y.sizeClass = "compact"
            seed(yMicro)
            compare(y.micro, true, "a 348x409 compact box is the micro tile")
            compare(y.showHeader, false, "micro drops the chrome header")
            compare(y.showGrid, false, "micro drops the glass grid — 8 droplets there are mush")
            compare(y.showStreak, false, "…and the streak line")
            verify(y.countPx >= 20, "the count is a readout, not a caption ("
                   + y.countPx.toFixed(0) + "px)")
            // The +1 survives, at a real touch size.
            var p = pills(yMicro)
            compare(p.length, 1, "micro keeps exactly one control: +1")
            compare(p[0].label, "+1", "…and it is the +1")
            verify(p[0].height >= yMicro.theme.touchTertiary,
                   "the +1 is >= touchTertiary (" + p[0].height + " >= "
                   + yMicro.theme.touchTertiary + ") — never shrunk to fit")
        }

        // 1x1 — the grid comes back and scales to the box.
        function test_baseline_earns_the_grid() {
            tryVerify(function () { return yBase.ready }, 3000)
            tryVerify(function () { return yMicro.ready }, 3000)
            yMicro.item.sizeClass = "compact"; seed(yMicro)
            var y = yBase.item
            y.sizeClass = "compact"
            seed(yBase)
            compare(y.micro, false, "a 696x819 baseline tile is not micro")
            compare(y.showGrid, true, "the baseline earns the glass grid")
            verify(y.glassPx > 16, "the droplets scale to the box, past the old fixed 16px ("
                   + y.glassPx.toFixed(0) + ")")
            // Both controls, both real targets.
            var p = pills(yBase)
            compare(p.length, 2, "the baseline carries both − and +1")
            for (var i = 0; i < p.length; i++)
                verify(p[i].height >= yBase.theme.touchTertiary,
                       p[i].label + " is >= touchTertiary (" + p[i].height + ")")
        }

        // wide — the grid moves BESIDE the count/controls; same delegates.
        function test_wide_puts_the_grid_beside_the_controls() {
            tryVerify(function () { return yWide.ready }, 3000)
            var y = yWide.item
            y.sizeClass = "compact"
            seed(yWide)
            var grid = gridOf(yWide)
            compare(grid.columns, 1, "a stacked box is one column")
            var dropBefore = findAll(y, function (n) {
                return n.hasOwnProperty("text") && String(n.text) === "💧" }, [])[0]
            y.sizeClass = "wide"
            compare(y.horiz, true, "wide is the horizontal shape")
            compare(grid.columns, 2, "wide flows the grid beside the controls")
            var dropAfter = findAll(y, function (n) {
                return n.hasOwnProperty("text") && String(n.text) === "💧" }, [])[0]
            verify(dropAfter === dropBefore,
                   "the same droplet object survives the class flip (no rebuild)")
            y.sizeClass = "compact"
        }
        // The content GridLayout: the glass Grid's parent.
        function gridOf(host) {
            var g = findAll(host.item, function (n) {
                return n.hasOwnProperty("horizontalItemAlignment")
                       && n.hasOwnProperty("columns") }, [])[0]
            return g ? g.parent : null
        }
    }

    // ── The overlay's hero actions ──────────────────────────────────────────
    // Remove / Add a glass are deliberately far wider than their text — this is
    // the full-screen view of a one-tap widget. That was written as
    // `implicitWidth: 170` / `240`, i.e. as the BOX rather than as a MINIMUM, so
    // the pill could never grow past it and a longer label would elide inside a
    // button with no reason to be narrow. They are floors now; these assertions
    // pin down BOTH halves of that, because the generosity alone is equally true
    // of the literal it replaced.
    TestCase {
        name: "HydrationOverlayActions"
        when: windowShown

        function initTestCase() { tryVerify(function () { return h.ready }, 3000) }
        function init() { h.theme.textScale = 1.0; settle() }
        // Restore in cleanup(), not inline at the end of the test: a failing
        // verify() aborts the function on the spot, so an inline restore is
        // skipped exactly when it is needed and the relabelled pill leaks into
        // the next test as a second, bogus failure. cleanup() always runs.
        function cleanup() {
            h.theme.textScale = 1.0
            var p = findAll(h.item, function (n) {
                return n.hasOwnProperty("minWidth") && n.hasOwnProperty("glyph")
                       && n.visible && n.minWidth === 170
            }, [])[0]
            if (p) p.label = "Remove"
            settle()
        }
        // A real event-loop turn: a textScale change re-polishes the layout, and
        // wait(0) returns before the new geometry lands. waitForRendering is the
        // wrong tool offscreen — no frame is ever swapped, so it just burns its
        // timeout.
        function settle() { wait(16) }

        function findAll(node, pred, acc) {
            if (!node) return acc
            if (pred(node)) acc.push(node)
            var kids = node.children
            for (var i = 0; kids && i < kids.length; i++) findAll(kids[i], pred, acc)
            return acc
        }
        // The VISIBLE pill carrying a given label — the tile layout's own pills
        // exist alongside these but are hidden while expanded.
        function pillNamed(label) {
            return findAll(h.item, function (n) {
                return n.hasOwnProperty("minWidth") && n.hasOwnProperty("glyph")
                       && n.visible && String(n.label) === label
            }, [])[0] || null
        }
        function labelRun(p) {
            return findAll(p, function (n) {
                return n.hasOwnProperty("elide") && n.hasOwnProperty("baselineOffset")
                       && String(n.text) === String(p.label)
            }, [])[0] || null
        }

        // Half one: the generosity is intact — the pills are still much larger
        // than their text at every reachable text size.
        function test_hero_actions_keep_their_generous_floor() {
            var cases = [ { l: "Remove", w: 170 }, { l: "Add a glass", w: 240 } ]
            var scales = [0.8, 1.0, 1.3, 1.6]
            for (var s = 0; s < scales.length; s++) {
                h.theme.textScale = scales[s]
                settle()
                for (var i = 0; i < cases.length; i++) {
                    var p = pillNamed(cases[i].l)
                    verify(p !== null, cases[i].l + " is present in the overlay")
                    compare(p.minWidth, cases[i].w,
                            cases[i].l + " declares its designed floor")
                    // The RENDERED width, not the implicit hint behind it.
                    verify(p.width >= cases[i].w,
                           cases[i].l + " renders at least its floor at textScale "
                           + scales[s] + " (w=" + p.width.toFixed(1) + ")")
                }
            }
        }

        // Half two, and the half that actually distinguishes the fix: a floor
        // YIELDS to bigger content; `implicitWidth: 170` cannot. The reachable
        // textScale range can never show this — at 1.6 "Remove" wants ~141px and
        // "Add a glass" ~193px, both still under their floors, which is exactly
        // why the literal survived this long. Give the pill a genuinely longer
        // label (what a translation or a relabel does) and the difference is the
        // whole widget.
        function test_hero_actions_grow_for_a_longer_label_instead_of_eliding() {
            h.theme.textScale = 1.6
            settle()
            var p = pillNamed("Remove")
            verify(p !== null, "precondition: the Remove pill")
            // Deliberately NOT "p.width <= minWidth" — that would assert that
            // "Remove" measures under 170px, which is a claim about the font. It
            // holds locally (~141px at textScale 1.6) and almost certainly on CI's
            // DejaVu, but it is exactly the kind of assertion that means two
            // different things on the two machines. The floor holding is
            // font-independent and is all this precondition needs to establish.
            verify(p.width >= p.minWidth,
                   "precondition: the floor is intact at the pill's own label (w="
                   + p.width.toFixed(1) + " floor=" + p.minWidth + ")")

            // A label no reachable textScale can produce from "Remove".
            p.label = "Ein Glas Wasser entfernen"
            settle()
            var row = p.children[0]
            verify(row.implicitWidth + 2 * p._padH > p.minWidth,
                   "precondition: the longer label genuinely outgrows the floor ("
                   + (row.implicitWidth + 2 * p._padH).toFixed(1) + " > " + p.minWidth + ")")
            verify(p.width >= row.implicitWidth + 2 * p._padH - 0.51,
                   "the pill GROWS past its floor to hold the label — the floor is a "
                   + "minimum, not the box (w=" + p.width.toFixed(1) + " content+pad="
                   + (row.implicitWidth + 2 * p._padH).toFixed(1) + ")")
            var lr = labelRun(p)
            verify(lr !== null, "the label run resolves")
            verify(lr.width >= lr.implicitWidth - 0.51,
                   "…so the label renders in full rather than eliding inside a "
                   + "button pinned narrower than its own text (" + lr.width.toFixed(1)
                   + " vs " + lr.implicitWidth.toFixed(1) + ")")
            // (the label is restored by cleanup(), which runs even on failure)
        }
    }
}
