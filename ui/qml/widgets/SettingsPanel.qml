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

    // Bundled "standard" wallpapers + animated styles offered in the pickers below.
    WallpaperCatalog { id: wallpapers }
    BackgroundCatalog { id: bgCatalog }

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
                spacing: theme.spacingSm
                AppIcon { name: "ui-settings"; color: theme.textPrimary; size: 24; Layout.alignment: Qt.AlignVCenter }
                Text {
                    text: "Appearance"; font.pixelSize: 22; font.bold: true
                    font.family: theme.fontDisplay; color: theme.textPrimary
                    Layout.fillWidth: true
                }
                Rectangle {
                    width: theme.touchSecondary; height: theme.touchSecondary
                    radius: width / 2; color: theme.cardBackground
                    border.width: 1; border.color: theme.cardBorder
                    AppIcon { anchors.centerIn: parent; name: "ui-close"; size: 18; color: theme.textPrimary }
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

                    // --- Theme mode (live gradient previews) ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        Text { text: "Theme"; font.pixelSize: theme.fontLabel; font.bold: true; color: theme.textSecondary }
                        Flow {
                            Layout.fillWidth: true; spacing: theme.spacingMd
                            Repeater {
                                model: [
                                    { v: "dark",          l: "Dark",     c1: "#161B22", c2: "#0A0E14" },
                                    { v: "midnight",      l: "Midnight", c1: "#1B1247", c2: "#070A1C" },
                                    { v: "aurora",        l: "Aurora",   c1: "#0C2E3A", c2: "#111C40" },
                                    { v: "sunset",        l: "Sunset",   c1: "#3A1230", c2: "#40161C" },
                                    { v: "nebula",        l: "Nebula",   c1: "#2A1048", c2: "#120A2E" },
                                    { v: "oled",          l: "OLED",     c1: "#0A0A0A", c2: "#000000" },
                                    { v: "light",         l: "Light",    c1: "#F6F8FA", c2: "#E4E9F0" },
                                    { v: "high_contrast", l: "Contrast", c1: "#1A1A1A", c2: "#000000" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 150; height: 84; radius: theme.radiusLg; clip: true
                                    property bool active: root.themeMode === modelData.v
                                    border.width: active ? 3 : 1
                                    border.color: active ? theme.accent : theme.cardBorder
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: modelData.c1 }
                                        GradientStop { position: 1.0; color: modelData.c2 }
                                    }
                                    Text {
                                        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 10
                                        text: modelData.l; font.pixelSize: 15; font.bold: true
                                        color: modelData.v === "light" ? "#1F2328" : "#FFFFFF"
                                    }
                                    Text {
                                        visible: parent.active
                                        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 8
                                        text: "✓"; font.pixelSize: 22; font.bold: true; color: theme.accent
                                    }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.themeMode = modelData.v; theme.applyTheme(modelData.v) } }
                                }
                            }
                        }
                    }

                    // --- Orientation ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        Text { text: "Orientation"; font.pixelSize: theme.fontLabel; font.bold: true; color: theme.textSecondary }
                        Text { text: "Pick how the dashboard sits on the panel. Use a fixed mode to rotate for a wall/arm mount. (Auto follows the system only when an orientation sensor is present.)"
                            font.pixelSize: theme.fontCaption; color: theme.textTertiary
                            Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        Flow {
                            Layout.fillWidth: true; spacing: theme.spacingSm
                            Repeater {
                                model: [ { v: "auto", l: "Auto" }, { v: "portrait", l: "Portrait" },
                                         { v: "landscape", l: "Landscape" }, { v: "inverted-portrait", l: "Portrait (flipped)" },
                                         { v: "inverted-landscape", l: "Landscape (flipped)" } ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: oLbl.implicitWidth + 26; height: theme.touchSecondary; radius: theme.radiusMd
                                    property bool active: root.orientationMode === modelData.v
                                    color: active ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18) : theme.cardBackground
                                    border.width: active ? 2 : 1; border.color: active ? theme.accent : theme.cardBorder
                                    Text { id: oLbl; anchors.centerIn: parent; text: modelData.l; color: theme.textPrimary; font.pixelSize: theme.fontLabel }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.orientationMode = modelData.v }
                                }
                            }
                        }
                    }

                    // --- Animated background ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        Text { text: "Animated background"; font.pixelSize: theme.fontLabel; font.bold: true; color: theme.textSecondary }
                        Text { text: "A living backdrop behind the frosted widgets. Picking one clears the wallpaper below."
                            font.pixelSize: theme.fontCaption; color: theme.textTertiary
                            Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        Flow {
                            Layout.fillWidth: true; spacing: theme.spacingSm
                            Repeater {
                                model: bgCatalog.styles
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 150; height: theme.touchSecondary; radius: theme.radiusMd
                                    // A style is "active" only when no wallpaper is set (a wallpaper wins).
                                    property bool active: (store.revision,
                                        !store.appearance().wallpaper && (store.appearance().bgStyle || "orbs") === modelData.v)
                                    color: active ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18) : theme.cardBackground
                                    border.width: active ? 2 : 1; border.color: active ? theme.accent : theme.cardBorder
                                    Text { anchors.centerIn: parent; text: modelData.l; color: theme.textPrimary; font.pixelSize: theme.fontLabel }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { store.setAppearance("bgStyle", modelData.v); store.setAppearance("wallpaper", "") } }
                                }
                            }
                        }
                    }

                    // --- Wallpaper ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        Text { text: "Wallpaper"; font.pixelSize: theme.fontLabel; font.bold: true; color: theme.textSecondary }
                        Text { text: "Shows through the frosted widgets. Set “None” to use the animated background only."
                            font.pixelSize: theme.fontCaption; color: theme.textTertiary
                            Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        Flow {
                            Layout.fillWidth: true; spacing: theme.spacingSm
                            // "None" clears the wallpaper (falls back to the animated backdrop).
                            Rectangle {
                                width: 88; height: 120; radius: theme.radiusMd
                                property bool active: (store.revision, !(store.appearance().wallpaper))
                                color: theme.cardBackground
                                border.width: active ? 3 : 1; border.color: active ? theme.accent : theme.cardBorder
                                Text { anchors.centerIn: parent; text: "None"; color: theme.textSecondary; font.pixelSize: theme.fontCaption }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: store.setAppearance("wallpaper", "") }
                            }
                            Repeater {
                                model: wallpapers.items
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 88; height: 120; radius: theme.radiusMd; clip: true
                                    property bool active: (store.revision, store.appearance().wallpaper === modelData.source)
                                    border.width: active ? 3 : 1; border.color: active ? theme.accent : theme.cardBorder
                                    color: theme.cardBackground
                                    Image { anchors.fill: parent; anchors.margins: 2; source: modelData.source
                                        fillMode: Image.PreserveAspectCrop; asynchronous: true }
                                    Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                                        height: 22; color: Qt.rgba(0, 0, 0, 0.45)
                                        Text { anchors.centerIn: parent; text: modelData.label; color: "#fff"; font.pixelSize: 11 } }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: store.setAppearance("wallpaper", modelData.source) }
                                }
                            }
                        }
                    }

                    // --- Layout columns ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        Text { text: "Layout Columns"; font.pixelSize: theme.fontLabel; font.bold: true; color: theme.textSecondary }
                        Flow {
                            Layout.fillWidth: true; spacing: theme.spacingSm
                            Repeater {
                                model: [ { v: 1, l: "1 Column" }, { v: 2, l: "2 Columns" } ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 150; height: theme.touchSecondary; radius: theme.radiusMd
                                    property bool active: (store.revision, store.appearance().gridCols || 1) === modelData.v
                                    color: active ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18) : theme.cardBackground
                                    border.width: active ? 2 : 1; border.color: active ? theme.accent : theme.cardBorder
                                    Text { anchors.centerIn: parent; text: modelData.l; color: theme.textPrimary; font.pixelSize: theme.fontLabel }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: store.setAppearance("gridCols", modelData.v) }
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
                            Text { text: "Animated background"; font.pixelSize: theme.fontLabel; color: theme.textPrimary; Layout.fillWidth: true }
                            Switch { checked: root.animatedBackground; onToggled: root.animatedBackground = checked }
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

