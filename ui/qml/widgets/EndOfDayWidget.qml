import QtQuick
import QtQuick.Layouts

// End of Day — progress through the workday + time remaining. Real (system
// clock). Start/end hours are configurable and persisted.
//
// Sizing (W1 wave 2a): layout keys off the injected `sizeClass`.
//   • 0.5x0.5 (micro) — headerless: the remaining time + a slim bar.
//   • 1x1 (baseline)  — remaining + bar + "% of window" caption (the classic).
//   • wide            — remaining/caption beside the progress (bar or ring —
//                       progressStyle is finally honoured outside the overlay).
//   • tall            — progress hero (ring or bar) + a Started/Ends/Elapsed
//                       detail column: the workday spelled out.
//   • full (overlay)  — unchanged: optional ring + the Start/End pills.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "End of Day"; iconName: "eod"; accentColor: theme.catInfo
    showHeader: !micro

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

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    readonly property bool horiz: sizeClass === "wide"
    readonly property bool tallish: sizeClass === "tall" || sizeClass === "large"
    // The ring style is honoured wherever a ring has room — the overlay (as
    // before) and now tall/wide tiles. micro/baseline keep the quiet bar.
    readonly property bool useRing: progressStyle === "ring" && (expanded || tallish || horiz)
    // The remaining time lives INSIDE the ring in vertical ring layouts; wide
    // keeps it beside the ring (the ring centre carries the percent instead).
    readonly property bool timeInRing: useRing && !horiz
    // Elapsed time inside the current window (for the tall detail column).
    readonly property string elapsedStr: {
        w.tick
        var n = nowDate()
        var wb = windowBounds(n)
        if (wb[1] <= wb[0] || n < wb[0]) return "0h 0m"
        return fmtDur((Math.min(n, wb[1]) - wb[0]) / 1000)
    }

    GridLayout {
        id: lay
        anchors.centerIn: parent
        width: parent.width * 0.88
        columns: w.horiz ? 2 : 1
        columnSpacing: theme.spacingLg
        rowSpacing: w.expanded ? 14 : 6

        // Circular progress — the overlay's ring, now also earned by tall/wide
        // ring-style tiles.
        Item {
            id: ringBox
            visible: w.useRing
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            Layout.preferredWidth: Math.round(w.expanded ? Math.min(w.width * 0.7, w.height * 0.55, 320)
                                            : w.horiz ? Math.min(w.height * 0.58, w.width * 0.34, 280)
                                                      : Math.min(w.width * 0.62, w.height * 0.42, 300))
            Layout.preferredHeight: Layout.preferredWidth
            RingProgress {
                anchors.fill: parent
                value: w.frac
                progressColor: w.effAccent; progressColor2: w.effAccent
            }
            ColumnLayout {
                anchors.centerIn: parent; spacing: 2
                width: Math.max(24, ringBox.width * 0.72)
                Text { Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: w.timeInRing ? w.remaining : Math.round(w.frac * 100) + "%"
                    elide: Text.ElideRight; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 10
                    font.pixelSize: Math.min(ringBox.width * 0.22, 56)
                    font.bold: true; font.family: theme.fontMono; color: w.effAccent }
                Text { Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: w.timeInRing && w.showPercent
                    text: Math.round(w.frac * 100) + "%"; font.pixelSize: 18; color: theme.textSecondary }
            }
        }

        // Text + bar column (everything that is not the ring).
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: w.expanded ? 14 : 6

            Text {
                visible: !w.timeInRing
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter; text: w.remaining
                elide: Text.ElideRight; fontSizeMode: Text.HorizontalFit
                font.pixelSize: w.expanded ? 80
                              : Math.max(24, Math.min(w.width * 0.24, w.micro ? 64 : 52))
                font.bold: true; font.family: theme.fontMono; color: w.effAccent
            }
            Rectangle {
                visible: !w.useRing
                Layout.fillWidth: true; Layout.preferredHeight: w.expanded ? 14 : w.micro ? 8 : 10
                radius: height / 2; color: theme.cardBorder
                Rectangle { height: parent.height; radius: height / 2; width: parent.width * w.frac; color: w.effAccent
                    Behavior on width { NumberAnimation { duration: theme.motionValue; easing.type: Easing.OutCubic } } }
            }
            // The percent-of-window caption. micro is the one number + bar; a
            // tall TILE's detail column below spells the window out instead
            // (tall && expanded keeps it — only the rendered detail column may
            // replace it).
            Text {
                visible: w.showPercent && !w.timeInRing && !w.micro
                         && !(w.tallish && !w.expanded && w.validHours)
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight; fontSizeMode: Text.HorizontalFit
                text: Math.round(w.frac * 100) + "% of " + w.fmtHour(w.startHour) + "–" + w.fmtHour(w.endHour)
                font.pixelSize: w.expanded ? 15 : 12; color: theme.textSecondary
            }
            // Tall tiles spell the workday out — genuinely more information.
            ColumnLayout {
                visible: w.tallish && !w.expanded && w.validHours
                Layout.fillWidth: true
                Layout.topMargin: theme.spacingSm
                spacing: theme.spacingXs
                Repeater {
                    model: [
                        { k: "Started", val: w.fmtHour(w.startHour) },
                        { k: "Ends",    val: w.fmtHour(w.endHour) },
                        { k: "Elapsed", val: w.elapsedStr },
                        { k: "Done",    val: Math.round(w.frac * 100) + "%" }
                    ]
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: theme.spacingMd
                        // The Done row duplicates the caption's percent — it
                        // honours the same showPercent switch.
                        visible: modelData.k !== "Done" || w.showPercent
                        Text { text: modelData.k
                            font.pixelSize: Math.max(13, Math.min(w.width * 0.045, 17))
                            color: theme.textSecondary }
                        Item { Layout.fillWidth: true }
                        Text { text: modelData.val
                            font.pixelSize: Math.max(13, Math.min(w.width * 0.05, 19))
                            font.family: theme.fontMono; color: theme.textPrimary }
                    }
                }
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
}
