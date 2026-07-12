import QtQuick

// Theme — THE single source of design-system tokens (colors, category tones,
// spacing, radii, touch targets, icon sizes, typography, motion) + the
// theme/accent appliers. Consumed by BOTH the Edge hub (main.qml) and the
// companion Manager (clone preview) and the QML test harness, so the two apps
// can never visually drift. The four runtime knobs (glass/glow/reduceMotion/
// accent) are own-properties here; the hub aliases its persisted values onto them.
QtObject {
    id: t

    property real glassOpacity: 0.6
    property bool showWidgetGlow: true
    property bool reduceMotion: false
    property string accentName: "blue"

    property color backgroundColor: "#0D1117"
    property color backgroundColor2: "#0A0E14"
    property color backgroundColor3: "#0A0E14"
    property color cardBackground: "#161B22"
    property color cardBackgroundAlt: "#1C222B"
    property color cardBorder: "#30363D"
    property color textPrimary: "#E6EDF3"
    property color textSecondary: "#8B949E"
    property color textTertiary: "#6E7681"
    property color accent: "#58A6FF"
    property color accent2: "#7EE787"
    property color warning: "#D29922"
    property color error: "#F85149"
    property color success: "#3FB950"

    property color catSystem: "#58A6FF"
    property color catProductivity: "#A371F7"
    property color catInfo: "#3FB950"
    property color catEntertainment: "#F778BA"
    property color catGaming: "#F0883E"
    property color catServices: "#56D4DD"

    readonly property var accentPresets: ({
        "blue":   { a: "#58A6FF", b: "#79C0FF" }, "purple": { a: "#A371F7", b: "#D2A8FF" },
        "green":  { a: "#3FB950", b: "#7EE787" }, "orange": { a: "#F0883E", b: "#FFA657" },
        "pink":   { a: "#F778BA", b: "#FF9BCE" }, "teal":   { a: "#56D4DD", b: "#76E3EA" },
        "red":    { a: "#F85149", b: "#FF7B72" }, "gold":   { a: "#E3B341", b: "#F2CC60" }
    })

    property int spacingXs: 4
    property int spacingSm: 8
    property int spacingMd: 12
    property int spacingLg: 16
    property int spacingXl: 24

    property int radiusSm: 8
    property int radiusMd: 12
    property int radiusLg: 16
    property int radiusXl: 22

    property int cardBorderWidth: 1
    property bool decorative: true

    property int touchPrimary: 76
    property int touchSecondary: 60
    property int touchTertiary: 52
    property int iconLg: 34
    property int iconMd: 28
    property int iconSm: 22

    property int fontData: 40
    property int fontDataLarge: 48
    property int fontTitle: 17
    property int fontLabel: 15
    property int fontCaption: 13
    property string fontMono: "JetBrains Mono, Fira Code, monospace"
    property string fontDisplay: "Inter, Segoe UI, Roboto, sans-serif"

    property real glass: glassOpacity
    property bool glow: showWidgetGlow
    // Card surface alpha. Higher glassOpacity → more translucent so the page
    // backdrop / wallpaper reads THROUGH the cards (frosted-glass look), not just
    // in the gaps between them. Range ~0.22 (max glass) .. 0.84 (opaque).
    // High-contrast forces fully opaque cards for legibility.
    function cardFill() {
        if (!decorative)
            return cardBackground
        return Qt.rgba(cardBackground.r, cardBackground.g, cardBackground.b,
                       0.22 + (1.0 - glassOpacity) * 0.62)
    }

    property int motionPage: reduceMotion ? 0 : 250
    property int motionAdd: reduceMotion ? 0 : 200
    property int motionRemove: reduceMotion ? 0 : 150
    property int motionEdit: reduceMotion ? 0 : 200
    property int motionFast: reduceMotion ? 0 : 150
    property int motionSlow: reduceMotion ? 0 : 500

    function applyAccent(name) {
        var p = accentPresets[name] || accentPresets["blue"]
        accent = p.a; accent2 = p.b; accentName = name
    }

    function applyTheme(mode) {
        switch (mode) {
        case "light":
            backgroundColor = "#FFFFFF"; backgroundColor2 = "#EEF1F5"; backgroundColor3 = "#E4E9F0"
            cardBackground = "#F6F8FA"; cardBackgroundAlt = "#ECEFF3"; cardBorder = "#D0D7DE"
            textPrimary = "#1F2328"; textSecondary = "#656D76"; textTertiary = "#8C959F"
            radiusSm = 6; radiusMd = 9; radiusLg = 12; radiusXl = 16; decorative = true; cardBorderWidth = 1; break
        case "oled":
            backgroundColor = "#000000"; backgroundColor2 = "#000000"; backgroundColor3 = "#000000"
            cardBackground = "#0A0A0A"; cardBackgroundAlt = "#121212"; cardBorder = "#1A1A1A"
            textPrimary = "#E0E0E0"; textSecondary = "#808080"; textTertiary = "#5A5A5A"
            radiusSm = 8; radiusMd = 12; radiusLg = 16; radiusXl = 22; decorative = true; cardBorderWidth = 1; break
        case "high_contrast":
            backgroundColor = "#000000"; backgroundColor2 = "#000000"; backgroundColor3 = "#000000"
            cardBackground = "#1A1A1A"; cardBackgroundAlt = "#242424"; cardBorder = "#FFFFFF"
            textPrimary = "#FFFFFF"; textSecondary = "#CCCCCC"; textTertiary = "#AAAAAA"
            radiusSm = 2; radiusMd = 3; radiusLg = 4; radiusXl = 6; decorative = false; cardBorderWidth = 2; break
        case "midnight":
            backgroundColor = "#0B1026"; backgroundColor2 = "#1B1247"; backgroundColor3 = "#070A1C"
            cardBackground = "#16192E"; cardBackgroundAlt = "#232748"; cardBorder = "#33385F"
            textPrimary = "#EDEFFF"; textSecondary = "#A6ABD6"; textTertiary = "#71769E"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "aurora":
            backgroundColor = "#04140F"; backgroundColor2 = "#0C2E3A"; backgroundColor3 = "#111C40"
            cardBackground = "#0E1E24"; cardBackgroundAlt = "#16303A"; cardBorder = "#25505A"
            textPrimary = "#EAFBF4"; textSecondary = "#9FC9C4"; textTertiary = "#6C918E"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "sunset":
            backgroundColor = "#1B0A20"; backgroundColor2 = "#3A1230"; backgroundColor3 = "#40161C"
            cardBackground = "#26132A"; cardBackgroundAlt = "#38203C"; cardBorder = "#5A3355"
            textPrimary = "#FFEFF6"; textSecondary = "#D6A9C4"; textTertiary = "#9E7690"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "nebula":
            backgroundColor = "#0E0722"; backgroundColor2 = "#2A1048"; backgroundColor3 = "#120A2E"
            cardBackground = "#1A1132"; cardBackgroundAlt = "#2A1D48"; cardBorder = "#413063"
            textPrimary = "#F1EBFF"; textSecondary = "#B7A9D6"; textTertiary = "#8276A0"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        default:
            backgroundColor = "#0D1117"; backgroundColor2 = "#0A0E14"; backgroundColor3 = "#0A0E14"
            cardBackground = "#161B22"; cardBackgroundAlt = "#1C222B"; cardBorder = "#30363D"
            textPrimary = "#E6EDF3"; textSecondary = "#8B949E"; textTertiary = "#6E7681"
            radiusSm = 8; radiusMd = 12; radiusLg = 16; radiusXl = 22; decorative = true; cardBorderWidth = 1; break
        }
        applyAccent(accentName)
    }
}
