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
    property real _cyclePos: {
        w.tick
        var lp = 2551443.0 // synodic month in seconds
        var now = new Date().getTime() / 1000
        var newMoonRef = new Date(2000, 0, 6, 18, 14).getTime() / 1000
        var frac = ((now - newMoonRef) % lp) / lp
        if (frac < 0) frac += 1
        return frac
    }
    property int idx: Math.floor(_cyclePos * 8 + 0.5) % 8
    property int illum: Math.round((1 - Math.abs(0.5 - _cyclePos) * 2) * 100)

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
            text: w.illum + "% illuminated"; font.pixelSize: 16; color: theme.textTertiary }
    }
}
