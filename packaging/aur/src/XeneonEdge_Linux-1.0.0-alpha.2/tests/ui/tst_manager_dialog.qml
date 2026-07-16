import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as W

// Reproduces the Edge Manager's config DIALOG structure — a Controls Dialog whose
// contentItem holds the shared WidgetConfigPanel — and drives it with real clicks
// + wheel, to catch bugs that only appear inside the Dialog wrapper (which the
// isolated panel test cannot). This is "the config options in the Manager".
Item {
    id: root
    width: 1000; height: 760

    property var col: ({ textPrimary: "#E6EDF3", textSecondary: "#8B949E", bg: "#0D1117",
        accent: "#58A6FF", border: "#30363D", panel: "#161B22", panelAlt: "#1C222B",
        radius: 10, ctlH: 46 })

    App.Theme { id: theme }
    App.DashboardStore { id: store }
    App.WidgetConfigSchema { id: sc }

    // Match the real WidgetConfigDialog: a RowLayout contentItem holding an
    // INTERACTIVE preview widget beside the WidgetConfigPanel.
    Dialog {
        id: dlg
        anchors.centerIn: parent
        width: 900; height: 640
        modal: true
        standardButtons: Dialog.Close
        contentItem: RowLayout {
            spacing: 18
            ColumnLayout {
                Layout.preferredWidth: 320; Layout.maximumWidth: 320; Layout.fillHeight: true
                // Mirrors WidgetConfigDialog's WYSIWYG preview: render the expanded
                // widget at the Edge content width (logicalW) and scale it down to fit
                // the narrow pane, so multi-button action rows don't overflow + clip.
                Item {
                    id: previewClip
                    objectName: "previewClip"
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    readonly property real logicalW: 688
                    readonly property real fit: width > 0 ? width / logicalW : 1
                    Item {
                        id: previewScaler
                        objectName: "previewScaler"
                        width: previewClip.logicalW
                        height: previewClip.fit > 0 ? previewClip.height / previewClip.fit : previewClip.height
                        transformOrigin: Item.TopLeft
                        scale: previewClip.fit
                        Loader {
                            anchors.fill: parent
                            source: "../../ui/qml/widgets/FocusWidget.qml"
                            onLoaded: {
                                if (!item) return
                                store.ensureSettings("t", {})
                                item.instanceId = "t"; item.store = store; item.expanded = true
                                if (item.hasOwnProperty("active")) item.active = true
                                if (item.hasOwnProperty("showHeader")) item.showHeader = false
                            }
                        }
                    }
                }
            }
            W.WidgetConfigPanel {
                id: panel
                Layout.fillWidth: true; Layout.fillHeight: true
                schema: sc.schemaFor("focus"); st: store; instanceId: "t"; col: root.col
            }
        }
    }

    TestCase {
        name: "ManagerConfigDialog"
        when: windowShown

        function initTestCase() { store.load("blank"); store.ensureSettings("t", {}) }
        function init() { if (!dlg.opened) dlg.open(); tryVerify(function () { return dlg.opened && panel.width > 0 }, 2000) }

        function cfg() { return store.settingsFor("t") }
        function toggleOf(key) { return findChild(findChild(panel, "field-" + key), "control") }

        // Phase 1c: the scaled preview renders the 688px-wide expanded widget but its
        // ON-SCREEN width (logicalW * scale) must fit inside the pane — no horizontal
        // overflow/clip of the Focus 4-button action row.
        function test_preview_content_not_clipped() {
            var clip = findChild(dlg.contentItem, "previewClip")
            var scaler = findChild(dlg.contentItem, "previewScaler")
            verify(clip && scaler, "scaled preview present")
            verify(clip.width > 0, "pane has width")
            var onScreen = scaler.width * scaler.scale
            verify(onScreen <= clip.width + 1,
                   "scaled content (" + onScreen + ") fits pane (" + clip.width + ")")
            verify(scaler.scale < 1, "wide expanded widget is scaled down, got " + scaler.scale)
        }

        // A toggle near the TOP of the form (visible without scrolling).
        function test_top_toggle_clicks_inside_dialog() {
            var sw = toggleOf("autoStartBreak")
            verify(sw, "autoStartBreak toggle rendered in the dialog")
            var before = sw.checked
            mouseClick(sw)
            verify(sw.checked !== before, "toggle flipped on click inside the Dialog")
            compare(cfg().autoStartBreak, sw.checked, "persisted to the store")
        }

        // Scrolling must work INSIDE the Dialog so lower options are reachable
        // (the form is taller than the dialog — "clipped, can't reach the rest").
        function test_scroll_works_inside_dialog() {
            var f = findChild(panel, "cfgScroll")
            verify(f, "scroll flickable exists")
            verify(f.contentHeight > f.height, "form overflows the dialog (so scroll matters)")
            f.contentY = 0
            mouseWheel(panel, panel.width / 2, panel.height / 2, 0, -120)
            tryVerify(function () { return f.contentY >= 100 }, 1000,
                      "wheel scrolls inside the dialog, got " + f.contentY)
        }

        // A control that requires scrolling: scroll it into view, then click it.
        function test_lower_control_reachable_and_clickable() {
            var f = findChild(panel, "cfgScroll")
            var rp = findChild(panel, "field-rewardPoints")
            verify(rp, "rewardPoints field exists")
            // Scroll so the field sits ~centre of the viewport (not past it).
            var vy = rp.mapToItem(f, 0, 0).y
            f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY + vy - f.height / 2))
            wait(100)
            var sw = toggleOf("rewardPoints")
            verify(sw, "rewardPoints toggle exists")
            verify(sw.height > 0, "toggle has size")
            var before = sw.checked
            mouseClick(sw)
            verify(sw.checked !== before, "a scrolled-into-view control is clickable, was " + before)
            compare(cfg().rewardPoints, sw.checked, "persisted to the store")
        }
    }
}
