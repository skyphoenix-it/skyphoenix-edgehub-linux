import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ─────────────────────────────────────────────────────────────────────────
// SettingsPanel — in-app customization overlay.
// Lets the user pick theme mode, accent color, glass/transparency level,
// widget glow, and reduced motion. Changes apply live to `theme` / root.
// ─────────────────────────────────────────────────────────────────────────
Rectangle {
    id: panel
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.6)
    z: 200
    property bool shown: false
    signal closeRequested()

    visible: shown || opacity > 0.01
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: theme.motionFast } }

    // scrim click closes
    MouseArea { anchors.fill: parent; onClicked: panel.closeRequested() }

    Rectangle {
        id: sheet
        width: Math.min(parent.width * 0.9, 620)
        height: Math.min(parent.height * 0.92, 640)
        anchors.centerIn: parent
        radius: theme.radiusXl
        color: theme.backgroundColor
        border.width: 1; border.color: theme.cardBorder
        scale: panel.shown ? 1 : 0.95
        Behavior on scale { NumberAnimation { duration: theme.motionPage; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent } // swallow clicks

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: theme.spacingXl
            spacing: theme.spacingLg

            // Header
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "⚙  Appearance"; font.pixelSize: 22; font.bold: true
                    font.family: theme.fontDisplay; color: theme.textPrimary
                    Layout.fillWidth: true
                }
                Rectangle {
                    width: theme.touchSecondary; height: theme.touchSecondary
                    radius: width / 2; color: theme.cardBackground
                    border.width: 1; border.color: theme.cardBorder
                    Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 18; color: theme.textPrimary }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: panel.closeRequested() }
                }
            }

            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true
                contentHeight: form.implicitHeight; clip: true
                ColumnLayout {
                    id: form
                    width: parent.width
                    spacing: theme.spacingXl

                    // --- Theme mode ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        Text { text: "Theme"; font.pixelSize: theme.fontLabel; font.bold: true; color: theme.textSecondary }
                        Flow {
                            Layout.fillWidth: true; spacing: theme.spacingSm
                            Repeater {
                                model: [
                                    { v: "dark", l: "Dark" }, { v: "oled", l: "OLED Black" },
                                    { v: "light", l: "Light" }, { v: "high_contrast", l: "High Contrast" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 140; height: theme.touchSecondary; radius: theme.radiusMd
                                    property bool active: root.themeMode === modelData.v
                                    color: active ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18) : theme.cardBackground
                                    border.width: active ? 2 : 1
                                    border.color: active ? theme.accent : theme.cardBorder
                                    Text { anchors.centerIn: parent; text: modelData.l; color: theme.textPrimary; font.pixelSize: theme.fontLabel }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.themeMode = modelData.v; theme.applyTheme(modelData.v) } }
                                }
                            }
                        }
                    }

                    // --- Accent color ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        Text { text: "Accent Color"; font.pixelSize: theme.fontLabel; font.bold: true; color: theme.textSecondary }
                        Flow {
                            Layout.fillWidth: true; spacing: theme.spacingMd
                            Repeater {
                                model: ["blue","purple","green","orange","pink","teal","red","gold"]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 52; height: 52; radius: 26
                                    property bool active: root.accentName === modelData
                                    color: theme.accentPresets[modelData].a
                                    border.width: active ? 3 : 0
                                    border.color: theme.textPrimary
                                    scale: active ? 1.08 : 1.0
                                    Behavior on scale { NumberAnimation { duration: theme.motionFast } }
                                    Text { anchors.centerIn: parent; visible: parent.active; text: "✓"; color: "#0D1117"; font.pixelSize: 22; font.bold: true }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: theme.applyAccent(modelData) }
                                }
                            }
                        }
                    }

                    // --- Glass / transparency ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Glass / Transparency"; font.pixelSize: theme.fontLabel; font.bold: true; color: theme.textSecondary; Layout.fillWidth: true }
                            Text { text: Math.round(root.glassOpacity * 100) + "%"; font.pixelSize: theme.fontLabel; font.family: theme.fontMono; color: theme.accent }
                        }
                        Slider {
                            Layout.fillWidth: true
                            from: 0; to: 1; value: root.glassOpacity
                            onMoved: root.glassOpacity = value
                        }
                    }

                    // --- Toggles ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Accent glow"; font.pixelSize: theme.fontLabel; color: theme.textPrimary; Layout.fillWidth: true }
                            Switch { checked: root.showWidgetGlow; onToggled: root.showWidgetGlow = checked }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Reduce motion"; font.pixelSize: theme.fontLabel; color: theme.textPrimary; Layout.fillWidth: true }
                            Switch { checked: root.reduceMotion; onToggled: root.reduceMotion = checked }
                        }
                    }

                    Text {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: "Changes apply instantly. Your Xeneon Edge display will use these settings across all widgets."
                        font.pixelSize: theme.fontCaption; color: theme.textTertiary
                    }
                }
            }
        }
    }
}

