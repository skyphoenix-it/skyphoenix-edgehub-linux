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

    // ── Reduce motion: OS signal vs. explicit choice ─────────────────────────
    // `reduceMotion` above is the PERSISTED config flag. Two more inputs decide
    // what actually renders; `effectiveReduceMotion` is what the motion tokens
    // consume. Kept separate (rather than folded into `reduceMotion`) because
    // main.qml aliases `reduceMotion` onto the persisted value — collapsing them
    // would let an OS signal write itself back into the user's config.
    //
    // Qt cannot report the OS setting: there is NO reduce-motion style hint in
    // Qt 6 — verified on 6.11 (`Qt.styleHints.useReducedMotion === undefined`;
    // the only a11y hint is `accessibility.contrastPreference`, itself 6.10+),
    // and 6.7 (CI) exposes strictly fewer hints. So the platform read (GNOME
    // `enable-animations`, XDG desktop-portal) must be injected here by the host
    // app. Default false = "no OS signal", which is also the safe CI value.
    property bool systemReduceMotion: false

    // "auto" (default) | "on" | "off" — an EXPLICIT choice, and it beats the OS.
    // Precedence: explicit > OS > legacy flag.
    //   "auto" → no explicit choice yet, so the OS signal (or the persisted
    //            `reduceMotion` flag) may turn motion off.
    //   "off"  → motion stays ON even when the OS asks to reduce it.
    // "off" deliberately overrides the OS because this hub is a dedicated
    // appliance, not a desktop window: a user who re-enabled motion *on this
    // device* must not have that silently undone by an unrelated global desktop
    // a11y setting. Mirrors the web, where prefers-reduced-motion is a default
    // an app-level setting is allowed to override.
    property string reduceMotionPreference: "auto"

    readonly property bool effectiveReduceMotion:
        reduceMotionPreference === "on" ? true
      : reduceMotionPreference === "off" ? false
      : (reduceMotion || systemReduceMotion)

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
        "blue":    { a: "#58A6FF", b: "#79C0FF" }, "purple":  { a: "#A371F7", b: "#D2A8FF" },
        "green":   { a: "#3FB950", b: "#7EE787" }, "orange":  { a: "#F0883E", b: "#FFA657" },
        "pink":    { a: "#F778BA", b: "#FF9BCE" }, "teal":    { a: "#56D4DD", b: "#76E3EA" },
        "red":     { a: "#F85149", b: "#FF7B72" }, "gold":    { a: "#E3B341", b: "#F2CC60" },
        "cyan":    { a: "#22D3EE", b: "#67E8F9" }, "indigo":  { a: "#818CF8", b: "#A5B4FC" },
        "mint":    { a: "#34D399", b: "#6EE7B7" }, "coral":   { a: "#FB7185", b: "#FDA4AF" },
        "amber":   { a: "#FBBF24", b: "#FCD34D" }, "magenta": { a: "#E879F9", b: "#F0ABFC" },

        // Okabe–Ito: the published Color Universal Design palette, chosen to stay
        // mutually distinguishable under protanopia/deuteranopia/tritanopia.
        // Okabe & Ito (2008), "Color Universal Design (CUD)" — https://jfly.uni-koeln.de/color/
        // The `a` tones are the canonical hexes and must NOT be hand-tuned: the
        // set's guarantee is a property of the 8 colours *together*. `b` is a 35%
        // tint toward white, matching the lighter-second-tone rule above.
        // Namespaced `oi_*` so they ADD to the table — the 14 names above are
        // referenced by name in saved configs and must keep resolving unchanged.
        "oi_black":          { a: "#000000", b: "#595959" },
        "oi_orange":         { a: "#E69F00", b: "#EFC159" },
        "oi_sky_blue":       { a: "#56B4E9", b: "#91CEF1" },
        "oi_bluish_green":   { a: "#009E73", b: "#59C0A4" },
        "oi_yellow":         { a: "#F0E442", b: "#F5ED84" },
        "oi_blue":           { a: "#0072B2", b: "#59A3CD" },
        "oi_vermillion":     { a: "#D55E00", b: "#E49659" },
        "oi_reddish_purple": { a: "#CC79A7", b: "#DEA8C6" },

        // Accents that complete the distro-evoking theme modes (see applyTheme).
        // Colour is not protectable subject matter, so a palette may evoke a
        // familiar look — a logo never may, and none is shipped. The last two are
        // named for their colours ONLY; see the note in applyTheme before renaming
        // them. Separate from the theme modes on purpose: applyTheme re-applies the
        // user's accent rather than forcing one, so pairing these is the user's
        // choice. All clear 3:1 on their theme's card fill (WCAG non-text).
        "arch":      { a: "#1FA8DF", b: "#6BC5EA" },
        "cachyos":   { a: "#3DD68C", b: "#7FE5B5" },
        "debian":    { a: "#D70A53", b: "#E55D8A" },
        "fedora":    { a: "#3C6EB4", b: "#7FA3D3" },
        // The only pair where `b` is a different hue rather than a lighter tint of
        // `a`: the teal/amber *pairing* is the whole identity being evoked, and
        // accent→accent2 renders as a gradient, so the two-hue ramp is the point.
        "popos":     { a: "#48B9C7", b: "#FFAF33" },
        "aubergine": { a: "#E8642A", b: "#F09A6B" },
        "crimson":   { a: "#DC3B33", b: "#E87C76" }
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

    // Global text-size multiplier. Every font token below is derived from it, so
    // call sites keep reading `theme.fontLabel` and scale for free.
    // Clamped, not free-form: under 0.8 the captions stop being legible at the
    // Edge's viewing distance, and over 1.6 the 40–48px data readouts overflow
    // the narrow panel's tiles. An out-of-range value is a bug, not a taste —
    // clamp rather than let it break the layout.
    property real textScale: 1.0
    readonly property real textScaleEff: Math.max(0.8, Math.min(1.6, textScale))

    property int fontData: Math.round(40 * textScaleEff)
    property int fontDataLarge: Math.round(48 * textScaleEff)
    property int fontTitle: Math.round(17 * textScaleEff)
    property int fontLabel: Math.round(15 * textScaleEff)
    property int fontCaption: Math.round(13 * textScaleEff)
    property string fontMono: "JetBrains Mono, Fira Code, monospace"

    // ── Bundled a11y fonts (SIL OFL 1.1, unmodified; assets/fonts/) ──────────
    // Loaded HERE so both apps and the test harness get them from the single
    // token source. URL resolution: Theme.qml is loaded from qrc:/qml/ (hub),
    // qrc:/manager/ (Manager) and the plain filesystem (qmltestrunner), so the
    // qrc case uses the absolute resource path assets/fonts.qrc puts the files
    // at, and the filesystem case walks to <repo>/assets/fonts/ — same bytes.
    readonly property string _fontsDir:
        Qt.resolvedUrl(".").toString().indexOf("qrc:") === 0
            ? "qrc:/assets/fonts/"
            : Qt.resolvedUrl("../../assets/fonts/").toString()
    readonly property FontLoader hyperlegibleLoader:
        FontLoader { source: t._fontsDir + "AtkinsonHyperlegible-Regular.ttf" }
    readonly property FontLoader hyperlegibleBoldLoader:
        FontLoader { source: t._fontsDir + "AtkinsonHyperlegible-Bold.ttf" }
    readonly property FontLoader lexendLoader:
        FontLoader { source: t._fontsDir + "Lexend-Regular.ttf" }
    readonly property FontLoader lexendBoldLoader:
        FontLoader { source: t._fontsDir + "Lexend-Bold.ttf" }

    // Family tokens resolve through the loaders so a widget gets the REAL
    // loaded family name; the literal-name fallback only matters if the
    // resource is somehow missing (then fontconfig falls back to system).
    readonly property string fontFamilyHyperlegible:
        hyperlegibleLoader.status === FontLoader.Ready
            ? hyperlegibleLoader.name : "Atkinson Hyperlegible"
    readonly property string fontFamilyLexend:
        lexendLoader.status === FontLoader.Ready
            ? lexendLoader.name : "Lexend"

    // User-facing font preference: "system" (default — the product's look) |
    // "hyperlegible" | "lexend". Wires the UI family token (fontDisplay) so
    // every widget follows for free; fontMono stays mono on purpose (tabular
    // data readouts need fixed-pitch digits). Unknown values fall through to
    // system, so a config from a newer build degrades safely.
    property string fontChoice: "system"
    readonly property string _fontDisplaySystem: "Inter, Segoe UI, Roboto, sans-serif"
    property string fontDisplay:
        fontChoice === "hyperlegible" ? fontFamilyHyperlegible
      : fontChoice === "lexend" ? fontFamilyLexend
      : _fontDisplaySystem

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

    property int motionPage: effectiveReduceMotion ? 0 : 250
    property int motionAdd: effectiveReduceMotion ? 0 : 200
    property int motionRemove: effectiveReduceMotion ? 0 : 150
    property int motionEdit: effectiveReduceMotion ? 0 : 200
    property int motionFast: effectiveReduceMotion ? 0 : 150
    property int motionSlow: effectiveReduceMotion ? 0 : 500
    // Continuous VALUE tracking (bar lengths, gauge sweeps, live readouts): long
    // enough that a 2s metrics tick reads as one smooth glide instead of a cut,
    // short enough that the display never lags the data by a readable amount.
    // Every widget that eases a data value must use THIS token (not a literal),
    // so reduce-motion collapses them all to an instant jump in one place.
    property int motionValue: effectiveReduceMotion ? 0 : 400

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
        case "synthwave":
            backgroundColor = "#1A0B2E"; backgroundColor2 = "#2D0B45"; backgroundColor3 = "#0F0524"
            cardBackground = "#241141"; cardBackgroundAlt = "#34195C"; cardBorder = "#5B2A8C"
            textPrimary = "#FCEEFF"; textSecondary = "#C89BE0"; textTertiary = "#9070B0"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "cyberpunk":
            backgroundColor = "#04110F"; backgroundColor2 = "#0A2A26"; backgroundColor3 = "#020A08"
            cardBackground = "#0A1A18"; cardBackgroundAlt = "#12302B"; cardBorder = "#1C4A42"
            textPrimary = "#EAFFF9"; textSecondary = "#7FD8C8"; textTertiary = "#559488"
            radiusSm = 6; radiusMd = 9; radiusLg = 12; radiusXl = 16; decorative = true; cardBorderWidth = 1; break
        case "deep_forest":
            backgroundColor = "#0A1A0E"; backgroundColor2 = "#143021"; backgroundColor3 = "#06120A"
            cardBackground = "#12251A"; cardBackgroundAlt = "#1B3626"; cardBorder = "#2E5238"
            textPrimary = "#EAF7EC"; textSecondary = "#A8C9AE"; textTertiary = "#75997C"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "deep_ocean":
            backgroundColor = "#04121F"; backgroundColor2 = "#0A2A3F"; backgroundColor3 = "#020A14"
            cardBackground = "#0A1E2E"; cardBackgroundAlt = "#12324A"; cardBorder = "#1E4A63"
            textPrimary = "#E6F6FF"; textSecondary = "#9BC4DC"; textTertiary = "#6689A0"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "ember":
            backgroundColor = "#1A0E0A"; backgroundColor2 = "#3A1509"; backgroundColor3 = "#0F0705"
            cardBackground = "#241310"; cardBackgroundAlt = "#38201A"; cardBorder = "#5C3324"
            textPrimary = "#FFEFE6"; textSecondary = "#DDA989"; textTertiary = "#A67A61"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "vaporwave":
            backgroundColor = "#1E0F2E"; backgroundColor2 = "#3A1A52"; backgroundColor3 = "#140A20"
            cardBackground = "#281640"; cardBackgroundAlt = "#382058"; cardBorder = "#563A78"
            textPrimary = "#FBEEFF"; textSecondary = "#CBB0E6"; textTertiary = "#9986B8"
            radiusSm = 12; radiusMd = 18; radiusLg = 24; radiusXl = 30; decorative = true; cardBorderWidth = 1; break
        case "rose_gold":
            backgroundColor = "#21121A"; backgroundColor2 = "#3A1E2C"; backgroundColor3 = "#170C12"
            cardBackground = "#2A1721"; cardBackgroundAlt = "#3D2431"; cardBorder = "#5E3A4A"
            textPrimary = "#FDEEF3"; textSecondary = "#D9AEBB"; textTertiary = "#A67E8B"
            radiusSm = 12; radiusMd = 18; radiusLg = 24; radiusXl = 30; decorative = true; cardBorderWidth = 1; break
        case "matrix":
            backgroundColor = "#000000"; backgroundColor2 = "#030A03"; backgroundColor3 = "#000000"
            cardBackground = "#050D05"; cardBackgroundAlt = "#0A160A"; cardBorder = "#164016"
            textPrimary = "#B6FFB6"; textSecondary = "#5FCF5F"; textTertiary = "#3E8F3E"
            radiusSm = 4; radiusMd = 6; radiusLg = 9; radiusXl = 12; decorative = true; cardBorderWidth = 1; break
        case "nord":
            backgroundColor = "#2E3440"; backgroundColor2 = "#3B4252"; backgroundColor3 = "#272B35"
            cardBackground = "#3B4252"; cardBackgroundAlt = "#434C5E"; cardBorder = "#4C566A"
            textPrimary = "#ECEFF4"; textSecondary = "#D8DEE9"; textTertiary = "#7B8494"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "dracula":
            backgroundColor = "#282A36"; backgroundColor2 = "#343746"; backgroundColor3 = "#21222C"
            cardBackground = "#343746"; cardBackgroundAlt = "#3C3F51"; cardBorder = "#44475A"
            textPrimary = "#F8F8F2"; textSecondary = "#BFBFD0"; textTertiary = "#6272A4"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "solarized":
            backgroundColor = "#002B36"; backgroundColor2 = "#073642"; backgroundColor3 = "#00212B"
            cardBackground = "#073642"; cardBackgroundAlt = "#0E4B59"; cardBorder = "#17616B"
            textPrimary = "#EEE8D5"; textSecondary = "#93A1A1"; textTertiary = "#657B83"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "gruvbox":
            backgroundColor = "#282828"; backgroundColor2 = "#32302F"; backgroundColor3 = "#1D2021"
            cardBackground = "#3C3836"; cardBackgroundAlt = "#504945"; cardBorder = "#665C54"
            textPrimary = "#EBDBB2"; textSecondary = "#D5C4A1"; textTertiary = "#A89984"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "catppuccin":
            backgroundColor = "#1E1E2E"; backgroundColor2 = "#181825"; backgroundColor3 = "#11111B"
            cardBackground = "#313244"; cardBackgroundAlt = "#45475A"; cardBorder = "#585B70"
            textPrimary = "#CDD6F4"; textSecondary = "#A6ADC8"; textTertiary = "#7F849C"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        case "tokyonight":
            backgroundColor = "#1A1B26"; backgroundColor2 = "#24283B"; backgroundColor3 = "#16161E"
            cardBackground = "#24283B"; cardBackgroundAlt = "#2F344D"; cardBorder = "#3B4261"
            textPrimary = "#C0CAF5"; textSecondary = "#A9B1D6"; textTertiary = "#565F89"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break

        // ── Palettes evoking familiar Linux distributions ────────────────────
        // COLOUR ONLY. This product is sold, and distro logos/wordmarks are
        // trademarks that our own MIT/Apache licensing does nothing about — but a
        // colour palette is not protectable subject matter. So these cases ship a
        // *palette inspired by* a look and nothing else: no logo, no glyph, no
        // traced or approximated mark, anywhere in the theme or its assets.
        //
        // Two naming registers, and the difference is deliberate:
        //  • Descriptive names below (arch/cachyos/debian/fedora/popos) name
        //    community projects with published, permissive guidelines, where
        //    naming a palette after the look it evokes is nominative use.
        //  • `aubergine` and `crimson` evoke looks whose owners actively enforce
        //    their marks against commercial use. They are named for their colours
        //    and MUST stay that way: do not reintroduce the project name into the
        //    case label, the UI string, or a comment. The colour is the whole
        //    point; the name would be the whole liability.
        //
        // Each carries its hue in the SURFACES (backgrounds, card fills, borders)
        // rather than in `accent` — applyTheme deliberately ends by re-applying
        // the user's own accent, so a theme must never clobber it. The matching
        // accents live in `accentPresets` for users who want the full look.

        // Cyan-tinted graphite.
        case "arch":
            backgroundColor = "#14181D"; backgroundColor2 = "#1B2229"; backgroundColor3 = "#0E1216"
            cardBackground = "#1B2129"; cardBackgroundAlt = "#232B35"; cardBorder = "#2C4453"
            textPrimary = "#E4EEF5"; textSecondary = "#9FB6C4"; textTertiary = "#6E8291"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        // Spring green on a near-neutral dark.
        case "cachyos":
            backgroundColor = "#131611"; backgroundColor2 = "#1D2419"; backgroundColor3 = "#0C0E0A"
            cardBackground = "#1C221A"; cardBackgroundAlt = "#26301F"; cardBorder = "#35492E"
            textPrimary = "#EAF7E4"; textSecondary = "#AEC9A6"; textTertiary = "#7C9276"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        // Magenta-red on a dark neutral.
        case "debian":
            backgroundColor = "#16121A"; backgroundColor2 = "#241823"; backgroundColor3 = "#0F0C12"
            cardBackground = "#1F1922"; cardBackgroundAlt = "#2A212D"; cardBorder = "#4A2C3C"
            textPrimary = "#F5EAF0"; textSecondary = "#C4A8B8"; textTertiary = "#8E7684"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        // Deep navy-blue surfaces.
        case "fedora":
            backgroundColor = "#0E1626"; backgroundColor2 = "#17284A"; backgroundColor3 = "#080E1A"
            cardBackground = "#152034"; cardBackgroundAlt = "#1D2C48"; cardBorder = "#2C4270"
            textPrimary = "#E8F0FB"; textSecondary = "#A6BCDA"; textTertiary = "#728CAB"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        // Warm graphite; the teal/amber pairing it evokes lives in the accent.
        case "popos":
            backgroundColor = "#1E1C1B"; backgroundColor2 = "#2B2827"; backgroundColor3 = "#141312"
            cardBackground = "#262322"; cardBackgroundAlt = "#33302E"; cardBorder = "#48423F"
            textPrimary = "#F2EFEC"; textSecondary = "#BDB5AE"; textTertiary = "#8A827B"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        // Deep purple; pairs with a warm orange accent.
        case "aubergine":
            backgroundColor = "#2C0A20"; backgroundColor2 = "#46102F"; backgroundColor3 = "#1D0616"
            cardBackground = "#3A0F2A"; cardBackgroundAlt = "#4C1738"; cardBorder = "#6B2650"
            textPrimary = "#FBECF5"; textSecondary = "#D5AAC4"; textTertiary = "#A47C93"
            radiusSm = 10; radiusMd = 16; radiusLg = 22; radiusXl = 28; decorative = true; cardBorderWidth = 1; break
        // Deep red on near-black.
        case "crimson":
            backgroundColor = "#0B0507"; backgroundColor2 = "#1E070B"; backgroundColor3 = "#050203"
            cardBackground = "#16080B"; cardBackgroundAlt = "#230E12"; cardBorder = "#3E1A20"
            textPrimary = "#FBE9EA"; textSecondary = "#D0A2A6"; textTertiary = "#996E73"
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
