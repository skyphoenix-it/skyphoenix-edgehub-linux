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
    // Colour tokens for the shared BackgroundPicker.
    readonly property var pickerCol: ({ textPrimary: theme.textPrimary, textSecondary: theme.textSecondary,
        panel: theme.cardBackground, panelAlt: theme.cardBackgroundAlt, border: theme.cardBorder,
        accent: theme.accent, radius: theme.radiusMd })

    // scrim click closes
    MouseArea { anchors.fill: parent; onClicked: panel.closeRequested() }

    // One swatch shape for both accent groups (house palette + Okabe–Ito).
    Component {
        id: accentSwatch
        Rectangle {
            required property var modelData
            width: 52; height: 52; radius: 26
            property bool active: root.accentName === modelData
            color: theme.accentPresets[modelData].a
            // Okabe–Ito includes pure black, which would otherwise disappear
            // against the dark sheet — every swatch keeps a hairline so the
            // unselected ones stay findable whatever their tone.
            border.width: active ? 3 : 1
            border.color: active ? theme.textPrimary : theme.cardBorder
            scale: active ? 1.08 : 1.0
            Behavior on scale { NumberAnimation { duration: theme.motionFast } }
            // The check sits ON the swatch, so it must contrast with the swatch,
            // not with the sheet: the palette spans near-black (oi_black) to
            // near-white (oi_yellow). Rec. 601 luma picks the readable ink.
            AppIcon {
                anchors.centerIn: parent; visible: parent.active
                name: "ui-check"; size: 22
                color: (0.299 * parent.color.r + 0.587 * parent.color.g
                        + 0.114 * parent.color.b) > 0.55 ? "#000000" : "#FFFFFF"
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: theme.applyAccent(modelData) }
        }
    }

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
                                    { v: "dark",          l: "Dark",      c1: "#161B22", c2: "#0A0E14" },
                                    { v: "midnight",      l: "Midnight",  c1: "#1B1247", c2: "#070A1C" },
                                    { v: "aurora",        l: "Aurora",    c1: "#0C2E3A", c2: "#111C40" },
                                    { v: "sunset",        l: "Sunset",    c1: "#3A1230", c2: "#40161C" },
                                    { v: "nebula",        l: "Nebula",    c1: "#2A1048", c2: "#120A2E" },
                                    { v: "synthwave",     l: "Synthwave", c1: "#2D0B45", c2: "#0F0524" },
                                    { v: "cyberpunk",     l: "Cyberpunk", c1: "#0A2A26", c2: "#020A08" },
                                    { v: "deep_forest",   l: "Forest",    c1: "#143021", c2: "#06120A" },
                                    { v: "deep_ocean",    l: "Ocean",     c1: "#0A2A3F", c2: "#020A14" },
                                    { v: "ember",         l: "Ember",     c1: "#3A1509", c2: "#0F0705" },
                                    { v: "vaporwave",     l: "Vaporwave", c1: "#3A1A52", c2: "#140A20" },
                                    { v: "rose_gold",     l: "Rose Gold", c1: "#3A1E2C", c2: "#170C12" },
                                    { v: "matrix",        l: "Matrix",    c1: "#0A160A", c2: "#000000" },
                                    { v: "nord",          l: "Nord",      c1: "#3B4252", c2: "#272B35" },
                                    { v: "dracula",       l: "Dracula",   c1: "#343746", c2: "#21222C" },
                                    { v: "solarized",     l: "Solarized", c1: "#073642", c2: "#00212B" },
                                    { v: "gruvbox",       l: "Gruvbox",   c1: "#32302F", c2: "#1D2021" },
                                    { v: "catppuccin",    l: "Catppuccin",c1: "#181825", c2: "#11111B" },
                                    { v: "tokyonight",    l: "Tokyo Night",c1: "#24283B", c2: "#16161E" },
                                    { v: "arch", l: "Arch", c1: "#1B2129", c2: "#14181D" },
                                    { v: "cachyos", l: "CachyOS", c1: "#1C221A", c2: "#131611" },
                                    { v: "debian", l: "Debian", c1: "#1F1922", c2: "#16121A" },
                                    { v: "fedora", l: "Fedora", c1: "#152034", c2: "#0E1626" },
                                    { v: "popos", l: "Pop!_OS", c1: "#262322", c2: "#1E1C1B" },
                                    { v: "aubergine", l: "Aubergine", c1: "#3A0F2A", c2: "#2C0A20" },
                                    { v: "crimson", l: "Crimson", c1: "#16080B", c2: "#0B0507" },
                                    { v: "oled",          l: "OLED",      c1: "#0A0A0A", c2: "#000000" },
                                    { v: "light",         l: "Light",     c1: "#F6F8FA", c2: "#E4E9F0" },
                                    { v: "high_contrast", l: "Contrast",  c1: "#1A1A1A", c2: "#000000" }
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
                                    AppIcon {
                                        visible: parent.active
                                        anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 8
                                        name: "ui-check"; size: 22; color: theme.accent
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

                    // --- Background (one unified picker: animated style OR wallpaper) ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        Text { text: "Background"; font.pixelSize: theme.fontLabel; font.bold: true; color: theme.textSecondary }
                        Text { text: "Pick a living animation OR a wallpaper — they show through the frosted widgets."
                            font.pixelSize: theme.fontCaption; color: theme.textTertiary
                            Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        RowLayout {
                            visible: !theme.decorative; Layout.fillWidth: true; spacing: theme.spacingSm
                            AppIcon { name: "ui-warning"; size: theme.iconSm; color: theme.warning; Layout.alignment: Qt.AlignTop }
                            Text { text: "The High Contrast theme keeps backgrounds off for legibility — switch themes to see them."
                                font.pixelSize: theme.fontCaption; color: theme.warning
                                Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        }
                        BackgroundPicker {
                            Layout.fillWidth: true
                            // Backgrounds have no effect in High Contrast — disable the
                            // picker there instead of letting taps silently no-op.
                            enabled: theme.decorative
                            opacity: theme.decorative ? 1.0 : 0.4
                            store: store; pageIndex: -1; col: panel.pickerCol
                            bgCatalog: bgCatalog; wpCatalog: wallpapers
                        }
                    }

                    // A "Layout Columns" picker stood here. The grid is now fixed at
                    // WidgetSizes.shortHalves across the short axis, because a size is
                    // a fraction of the SCREEN — a user-chosen column count would make
                    // `1x1` mean something different per page, which is the exact
                    // property the size model exists to remove. A tile's share of the
                    // screen is now chosen per TILE (its size), not per page.

                    // --- Accent color ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        Text { text: "Accent Color"; font.pixelSize: theme.fontLabel; font.bold: true; color: theme.textSecondary }
                        Flow {
                            Layout.fillWidth: true; spacing: theme.spacingMd
                            Repeater {
                                model: ["blue","purple","green","orange","pink","teal","red","gold",
                                        "cyan","indigo","mint","coral","amber","magenta"]
                                delegate: accentSwatch
                            }
                        }

                        // The Okabe–Ito set stays mutually distinguishable for the
                        // ~1-in-12 of men with a colour-vision deficiency. Split out
                        // under its own heading so it reads as a deliberate choice
                        // rather than eight more decorative tones.
                        Text {
                            text: "Colour-blind safe (Okabe–Ito)"
                            font.pixelSize: theme.fontLabel; font.bold: true; color: theme.textSecondary
                            Layout.topMargin: theme.spacingSm
                        }
                        Flow {
                            Layout.fillWidth: true; spacing: theme.spacingMd
                            Repeater {
                                model: ["oi_blue","oi_sky_blue","oi_bluish_green","oi_yellow",
                                        "oi_orange","oi_vermillion","oi_reddish_purple","oi_black"]
                                delegate: accentSwatch
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
                            // Dragging writes `value` internally, which would sever the
                            // `value: root.glassOpacity` binding forever. Push to source,
                            // then re-assert the binding so later external changes still
                            // move the handle. (S2)
                            onMoved: {
                                root.glassOpacity = value
                                value = Qt.binding(() => root.glassOpacity)
                            }
                        }
                    }

                    // --- Toggles ---
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Accent glow"; font.pixelSize: theme.fontLabel; color: theme.textPrimary; Layout.fillWidth: true }
                            // Toggling writes `checked` internally, severing the
                            // `checked: root.showWidgetGlow` binding. Push to source,
                            // then re-bind so external/store pushes still move it. (S2)
                            Switch {
                                checked: root.showWidgetGlow
                                onToggled: {
                                    root.showWidgetGlow = checked
                                    checked = Qt.binding(() => root.showWidgetGlow)
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Animated background"; font.pixelSize: theme.fontLabel; color: theme.textPrimary; Layout.fillWidth: true }
                            Switch {
                                checked: root.animatedBackground
                                onToggled: {
                                    root.animatedBackground = checked
                                    checked = Qt.binding(() => root.animatedBackground)
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Reduce motion"; font.pixelSize: theme.fontLabel; color: theme.textPrimary; Layout.fillWidth: true }
                            Switch {
                                checked: root.reduceMotion
                                onToggled: {
                                    root.reduceMotion = checked
                                    checked = Qt.binding(() => root.reduceMotion)
                                }
                            }
                        }
                        // These two knobs are independent: "Animated background" decides
                        // whether the living backdrop shows at all (off → plain gradient),
                        // while "Reduce motion" keeps the backdrop but freezes its motion
                        // (and shortens transitions everywhere).
                        Text {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: "“Animated background” shows the drifting backdrop (off = plain gradient). “Reduce motion” keeps the backdrop but stops all animation."
                            font.pixelSize: theme.fontCaption; color: theme.textTertiary
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

