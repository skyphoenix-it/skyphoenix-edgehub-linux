import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Countdown — days until a user-set date. Persisted; genuinely real once set.
//
// Sizing (W1): layout keys off `sizeClass` (injected by Dashboard — compact/
// wide/tall/large/full), NEVER off `expanded`, which is only used for the
// overlay's settings editor. Each declared size earns its space:
//   • 0.5x0.5 (micro) — the day count + a one-line caption, nothing else.
//   • 1x1 (compact)   — count + caption + the target-date row.
//   • wide            — count beside a left-aligned caption/date/progress column
//                       (1x0.5 portrait, 0.5x1 + 1x1.5 landscape).
//   • tall            — count over caption/date/progress, roomier type
//                       (0.5x1 + 1x1.5 portrait, 1x0.5 landscape).
//   • full            — the overlay: hero count + date + progress + editor.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "Countdown"; iconName: "countdown"; accentColor: theme.catInfo
    showHeader: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string label: cfg.label || ""
    readonly property string dateStr: cfg.date || ""
    readonly property bool repeatYearly: cfg.repeatYearly !== undefined ? cfg.repeatYearly : false
    function dayStart(d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x }
    // Parse "YYYY-MM-DD" into a LOCAL-midnight Date, or null when malformed —
    // new Date(str) would treat it as UTC midnight and, west of UTC, land the
    // countdown one day off. Returns null for impossible days (Feb-31, Apr-31),
    // which JS would otherwise silently roll into the following month.
    function parseDate(str) {
        if (!str || !("" + str).length) return null
        var p = ("" + str).split("-")
        if (p.length < 3) return null
        var y = +p[0], mo = +p[1] - 1, d = +p[2]
        if (isNaN(y) || isNaN(mo) || isNaN(d) || mo < 0 || mo > 11 || d < 1 || d > 31) return null
        var target = new Date(y, mo, d)
        // Reject rollovers (e.g. Feb-31 → Mar-3): the built date must round-trip.
        if (isNaN(target.getTime()) || target.getFullYear() !== y ||
            target.getMonth() !== mo || target.getDate() !== d) return null
        return target
    }
    // The date the countdown is actually aiming at: the stored date, or — for a
    // yearly repeat — its next occurrence on or after today (skipping non-leap
    // years for a Feb-29 anniversary, where new Date(y,1,29) rolls to Mar-1).
    function nextTarget() {
        var target = parseDate(dateStr)
        if (!target) return null
        if (!w.repeatYearly) return target
        var today0 = dayStart(new Date())
        var mo = target.getMonth(), d = target.getDate()
        for (var i = 0; i < 12; i++) {
            var c = new Date(today0.getFullYear() + i, mo, d)
            if (c.getMonth() !== mo || c.getDate() !== d) continue
            if (dayStart(c) >= today0) return c
        }
        return null
    }
    // Validity is derived from parsing, NOT from `days`: a real date exactly 999
    // days in the past legitimately yields days === -999, which must not be
    // mistaken for the invalid sentinel.
    property bool valid: parseDate(dateStr) !== null
    property int days: {
        w.tick
        var target = nextTarget()
        if (!target) return -999   // -999 sentinel = invalid/unset
        return Math.round((dayStart(target) - dayStart(new Date())) / 86400000)
    }

    // ── Progress context (an honest baseline or none at all) ────────────────
    // • repeatYearly: previous → next occurrence (the year cycle) — always real.
    // • one-time: from the moment THIS date was stored (dateSetEpoch, stamped
    //   below). No baseline → no bar; a made-up one would be a lie.
    readonly property real progress: {
        w.tick
        var target = nextTarget()
        if (!target || w.days < 0) return -1
        var end = dayStart(target).getTime()
        var start = -1
        if (w.repeatYearly) {
            for (var back = 1; back <= 8; back++) {
                var prev = new Date(target.getFullYear() - back, target.getMonth(), target.getDate())
                if (prev.getMonth() === target.getMonth() && prev.getDate() === target.getDate()) {
                    start = dayStart(prev).getTime()
                    break
                }
            }
        } else if (cfg.dateSetFor === w.dateStr && cfg.dateSetEpoch > 0) {
            start = cfg.dateSetEpoch
        }
        if (start < 0 || end <= start) return -1
        return Math.max(0, Math.min(1, (Date.now() - start) / (end - start)))
    }
    // Stamp when a (valid) date is stored so the one-time progress bar has a real
    // starting line. Keyed to the date string, so re-saving the same date never
    // moves the baseline; only the active instance writes (tile + overlay are two
    // instances of the same id) and the write is deferred out of binding eval.
    onDateStrChanged: Qt.callLater(_stampDateSet)
    function _stampDateSet() {
        if (!w.active || !store || !instanceId) return
        if (!w.valid || cfg.dateSetFor === w.dateStr) return
        store.patchSettings(instanceId, { dateSetFor: w.dateStr, dateSetEpoch: Date.now() })
    }

    // ── Per-size layout flags ────────────────────────────────────────────────
    // 0.5x0.5 and 1x1 are BOTH "compact" (the class describes shape, not
    // footprint); the micro half-cell is told apart by the box itself — its short
    // side is ~344-416px in either orientation vs ~690px+ for a full cell.
    readonly property bool micro: sizeClass === "compact" && Math.min(width, height) < 480
    readonly property bool horiz: sizeClass === "wide"
    readonly property bool showDateRow: valid && days >= 0 && !micro
    readonly property bool showProgress: progress >= 0 && sizeClass !== "compact"
    readonly property real numPx: {
        if (sizeClass === "full") return 120
        if (micro) return Math.max(24, Math.min(width * 0.30, height * 0.36))
        if (sizeClass === "compact") return Math.max(30, Math.min(width * 0.26, height * 0.22, 140))
        if (horiz) return Math.max(34, Math.min(width * 0.20, height * 0.42, 150))
        return Math.max(32, Math.min(width * 0.30, height * 0.18, 150))   // tall
    }

    GridLayout {
        id: tileLayout
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left; anchors.right: parent.right
        visible: !w.expanded || w.valid
        columns: w.horiz ? 2 : 1
        rowSpacing: w.micro ? 2 : (w.sizeClass === "full" ? theme.spacingSm : theme.spacingXs)
        columnSpacing: theme.spacingLg

        Text {
            id: numText
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            // Constrain to the cell width and shrink-to-fit so a large (5-digit)
            // day count never overflows/clips a narrow tile. preferredWidth (not
            // just maximumWidth) forces the layout to allocate exactly this
            // width, so HorizontalFit has a fixed box to shrink into — a bare
            // maximumWidth cap is ignored for an oversized implicitWidth on some
            // Qt versions (e.g. 6.7), letting the number overflow.
            Layout.preferredWidth: w.horiz ? Math.round(tileLayout.width * 0.42)
                                           : tileLayout.width
            Layout.maximumWidth: w.horiz ? Math.round(tileLayout.width * 0.42)
                                         : tileLayout.width
            horizontalAlignment: Text.AlignHCenter
            text: !w.valid ? "—" : (w.days > 0 ? w.days : (w.days === 0 ? "🎉" : Math.abs(w.days)))
            font.pixelSize: w.numPx
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 12; elide: Text.ElideRight
            font.bold: true; font.family: theme.fontMono; color: w.effAccent
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            spacing: w.micro ? 0 : theme.spacingXs

            Text {
                Layout.fillWidth: true
                horizontalAlignment: w.horiz ? Text.AlignLeft : Text.AlignHCenter
                text: !w.valid ? "Set a date below" :
                      (w.days > 0 ? (w.days === 1 ? "day until " : "days until ") + (w.label || "the day")
                       : w.days === 0 ? (w.label || "Today") + "!"
                       : (w.label || "the day") + " passed")
                font.pixelSize: w.sizeClass === "full" ? 22 : (w.micro ? 11 : (w.sizeClass === "compact" ? 14 : 16))
                color: theme.textSecondary
                wrapMode: Text.WordWrap; maximumLineCount: w.micro ? 1 : 2; elide: Text.ElideRight
            }
            Text {
                visible: w.showDateRow
                Layout.fillWidth: true
                horizontalAlignment: w.horiz ? Text.AlignLeft : Text.AlignHCenter
                text: {
                    w.tick
                    var target = w.nextTarget()
                    return target ? Qt.formatDate(target, "ddd, d MMM yyyy") : ""
                }
                font.pixelSize: w.sizeClass === "full" ? 18
                                : Math.max(12, Math.min(w.width * 0.035, 17))
                font.family: theme.fontMono
                color: theme.textTertiary
                elide: Text.ElideRight; maximumLineCount: 1
            }
            // Progress toward the day: only with room (never in compact) and only
            // when a real baseline exists.
            Rectangle {
                visible: w.showProgress
                Layout.topMargin: theme.spacingSm
                Layout.fillWidth: true
                Layout.maximumWidth: w.horiz ? tileLayout.width : Math.round(tileLayout.width * 0.86)
                Layout.alignment: w.horiz ? Qt.AlignLeft : Qt.AlignHCenter
                height: 6; radius: 3
                color: Qt.rgba(theme.cardBorder.r, theme.cardBorder.g, theme.cardBorder.b, 0.6)
                Rectangle {
                    width: Math.round(parent.width * Math.max(0, Math.min(1, w.progress)))
                    height: parent.height; radius: parent.radius
                    color: w.effAccent
                }
            }
        }
    }

    // Settings (expanded overlay only — a mode, not a size)
    ColumnLayout {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        visible: w.expanded; spacing: theme.spacingSm
        RowLayout {
            Layout.fillWidth: true; spacing: theme.spacingSm
            TextField {
                id: labelField; Layout.fillWidth: true; Layout.preferredHeight: theme.touchSecondary; text: w.label
                placeholderText: "Label (e.g. Vacation)"; placeholderTextColor: theme.textTertiary
                color: theme.textPrimary; font.pixelSize: 15
                background: Rectangle { radius: theme.radiusSm; color: theme.backgroundColor
                    border.color: labelField.activeFocus ? theme.accent : theme.cardBorder; border.width: 1 }
                onEditingFinished: if (w.store) w.store.setSetting(w.instanceId, "label", text)
            }
            TextField {
                id: dateField; Layout.preferredWidth: 150; Layout.preferredHeight: theme.touchSecondary; text: w.dateStr
                placeholderText: "YYYY-MM-DD"; placeholderTextColor: theme.textTertiary
                color: theme.textPrimary; font.pixelSize: 15; inputMask: "9999-99-99"
                background: Rectangle { radius: theme.radiusSm; color: theme.backgroundColor
                    border.color: dateField.activeFocus ? theme.accent : theme.cardBorder; border.width: 1 }
                onEditingFinished: if (w.store) w.store.setSetting(w.instanceId, "date", text)
            }
            PillButton { label: "Save"; primary: true; tint: w.effAccent
                onClicked: if (w.store) w.store.patchSettings(w.instanceId, { "label": labelField.text, "date": dateField.text }) }
        }
    }
}
