import QtQuick
import QtQuick.Layouts

// Moon phase — computed locally from the current date (synodic month).
//
// Sizing (W1 wave 2a): layout keys off the injected `sizeClass`. The tile
// stays headerless (the glyph IS the header); each size earns its box:
//   • 0.5x0.5 (micro) — the glyph alone, scaled to the box.
//   • 1x1 (baseline)  — glyph + phase name + "% illuminated" (the old 58px
//                       emoji floated tiny in a third of the screen).
//   • wide            — glyph beside a name / illumination / age column.
//   • tall            — glyph + name + illumination/age + next new/full dates
//                       (the dates used to be locked behind the overlay).
//   • full (overlay)  — the full readout, header shown.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Moon Phase"; iconName: "moon"; accentColor: theme.catInfo
    showHeader: expanded

    // Live per-instance config (see WidgetConfigSchema "moon").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string hemisphere: cfg.hemisphere !== undefined ? cfg.hemisphere : "north"

    readonly property var phases: ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]
    readonly property var names: ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
                                  "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
    // Recompute daily via the tick (cheap; changes only across midnight).
    readonly property real _synodicSec: 2551443.0 // synodic month in seconds
    property real _cyclePos: {
        w.tick
        var now = new Date().getTime() / 1000
        // Canonical reference new moon: 2000-01-06 18:14 UTC (must be built in UTC,
        // else the viewer's timezone offset skews the phase).
        var newMoonRef = Date.UTC(2000, 0, 6, 18, 14) / 1000
        var frac = ((now - newMoonRef) % w._synodicSec) / w._synodicSec
        if (frac < 0) frac += 1
        return frac
    }
    property int idx: Math.floor(_cyclePos * 8 + 0.5) % 8
    // True illuminated fraction of a sphere: (1 - cos(phase angle)) / 2, where the
    // phase angle sweeps 0→2π across the synodic month (0 at new, π at full).
    property int illum: Math.round((1 - Math.cos(_cyclePos * 2 * Math.PI)) / 2 * 100)
    // Lunar age in days and the dates of the next new / full moon (all derived).
    property real ageDays: _cyclePos * (_synodicSec / 86400)
    function _nextDate(targetPos) {
        var ahead = targetPos - _cyclePos
        if (ahead <= 0) ahead += 1
        return new Date(new Date().getTime() + ahead * _synodicSec * 1000)
    }
    property var nextNew: (w.tick, _nextDate(0))
    property var nextFull: (w.tick, _nextDate(0.5))

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    readonly property bool horiz: sizeClass === "wide"
    readonly property bool tallish: sizeClass === "tall" || sizeClass === "large"
    // The glyph scales to its box (line box ≈ pixelSize * 1.3), clamped per
    // class so it reads as a moon, not a wall.
    readonly property real glyphPx: expanded ? 150
        : micro ? Math.min(width * 0.5, height * 0.55, 130)
        : horiz ? Math.min(width * 0.30, height * 0.55, 170)
        : Math.min(width * 0.42, height * 0.38, 190)
    // Illumination context: the tiles that have room add the lunar age.
    readonly property string illumLine: (horiz || tallish || expanded)
        ? w.illum + "% illuminated  ·  " + w.ageDays.toFixed(1) + " days old"
        : w.illum + "% illuminated"

    GridLayout {
        id: moonLay
        anchors.centerIn: parent
        width: parent.width
        columns: w.horiz ? 2 : 1
        rowSpacing: w.expanded ? 14 : 2
        columnSpacing: theme.spacingLg

        Text { id: moonGlyph
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            text: w.phases[w.idx]
            font.pixelSize: Math.max(12, w.glyphPx)
            // Southern hemisphere sees the moon mirrored: flip the lit side horizontally.
            transform: Scale { origin.x: moonGlyph.width / 2
                xScale: w.hemisphere === "south" ? -1 : 1 } }

        ColumnLayout {
            visible: !w.micro
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: w.expanded ? 14 : 4

            // fillWidth (not maximumWidth): a non-fill Text caps the nested
            // column's own stretch, which pinned the whole block to the left.
            Text { Layout.fillWidth: true; text: w.names[w.idx]
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight; fontSizeMode: Text.HorizontalFit
                font.pixelSize: w.expanded ? 26 : Math.max(14, Math.min(w.width * 0.045, 24))
                font.family: theme.fontDisplay
                color: w.effAccent }
            Text { Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 9
                text: w.illumLine
                font.pixelSize: w.expanded ? 16 : Math.max(12, Math.min(w.width * 0.032, 16))
                color: theme.textTertiary }
            // Next new/full dates — the overlay's readout, now also earned by
            // tall tiles (genuinely more information, not a stretched glyph).
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                visible: w.expanded || w.tallish
                spacing: theme.spacingXl
                Layout.topMargin: theme.spacingSm
                ColumnLayout {
                    spacing: 1
                    Text { Layout.alignment: Qt.AlignHCenter; text: "🌑 New"; font.pixelSize: 13; color: theme.textSecondary }
                    Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDate(w.nextNew, "ddd, d MMM")
                        font.pixelSize: 14; font.bold: true; color: w.effAccent }
                }
                ColumnLayout {
                    spacing: 1
                    Text { Layout.alignment: Qt.AlignHCenter; text: "🌕 Full"; font.pixelSize: 13; color: theme.textSecondary }
                    Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDate(w.nextFull, "ddd, d MMM")
                        font.pixelSize: 14; font.bold: true; color: w.effAccent }
                }
            }
        }
    }
}
