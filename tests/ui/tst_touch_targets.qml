import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as W

// Enforces the "larger buttons / good touch UX" requirement: the shared controls
// and the redesigned Media transport meet the design-system touch minimums.
Item {
    id: root
    width: 500; height: 400
    property alias theme: _theme
    App.Theme { id: _theme }

    W.PillButton { id: pill; label: "Test"; glyph: "▶" }
    W.SegmentedControl { id: seg; width: 300
        options: [ { label: "A", value: "a" }, { label: "B", value: "b" } ] }

    WidgetHarness { id: hMedia; anchors.fill: parent; widgetFile: "MediaWidget.qml"; expanded: true }

    function findAll(node, pred, acc) {
        if (!node) return acc
        if (pred(node)) acc.push(node)
        var kids = node.children
        for (var i = 0; kids && i < kids.length; i++) findAll(kids[i], pred, acc)
        return acc
    }

    TestCase {
        name: "TouchTargets"
        when: windowShown

        function test_pillbutton_min_height() {
            verify(pill.implicitHeight >= 44, "PillButton height " + pill.implicitHeight + " >= 44")
            compare(pill.implicitHeight, root.theme.touchSecondary)
        }
        function test_segmented_min_height() {
            verify(seg.implicitHeight >= 44, "SegmentedControl height " + seg.implicitHeight + " >= 44")
        }
        function test_media_transport_are_touch_sized() {
            tryVerify(function () { return hMedia.ready }, 3000)
            hMedia.mediaCtl.loadTrack("Song", "Artist")
            wait(32)
            // Every circular transport button holds exactly one MouseArea; collect
            // the button rectangles (a MouseArea's parent) and check their size.
            var mouseAreas = root.findAll(hMedia.item, function (n) {
                return n.hasOwnProperty("pressed") && n.hasOwnProperty("containsMouse")
            }, [])
            verify(mouseAreas.length >= 3, "found transport controls (" + mouseAreas.length + ")")
            var sized = 0
            for (var i = 0; i < mouseAreas.length; i++) {
                var p = mouseAreas[i].parent
                if (p && p.width >= 44 && p.height >= 44) sized++
            }
            verify(sized >= 3, "at least prev/play/next are >=44px touch targets (" + sized + ")")
        }
    }
}
