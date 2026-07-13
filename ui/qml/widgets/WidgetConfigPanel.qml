import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// WidgetConfigPanel — renders a widget's config schema into a professional,
// sectioned, scrollable form. Shared by the on-device (hub) config view and the
// desktop Manager so both stay identical. Each field reads/writes live through
// the store, so edits apply immediately.
//
// Required: schema, store, instanceId, col (colour+sizing tokens for ConfigField
// + section chrome: panel, border, textPrimary, textSecondary, radius).
Item {
    id: panel
    property var schema: ({ sections: [] })
    property var store: null
    property string instanceId: ""
    property var col: null
    property string statusText: ""      // e.g. geocode result, shown under the form
    signal actionRequested(string action)

    // A plain Flickable (not ScrollView) so the mouse-wheel step is fully under
    // our control — the default was tiny ("~10px per scroll"). A WheelHandler as a
    // direct child intercepts the wheel and moves a sensible amount per notch,
    // handling both mice (angleDelta) and trackpads (pixelDelta). pressDelay 0 +
    // StopAtBounds keeps controls feeling instantly clickable, never draggy.
    Flickable {
        id: scroll
        objectName: "cfgScroll"
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: formCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        pressDelay: 0
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function (ev) {
                var dy = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y
                var maxY = Math.max(0, scroll.contentHeight - scroll.height)
                scroll.contentY = Math.max(0, Math.min(maxY, scroll.contentY - dy * 1.1))
                ev.accepted = true
            }
        }

        ColumnLayout {
            id: formCol
            width: scroll.width
            spacing: 14

            Repeater {
                // The "About this widget" section duplicates the header description
                // shown above the panel, so don't render it here.
                model: (panel.schema && panel.schema.sections)
                       ? panel.schema.sections.filter(function (s) { return s.title !== "About this widget" })
                       : []
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    radius: (panel.col && panel.col.radius) ? panel.col.radius : 12
                    color: panel.col.panel
                    border.width: 1; border.color: panel.col.border
                    implicitHeight: sectionCol.implicitHeight + 28

                    ColumnLayout {
                        id: sectionCol
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: 14; spacing: 12

                        Text {
                            text: modelData.title || ""
                            color: panel.col.textPrimary; font.pixelSize: 16; font.bold: true
                            visible: (modelData.title || "").length > 0
                        }
                        Text {
                            text: modelData.desc || ""
                            color: panel.col.textSecondary; font.pixelSize: 13
                            wrapMode: Text.WordWrap; Layout.fillWidth: true
                            visible: (modelData.desc || "").length > 0
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: modelData.cols || 1
                            columnSpacing: 16; rowSpacing: 14
                            Repeater {
                                model: modelData.fields || []
                                delegate: ConfigField {
                                    required property var modelData
                                    field: modelData
                                    st: panel.store
                                    instanceId: panel.instanceId
                                    col: panel.col
                                    onActionRequested: (a) => panel.actionRequested(a)
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: panel.statusText.length > 0
                text: panel.statusText; color: panel.col.textSecondary; font.pixelSize: 13
                Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
        }
    }
}
