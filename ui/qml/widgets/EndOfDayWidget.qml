import QtQuick
import QtQuick.Layouts

// End of Day — progress through the workday + time remaining. Real (system
// clock). Start/end hours are configurable and persisted.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "End of Day"; iconName: "eod"; accentColor: theme.catInfo

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    // Config can arrive out of range (the number stepper writes raw values, or a
    // pushed doc). Wrap the start into 0..23 (25:00 → 01:00) and clamp the end
    // into 0..24 (24:00 = next-day midnight is a valid "end of day"), so a bad
    // config can never corrupt the window.
    property int startHour: {
        var raw = cfg.startHour !== undefined ? Math.round(cfg.startHour) : 9
        return ((raw % 24) + 24) % 24
    }
    property int endHour: {
        var raw = cfg.endHour !== undefined ? Math.round(cfg.endHour) : 17
        return Math.max(0, Math.min(24, raw))
    }
    readonly property bool showPercent: cfg.showPercent !== undefined ? cfg.showPercent : true
    readonly property string progressStyle: cfg.progressStyle !== undefined ? cfg.progressStyle : "bar"

    property bool validHours: endHour > startHour
    // Longest overnight (end < start) window we treat as a real night shift; a
    // longer wrap is almost certainly swapped hours, so it stays invalid.
    readonly property int maxOvernightSpan: 12
    // Test seam: force a deterministic "now" (a Date) so the time math can be
    // exercised without the wall clock. null → live system clock.
    property var nowOverride: null
    function nowDate() { return nowOverride !== null ? nowOverride : new Date() }
    // Window endpoints containing (or, failing that, next after) `ref`.
    //   • Same-day windows (start < end) anchor both ends on ref's date.
    //   • Overnight windows (end ≤ start, within maxOvernightSpan) span midnight,
    //     so a single date-anchoring is wrong after midnight. We consider TWO
    //     candidate anchorings — one that started YESTERDAY and ends today, and
    //     one that starts today and ends tomorrow — and return whichever
    //     currently CONTAINS ref. So at 03:00 a 22→06 shift resolves to
    //     [yesterday 22:00, today 06:00] (in-window, ~62%, 3h left), while at
    //     23:00 it resolves to [today 22:00, tomorrow 06:00] (7h left).
    //     If neither contains ref, the today-anchored window is the next
    //     upcoming one and drives the "Starts in …" label.
    // Calendar construction (new Date(y,m,d,h,…)) keeps this DST-safe.
    function windowBounds(ref) {
        var y = ref.getFullYear(), mo = ref.getMonth(), d = ref.getDate()
        if (endHour > startHour)                              // same-day window
            return [new Date(y, mo, d, startHour, 0, 0, 0),
                    new Date(y, mo, d, endHour,   0, 0, 0)]
        if ((24 - startHour + endHour) > maxOvernightSpan)    // implausible wrap → invalid
            return [ref, ref]
        var sPrev = new Date(y, mo, d - 1, startHour, 0, 0, 0)   // started yesterday
        var ePrev = new Date(y, mo, d,     endHour,   0, 0, 0)   // ends today
        if (ref >= sPrev && ref < ePrev) return [sPrev, ePrev]
        return [new Date(y, mo, d,     startHour, 0, 0, 0),      // starts today
                new Date(y, mo, d + 1, endHour,   0, 0, 0)]      // ends tomorrow
    }
    property real frac: {
        w.tick
        var n = nowDate()
        var wb = windowBounds(n)
        var s = wb[0], e = wb[1]
        if (e <= s) return 0
        return Math.max(0, Math.min(1, (n - s) / (e - s)))
    }
    function fmtDur(secs) {
        return Math.floor(secs / 3600) + "h " + Math.floor((secs % 3600) / 60) + "m"
    }
    function fmtHour(h) { return (h < 10 ? "0" + h : "" + h) + ":00" }   // zero-padded, editor-style
    property string remaining: {
        w.tick
        var n = nowDate()
        var wb = windowBounds(n)
        var s = wb[0], e = wb[1]
        if (e <= s) return "Set hours"                    // invalid (end ≤ start, not overnight)
        if (n < s) return "Starts in " + fmtDur((s - n) / 1000)  // before the workday
        var d = (e - n) / 1000
        if (d <= 0) return "Done! 🎉"
        return fmtDur(d)
    }
    // Keep a 1-hour minimum span: whichever end the user moved yields, so the
    // work window can never invert (end ≤ start) and get stuck.
    function setHours(sh, eh) {
        var s = Math.max(0, Math.min(23, sh))
        var e = Math.max(1, Math.min(24, eh))
        if (s >= e) { if (sh !== w.startHour) s = e - 1; else e = s + 1 }
        if (store) store.patchSettings(instanceId, { "startHour": s, "endHour": e })
    }

    ColumnLayout {
        anchors.centerIn: parent; width: parent.width * 0.88; spacing: w.expanded ? 14 : 6

        // Optional circular progress (expanded only) with the time in the centre.
        Item {
            visible: w.expanded && w.progressStyle === "ring"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(w.width * 0.7, w.height * 0.55, 320)
            Layout.preferredHeight: Layout.preferredWidth
            RingProgress {
                anchors.fill: parent
                value: w.frac
                progressColor: w.effAccent; progressColor2: w.effAccent
            }
            ColumnLayout {
                anchors.centerIn: parent; spacing: 2
                Text { Layout.alignment: Qt.AlignHCenter; text: w.remaining
                    font.pixelSize: Math.min(parent.parent.width * 0.22, 56)
                    font.bold: true; font.family: theme.fontMono; color: w.effAccent }
                Text { Layout.alignment: Qt.AlignHCenter; visible: w.showPercent
                    text: Math.round(w.frac * 100) + "%"; font.pixelSize: 18; color: theme.textSecondary }
            }
        }

        Text {
            visible: !(w.expanded && w.progressStyle === "ring")
            Layout.fillWidth: true; Layout.maximumWidth: parent.width
            Layout.alignment: Qt.AlignHCenter; text: w.remaining
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight; fontSizeMode: Text.HorizontalFit
            font.pixelSize: w.expanded ? 80 : Math.max(24, Math.min(w.width * 0.24, 44))
            font.bold: true; font.family: theme.fontMono; color: w.effAccent
        }
        Rectangle {
            visible: !(w.expanded && w.progressStyle === "ring")
            Layout.fillWidth: true; Layout.preferredHeight: w.expanded ? 14 : 8
            radius: height / 2; color: theme.cardBorder
            Rectangle { height: parent.height; radius: height / 2; width: parent.width * w.frac; color: w.effAccent
                Behavior on width { NumberAnimation { duration: theme.motionValue; easing.type: Easing.OutCubic } } }
        }
        Text {
            visible: w.showPercent && !(w.expanded && w.progressStyle === "ring")
            Layout.fillWidth: true; Layout.maximumWidth: parent.width
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight; fontSizeMode: Text.HorizontalFit
            text: Math.round(w.frac * 100) + "% of " + w.fmtHour(w.startHour) + "–" + w.fmtHour(w.endHour)
            font.pixelSize: w.expanded ? 15 : 12; color: theme.textSecondary
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded; spacing: theme.spacingMd
            PillButton { label: "Start −"; onClicked: w.setHours(w.startHour - 1, w.endHour) }
            PillButton { label: "Start +"; onClicked: w.setHours(w.startHour + 1, w.endHour) }
            PillButton { label: "End −"; onClicked: w.setHours(w.startHour, w.endHour - 1) }
            PillButton { label: "End +"; onClicked: w.setHours(w.startHour, w.endHour + 1) }
        }
    }
}
