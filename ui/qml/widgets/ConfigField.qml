import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ConfigField - renders a single schema field into the right control. Reads/
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
    function setV(v) { if (st && instanceId !== "") st.setSetting(instanceId, field.key, v) }
    // Text legible on an accent fill. Prefer a theme token so a dark accent can't
    // make selected/on labels vanish; fall back to the historic literal.
    function onAccent() { return (col && col.textOnAccent) ? col.textOnAccent : "#0D1117" }
    // Tasks values are user/IPC-sourced - coerce to an array so a corrupt (non-array)
    // stored value renders as empty instead of throwing on .slice()/Repeater.
    function curTasks() { var v = cur(); return Array.isArray(v) ? v : [] }
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
                case "accent": return accentC
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
            id: txtIn
            implicitHeight: f.ctlH
            text: f.cur()
            placeholderText: f.field.placeholder || ""
            color: f.col.textPrimary; placeholderTextColor: f.col.textSecondary
            font.pixelSize: f.fontBase
            leftPadding: 12; rightPadding: 12
            background: Rectangle { radius: 8; color: f.col.bg; border.width: 1
                border.color: parent.activeFocus ? f.col.accent : f.col.border }
            onEditingFinished: f.setV(text)
            // S2: typing severs the `text:` binding, so re-assert from the store on
            // any external push (Manager live mirror / geocode) when not being edited.
            Connections { target: f.st
                function onRevisionChanged() { if (!txtIn.activeFocus) txtIn.text = f.cur() } }
        }
    }
    Component {
        id: areaC
        Rectangle {
            implicitHeight: 150; radius: 8; color: f.col.bg; border.width: 1
            border.color: ta.activeFocus ? f.col.accent : f.col.border
            ScrollView {
                anchors.fill: parent; anchors.margins: 6; clip: true
                // Dark, token-styled scrollbar (default Fusion bar clashes on the dark UI).
                ScrollBar.vertical: ScrollBar {
                    id: areaSb
                    contentItem: Rectangle {
                        implicitWidth: 5; radius: 3
                        color: areaSb.pressed ? f.col.accent : f.col.border
                        opacity: areaSb.active ? 0.9 : 0.35
                    }
                    background: Rectangle {
                        implicitWidth: 5; radius: 3; color: f.col.panelAlt
                        opacity: areaSb.active ? 0.4 : 0
                    }
                }
                TextArea {
                    id: ta
                    text: f.cur(); wrapMode: TextArea.Wrap
                    placeholderText: f.field.placeholder || ""
                    color: f.col.textPrimary; placeholderTextColor: f.col.textSecondary
                    font.pixelSize: f.fontBase; background: null
                    // Commit on blur, not on every keystroke - otherwise each character
                    // bumps store.revision and re-runs every revision-bound binding.
                    onActiveFocusChanged: if (!activeFocus && text !== f.cur()) f.setV(text)
                    // S2: re-assert from the store on external pushes when not editing.
                    Connections { target: f.st
                        function onRevisionChanged() { if (!ta.activeFocus) ta.text = f.cur() } }
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
                var isHour = f.field.type === "hour"
                var lo = f.field.min !== undefined ? f.field.min : (isHour ? 0 : -1e9)
                var hi = f.field.max !== undefined ? f.field.max : (isHour ? 23 : 1e9)
                return Math.max(lo, Math.min(hi, v))
            }
            // Snap to the field's step precision so sub-1 steps (lat/lon, 0.01)
            // don't accumulate binary FP error into the persisted config.
            function snap(v) {
                var s = step()
                if (s < 1) {
                    var frac = String(s).split(".")[1]
                    return Number(v.toFixed(frac ? frac.length : 2))
                }
                return Math.round(v)
            }
            Rectangle {
                Layout.preferredWidth: f.ctlH; Layout.preferredHeight: f.ctlH
                radius: 10; color: dec.pressed ? f.col.accent : f.col.panelAlt; border.width: 1; border.color: f.col.border
                AppIcon { anchors.centerIn: parent; name: "ui-minus"; size: 18; color: f.col.textPrimary }
                MouseArea { id: dec; anchors.fill: parent; onClicked: f.setV(parent.parent.snap(parent.parent.clamp(Number(f.cur()) - parent.parent.step()))) }
            }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: f.ctlH; radius: 10
                color: f.col.bg; border.width: 1
                border.color: numIn.activeFocus ? f.col.accent : f.col.border
                // Keyboard entry path - steppers alone can't reach e.g. lat/lon at
                // step 0.01. Typed input is parsed, clamped and snapped on commit.
                TextField {
                    id: numIn
                    anchors.fill: parent
                    text: f.numStr()
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    color: f.col.textPrimary; font.pixelSize: f.fontBase + 3; font.bold: true
                    background: null; selectByMouse: true
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    onEditingFinished: {
                        var raw = String(text)
                        var n = (f.field.type === "hour") ? parseInt(raw, 10)
                                                          : parseFloat(raw.replace(/[^0-9.eE+\-]/g, ""))
                        // Reject NaN AND non-finite (e.g. "1e400" → Infinity) before
                        // clamp/snap, so a bad parse can't persist ±Infinity.
                        if (!isFinite(n)) { text = f.numStr(); return }
                        f.setV(parent.parent.snap(parent.parent.clamp(n)))
                    }
                    // S2: re-assert the display after a stepper/external push (typing
                    // severs the `text:` binding).
                    Connections { target: f.st
                        function onRevisionChanged() { if (!numIn.activeFocus) numIn.text = f.numStr() } }
                }
            }
            Rectangle {
                Layout.preferredWidth: f.ctlH; Layout.preferredHeight: f.ctlH
                radius: 10; color: inc.pressed ? f.col.accent : f.col.panelAlt; border.width: 1; border.color: f.col.border
                AppIcon { anchors.centerIn: parent; name: "ui-plus"; size: 18; color: f.col.textPrimary }
                MouseArea { id: inc; anchors.fill: parent; onClicked: f.setV(parent.parent.snap(parent.parent.clamp(Number(f.cur()) + parent.parent.step()))) }
            }
        }
    }
    Component {
        id: sliderC
        RowLayout {
            spacing: 12
            Slider {
                id: sld
                objectName: "control"
                Layout.fillWidth: true; implicitHeight: f.ctlH
                from: f.field.min || 0; to: f.field.max || 100; stepSize: f.field.step || 1
                value: Number(f.cur())
                onMoved: f.setV(value)
                // Dark groove + accent-filled portion (mirrors the MSwitch/MButton
                // token look instead of the pale default Fusion slider).
                background: Rectangle {
                    objectName: "groove"
                    x: sld.leftPadding; y: sld.topPadding + sld.availableHeight / 2 - height / 2
                    width: sld.availableWidth; height: 6; radius: 3
                    color: f.col.panelAlt
                    Rectangle {
                        objectName: "grooveFill"
                        width: sld.visualPosition * parent.width; height: parent.height
                        radius: 3; color: f.col.accent
                    }
                }
                handle: Rectangle {
                    objectName: "handle"
                    x: sld.leftPadding + sld.visualPosition * (sld.availableWidth - width)
                    y: sld.topPadding + sld.availableHeight / 2 - height / 2
                    width: 20; height: 20; radius: 10
                    color: sld.pressed ? Qt.lighter(f.col.accent, 1.15) : f.col.accent
                    border.width: 1; border.color: f.col.border
                }
            }
            Text { text: f.cur() + (f.field.suffix || ""); color: f.col.accent
                font.pixelSize: f.fontBase + 1; font.bold: true; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight }
        }
    }
    Component {
        id: toggleC
        // Token-styled toggle mirroring the Manager's MSwitch: accent track when on,
        // dark panelAlt track when off, so it matches the app design in both hosts
        // instead of the pale default Fusion switch. Behaviour/signals unchanged.
        Switch {
            id: sw
            objectName: "control"
            checked: f.cur() === true
            onToggled: f.setV(checked)
            implicitHeight: f.ctlH
            padding: 0
            indicator: Rectangle {
                objectName: "track"
                implicitHeight: Math.max(26, f.ctlH * 0.5)
                implicitWidth: implicitHeight * 1.85
                x: sw.leftPadding; anchors.verticalCenter: parent.verticalCenter
                radius: height / 2
                color: sw.checked ? f.col.accent : f.col.panelAlt
                border.width: 1; border.color: sw.checked ? f.col.accent : f.col.border
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle {
                    objectName: "knob"
                    width: parent.height - 6; height: width; radius: height / 2
                    y: 3
                    x: sw.checked ? parent.width - width - 3 : 3
                    color: sw.checked ? f.onAccent() : f.col.textSecondary
                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
    Component {
        id: segC
        // A JOINED segmented control (one bordered track, segments inside), matching
        // the Manager's MSegment and the app's SegmentedControl - reads as "pick one
        // of a set" rather than the old row of loose pills. Selected = accent fill;
        // uses the shared f.col tokens so it themes for both the hub and the Manager.
        Rectangle {
            // Track wraps the segments (content-sized, +6 for the 3px margins) rather
            // than the segments filling the track - so each chip keeps its explicit
            // touch height even where the parent has no resolved height (e.g. a config
            // column that sizes to content), exactly like the accent swatches.
            implicitHeight: segRow.implicitHeight + 6
            radius: 10
            color: f.col.bg
            border.width: 1; border.color: f.col.border
            RowLayout {
                id: segRow
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 3; anchors.rightMargin: 3; spacing: 3
                Repeater {
                    model: f.field.options || []
                    delegate: Rectangle {
                        required property var modelData
                        // Explicit touch height (>= 44px), independent of the parent -
                        // the width still fills the track evenly across the segments.
                        Layout.fillWidth: true
                        implicitHeight: Math.max(44, f.ctlH - 2)
                        radius: 8
                        property bool sel: f.cur() === modelData.value
                        color: sel ? f.col.accent
                                   : (segMA.containsMouse ? f.col.panelAlt : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: segMA.pressed ? 0.97 : 1.0
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        Text {
                            anchors.centerIn: parent; text: modelData.label
                            width: parent.width - 8; horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            color: parent.sel ? f.onAccent() : f.col.textPrimary
                            font.pixelSize: f.fontBase - 1; font.bold: parent.sel
                        }
                        MouseArea { id: segMA; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: f.setV(modelData.value) }
                    }
                }
            }
        }
    }
    // Accent-colour swatches (theme presets) + a "Default" (no override) chip.
    Component {
        id: accentC
        Flow {
            spacing: 8
            Rectangle {
                width: f.ctlH; height: f.ctlH; radius: 10
                property bool sel: f.cur() === "" || f.cur() === undefined
                color: f.col.panelAlt; border.width: sel ? 3 : 1
                border.color: sel ? f.col.accent : f.col.border
                Text { anchors.centerIn: parent; text: "Auto"; color: f.col.textSecondary; font.pixelSize: f.fontBase - 4 }
                MouseArea { anchors.fill: parent; onClicked: f.setV("") }
            }
            Repeater {
                model: Object.keys(theme.accentPresets)
                delegate: Rectangle {
                    required property var modelData
                    width: f.ctlH; height: f.ctlH; radius: 10
                    property bool sel: f.cur() === modelData
                    color: theme.accentPresets[modelData].a
                    border.width: sel ? 3 : 1; border.color: sel ? "#FFFFFF" : f.col.border
                    MouseArea { anchors.fill: parent; onClicked: f.setV(modelData) }
                }
            }
        }
    }
    Component {
        id: dateC
        TextField {
            id: dateIn
            implicitHeight: f.ctlH
            text: f.cur(); inputMask: "9999-99-99"
            placeholderText: "YYYY-MM-DD"
            color: f.col.textPrimary; placeholderTextColor: f.col.textSecondary; font.pixelSize: f.fontBase
            leftPadding: 12
            // The mask restricts to digits but still allows impossible dates
            // (2026-19-45); the validator rejects out-of-range month/day and keeps
            // partial input in the Intermediate state (feedback, not committed).
            validator: RegularExpressionValidator {
                regularExpression: /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/ }
            background: Rectangle { radius: 8; color: f.col.bg; border.width: 1
                border.color: parent.activeFocus ? f.col.accent : f.col.border }
            onEditingFinished: f.setV(text)
            // S2: re-assert from the store on external pushes when not editing.
            Connections { target: f.st
                function onRevisionChanged() { if (!dateIn.activeFocus) dateIn.text = f.cur() } }
        }
    }
    Component {
        id: actionC
        Rectangle {
            implicitHeight: f.ctlH; radius: 10
            color: actMA.pressed ? f.col.accent : f.col.panelAlt
            border.width: 1; border.color: f.col.accent
            Text { anchors.centerIn: parent; text: f.field.actionLabel || "Run"
                color: actMA.pressed ? f.onAccent() : f.col.textPrimary; font.pixelSize: f.fontBase }
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
                model: f.curTasks()
                delegate: RowLayout {
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true; spacing: 8
                    Rectangle {
                        // Scale with ctlH but keep >= 44px touch minimum on the Edge.
                        width: Math.min(48, Math.max(44, f.ctlH - 14)); height: width; radius: 6
                        color: modelData.done ? f.col.accent : "transparent"
                        border.width: 2; border.color: modelData.done ? f.col.accent : f.col.border
                        AppIcon { anchors.centerIn: parent; visible: modelData.done; name: "ui-check"; size: 16; color: f.onAccent() }
                        MouseArea { anchors.fill: parent; onClicked: {
                            var a = f.curTasks().slice()
                            if (!a[index]) return   // guard a corrupt/stale row
                            a[index] = { text: a[index].text, done: !a[index].done }; f.setV(a) } }
                    }
                    TextField {
                        Layout.fillWidth: true; text: modelData.text; implicitHeight: Math.max(36, f.ctlH - 12)
                        color: f.col.textPrimary; font.pixelSize: f.fontBase - 1
                        background: Rectangle { radius: 6; color: f.col.bg; border.width: 1
                            border.color: parent.activeFocus ? f.col.accent : f.col.border }
                        onEditingFinished: {
                            var a = f.curTasks().slice()
                            if (!a[index]) return   // row vanished (live push) - drop the edit
                            a[index] = { text: text, done: a[index].done }; f.setV(a)
                        }
                    }
                    Rectangle {
                        // Scale with ctlH but keep >= 44px touch minimum on the Edge.
                        width: Math.min(48, Math.max(44, f.ctlH - 12)); height: width; radius: 6; color: f.col.panelAlt
                        AppIcon { anchors.centerIn: parent; name: "ui-close"; size: 13; color: f.col.textSecondary }
                        MouseArea { anchors.fill: parent; onClicked: {
                            var a = f.curTasks().slice()
                            if (index < 0 || index >= a.length) return
                            a.splice(index, 1); f.setV(a) } }
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
                        var a = f.curTasks().slice(); a.push({ text: text.trim(), done: false }); f.setV(a); text = ""
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
