import QtQuick
import QtQuick.Layouts

// Moon phase — computed locally from the current date (synodic month).
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Moon Phase"; icon: "🌙"; accentColor: theme.catInfo
    big: expanded; showHeader: expanded

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
        Text { Layout.alignment: Qt.AlignHCenter; text: w.phases[w.idx]
            font.pixelSize: w.expanded ? 150 : Math.min(w.width * 0.4, 58) }
        Text { Layout.alignment: Qt.AlignHCenter; text: w.names[w.idx]
            font.pixelSize: w.expanded ? 26 : 12; color: theme.textSecondary }
        Text { Layout.alignment: Qt.AlignHCenter; visible: w.expanded
            text: w.illum + "% illuminated"; font.pixelSize: 16; color: theme.textTertiary }
    }
}
