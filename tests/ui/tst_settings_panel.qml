import QtQuick
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Wg

// SettingsPanel (ui/qml/widgets/SettingsPanel.qml) — the in-app appearance sheet.
// Each control row is bound to an appearance key on `root`/`theme`/`store`; we
// assert BOTH directions: the control REFLECTS external state (read) and a tap
// WRITES through the bound sink (write). The sheet height is capped, so the form
// scrolls — a helper brings each target into view before clicking it.
Item {
    id: root
    width: 720; height: 1000

    property alias theme: _theme
    App.Theme { id: _theme }
    App.DashboardStore { id: store }

    // Appearance knobs the panel reads/writes on `root` (in the app these alias
    // onto the persisted config). accentName mirrors theme so the accent swatch
    // highlight updates after applyAccent(), exactly as in the hub.
    property string themeMode: "dark"
    property string orientationMode: "auto"
    property real glassOpacity: 0.6
    property bool showWidgetGlow: true
    property bool animatedBackground: true
    property bool reduceMotion: false
    property string accentName: _theme.accentName

    Component.onCompleted: store.load("blank")

    Wg.SettingsPanel { id: panel }

    // ── tree helpers ─────────────────────────────────────────────────────────
    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids) for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
    }
    function findPred(node, pred) {
        var f = null
        eachItem(node, function (n) { if (!f && pred(n)) f = n })
        return f
    }
    function findText(node, str) {
        return findPred(node, function (n) {
            return n.text !== undefined && typeof n.text === "string" && n.text === str
        })
    }
    function findFlick() {
        return findPred(panel, function (n) {
            return n.contentHeight !== undefined && n.contentY !== undefined && n.boundsBehavior !== undefined
        })
    }
    // Theme/orientation/gridCols delegates carry an `active` bool + `modelData`.
    function delegateWhere(pred) {
        return findPred(panel, function (n) { return n.active !== undefined && n.modelData !== undefined && pred(n) })
    }

    TestCase {
        name: "SettingsPanel"
        when: windowShown

        function init() {
            root.themeMode = "dark"; root.glassOpacity = 0.6
            root.showWidgetGlow = true; root.animatedBackground = true; root.reduceMotion = false
            _theme.applyTheme("dark"); _theme.applyAccent("blue")
            panel.shown = true
            tryVerify(function () { return panel.opacity > 0.99 }, 2000)
        }

        function bringIntoView(target) {
            var scroll = findFlick()
            verify(scroll !== null, "found the settings Flickable")
            var p = target.mapToItem(scroll.contentItem, 0, 0)
            var maxY = Math.max(0, scroll.contentHeight - scroll.height)
            scroll.contentY = Math.max(0, Math.min(maxY, p.y - 40))
            wait(60)
        }
        function clickTarget(target) { bringIntoView(target); mouseClick(target) }

        // ── Theme mode (segmented) ───────────────────────────────────────────
        function test_theme_mode_reflects_external_state() {
            root.themeMode = "midnight"
            var d = delegateWhere(function (n) { return n.modelData.v === "midnight" })
            verify(d !== null, "midnight theme swatch exists")
            verify(d.active, "the swatch matching root.themeMode is active")
        }

        function test_theme_mode_click_writes_and_applies() {
            var d = delegateWhere(function (n) { return n.modelData.v === "midnight" })
            clickTarget(d)
            compare(root.themeMode, "midnight", "tapping a theme swatch writes root.themeMode")
            verify(Qt.colorEqual(_theme.backgroundColor, "#0B1026"),
                   "…and applies the theme (background is the midnight tone)")
        }

        // ── Accent color ─────────────────────────────────────────────────────
        function test_accent_swatch_click_applies_accent() {
            var d = findPred(panel, function (n) {
                return n.modelData === "green" && n.color !== undefined && n.radius === 26
            })
            verify(d !== null, "found the green accent swatch")
            clickTarget(d)
            compare(_theme.accentName, "green", "tapping a swatch calls applyAccent")
            verify(Qt.colorEqual(_theme.accent, _theme.accentPresets["green"].a), "accent recoloured")
            compare(root.accentName, "green", "the active-swatch source (accentName) tracks the applied accent")
        }

        // ── Layout columns (writes through the store) ────────────────────────
        function test_grid_columns_reflect_store() {
            store.setAppearance("gridCols", 2)
            var d = delegateWhere(function (n) { return n.modelData.v === 2 && n.modelData.l === "2 Columns" })
            verify(d !== null, "2-column delegate exists")
            verify(d.active, "the delegate matching the stored gridCols is active")
        }

        function test_grid_columns_click_writes_store() {
            store.setAppearance("gridCols", 1)
            var d = delegateWhere(function (n) { return n.modelData.v === 2 && n.modelData.l === "2 Columns" })
            clickTarget(d)
            compare(store.appearance().gridCols, 2, "tapping writes gridCols to the store")
        }

        // ── Orientation (segmented) ──────────────────────────────────────────
        function test_orientation_click_writes() {
            var d = delegateWhere(function (n) { return n.modelData.v === "portrait" })
            verify(d !== null, "portrait orientation option exists")
            clickTarget(d)
            compare(root.orientationMode, "portrait", "tapping an orientation writes root.orientationMode")
        }

        // ── Glass / transparency ─────────────────────────────────────────────
        function test_glass_slider_and_label_reflect_value() {
            root.glassOpacity = 0.25
            var slider = findPred(panel, function (n) {
                return n.from !== undefined && n.to !== undefined && n.value !== undefined && n.stepSize !== undefined
            })
            verify(slider !== null, "glass slider present")
            fuzzyCompare(slider.value, 0.25, 0.001, "slider reflects root.glassOpacity")
            verify(findText(panel, "25%") !== null, "the percentage label reflects the value")
        }

        // ── Toggles: glow / animated background / reduce motion ──────────────
        function switchForLabel(labelText) {
            var t = findText(panel, labelText)
            if (!t) return null
            var rowKids = t.parent.children
            for (var i = 0; i < rowKids.length; i++)
                if (rowKids[i].checked !== undefined && rowKids[i].checkable !== undefined) return rowKids[i]
            return null
        }

        function test_reduce_motion_toggle_writes() {
            var sw = switchForLabel("Reduce motion")
            verify(sw !== null, "found the reduce-motion switch")
            compare(sw.checked, false, "reflects reduceMotion=false")
            clickTarget(sw)
            compare(root.reduceMotion, true, "toggling writes root.reduceMotion")
            compare(sw.checked, true, "the switch re-reflects the source after re-binding")
        }

        function test_glow_toggle_writes() {
            var sw = switchForLabel("Accent glow")
            verify(sw !== null, "found the accent-glow switch")
            compare(sw.checked, true, "reflects showWidgetGlow=true")
            clickTarget(sw)
            compare(root.showWidgetGlow, false, "toggling writes root.showWidgetGlow")
        }

        function test_animated_background_toggle_writes() {
            var sw = switchForLabel("Animated background")
            verify(sw !== null, "found the animated-background switch")
            clickTarget(sw)
            compare(root.animatedBackground, false, "toggling writes root.animatedBackground")
        }
    }
}
