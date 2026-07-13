import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Wg

// Shared touch controls: PillButton + SegmentedControl. Assert selection state,
// clicked / selected signals, disabled state and declarative-binding integrity.
Item {
    id: root
    width: 500; height: 300

    property alias theme: _theme
    App.Theme { id: _theme }

    property int pillClicks: 0
    property var lastSelected: undefined
    property int selectCount: 0

    // External selection source for the segmented control (declarative binding
    // that the control must NOT clobber when a segment is tapped).
    property string mode: "work"

    Column {
        anchors.fill: parent
        Wg.PillButton {
            id: pill
            label: "Start"; glyph: "▶"; primary: true
            onClicked: root.pillClicks++
        }
        Wg.SegmentedControl {
            id: seg
            width: 400; height: 52
            options: [ { label: "Work", value: "work" },
                       { label: "Short", value: "short" },
                       { label: "Long", value: "long" } ]
            currentValue: root.mode
            onSelected: function (v) { root.lastSelected = v; root.selectCount++ }
        }
    }

    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids) for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
    }
    function findAll(node, pred) {
        var out = []
        eachItem(node, function (n) { if (pred(n)) out.push(n) })
        return out
    }
    // Segment delegates carry the distinctive `active` bool alongside modelData.
    function segments() {
        return findAll(seg, function (n) {
            return n.active !== undefined && n.modelData !== undefined && n.radius !== undefined
        })
    }

    TestCase {
        name: "PillButton"
        when: windowShown

        function init() { root.pillClicks = 0; pill.enabledState = true }

        function test_defaults_and_labels() {
            compare(pill.label, "Start", "label stored")
            compare(pill.glyph, "▶", "glyph stored")
            verify(pill.implicitHeight >= _theme.touchTertiary, "meets a touch-sized height")
        }

        function test_clicked_signal_fires() {
            var spy = signalSpy.createObject(root, { target: pill, signalName: "clicked" })
            mouseClick(pill)
            compare(spy.count, 1, "a tap emits clicked once")
            compare(root.pillClicks, 1, "handler ran")
            spy.destroy()
        }

        function test_primary_vs_outline_border() {
            pill.primary = true
            compare(pill.border.width, 0, "primary (filled) button has no outline border")
            pill.primary = false
            compare(pill.border.width, 1, "outline button has a 1px border")
            pill.primary = true
        }

        function test_disabled_blocks_clicks_and_dims() {
            pill.enabledState = false
            compare(pill.opacity, 0.4, "disabled button is dimmed")
            var before = root.pillClicks
            mouseClick(pill)
            compare(root.pillClicks, before, "a disabled button does not fire clicked")
        }

        function test_danger_recolors() {
            pill.danger = true
            verify(Qt.colorEqual(pill._c, _theme.error), "danger uses the error colour")
            pill.danger = false
        }
    }

    TestCase {
        name: "SegmentedControl"
        when: windowShown

        function init() { root.mode = "work"; root.lastSelected = undefined; root.selectCount = 0 }

        function test_options_rendered() {
            compare(segments().length, 3, "one delegate per option")
        }

        function test_current_value_marks_active_segment() {
            var segs = segments()
            var active = segs.filter(function (s) { return s.active })
            compare(active.length, 1, "exactly one active segment")
            compare(seg._val(active[0].modelData), "work", "the active segment matches currentValue")
        }

        function test_selected_signal_emits_value_without_clobbering_binding() {
            var target = null
            var segs = segments()
            for (var i = 0; i < segs.length; i++)
                if (seg._val(segs[i].modelData) === "short") target = segs[i]
            verify(target !== null, "found the 'short' segment")
            mouseClick(target)
            compare(root.selectCount, 1, "selected fired once")
            compare(root.lastSelected, "short", "selected carried the tapped value")
            // The control must NOT imperatively assign currentValue — the external
            // binding (root.mode) still governs it (S2 self-destruct guard).
            compare(seg.currentValue, "work", "currentValue still follows the external binding, not the tap")
        }

        function test_external_state_change_moves_selection() {
            root.mode = "long"
            var segs = segments()
            var active = segs.filter(function (s) { return s.active })
            compare(active.length, 1, "still exactly one active segment")
            compare(seg._val(active[0].modelData), "long", "selection follows an external state change")
        }

        function test_string_options_supported() {
            seg.options = ["a", "b"]
            seg.currentValue = "b"
            var segs = segments()
            compare(segs.length, 2, "plain-string options render")
            var active = segs.filter(function (s) { return s.active })
            compare(seg._val(active[0].modelData), "b", "string option can be active")
            // restore
            seg.options = [ { label: "Work", value: "work" },
                            { label: "Short", value: "short" },
                            { label: "Long", value: "long" } ]
            seg.currentValue = Qt.binding(function () { return root.mode })
        }
    }

    Component { id: signalSpy; SignalSpy {} }
}
