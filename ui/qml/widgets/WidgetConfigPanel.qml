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

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 14

            Repeater {
                model: panel.schema ? panel.schema.sections : []
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
