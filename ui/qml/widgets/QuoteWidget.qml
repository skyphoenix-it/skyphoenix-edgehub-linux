import QtQuick
import QtQuick.Layouts

// Daily quote — rotates once per day from a chosen category (or your own custom
// list); no network. A "Shuffle" picks a fresh one on demand.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Daily Quote"; iconName: "quote"; accentColor: theme.catInfo
    showHeader: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string category: cfg.category !== undefined ? cfg.category : "focus"
    readonly property string customText: cfg.customText !== undefined ? cfg.customText : ""

    readonly property var library: ({
        "focus": [
            { t: "Simplicity is the soul of efficiency.", a: "Austin Freeman" },
            { t: "Make it work, make it right, make it fast.", a: "Kent Beck" },
            { t: "Focus is saying no to a thousand good ideas.", a: "Steve Jobs" },
            { t: "Well done is better than well said.", a: "Ben Franklin" },
            { t: "Done is better than perfect.", a: "Sheryl Sandberg" },
            { t: "Small steps every day.", a: "Unknown" },
            { t: "Action is the antidote to anxiety.", a: "Unknown" }
        ],
        "stoic": [
            { t: "We suffer more in imagination than in reality.", a: "Seneca" },
            { t: "You have power over your mind — not outside events.", a: "Marcus Aurelius" },
            { t: "The best way out is always through.", a: "Robert Frost" },
            { t: "Discipline equals freedom.", a: "Jocko Willink" },
            { t: "First say to yourself what you would be; then do what you have to do.", a: "Epictetus" },
            { t: "He who fears death will never do anything worthy of a living man.", a: "Seneca" }
        ],
        "humor": [
            { t: "I always wanted to be somebody, but I should have been more specific.", a: "Lily Tomlin" },
            { t: "The road to success is always under construction.", a: "Lily Tomlin" },
            { t: "I can resist everything except temptation.", a: "Oscar Wilde" },
            { t: "Hard work never killed anybody, but why take the chance?", a: "Edgar Bergen" },
            { t: "If at first you don't succeed, then skydiving isn't for you.", a: "Steven Wright" }
        ],
        "kindness": [
            { t: "Start where you are. Use what you have. Do what you can.", a: "Arthur Ashe" },
            { t: "No act of kindness, no matter how small, is ever wasted.", a: "Aesop" },
            { t: "Be kind whenever possible. It is always possible.", a: "Dalai Lama" },
            { t: "You are enough, just as you are.", a: "Unknown" },
            { t: "Progress, not perfection.", a: "Unknown" }
        ]
    })

    // Parse the user's custom list: one quote per line, optional " — Author".
    function parseCustom() {
        var out = []
        var lines = ("" + w.customText).split("\n")
        for (var i = 0; i < lines.length; i++) {
            var ln = lines[i].trim()
            if (!ln.length) continue
            var sep = ln.indexOf(" — ")
            if (sep < 0) sep = ln.indexOf(" -- ")
            if (sep < 0) sep = ln.indexOf(" | ")
            if (sep < 0) sep = ln.indexOf(" - ")   // plain ASCII hyphen (on-device keyboards)
            if (sep >= 0) out.push({ t: ln.substring(0, sep).trim(), a: ln.substring(sep + 3).trim() })
            else out.push({ t: ln, a: "" })
        }
        return out
    }
    // Active pool for the chosen category (custom falls back to focus if empty).
    readonly property var pool: {
        if (w.category === "custom") { var c = parseCustom(); return c.length ? c : library["focus"] }
        return library[w.category] || library["focus"]
    }

    // Calendar day key (local) → changes exactly once per local midnight when the
    // dashboard bumps `tick`. Drives both the daily rotation and the release of a
    // manual shuffle, so a pinned quote can't survive forever (S6).
    readonly property string todayKey: {
        w.tick
        var d = new Date()
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }
    // Day-of-year index → stable for the whole day, rotates at midnight (via tick).
    // Uses UTC calendar-date midnights so the count can't drift an hour across a
    // DST boundary the way a raw ms delta between local timestamps would (S6).
    property int dailyIdx: {
        w.tick
        var n = new Date()
        var doy = Math.round((Date.UTC(n.getFullYear(), n.getMonth(), n.getDate())
                              - Date.UTC(n.getFullYear(), 0, 0)) / 86400000)
        return doy % Math.max(1, w.pool.length)
    }
    // A manual "shuffle" overrides the daily pick until the next day / reset.
    property int manualIdx: -1
    // Identity of the manually-pinned quote, captured when the pin is set, so an
    // edit to the custom list (which reindexes the pool) keeps the same quote
    // pinned instead of silently repointing to whatever slid into that index.
    property string pinnedText: ""
    onManualIdxChanged: pinnedText = (w.manualIdx >= 0 && w.manualIdx < w.pool.length)
                                     ? w.pool[w.manualIdx].t : ""
    onCategoryChanged: manualIdx = -1
    onTodayKeyChanged: manualIdx = -1        // release yesterday's shuffle at midnight
    property int idx: {
        if (w.manualIdx >= 0) {
            if (w.pinnedText.length) {
                for (var i = 0; i < w.pool.length; i++)
                    if (w.pool[i].t === w.pinnedText) return i
            }
            if (w.manualIdx < w.pool.length) return w.manualIdx
        }
        return w.dailyIdx
    }
    property var q: w.pool[idx] || ({ t: "", a: "" })
    function shuffle() {
        if (w.pool.length <= 1) return
        var n = w.idx
        while (n === w.idx) n = Math.floor(Math.random() * w.pool.length)
        w.manualIdx = n
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.9
        spacing: w.expanded ? 14 : 4
        Text { Layout.alignment: Qt.AlignHCenter; text: "“"; font.bold: true
            font.pixelSize: w.expanded ? 72 : 30; color: w.effAccent }
        Text {
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: w.q.t; font.italic: true; color: theme.textPrimary
            font.pixelSize: w.expanded ? 30 : Math.max(12, Math.min(w.width * 0.075, 16))
            maximumLineCount: w.expanded ? 6 : 4; elide: Text.ElideRight
            fontSizeMode: Text.Fit; minimumPixelSize: 10
        }
        Text {
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
            visible: w.q.a.length > 0; text: "— " + w.q.a
            font.pixelSize: w.expanded ? 18 : 12; color: theme.textSecondary
            elide: Text.ElideRight; maximumLineCount: 1
        }
        PillButton {
            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: theme.spacingSm
            visible: w.expanded && w.pool.length > 1
            label: "Shuffle"; glyph: "🔀"; tint: w.effAccent; onClicked: w.shuffle()
        }
    }

    // Compact shuffle — the one useful basic action in the collapsed tile. The
    // top-right is reserved for config, so it sits bottom-right, clear of the
    // centred quote text. Reuses the same shuffle() the expanded pill calls.
    Rectangle {
        id: shuffleCompact
        visible: !w.expanded && w.pool.length > 1
        anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.rightMargin: theme.spacingXs; anchors.bottomMargin: theme.spacingXs
        width: 36; height: 36; radius: width / 2
        color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b,
                       shufMA.pressed ? 0.32 : (shufMA.containsMouse ? 0.22 : 0.14))
        Text { anchors.centerIn: parent; text: "🔀"; font.pixelSize: 16 }
        MouseArea {
            id: shufMA; anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor; onClicked: w.shuffle()
        }
    }
}
