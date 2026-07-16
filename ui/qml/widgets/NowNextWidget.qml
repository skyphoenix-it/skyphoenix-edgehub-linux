import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ─────────────────────────────────────────────────────────────────────────
// Now / Next — the two questions an agenda actually gets asked: what am I
// supposed to be doing, and what is coming.
//
// WHY IT EMBEDS CalendarWidget. Calendar already answers this: its `events` model
// is expanded, sorted, recurrence-aware, EXDATE-aware, TZID-aware and horizon-
// bounded. Re-deriving now/next from a second, simpler ICS parser would mean two
// implementations of "when is this event, really" — and the one in Calendar took
// DST-safe day stepping, webcal rewriting and a supersede guard to get right. So
// this widget instantiates a headless CalendarWidget (zero-sized, invisible) purely
// as an agenda MODEL and reads `events` off it. The nested instance is passed our
// own `instanceId`, so it reads the same `url` setting and there is exactly one
// source of truth per tile.
//
// EGRESS. Nothing new: the nested Calendar fetches through the injected NetHub —
// the same gate, the same kill switch, the same allowlist, the same counters, and
// the same 15-minute poll gated on `active`. This widget constructs no XHR of its
// own (`check_no_raw_xhr.sh` would fail the build if it did). It is honestly ONE
// MORE request of the URL you already gave it, not a new destination: a tile
// cannot see another tile's parsed model, and wiring a shared agenda cache into
// Dashboard is a bigger change than this widget's remit.
//
// Sizing (W1 wave 2b): there are exactly TWO blocks, ever, so this widget cannot
// earn a size with more rows — it earns it with LEGIBILITY. The type was a flat
// 17px on every tile and 44px in the overlay, so a 696x819 baseline tile rendered
// the same cramped pair as a 348x819 sliver.
//   • wide  — NOW and NEXT side by side. A 846x306 banner stacked into two blocks
//             leaves each ~120px; beside each other they get the full height.
//   • every other shape — stacked, with the type scaled to the box.
//   • full (overlay) — as before, plus the URL editor (genuinely modal, so that
//             one stays keyed off `expanded`).
// (No 0.5x0.5 is declared, so `micro` is never true here — see WidgetCatalog.)
// ─────────────────────────────────────────────────────────────────────────
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0
    // The app-global egress gate, injected by Dashboard; forwarded to the nested
    // Calendar, which is what actually talks to the network.
    property var netHub: null
    // Test seam, forwarded the same way.
    property var xhrFactory: null

    title: "Now / Next"; iconName: "nownext"; accentColor: theme.catServices

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    readonly property string url: cfg.url || ""

    // The agenda model. Zero-sized + invisible: it is data, not chrome.
    CalendarWidget {
        id: agenda
        width: 0; height: 0; visible: false
        store: w.store
        instanceId: w.instanceId
        active: w.active
        netHub: w.netHub
        xhrFactory: w.xhrFactory
        tick: w.tick
    }

    // Proxies, so this widget's own state reads (and its tests) never have to
    // know the model is a nested component.
    readonly property var events: agenda.events
    readonly property bool loading: agenda.loading
    readonly property string errorText: agenda.errorText
    function refresh() { agenda.refresh() }

    // An all-day event carries DTEND exclusive, and CalendarWidget leaves dur = 0
    // when there is no DTEND at all — so `end` can equal `start` (midnight) and a
    // naive start<=now<end would say an all-day event is never happening. Give it
    // its whole day.
    function endOf(ev) {
        if (!ev || !ev.start) return 0
        var s = ev.start.getTime()
        var e = ev.end ? ev.end.getTime() : s
        if (ev.allDay) return Math.max(e, s + 86400000)
        return e
    }

    // `tick` is what makes these re-evaluate each second; nothing is written.
    readonly property var nowEvent: {
        var t = (w.tick, Date.now())
        var evs = w.events
        for (var i = 0; i < evs.length; i++)
            if (evs[i].start.getTime() <= t && t < w.endOf(evs[i])) return evs[i]
        return null
    }
    readonly property var nextEvent: {
        var t = (w.tick, Date.now())
        var evs = w.events
        for (var i = 0; i < evs.length; i++)
            if (evs[i].start.getTime() > t) return evs[i]
        return null
    }

    status: w.expanded ? "" : (w.nowEvent ? "now" : (w.nextEvent ? "next" : ""))

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    // Two blocks side by side once the box is genuinely wider than it is tall.
    readonly property bool horiz: sizeClass === "wide"
    // Both blocks show together, so each gets half the height when stacked.
    readonly property int _blocks: (w.nowEvent !== null ? 1 : 0) + (w.nextEvent !== null ? 1 : 0)
    readonly property real _colW: w.horiz ? width * 0.5 : width
    readonly property real _blockH: w.horiz ? height : height / Math.max(1, w._blocks)
    // The event title is the thing you read from across the room.
    readonly property real titlePx: w.expanded ? 44
        : Math.max(15, Math.min(w._colW * 0.075, w._blockH * 0.22, 40))
    readonly property real nextTitlePx: w.expanded ? 32
        : Math.max(14, Math.round(w.titlePx * (w.nowEvent ? 0.78 : 1.0)))
    readonly property real labelPx: w.expanded ? 15
        : Math.max(10, Math.min(w.titlePx * 0.36, 16))
    readonly property real metaPx: w.expanded ? 18
        : Math.max(11, Math.min(w.titlePx * 0.44, 20))

    // Whole minutes, rounded UP: "in 1 min" must not appear as "in 0 min" for the
    // 59 seconds before the thing starts.
    function minutesUntil(d) { return Math.ceil((d.getTime() - Date.now()) / 60000) }
    function humanDelta(mins) {
        if (mins <= 0) return "now"
        if (mins < 60) return "in " + mins + " min"
        var h = Math.floor(mins / 60), m = mins % 60
        if (h < 24) return m ? "in " + h + " h " + m + " min" : "in " + h + " h"
        var days = Math.round(h / 24)
        return "in " + days + (days === 1 ? " day" : " days")
    }
    function whenText(ev) {
        if (!ev) return ""
        var t = (w.tick, 0)
        if (ev.allDay) {
            var today = new Date().toDateString() === ev.start.toDateString()
            return today ? "all day" : Qt.formatDate(ev.start, "ddd MMM d") + " · all day"
        }
        return Qt.formatTime(ev.start, "HH:mm") + " · " + w.humanDelta(w.minutesUntil(ev.start))
    }
    function untilText(ev) {
        if (!ev) return ""
        var t = (w.tick, 0)
        if (ev.allDay) return "all day"
        var mins = Math.ceil((w.endOf(ev) - Date.now()) / 60000)
        return "until " + Qt.formatTime(new Date(w.endOf(ev)), "HH:mm")
               + (mins > 0 && mins < 60 ? " · " + mins + " min left" : "")
    }

    // ── Empty / error state ────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        width: parent.width - 2 * theme.spacingSm
        visible: !w.url.length || (!w.nowEvent && !w.nextEvent)
        text: !w.url.length
              ? (w.expanded ? "Add an ICS calendar URL below to see what's now and next."
                            : "Add a calendar\n(ICS URL) in settings")
              : (w.loading ? "Loading…" : (w.errorText.length ? w.errorText : "Nothing scheduled"))
        color: theme.textTertiary; font.pixelSize: w.expanded ? 15 : 12
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
    }

    // ── The two blocks ─────────────────────────────────────────────────────
    // `columns` flips for a wide box: NOW and NEXT sit side by side rather than
    // splitting a 306px-tall banner between them. Only a reshape.
    GridLayout {
        anchors.fill: parent
        anchors.margins: w.expanded ? theme.spacingMd : 0
        // Keep clear of the expanded URL editor, which is anchored to the bottom.
        anchors.bottomMargin: w.expanded ? theme.touchSecondary + theme.spacingXl : 0
        visible: w.url.length > 0 && (w.nowEvent !== null || w.nextEvent !== null)
        columns: w.horiz ? 3 : 1        // NOW | hairline | NEXT
        rowSpacing: w.expanded ? theme.spacingXl : theme.spacingSm
        columnSpacing: theme.spacingLg

        // NOW — the accent block. It is the answer to "am I meant to be somewhere".
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter
            visible: w.nowEvent !== null
            spacing: 2
            Item { Layout.fillHeight: true }
            Text {
                text: "NOW"; color: w.effAccent; font.bold: true
                font.pixelSize: Math.round(w.labelPx); font.letterSpacing: 1.5
            }
            Text {
                Layout.fillWidth: true
                text: w.nowEvent ? (w.nowEvent.title || "(busy)") : ""
                color: theme.textPrimary; font.family: theme.fontDisplay
                font.pixelSize: Math.round(w.titlePx); font.bold: true
                elide: Text.ElideRight; maximumLineCount: 1
            }
            Text {
                Layout.fillWidth: true
                text: w.nowEvent ? w.untilText(w.nowEvent)
                                   + (w.nowEvent.location ? "  ·  " + w.nowEvent.location : "") : ""
                color: theme.textSecondary; font.pixelSize: Math.round(w.metaPx)
                elide: Text.ElideRight
            }
            Item { Layout.fillHeight: true }
        }

        // A hairline between the blocks, only when both are showing. It runs
        // across a stacked pair and DOWN a side-by-side one.
        Rectangle {
            visible: w.nowEvent !== null && w.nextEvent !== null
            Layout.fillWidth: !w.horiz
            Layout.fillHeight: w.horiz
            Layout.preferredWidth: w.horiz ? 1 : -1
            Layout.preferredHeight: w.horiz ? -1 : 1
            color: theme.cardBorder
        }

        // NEXT — deliberately quieter than NOW.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter
            visible: w.nextEvent !== null
            spacing: 2
            Item { Layout.fillHeight: true }
            Text {
                text: "NEXT"; color: theme.textTertiary; font.bold: true
                font.pixelSize: Math.round(w.labelPx); font.letterSpacing: 1.5
            }
            Text {
                Layout.fillWidth: true
                text: w.nextEvent ? (w.nextEvent.title || "(busy)") : ""
                color: w.nowEvent ? theme.textSecondary : theme.textPrimary
                font.family: theme.fontDisplay
                font.pixelSize: Math.round(w.nextTitlePx); font.bold: !w.nowEvent
                elide: Text.ElideRight; maximumLineCount: 1
            }
            Text {
                Layout.fillWidth: true
                text: w.nextEvent ? w.whenText(w.nextEvent)
                                    + (w.nextEvent.location ? "  ·  " + w.nextEvent.location : "") : ""
                color: theme.textSecondary; font.pixelSize: Math.round(w.metaPx)
                elide: Text.ElideRight
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ── Expanded: the URL field, mirroring Calendar's own editor ────────────
    RowLayout {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        visible: w.expanded
        spacing: theme.spacingSm
        TextField {
            id: urlField
            Layout.fillWidth: true; Layout.preferredHeight: theme.touchSecondary
            text: w.url; placeholderText: "Paste an ICS calendar URL…"
            placeholderTextColor: theme.textTertiary; color: theme.textPrimary; font.pixelSize: 15
            background: Rectangle {
                radius: theme.radiusSm; color: theme.backgroundColor
                border.color: urlField.activeFocus ? w.effAccent : theme.cardBorder; border.width: 1
            }
            onEditingFinished: if (w.store) w.store.setSetting(w.instanceId, "url", text)
            // Re-assert the store value after an external/store push: typing severs
            // the `text:` binding permanently. Skip while the user is in the field.
            Connections {
                target: w
                function onUrlChanged() { if (!urlField.activeFocus) urlField.text = w.url }
            }
        }
        PillButton {
            label: "Save"; primary: true; tint: w.effAccent
            onClicked: if (w.store) w.store.setSetting(w.instanceId, "url", urlField.text)
        }
    }
}
