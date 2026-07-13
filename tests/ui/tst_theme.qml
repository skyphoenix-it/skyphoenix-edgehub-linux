import QtQuick
import QtTest
import "../../ui/qml" as App

// Theme (ui/qml/Theme.qml) — the design-token source + accent/theme appliers.
// Pure logic (a QtObject), so we assert the derived values directly.
Item {
    id: root
    width: 100; height: 100
    App.Theme { id: theme }

    TestCase {
        name: "Theme"
        when: windowShown

        function init() { theme.applyTheme("dark"); theme.applyAccent("blue"); theme.glassOpacity = 0.6 }

        // ── accentPresets ────────────────────────────────────────────────────
        function test_accent_presets_complete() {
            var names = ["blue","purple","green","orange","pink","teal","red","gold"]
            compare(Object.keys(theme.accentPresets).length, 8, "eight accent presets")
            for (var i = 0; i < names.length; i++) {
                var p = theme.accentPresets[names[i]]
                verify(p && p.a !== undefined && p.b !== undefined, names[i] + " has a+b tones")
            }
        }

        // ── applyAccent ──────────────────────────────────────────────────────
        function test_applyAccent_sets_primary_secondary_and_name() {
            theme.applyAccent("green")
            compare(theme.accentName, "green", "accentName updated")
            verify(Qt.colorEqual(theme.accent, theme.accentPresets["green"].a), "primary accent set")
            verify(Qt.colorEqual(theme.accent2, theme.accentPresets["green"].b), "secondary accent set")
        }

        function test_applyAccent_unknown_falls_back_to_blue() {
            theme.applyAccent("chartreuse")
            verify(Qt.colorEqual(theme.accent, theme.accentPresets["blue"].a),
                   "an unknown accent name falls back to blue")
        }

        // ── applyTheme ───────────────────────────────────────────────────────
        function test_applyTheme_light() {
            theme.applyTheme("light")
            verify(Qt.colorEqual(theme.backgroundColor, "#FFFFFF"), "light background")
            verify(Qt.colorEqual(theme.textPrimary, "#1F2328"), "light text")
            compare(theme.decorative, true, "light keeps decoration on")
            compare(theme.cardBorderWidth, 1, "light border width")
        }

        function test_applyTheme_dark_default() {
            theme.applyTheme("dark")
            verify(Qt.colorEqual(theme.backgroundColor, "#0D1117"), "dark background")
            compare(theme.decorative, true, "dark keeps decoration on")
        }

        function test_applyTheme_high_contrast_disables_decoration() {
            theme.applyTheme("high_contrast")
            compare(theme.decorative, false, "high-contrast turns decoration off")
            compare(theme.cardBorderWidth, 2, "high-contrast thickens the border")
            verify(Qt.colorEqual(theme.cardBorder, "#FFFFFF"), "high-contrast uses a white border")
        }

        function test_applyTheme_reapplies_accent() {
            theme.applyAccent("red")
            theme.applyTheme("midnight")   // ends with applyAccent(accentName)
            verify(Qt.colorEqual(theme.accent, theme.accentPresets["red"].a),
                   "applyTheme re-applies the current accent so it survives a mode switch")
        }

        function test_unknown_mode_uses_dark_default() {
            theme.applyTheme("banana")
            verify(Qt.colorEqual(theme.backgroundColor, "#0D1117"), "an unknown mode falls back to the dark default")
        }

        // ── cardFill derivation ──────────────────────────────────────────────
        function test_cardFill_translucency_scales_with_glass() {
            theme.applyTheme("dark")   // decorative
            theme.glassOpacity = 0.0
            var opaqueA = theme.cardFill().a
            theme.glassOpacity = 1.0
            var glassA = theme.cardFill().a
            fuzzyCompare(opaqueA, 0.84, 0.001, "glass 0 → ~0.84 alpha (near opaque)")
            fuzzyCompare(glassA, 0.22, 0.001, "glass 1 → ~0.22 alpha (most translucent)")
            verify(opaqueA > glassA, "more glass means a more translucent card")
        }

        function test_cardFill_preserves_card_rgb() {
            theme.applyTheme("dark")
            var f = theme.cardFill()
            verify(Qt.colorEqual(Qt.rgba(f.r, f.g, f.b, 1), Qt.rgba(theme.cardBackground.r, theme.cardBackground.g, theme.cardBackground.b, 1)),
                   "cardFill keeps the cardBackground RGB, varying only alpha")
        }

        function test_cardFill_opaque_when_not_decorative() {
            theme.applyTheme("high_contrast")   // decorative false
            var f = theme.cardFill()
            verify(Qt.colorEqual(f, theme.cardBackground), "non-decorative themes use fully-opaque cards")
        }

        // ── Category colours are stable across theme switches ────────────────
        function test_category_colors_stable() {
            var before = [theme.catSystem, theme.catProductivity, theme.catInfo,
                          theme.catEntertainment, theme.catGaming, theme.catServices]
            theme.applyTheme("light"); theme.applyTheme("nebula"); theme.applyTheme("dark")
            var after = [theme.catSystem, theme.catProductivity, theme.catInfo,
                         theme.catEntertainment, theme.catGaming, theme.catServices]
            for (var i = 0; i < before.length; i++)
                verify(Qt.colorEqual(before[i], after[i]), "category colour " + i + " is stable across theme switches")
        }

        function test_category_colors_known_values() {
            verify(Qt.colorEqual(theme.catSystem, "#58A6FF"), "catSystem tone")
            verify(Qt.colorEqual(theme.catGaming, "#F0883E"), "catGaming tone")
        }

        // ── glass / glow aliases + motion tokens ─────────────────────────────
        function test_glass_glow_aliases() {
            theme.glassOpacity = 0.33
            fuzzyCompare(theme.glass, 0.33, 1e-9, "glass mirrors glassOpacity")
            theme.showWidgetGlow = false
            compare(theme.glow, false, "glow mirrors showWidgetGlow")
            theme.showWidgetGlow = true
        }

        function test_reduce_motion_zeroes_motion_tokens() {
            theme.reduceMotion = false
            verify(theme.motionPage > 0 && theme.motionFast > 0, "non-zero when motion allowed")
            theme.reduceMotion = true
            compare(theme.motionPage, 0, "motionPage zeroed")
            compare(theme.motionAdd, 0, "motionAdd zeroed")
            compare(theme.motionFast, 0, "motionFast zeroed")
            theme.reduceMotion = false
        }
    }
}
