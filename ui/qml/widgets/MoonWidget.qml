import QtQuick
import QtQuick.Layouts

// Moon phase — computed locally from the current date (synodic month).
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Moon Phase"; iconName: "moon"; accentColor: theme.catInfo
    big: expanded; showHeader: expanded

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

    ColumnLayout {
        anchors.centerIn: parent
        spacing: w.expanded ? 14 : 2
        Text { id: moonGlyph; Layout.alignment: Qt.AlignHCenter; text: w.phases[w.idx]
            font.pixelSize: w.expanded ? 150 : Math.min(w.width * 0.4, 58)
            // Southern hemisphere sees the moon mirrored: flip the lit side horizontally.
            transform: Scale { origin.x: moonGlyph.width / 2
                xScale: w.hemisphere === "south" ? -1 : 1 } }
        Text { Layout.alignment: Qt.AlignHCenter; text: w.names[w.idx]
            font.pixelSize: w.expanded ? 26 : 12; color: theme.textSecondary }
        Text { Layout.alignment: Qt.AlignHCenter; visible: w.expanded
            text: w.illum + "% illuminated  ·  " + w.ageDays.toFixed(1) + " days old"
            font.pixelSize: 16; color: theme.textTertiary }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded; spacing: theme.spacingXl
            Layout.topMargin: theme.spacingSm
            ColumnLayout {
                spacing: 1
                Text { Layout.alignment: Qt.AlignHCenter; text: "🌑 New"; font.pixelSize: 13; color: theme.textSecondary }
                Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDate(w.nextNew, "ddd, d MMM")
                    font.pixelSize: 14; font.bold: true; color: theme.textPrimary }
            }
            ColumnLayout {
                spacing: 1
                Text { Layout.alignment: Qt.AlignHCenter; text: "🌕 Full"; font.pixelSize: 13; color: theme.textSecondary }
                Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDate(w.nextFull, "ddd, d MMM")
                    font.pixelSize: 14; font.bold: true; color: theme.textPrimary }
            }
        }
    }
}
