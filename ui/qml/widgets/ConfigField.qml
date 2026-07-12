import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ConfigField — renders a single schema field into the right control. Reads/
// writes live through the shared store, so edits apply immediately (and, in the
// Manager, push to the Edge). `col` carries colour + sizing tokens so the SAME
// component works in the desktop Manager and the on-device (touch) config view.
//
// col keys: textPrimary, textSecondary, bg, accent, border, panelAlt
//           (+ optional ctlH = control height, fontBase = base font size)
Item {
    id: f
    objectName: "field-" + (field.key || field.type || "")   // test hook
    property var field: ({})
    property var st: null        // the store (named 'st' to avoid a self-binding
                                 // collision with the caller's `store` id)
    property string instanceId: ""
    property var col: null
    signal actionRequested(string action)

    // Touch/desktop sizing: larger controls on the Edge, compact in the Manager.
    readonly property real ctlH: (col && col.ctlH) ? col.ctlH : 46
    readonly property real fontBase: (col && col.fontBase) ? col.fontBase : 15

    implicitHeight: body.implicitHeight
    Layout.fillWidth: true

    function cur() {
        if (!st) return field.dflt !== undefined ? field.dflt : ""
        st.revision
        var v = st.settingsFor(instanceId)[field.key]
        if (v !== undefined) return v
        return field.dflt !== undefined ? field.dflt : ""
    }
    function setV(v) { if (st) st.setSetting(instanceId, field.key, v) }
    function numStr() {
        var n = Number(cur())
        if (isNaN(n)) n = 0
        if (field.type === "hour") return (n < 10 ? "0" + n : n) + ":00"
        var s = (field.step && field.step < 1) ? n.toFixed(2) : String(n)
        return s + (field.suffix || "")
    }

    ColumnLayout {
        id: body
        width: f.width
        spacing: 5
        Text {
            visible: field.label !== undefined && field.label !== ""
            text: field.label || ""
            color: f.col.textSecondary; font.pixelSize: f.fontBase - 2
        }
        Text {
            visible: field.help !== undefined && field.help !== ""
            text: field.help || ""
            color: f.col.textSecondary; opacity: 0.8; font.pixelSize: f.fontBase - 3
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        Loader {
            Layout.fillWidth: true
            sourceComponent: {
                switch (field.type) {
                case "text": return textC
                case "textarea": return areaC
                case "number": return numberC
                case "hour": return numberC
                case "slider": return sliderC
                case "toggle": return toggleC
                case "segmented": return segC
                case "date": return dateC
                case "tasks": return tasksC
                case "action": return actionC
                case "info": return infoC
                default: return infoC
                }
            }
        }
    }

    // ── Controls ──
    Component {
        id: textC
        TextField {
            implicitHeight: f.ctlH
            text: f.cur()
            placeholderText: f.field.placeholder || ""
            color: f.col.textPrimary; placeholderTextColor: f.col.textSecondary
            font.pixelSize: f.fontBase
            leftPadding: 12; rightPadding: 12
            background: Rectangle { radius: 8; color: f.col.bg; border.width: 1
                border.color: parent.activeFocus ? f.col.accent : f.col.border }
            onEditingFinished: f.setV(text)
        }
    }
    Component {
        id: areaC
        Rectangle {
            implicitHeight: 150; radius: 8; color: f.col.bg; border.width: 1
            border.color: ta.activeFocus ? f.col.accent : f.col.border
            ScrollView {
                anchors.fill: parent; anchors.margins: 6; clip: true
                TextArea {
                    id: ta
                    text: f.cur(); wrapMode: TextArea.Wrap
                    placeholderText: f.field.placeholder || ""
                    color: f.col.textPrimary; placeholderTextColor: f.col.textSecondary
                    font.pixelSize: f.fontBase; background: null
                    onTextChanged: if (text !== f.cur()) f.setV(text)
                }
            }
        }
    }
    Component {
        id: numberC
        RowLayout {
            spacing: 10
            function step() { return f.field.step || 1 }
            function clamp(v) {
                var lo = f.field.min !== undefined ? f.field.min : -1e9
                var hi = f.field.max !== undefined ? f.field.max : 1e9
                return Math.max(lo, Math.min(hi, v))
            }
            Rectangle {
                Layout.preferredWidth: f.ctlH; Layout.preferredHeight: f.ctlH
                radius: 10; color: dec.pressed ? f.col.accent : f.col.panelAlt; border.width: 1; border.color: f.col.border
                Text { anchors.centerIn: parent; text: "−"; color: f.col.textPrimary; font.pixelSize: 24 }
                MouseArea { id: dec; anchors.fill: parent; onClicked: f.setV(parent.parent.clamp(Number(f.cur()) - parent.parent.step())) }
            }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: f.ctlH; radius: 10
                color: f.col.bg; border.width: 1; border.color: f.col.border
                Text {
                    anchors.centerIn: parent
                    text: f.numStr()
                    color: f.col.textPrimary; font.pixelSize: f.fontBase + 3; font.bold: true
                }
            }
            Rectangle {
                Layout.preferredWidth: f.ctlH; Layout.preferredHeight: f.ctlH
                radius: 10; color: inc.pressed ? f.col.accent : f.col.panelAlt; border.width: 1; border.color: f.col.border
                Text { anchors.centerIn: parent; text: "+"; color: f.col.textPrimary; font.pixelSize: 24 }
                MouseArea { id: inc; anchors.fill: parent; onClicked: f.setV(parent.parent.clamp(Number(f.cur()) + parent.parent.step())) }
            }
        }
    }
    Component {
        id: sliderC
        RowLayout {
            spacing: 12
            Slider {
                Layout.fillWidth: true; implicitHeight: f.ctlH
                from: f.field.min || 0; to: f.field.max || 100; stepSize: f.field.step || 1
                value: Number(f.cur())
                onMoved: f.setV(value)
            }
            Text { text: f.cur() + (f.field.suffix || ""); color: f.col.accent
                font.pixelSize: f.fontBase + 1; font.bold: true; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight }
        }
    }
    Component {
        id: toggleC
        Switch { objectName: "control"; checked: f.cur() === true; onToggled: f.setV(checked) }
    }
    Component {
        id: segC
        Flow {
            spacing: 8
            Repeater {
                model: f.field.options || []
                delegate: Rectangle {
                    required property var modelData
                    width: segLbl.implicitWidth + 30; height: Math.max(44, f.ctlH - 8); radius: 10
                    property bool sel: f.cur() === modelData.value
                    color: sel ? f.col.accent : f.col.panelAlt; border.width: 1
                    border.color: sel ? f.col.accent : f.col.border
                    Text { id: segLbl; anchors.centerIn: parent; text: modelData.label
                        color: sel ? "#0D1117" : f.col.textPrimary; font.pixelSize: f.fontBase - 1 }
                    MouseArea { anchors.fill: parent; onClicked: f.setV(modelData.value) }
                }
            }
        }
    }
    Component {
        id: dateC
        TextField {
            implicitHeight: f.ctlH
            text: f.cur(); inputMask: "9999-99-99"
            placeholderText: "YYYY-MM-DD"
            color: f.col.textPrimary; placeholderTextColor: f.col.textSecondary; font.pixelSize: f.fontBase
            leftPadding: 12
            background: Rectangle { radius: 8; color: f.col.bg; border.width: 1
                border.color: parent.activeFocus ? f.col.accent : f.col.border }
            onEditingFinished: f.setV(text)
        }
    }
    Component {
        id: actionC
        Rectangle {
            implicitHeight: f.ctlH; radius: 10
            color: actMA.pressed ? f.col.accent : f.col.panelAlt
            border.width: 1; border.color: f.col.accent
            Text { anchors.centerIn: parent; text: f.field.actionLabel || "Run"
                color: actMA.pressed ? "#0D1117" : f.col.textPrimary; font.pixelSize: f.fontBase }
            MouseArea { id: actMA; anchors.fill: parent; onClicked: f.actionRequested(f.field.action) }
        }
    }
    Component {
        id: infoC
        Text {
            width: f.width; wrapMode: Text.WordWrap
            text: f.field.text || ""; color: f.col.textSecondary; font.pixelSize: f.fontBase - 2
        }
    }

    // ── Task list editor ──
    Component {
        id: tasksC
        ColumnLayout {
            spacing: 6
            Repeater {
                model: f.cur() || []
                delegate: RowLayout {
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true; spacing: 8
                    Rectangle {
                        width: 30; height: 30; radius: 6
                        color: modelData.done ? f.col.accent : "transparent"
                        border.width: 2; border.color: modelData.done ? f.col.accent : f.col.border
                        Text { anchors.centerIn: parent; visible: modelData.done; text: "✓"; color: "#0D1117"; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: {
                            var a = (f.cur() || []).slice()
                            a[index] = { text: a[index].text, done: !a[index].done }; f.setV(a) } }
                    }
                    TextField {
                        Layout.fillWidth: true; text: modelData.text; implicitHeight: Math.max(36, f.ctlH - 12)
                        color: f.col.textPrimary; font.pixelSize: f.fontBase - 1
                        background: Rectangle { radius: 6; color: f.col.bg; border.width: 1
                            border.color: parent.activeFocus ? f.col.accent : f.col.border }
                        onEditingFinished: {
                            var a = (f.cur() || []).slice()
                            a[index] = { text: text, done: a[index].done }; f.setV(a)
                        }
                    }
                    Rectangle {
                        width: 34; height: 34; radius: 6; color: f.col.panelAlt
                        Text { anchors.centerIn: parent; text: "✕"; color: f.col.textSecondary; font.pixelSize: 15 }
                        MouseArea { anchors.fill: parent; onClicked: {
                            var a = (f.cur() || []).slice(); a.splice(index, 1); f.setV(a) } }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                TextField {
                    id: newTask; Layout.fillWidth: true; placeholderText: "Add a task…"; implicitHeight: Math.max(38, f.ctlH - 10)
                    color: f.col.textPrimary; placeholderTextColor: f.col.textSecondary; font.pixelSize: f.fontBase - 1
                    background: Rectangle { radius: 6; color: f.col.bg; border.width: 1
                        border.color: parent.activeFocus ? f.col.accent : f.col.border }
                    function commit() {
                        if (!text.trim().length) return
                        var a = (f.cur() || []).slice(); a.push({ text: text.trim(), done: false }); f.setV(a); text = ""
                    }
                    onAccepted: commit()
                }
                Rectangle {
                    Layout.preferredWidth: 64; Layout.preferredHeight: Math.max(38, f.ctlH - 10); radius: 8
                    color: addMA.pressed ? f.col.accent : f.col.panelAlt; border.width: 1; border.color: f.col.accent
                    Text { anchors.centerIn: parent; text: "Add"; color: f.col.textPrimary; font.pixelSize: f.fontBase - 1 }
                    MouseArea { id: addMA; anchors.fill: parent; onClicked: newTask.commit() }
                }
            }
        }
    }
}
