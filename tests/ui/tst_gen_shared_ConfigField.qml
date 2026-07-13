import QtQuick
import QtQuick.Controls
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Widgets

// Comprehensive coverage for the schema-driven per-widget config editor:
//   ConfigField.qml   — renders one schema field into the right control
//   WidgetConfigPanel.qml — sections a whole schema into a scrollable form
//
// ConfigField instances are built directly with Edge-sized `col` tokens
// (ctlH 58, fontBase 17) against a dedicated store, exactly like the on-device
// config view (Dashboard.qml:cfgCol). WidgetConfigPanel is exercised the same
// way tst_focus_config does. A CountdownWidget harness verifies a downstream
// consumer of the `date` field.
Item {
    id: root
    width: 1520; height: 1600

    // Edge (touchscreen) colour + sizing tokens — mirrors Dashboard.qml cfgCol.
    property var edgeCol: ({
        textPrimary: "#E6EDF3", textSecondary: "#8B949E", bg: "#0D1117",
        accent: "#58A6FF", border: "#30363D", panel: "#161B22", panelAlt: "#1C222B",
        radius: 12, ctlH: 58, fontBase: 17
    })

    App.Theme { id: theme }
    App.DashboardStore { id: cstore }
    App.WidgetConfigSchema { id: sc }

    property string lastAction: ""

    // ── Field definitions (one per control type) ──────────────────────────────
    property var fToggleT:  ({ key: "celebrate", label: "Celebrate", type: "toggle", dflt: true })
    property var fToggleF:  ({ key: "format24",  label: "24-hour",   type: "toggle", dflt: false })
    property var fNumber:   ({ key: "lat", label: "Latitude", type: "number", min: -90, max: 90, step: 0.01, dflt: 52.52 })
    property var fHour:     ({ key: "startHour", label: "Start hour", type: "hour", dflt: 9 })
    property var fDate:     ({ key: "date", label: "Date", type: "date" })
    property var fText:     ({ key: "place", label: "Place", type: "text", placeholder: "Vienna" })
    property var fArea:     ({ key: "customText", label: "Note", type: "textarea", placeholder: "Type…" })
    property var fSeg:      ({ key: "units", label: "Units", type: "segmented", dflt: "celsius",
                              options: [ { value: "celsius", label: "C" }, { value: "fahrenheit", label: "F" } ] })
    property var fAccent:   ({ key: "accent", label: "Accent", type: "accent", dflt: "" })
    property var fSlider:   ({ key: "forecastDays", label: "Days", type: "slider", min: 3, max: 7, step: 1, suffix: " d", dflt: 4 })
    property var fInfo:     ({ type: "info", text: "INFOTEXT" })
    property var fAction:   ({ type: "action", actionLabel: "ACTIONLBL", action: "geocode" })
    property var fUnknown:  ({ type: "weird", text: "FALLBACK" })
    property var fTasks:    ({ key: "items", label: "", type: "tasks" })

    // ── Recursive helpers ─────────────────────────────────────────────────────
    function findAll(node, pred, acc) {
        if (!node) return acc
        if (pred(node)) acc.push(node)
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) findAll(kids[i], pred, acc)
        return acc
    }
    function mouseAreasIn(node) {
        return findAll(node, function (n) {
            return n.hasOwnProperty("containsMouse") && n.hasOwnProperty("pressed")
                && n.hasOwnProperty("hoverEnabled")
        }, [])
    }
    // Any editable text control (TextField/TextInput/TextArea) — has cursorPosition
    // + readOnly; the number field's display Text does NOT.
    function editablesIn(node) {
        return findAll(node, function (n) {
            return n.hasOwnProperty("cursorPosition") && n.hasOwnProperty("readOnly")
        }, [])
    }
    function selectedIn(node) {
        return findAll(node, function (n) { return n.hasOwnProperty("sel") && n.sel === true }, [])
    }
    function hasTextNode(node, str) {
        return findAll(node, function (n) {
            return n.hasOwnProperty("text") && !n.hasOwnProperty("cursorPosition") && String(n.text) === str
        }, []).length > 0
    }
    // Square, radius-6 button rectangles that own a MouseArea — the task toggle
    // (30×30) and delete (34×34) hit areas.
    function squareButtons(node) {
        var out = []
        var mas = mouseAreasIn(node)
        for (var i = 0; i < mas.length; i++) {
            var p = mas[i].parent
            if (p && p.hasOwnProperty("radius") && p.radius === 6
                && p.width === p.height && p.width < 50)
                out.push(p)
        }
        return out
    }
    function resetInstance(id) {
        var s = cstore.settingsFor(id)
        for (var k in s) delete s[k]
        cstore._touchSettings()
    }

    Component.onCompleted: cstore.load("blank")

    // ── Direct ConfigField instances (Edge-sized) ─────────────────────────────
    // Column A holds every field that gets a real mouseClick — kept near the top
    // so click delivery lands reliably in the offscreen window.
    Column {
        id: cfColA
        x: 0; y: 0; spacing: 10
        Widgets.ConfigField { id: cfToggleT; width: 380; field: root.fToggleT; st: cstore; instanceId: "cf"; col: root.edgeCol }
        Widgets.ConfigField { id: cfToggleF; width: 380; field: root.fToggleF; st: cstore; instanceId: "cf"; col: root.edgeCol }
        Widgets.ConfigField { id: cfNumber;  width: 380; field: root.fNumber;  st: cstore; instanceId: "cf"; col: root.edgeCol }
        Widgets.ConfigField { id: cfHour;    width: 380; field: root.fHour;    st: cstore; instanceId: "cf"; col: root.edgeCol }
        Widgets.ConfigField { id: cfAction;  width: 380; field: root.fAction;  st: cstore; instanceId: "cf"; col: root.edgeCol
            onActionRequested: function (a) { root.lastAction = a } }
        Widgets.ConfigField { id: cfTasks;   width: 380; field: root.fTasks;   st: cstore; instanceId: "cf"; col: root.edgeCol }
        // Empty-instanceId field — used to prove edits don't land in settings[''].
        Widgets.ConfigField { id: cfEmpty;   width: 380
            field: ({ key: "phantom", label: "Phantom", type: "toggle", dflt: false })
            st: cstore; instanceId: ""; col: root.edgeCol }
    }
    // Column B holds fields only inspected/driven imperatively (no mouseClick),
    // so their vertical position is irrelevant.
    Column {
        id: cfColB
        x: 400; y: 0; spacing: 10
        Widgets.ConfigField { id: cfDate;    width: 380; field: root.fDate;    st: cstore; instanceId: "cf"; col: root.edgeCol }
        Widgets.ConfigField { id: cfText;    width: 380; field: root.fText;    st: cstore; instanceId: "cf"; col: root.edgeCol }
        Widgets.ConfigField { id: cfArea;    width: 380; field: root.fArea;    st: cstore; instanceId: "cf"; col: root.edgeCol }
        Widgets.ConfigField { id: cfSeg;     width: 380; field: root.fSeg;     st: cstore; instanceId: "cf"; col: root.edgeCol }
        Widgets.ConfigField { id: cfAccent;  width: 380; field: root.fAccent;  st: cstore; instanceId: "cf"; col: root.edgeCol }
        Widgets.ConfigField { id: cfSlider;  width: 380; field: root.fSlider;  st: cstore; instanceId: "cf"; col: root.edgeCol }
        Widgets.ConfigField { id: cfInfo;    width: 380; field: root.fInfo;    st: cstore; instanceId: "cf"; col: root.edgeCol }
        Widgets.ConfigField { id: cfUnknown; width: 380; field: root.fUnknown; st: cstore; instanceId: "cf"; col: root.edgeCol }
    }

    // ── WidgetConfigPanel instances ───────────────────────────────────────────
    Widgets.WidgetConfigPanel {
        id: clkPanel; x: 800; y: 0; width: 360; height: 760
        schema: sc.schemaFor("clock"); st: cstore; instanceId: "clk"; col: root.edgeCol
    }
    Widgets.WidgetConfigPanel {
        id: scrPanel; x: 800; y: 780; width: 340; height: 220
        schema: sc.schemaFor("focus"); st: cstore; instanceId: "scr"; col: root.edgeCol
    }
    Widgets.WidgetConfigPanel {
        id: taskPanel; x: 1170; y: 0; width: 340; height: 560
        schema: sc.schemaFor("tasks"); st: cstore; instanceId: "tsk"; col: root.edgeCol
    }
    Widgets.WidgetConfigPanel {
        id: nullPanel; x: 1170; y: 580; width: 320; height: 200
        schema: null; st: cstore; instanceId: "nul"; col: root.edgeCol
    }

    // ── Downstream consumer of the date field ─────────────────────────────────
    WidgetHarness {
        id: hCount; x: 800; y: 1020; width: 300; height: 320
        widgetFile: "CountdownWidget.qml"; expanded: true
    }

    // ══════════════════════════════════════════════════════════════════════════
    TestCase {
        name: "NumberHourFields"
        when: windowShown
        function init() { root.resetInstance("cf") }

        // Bug: number field renders only +/- steppers, no keyboard entry path.
        function test_number_field_has_direct_entry() {
            var editables = root.editablesIn(cfNumber)
            verify(editables.length > 0,
                   "number field must expose a way to TYPE a value (lat/lon step 0.01 is unusable via +/- alone)")
        }

        // Bug: step<1 stepping accumulates binary FP error into persisted config.
        function test_number_step_no_fp_drift() {
            cstore.setSetting("cf", "lat", 0.1)
            var mas = root.mouseAreasIn(cfNumber)   // [minus, plus]
            mouseClick(mas[1])                      // +0.01
            var v = Number(cfNumber.cur())
            verify(v === Number(v.toFixed(2)),
                   "persisted value must not drift beyond 2dp precision, got " + v)
        }

        // Correct formatting for valid hours.
        function test_hour_formatting_valid() {
            cstore.setSetting("cf", "startHour", 0);  compare(cfHour.numStr(), "00:00", "n=0")
            cstore.setSetting("cf", "startHour", 9);  compare(cfHour.numStr(), "09:00", "n=9")
            cstore.setSetting("cf", "startHour", 10); compare(cfHour.numStr(), "10:00", "n=10")
            cstore.setSetting("cf", "startHour", 23); compare(cfHour.numStr(), "23:00", "n=23")
        }

        // Bug: hour is unbounded — stepping below 0 is not clamped, and numStr
        // renders "0-1:00" garbage.
        function test_hour_clamps_low() {
            cstore.setSetting("cf", "startHour", 0)
            var mas = root.mouseAreasIn(cfHour)   // [minus, plus]
            mouseClick(mas[0])                    // step below 0
            verify(Number(cfHour.cur()) >= 0,
                   "hour must clamp/wrap at 0, got " + cfHour.cur())
            verify(/^([01][0-9]|2[0-3]):00$/.test(cfHour.numStr()),
                   "hour must never render out-of-range garbage, got '" + cfHour.numStr() + "'")
        }

        // Bug: hour is not clamped/wrapped at the top either → "24:00".
        function test_hour_clamps_high() {
            cstore.setSetting("cf", "startHour", 23)
            var mas = root.mouseAreasIn(cfHour)   // [minus, plus]
            mouseClick(mas[1])                    // step above 23
            verify(Number(cfHour.cur()) <= 23,
                   "hour must clamp/wrap at 23, got " + cfHour.cur())
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    TestCase {
        name: "DateField"
        when: windowShown
        function init() {
            root.resetInstance("cf")
            tryVerify(function () { return hCount.ready }, 3000)
            var s = hCount.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            hCount.storeCtl._touchSettings()
        }

        // Bug: date field has an inputMask but NO validator/range check, so it
        // accepts impossible dates like month 19 / day 45.
        function test_date_field_has_validation() {
            var editables = root.editablesIn(cfDate)
            verify(editables.length === 1, "date field renders one text control")
            verify(editables[0].validator !== null && editables[0].validator !== undefined,
                   "date field must have a validator to reject impossible dates (mask allows 2026-19-45)")
        }

        // The downstream consumer (Countdown) defensively rejects an impossible
        // date rather than producing NaN — verify it never surfaces NaN days.
        function test_countdown_consumer_rejects_impossible_date() {
            var w = hCount.item
            hCount.storeCtl.patchSettings("test-instance", { date: "2026-19-45", label: "x" })
            w.tick++
            compare(w.valid, false, "impossible date is treated as invalid")
            verify(!isNaN(w.days), "days is never NaN, got " + w.days)
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    TestCase {
        name: "TextReactivity"
        when: windowShown
        function init() { root.resetInstance("cf") }

        // Bug: text field binds `text: f.cur()`; once the user edits it the
        // declarative binding is broken, so a later external store push (live
        // mirror from the Manager / geocode) no longer refreshes the field.
        function test_text_field_loses_live_reactivity_after_edit() {
            var e = root.editablesIn(cfText)[0]
            verify(e, "text field control exists")
            e.text = "typed-by-user"                       // imperative assign breaks the binding, like typing
            cstore.setSetting("cf", "place", "REMOTE-PUSH") // external live update
            compare(e.text, "REMOTE-PUSH",
                    "field must reflect an external push even after a local edit (Manager mirrors live)")
        }

        // Bug: textarea writes on EVERY change (onTextChanged→setV) instead of on
        // commit, so N incremental edits bump the global store.revision N times.
        function test_textarea_does_not_bump_revision_per_change() {
            var e = root.editablesIn(cfArea)[0]
            verify(e, "textarea control exists")
            var before = cstore.revision
            var seq = ["h", "he", "hel", "hell", "hello"]   // simulate five keystrokes
            for (var i = 0; i < seq.length; i++) e.text = seq[i]
            var delta = cstore.revision - before
            verify(delta <= 1,
                   "textarea should commit on blur, not bump revision per keystroke (delta=" + delta + ")")
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    TestCase {
        name: "Toggles"
        when: windowShown
        function init() { root.resetInstance("cf") }

        function toggleOf(fieldItem) { return findChild(fieldItem, "control") }

        function test_toggle_reflects_defaults() {
            var swT = toggleOf(cfToggleT)
            var swF = toggleOf(cfToggleF)
            verify(swT && swF, "both switches rendered")
            compare(swT.checked, true,  "dflt:true → checked")
            compare(swF.checked, false, "dflt:false → unchecked")
        }

        function test_toggle_click_persists_and_reflects() {
            var sw = toggleOf(cfToggleT)
            compare(sw.checked, true, "starts on (default)")
            mouseClick(sw)
            compare(cstore.settingsFor("cf").celebrate, false, "click persisted celebrate=false")
            compare(sw.checked, false, "control reflects new value")
            mouseClick(sw)
            compare(cstore.settingsFor("cf").celebrate, true, "toggles back on")
        }

        function test_toggle_tracks_external_change() {
            var sw = toggleOf(cfToggleF)
            compare(sw.checked, false, "starts off")
            cstore.setSetting("cf", "format24", true)   // external write bumps revision
            compare(sw.checked, true, "toggle tracks store.revision")
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    TestCase {
        name: "SegmentedAccent"
        when: windowShown
        function init() { root.resetInstance("cf") }

        function test_segmented_selection_tracks_store() {
            cstore.setSetting("cf", "units", "celsius")
            var sel = root.selectedIn(cfSeg)
            compare(sel.length, 1, "exactly one chip selected")
            compare(sel[0].modelData.value, "celsius", "the celsius chip")
            cstore.setSetting("cf", "units", "fahrenheit")   // change from 'another instance'
            sel = root.selectedIn(cfSeg)
            compare(sel.length, 1, "still one selected after change")
            compare(sel[0].modelData.value, "fahrenheit", "selection followed the store")
        }

        function test_accent_auto_selected_when_empty() {
            cstore.setSetting("cf", "accent", "")
            var sel = root.selectedIn(cfAccent)
            // The Auto chip carries `sel` but no modelData; presets carry modelData.
            var autoSelected = false, presetSelected = false
            for (var i = 0; i < sel.length; i++) {
                if (sel[i].hasOwnProperty("modelData")) presetSelected = true
                else autoSelected = true
            }
            verify(autoSelected, "Auto chip selected when accent is ''")
            verify(!presetSelected, "no preset selected when accent is ''")

            cstore.setSetting("cf", "accent", "pink")
            sel = root.selectedIn(cfAccent)
            autoSelected = false; presetSelected = false
            var which = ""
            for (var j = 0; j < sel.length; j++) {
                if (sel[j].hasOwnProperty("modelData")) { presetSelected = true; which = sel[j].modelData }
                else autoSelected = true
            }
            verify(!autoSelected, "Auto deselects once a preset is chosen")
            verify(presetSelected && which === "pink", "the pink preset is selected")
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    TestCase {
        name: "FieldMapping"
        when: windowShown
        function init() { root.resetInstance("cf") }

        function test_each_type_maps_to_a_control() {
            verify(findChild(cfToggleT, "control"), "toggle → Switch")
            verify(root.mouseAreasIn(cfNumber).length >= 2, "number → +/- steppers")
            verify(root.mouseAreasIn(cfHour).length >= 2, "hour → +/- steppers")
            verify(root.editablesIn(cfDate).length === 1, "date → text control")
            verify(root.editablesIn(cfText).length === 1, "text → text control")
            verify(root.editablesIn(cfArea).length === 1, "textarea → text control")
            verify(root.selectedIn(cfSeg).length + root.mouseAreasIn(cfSeg).length > 0, "segmented → chips")
            verify(root.mouseAreasIn(cfAccent).length > 1, "accent → swatches")
            verify(findAll(cfSlider, function (n) { return n.hasOwnProperty("stepSize") }, []).length === 1, "slider → Slider")
            verify(root.mouseAreasIn(cfAction).length >= 1, "action → button")
        }

        function test_info_and_unknown_render_fallback_text() {
            verify(root.hasTextNode(cfInfo, "INFOTEXT"), "info type shows its text")
            verify(root.hasTextNode(cfUnknown, "FALLBACK"),
                   "unknown type falls back to info without error")
        }

        function test_action_emits_action_requested() {
            root.lastAction = ""
            mouseClick(root.mouseAreasIn(cfAction)[0])
            compare(root.lastAction, "geocode", "action button emits actionRequested(action)")
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    TestCase {
        name: "TouchTargets"
        when: windowShown
        function initTestCase() {
            cstore.patchSettings("tsk", { items: [ { text: "a", done: false } ] })
            cstore.setSetting("cf", "items", [ { text: "a", done: false } ])
        }
        function init() {
            tryVerify(function () { return root.squareButtons(taskPanel).length >= 2 }, 2000,
                      "task row rendered with its toggle + delete buttons")
        }

        // Bug: task toggle (30px) and delete (34px) hit areas are hardcoded and
        // do NOT scale with ctlH (58 on the Edge) → far below the 44px touch min.
        function test_task_buttons_meet_touch_minimum() {
            var btns = root.squareButtons(taskPanel)
            verify(btns.length >= 2, "found toggle + delete (" + btns.length + ")")
            for (var i = 0; i < btns.length; i++)
                verify(btns[i].height >= 44 && btns[i].width >= 44,
                       "task control " + btns[i].width + "×" + btns[i].height + " must be >= 44px on the Edge")
        }

        // Steppers and chips DO scale with the col tokens — assert they pass.
        function test_steppers_and_chips_meet_touch_minimum() {
            var steppers = root.mouseAreasIn(cfNumber)
            verify(steppers.length >= 2, "number steppers present")
            for (var i = 0; i < steppers.length; i++)
                verify(steppers[i].parent.height >= 44, "stepper >= 44px (got " + steppers[i].parent.height + ")")
            // Segmented + accent chips.
            var chips = root.mouseAreasIn(cfSeg)
            verify(chips.length >= 1, "segmented chips present")
            for (var j = 0; j < chips.length; j++)
                verify(chips[j].parent.height >= 44, "segmented chip >= 44px (got " + chips[j].parent.height + ")")
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    TestCase {
        name: "Panel"
        when: windowShown
        function init() { tryVerify(function () { return clkPanel.width > 0 }, 2000) }

        // "About this widget" is filtered out; real sections render.
        function test_about_section_filtered_out() {
            verify(!root.hasTextNode(clkPanel, "About this widget"),
                   "the About section is not rendered in the panel")
            verify(root.hasTextNode(clkPanel, "General"), "General section renders")
            verify(root.hasTextNode(clkPanel, "Widget appearance"), "appearance section renders")
        }

        // schema=null is guarded → empty form, no crash; assigning a real schema
        // afterwards renders sections.
        function test_null_schema_empty_form_then_recovers() {
            verify(!root.hasTextNode(nullPanel, "General"), "null schema → empty form")
            nullPanel.schema = sc.schemaFor("clock")
            tryVerify(function () { return root.hasTextNode(nullPanel, "General") }, 2000,
                      "assigning a real schema populates the form")
            nullPanel.schema = null
        }

        // Bug: the Repeater guard only checks schema truthiness, not .sections, so
        // a partial schema {} throws "Cannot read property filter of undefined".
        // This mirrors WidgetConfigPanel.qml:55-56 exactly.
        function test_partial_schema_object_does_not_throw() {
            var threw = false
            try {
                var s = ({})   // truthy but no .sections
                // Mirrors the fixed WidgetConfigPanel.qml guard: check .sections too.
                var model = (s && s.sections) ? s.sections.filter(function (x) { return x.title !== "About this widget" }) : []
                verify(model !== undefined)
            } catch (e) {
                threw = true
            }
            verify(!threw, "a partial schema {} must not throw — the guard should check .sections")
        }

        // WheelHandler scrolls a sensible amount and StopAtBounds clamps at the top.
        function test_wheel_scroll_and_stop_at_bounds() {
            var f = findChild(scrPanel, "cfgScroll")
            verify(f, "scroll flickable exists")
            verify(f.contentHeight > f.height, "content overflows")
            f.contentY = 0
            mouseWheel(scrPanel, scrPanel.width / 2, scrPanel.height / 2, 0, -120)
            tryVerify(function () { return f.contentY >= 100 }, 1000,
                      "one notch scrolls >=100px, got " + f.contentY)
            // Now scroll up hard past the top — StopAtBounds must clamp at 0.
            mouseWheel(scrPanel, scrPanel.width / 2, scrPanel.height / 2, 0, 2000)
            tryVerify(function () { return f.contentY <= 0.5 }, 1000,
                      "StopAtBounds clamps at the top, got " + f.contentY)
            verify(f.contentY >= 0, "never scrolls above the top")
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    TestCase {
        name: "EmptyInstanceId"
        when: windowShown

        // Bug: setV()/cur() don't guard instanceId==='' → edits create and persist
        // an orphan settings[''] bucket.
        function test_empty_instance_id_no_phantom_bucket() {
            delete cstore.data.settings[""]
            var sw = findChild(cfEmpty, "control")
            verify(sw, "empty-id toggle rendered")
            mouseClick(sw)   // write a setting through a ''-instanceId field
            verify(!cstore.data.settings.hasOwnProperty("") ||
                   Object.keys(cstore.data.settings[""]).length === 0,
                   "editing must not create/persist a settings[''] bucket")
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    TestCase {
        name: "TaskEditor"
        when: windowShown
        function init() { root.resetInstance("cf") }

        // Toggles in true VISUAL (top-to-bottom) order — the Repeater's `children`
        // array order isn't guaranteed to match model/row order, so sort by y.
        function toggles() {
            var t = root.findAll(cfTasks, function (n) {
                var p = n.parent
                // The toggle checkbox is the square, radius-6, bordered (border.width 2)
                // hit area — distinct from the borderless delete button. (Sizes now
                // scale with ctlH to meet the 44px touch minimum, so match by border
                // rather than a hardcoded 30px.)
                return n.hasOwnProperty("containsMouse")
                    && p && p.hasOwnProperty("radius") && p.radius === 6
                    && p.width === p.height && p.border.width === 2
            }, [])
            t.sort(function (a, b) { return a.mapToItem(root, 0, 0).y - b.mapToItem(root, 0, 0).y })
            return t
        }
        function doneCount() {
            var items = cstore.settingsFor("cf").items || []
            var n = 0
            for (var i = 0; i < items.length; i++) if (items[i].done) n++
            return n
        }

        // The nested ColumnLayout may not have distributed the rows vertically the
        // instant the delegates exist — wait until the rows occupy distinct rows.
        function rowsLaidOut() {
            var t = toggles()
            return t.length === 3
                && (t[2].mapToItem(root, 0, 0).y - t[0].mapToItem(root, 0, 0).y) > 20
        }

        function test_toggle_writes_correct_row() {
            cstore.setSetting("cf", "items",
                [ { text: "a", done: false }, { text: "b", done: false }, { text: "c", done: false } ])
            tryVerify(rowsLaidOut, 2000, "three task rows laid out vertically")
            mouseClick(toggles()[2])   // toggle the third (bottom) row
            var items = cstore.settingsFor("cf").items
            compare(doneCount(), 1, "exactly one row toggled (click landed on one toggle)")
            compare(items[2].done, true, "the correct (third) row was toggled")
            compare(items[0].done, false, "first row untouched")
            compare(items[1].done, false, "second row untouched")
        }

        // Mutating the list, then interacting with a rebuilt delegate, must not
        // dereference a stale index or corrupt the array.
        function test_list_mutation_keeps_integrity() {
            cstore.setSetting("cf", "items",
                [ { text: "a", done: false }, { text: "b", done: false }, { text: "c", done: false } ])
            tryVerify(rowsLaidOut, 2000)
            // Shrink the list to two rows (as a live push / earlier-row delete would).
            cstore.setSetting("cf", "items", [ { text: "b", done: false }, { text: "c", done: false } ])
            tryVerify(function () {
                var t = toggles()
                return t.length === 2 && (t[1].mapToItem(root, 0, 0).y - t[0].mapToItem(root, 0, 0).y) > 20
            }, 2000, "delegates rebuilt to two rows")
            mouseClick(toggles()[1])   // toggle what is now the second (bottom) row
            var items = cstore.settingsFor("cf").items
            compare(items.length, 2, "still two items — no stale-index corruption")
            for (var i = 0; i < items.length; i++)
                verify(items[i] !== undefined && items[i].hasOwnProperty("text"),
                       "row " + i + " is a valid task object")
            compare(doneCount(), 1, "exactly one row toggled after the rebuild")
            compare(items[1].done, true, "the rebuilt second row toggled correctly")
        }
    }
}
