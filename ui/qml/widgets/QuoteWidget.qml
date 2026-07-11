import QtQuick
import QtQuick.Layouts

// Daily quote — rotates once per day from a local list (no network).
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Daily Quote"; icon: "💬"; accentColor: theme.catInfo
    big: expanded; showHeader: expanded

    readonly property var quotes: [
        { t: "Simplicity is the soul of efficiency.", a: "Austin Freeman" },
        { t: "Make it work, make it right, make it fast.", a: "Kent Beck" },
        { t: "The best way out is always through.", a: "Robert Frost" },
        { t: "Focus is saying no to a thousand good ideas.", a: "Steve Jobs" },
        { t: "Well done is better than well said.", a: "Ben Franklin" },
        { t: "Discipline equals freedom.", a: "Jocko Willink" },
        { t: "Start where you are. Use what you have. Do what you can.", a: "Arthur Ashe" },
        { t: "Action is the antidote to anxiety.", a: "Unknown" },
        { t: "Done is better than perfect.", a: "Sheryl Sandberg" },
        { t: "Small steps every day.", a: "Unknown" }
    ]
    // Day-of-year index → stable for the whole day, rotates at midnight (via tick).
    property int idx: {
        w.tick
        var n = new Date()
        var start = new Date(n.getFullYear(), 0, 0)
        var doy = Math.floor((n - start) / 86400000)
        return doy % quotes.length
    }
    property var q: quotes[idx]

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.9
        spacing: w.expanded ? 14 : 4
        Text { Layout.alignment: Qt.AlignHCenter; text: "“"; font.bold: true
            font.pixelSize: w.expanded ? 72 : 30; color: theme.catInfo }
        Text {
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: w.q.t; font.italic: true; color: theme.textPrimary
            font.pixelSize: w.expanded ? 30 : Math.max(12, Math.min(w.width * 0.075, 16))
            maximumLineCount: w.expanded ? 6 : 4; elide: Text.ElideRight
        }
        Text { Layout.alignment: Qt.AlignHCenter; text: "— " + w.q.a
            font.pixelSize: w.expanded ? 18 : 11; color: theme.textSecondary }
    }
}
