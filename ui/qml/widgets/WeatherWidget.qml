import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Weather — real forecast from Open-Meteo (free, no API key). Location comes
// from the instance settings (lat/lon/place). Degrades gracefully offline.
//
// Both requests (forecast + city geocode) go through NetHub, never a raw XHR, so
// the global offline switch, the host allowlist and the attestation counters
// cover them. Readings stay in widget properties: they are never written to the
// store, so a poll cannot churn config.toml.
//
// Sizing (W1 wave 3): layout keys off the injected `sizeClass`. Every tile used
// to render the same glyph + temperature + place, so a 696x1228 box showed a
// 34px glyph over a 28px number and ~1000px of nothing.
//
// WHAT THE TILE CAN HONESTLY SHOW IS BOUNDED BY THE REQUEST, and the request is
// `&current=` + `&daily=` — never `hourly` (see refresh()). So there is no hourly
// series to chart, and a tall tile that drew one would be inventing data. Adding
// `&hourly=` would be new egress + a new feature: NetHub gates it and the
// no-egress attestation watches the default config. So the taller sizes grow the
// only way the payload allows — today's detail, then N DAILY rows:
//   • 0.5x0.5 (micro) — headerless: glyph + temperature + place.
//   • 1x1 (baseline)  — + "feels like", + the daily rows that fit.
//   • wide            — glyph/temp block beside the forecast as COLUMNS (the
//                       wide projections are 306-409px tall; rows would not fit).
//   • tall            — the daily forecast as a list, filling the height.
//   • full (overlay)  — unchanged (the city search is genuinely modal).
//
// `forecastDays` (the user's setting, capped at 7 by the schema) is how many days
// are FETCHED. The size decides how many of them are SHOWN: never more than the
// user asked for, never more than fits. Same rule as calendar's maxEvents.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    // The egress gate. Injected by Dashboard (one app-global instance); a local
    // fallback keeps the widget self-contained in tests / standalone use.
    property var netHub: null
    NetHub { id: _fallbackHub }
    function _hub() { return netHub ? netHub : _fallbackHub }
    // Test seam: a per-request XHR factory handed to the gate, so a FakeXHR can be
    // injected. null in production → the gate builds the real XHR.
    property var xhrFactory: null

    title: "Weather"; iconName: "weather"; accentColor: theme.catInfo
    showHeader: !micro

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    readonly property bool horiz: sizeClass === "wide"
    readonly property bool tallish: sizeClass === "tall" || sizeClass === "large"
    // Anything past "glyph + temperature + place" needs more than a half-cell.
    readonly property bool rich: !micro

    // The days we actually hold, minus today. `days` is only rebuilt by a fetch
    // (every 30 min), never by a tick.
    readonly property int futureDays: Math.max(0, w.days.length - 1)

    // "Now" scales with the box; the forecast takes what is left.
    readonly property real glyphPx: w.micro ? Math.min(w.width * 0.30, w.height * 0.26, 72)
        : w.horiz ? Math.min(w.width * 0.10, w.height * 0.26, 80)
        : Math.min(w.width * 0.18, w.height * 0.13, 88)
    readonly property real tempPx: Math.max(18, Math.round(w.glyphPx * 0.78))
    readonly property real subPx: Math.max(11, Math.min(w.tempPx * 0.30, 16))
    // Width the "now" block claims when the forecast sits beside it.
    readonly property real nowW: Math.min(w.width * 0.32, 340)

    // How many daily entries FIT. The user's forecastDays is a MAXIMUM (what to
    // fetch); the box decides how many of those are rendered — never more than we
    // hold, never an overflowing card.
    readonly property real dayRowH: Math.max(34, Math.min(w.height * 0.055, 52))
    readonly property int dayRowsFit: {
        if (w.expanded || w.micro || w.horiz || !w.loaded) return 0
        // "Now" keeps a legible minimum and the refresh strip its touch row.
        var avail = w.height - w.headerHeight - 150 - 3 * theme.spacingSm - theme.touchTertiary
        return Math.max(0, Math.min(w.futureDays, Math.floor(avail / (w.dayRowH + 4))))
    }
    readonly property real dayColW: Math.max(72, Math.min(w.width * 0.11, 120))
    readonly property int dayColsFit: {
        if (w.expanded || w.micro || !w.horiz || !w.loaded) return 0
        var avail = w.width - w.nowW - theme.touchTertiary - 3 * theme.spacingSm
        return Math.max(0, Math.min(w.futureDays, Math.floor(avail / w.dayColW)))
    }
    readonly property int shownDays: w.horiz ? w.dayColsFit : w.dayRowsFit

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    property real lat: cfg.lat !== undefined ? cfg.lat : 52.52
    property real lon: cfg.lon !== undefined ? cfg.lon : 13.405
    // Only default to "Berlin" when no coordinates are configured either — a
    // custom location with a blanked place field must not be mislabelled Berlin;
    // fall back to the coordinates instead.
    property string place: cfg.place ? cfg.place
        : ((cfg.lat === undefined && cfg.lon === undefined) ? "Berlin"
           : (Number(lat).toFixed(2) + ", " + Number(lon).toFixed(2)))
    readonly property string units: cfg.units || "celsius"
    readonly property int forecastDays: cfg.forecastDays !== undefined ? cfg.forecastDays : 4
    readonly property string degSym: units === "fahrenheit" ? "°F" : "°C"

    property bool loaded: false
    property string errorText: ""
    property real curTemp: 0
    property real feels: 0
    property int curCode: 0
    property var days: []   // [{ day, code, min, max }]

    function weatherGlyph(code) {
        if (code === 0) return "☀️"
        if (code <= 2) return "⛅"
        if (code === 3) return "☁️"
        if (code === 45 || code === 48) return "🌫️"
        if (code >= 51 && code <= 57) return "🌦️"
        if (code >= 61 && code <= 67) return "🌧️"
        if (code >= 71 && code <= 77) return "🌨️"
        if (code >= 80 && code <= 82) return "🌧️"
        if (code >= 85 && code <= 86) return "🌨️"
        if (code >= 95) return "⛈️"
        return "🌡️"
    }

    // In-flight requests, tracked so a newer fetch aborts an older one (last-write
    // wins cleanly) and a hung socket resolves via a timeout instead of spinning.
    // The sequence tokens — not the XHR object — are the supersede guard: the gate
    // refuses offline/blocked requests synchronously and returns null, so there is
    // no XHR to compare a callback against in exactly the cases that must still report.
    property var _fxhr: null
    property int _fseq: 0
    property var _gxhr: null
    property int _gseq: 0
    Component.onDestruction: { if (_fxhr) _fxhr.abort(); if (_gxhr) _gxhr.abort() }

    // Map a forecast payload → the rendered reading.
    function _applyForecast(body) {
        try {
            var d = JSON.parse(body)
            if (!d || !d.current || !d.daily || !d.daily.time) { w.loaded = false; w.errorText = "No data"; return }
            w.curTemp = d.current.temperature_2m
            w.feels = d.current.apparent_temperature
            w.curCode = d.current.weather_code
            var out = []
            var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            for (var i = 0; i < d.daily.time.length; i++) {
                // "YYYY-MM-DD" — parse as LOCAL midnight so getDay() names the
                // right weekday (new Date(str) would parse it as UTC and, west
                // of UTC, shift the label a day earlier).
                var p = ("" + d.daily.time[i]).split("-")
                var dt = new Date(+p[0], +p[1] - 1, +p[2])
                out.push({ day: i === 0 ? "Today" : names[dt.getDay()],
                           code: d.daily.weather_code[i],
                           max: Math.round(d.daily.temperature_2m_max[i]),
                           min: Math.round(d.daily.temperature_2m_min[i]) })
            }
            w.days = out; w.loaded = true; w.errorText = ""
        } catch (e) { w.loaded = false; w.errorText = "Parse error" }
    }

    function refresh() {
        var fdays = Math.max(1, Math.min(16, w.forecastDays + 1))
        var url = "https://api.open-meteo.com/v1/forecast?latitude=" + w.lat + "&longitude=" + w.lon
                + "&current=temperature_2m,apparent_temperature,weather_code"
                + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
                + (w.units === "fahrenheit" ? "&temperature_unit=fahrenheit" : "")
                + "&timezone=auto&forecast_days=" + fdays
        if (w._fxhr) w._fxhr.abort()
        w._fxhr = null
        var seq = ++w._fseq
        var xhr = w._hub().request({
            url: url,
            timeout: 8000,
            xhrFactory: w.xhrFactory,
            onDone: function (status, body) {
                if (seq !== w._fseq) return   // superseded by a newer request
                w._fxhr = null
                w._applyForecast(body)
            },
            onError: function (reason) {
                if (seq !== w._fseq) return
                w._fxhr = null
                // A timeout may still resolve into the same reading, so the last
                // one stays on screen; every other failure means what's displayed
                // is no longer live (curTemp/days still hold the previous city's
                // numbers — clear `loaded` so they aren't shown as current).
                if (reason === "timeout") { if (!w.loaded) w.errorText = "Timed out"; return }
                w.loaded = false
                w.errorText = reason === "blocked" ? "Blocked" : "Offline"
            }
        })
        if (seq === w._fseq) w._fxhr = xhr
    }

    // Look up a city name → lat/lon via Open-Meteo's geocoding API, then persist.
    // The result IS persisted (lat/lon/place): it is a deliberate user choice, not
    // a poll reading, so it belongs in config.toml.
    property bool geocoding: false
    function geocode(name) {
        if (!name || !name.trim().length) return
        geocoding = true
        var url = "https://geocoding-api.open-meteo.com/v1/search?count=1&name=" + encodeURIComponent(name.trim())
        if (w._gxhr) w._gxhr.abort()
        w._gxhr = null
        var seq = ++w._gseq
        var xhr = w._hub().request({
            url: url,
            timeout: 8000,
            xhrFactory: w.xhrFactory,
            onDone: function (status, body) {
                if (seq !== w._gseq) return
                w._gxhr = null
                w.geocoding = false
                try {
                    var d = JSON.parse(body)
                    if (d && d.results && d.results.length) {
                        var r = d.results[0]
                        var region = r.admin1 ? ", " + r.admin1 : ""
                        var label = r.name + region + (r.country_code ? ", " + r.country_code : "")
                        if (w.store) w.store.patchSettings(w.instanceId, { "lat": r.latitude, "lon": r.longitude, "place": label })
                    } else {
                        w.errorText = "City not found"
                    }
                } catch (e) { w.errorText = "Lookup failed" }
            },
            onError: function (reason) {
                if (seq !== w._gseq) return
                w._gxhr = null
                w.geocoding = false
                w.errorText = reason === "offline" ? "Offline"
                    : reason === "blocked" ? "Blocked"
                    : reason === "timeout" ? "Lookup timed out" : "Lookup failed"
            }
        })
        if (seq === w._gseq) w._gxhr = xhr
    }

    // Debounce: lat and lon both "change" as settings load — coalesce to one fetch.
    property string locKey: lat + "," + lon + "," + units + "," + forecastDays
    // Honor `active` (S3): don't fetch/repaint on the inactive (non-driver)
    // instance; refetch once when it becomes active again.
    onLocKeyChanged: if (w.active) refreshDebounce.restart()
    onActiveChanged: if (w.active) refreshDebounce.restart()
    // A units flip changes degSym synchronously, but curTemp still holds the old
    // reading in the previous unit — invalidate it so the tile never relabels a
    // Celsius number as "°F" until the refetch lands.
    onUnitsChanged: w.loaded = false
    Component.onCompleted: refreshDebounce.restart()
    Timer { id: refreshDebounce; interval: 350; onTriggered: w.refresh() }
    Timer { interval: 1800000; repeat: true; running: w.active; onTriggered: w.refresh() }

    // ── Tile (every non-overlay size) ────────────────────────────────────────
    GridLayout {
        anchors.fill: parent
        visible: !w.expanded
        // Wide puts the forecast BESIDE "now" (3 columns: now · forecast ·
        // refresh); everything else stacks them (3 rows).
        columns: w.horiz ? 3 : 1
        rowSpacing: theme.spacingSm
        columnSpacing: theme.spacingMd

        // "Now": glyph + temperature, then feels/place. Identical everywhere —
        // only its scale changes.
        ColumnLayout {
            id: nowCell
            Layout.fillWidth: !w.horiz
            // Stacked: "now" absorbs the slack the capped forecast rows leave, so
            // it sits centred in its share rather than pinned to the top edge.
            Layout.fillHeight: !w.horiz
            Layout.preferredWidth: w.horiz ? Math.round(w.nowW) : -1
            // Alignment ONLY in the horizontal projection: setting it on the
            // stacked path would cancel fillWidth/fillHeight above (Qt Layouts:
            // alignment beats fill on that axis) and collapse the block.
            Layout.alignment: w.horiz ? Qt.AlignVCenter : 0
            Layout.maximumWidth: Number.POSITIVE_INFINITY
            spacing: 0

            Item { Layout.fillHeight: true; visible: !w.horiz }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: theme.spacingSm
                Text { text: w.loaded ? w.weatherGlyph(w.curCode) : "…"
                    font.pixelSize: Math.max(14, w.glyphPx) }
                ColumnLayout {
                    spacing: 0
                    Text {
                        text: (w.loaded && !w.errorText.length)
                              ? Math.round(w.curTemp) + w.degSym
                              : (w.errorText.length ? "-" : "…")
                        font.pixelSize: w.tempPx; font.bold: true; color: theme.textPrimary
                    }
                    // "Feels like" is data the CURRENT reading already carries —
                    // it was locked in the overlay for no reason. The half-cell
                    // has no room for it.
                    Text {
                        visible: w.rich && w.loaded && !w.errorText.length
                        text: "Feels " + Math.round(w.feels) + w.degSym
                        font.pixelSize: w.subPx; color: theme.textSecondary
                    }
                }
            }
            Text {
                Layout.fillWidth: true; Layout.topMargin: 2
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: w.errorText.length ? w.errorText : w.place
                font.pixelSize: w.subPx
                color: w.errorText.length ? theme.warning : theme.textSecondary
            }

            Item { Layout.fillHeight: true; visible: !w.horiz }
        }

        // The forecast — the same delegates reflowed: a COLUMN per day when the
        // box is wide-and-short, a ROW per day when it is tall. Nothing is
        // recreated by a reflow, and the model is an int (the count), so a new
        // reading moves the bound VALUES rather than rebuilding delegates.
        GridLayout {
            id: forecastCell
            visible: w.shownDays > 0
            Layout.fillWidth: true
            Layout.fillHeight: !w.horiz
            Layout.alignment: w.horiz ? Qt.AlignVCenter : Qt.AlignTop
            Layout.maximumWidth: Number.POSITIVE_INFINITY
            columns: w.horiz ? w.shownDays : 1
            rowSpacing: 4
            columnSpacing: theme.spacingSm

            Repeater {
                model: w.shownDays
                delegate: GridLayout {
                    id: dayCell
                    required property int index
                    // days[0] is today — the forecast starts at 1.
                    readonly property var d: w.days[dayCell.index + 1]
                    columns: w.horiz ? 1 : 3
                    rowSpacing: 0
                    columnSpacing: theme.spacingSm
                    Layout.fillWidth: true
                    Layout.fillHeight: !w.horiz
                    // Rows share the height, but only up to a point: four days in
                    // an 819px box gave 125px rows with a 30px glyph adrift in the
                    // middle of each. Capped here, and every glyph/label below is
                    // sized from the row's ACTUAL height — so the row fills out
                    // instead of the row growing around fixed-size content.
                    Layout.maximumHeight: w.horiz ? 100000 : Math.max(44, w.dayRowH * 1.7)
                    // The scale each day entry is drawn at. Stacked: the row's own
                    // height. Wide: the column is bounded by its WIDTH but still
                    // has the box's height to spend — sizing off the width alone
                    // left 11px labels under a 19px glyph in a 409px-tall box.
                    readonly property real px: w.horiz
                        ? Math.min(w.dayColW * 0.75, w.height * 0.30)
                        : dayCell.height

                    Text {
                        text: dayCell.d ? dayCell.d.day : ""
                        font.pixelSize: Math.max(11, Math.min(dayCell.px * 0.30, 20))
                        color: theme.textSecondary
                        horizontalAlignment: w.horiz ? Text.AlignHCenter : Text.AlignLeft
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        Layout.preferredWidth: w.horiz ? -1 : Math.round(Math.min(w.width * 0.22, 96))
                        Layout.fillWidth: w.horiz
                        Layout.fillHeight: !w.horiz
                    }
                    Text {
                        text: dayCell.d ? w.weatherGlyph(dayCell.d.code) : ""
                        font.pixelSize: Math.max(14, Math.min(dayCell.px * 0.58, 44))
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        Layout.fillWidth: w.horiz
                        Layout.fillHeight: !w.horiz
                    }
                    Text {
                        text: dayCell.d ? (dayCell.d.max + w.degSym + " / " + dayCell.d.min + w.degSym) : ""
                        font.pixelSize: Math.max(11, Math.min(dayCell.px * 0.30, 20))
                        color: theme.textPrimary
                        horizontalAlignment: w.horiz ? Text.AlignHCenter : Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        // A 7-day °F row ("108°F / -12°F") must shrink, not clip.
                        fontSizeMode: Text.HorizontalFit; minimumPixelSize: 9
                        elide: Text.ElideRight
                        Layout.fillWidth: !w.horiz
                        Layout.preferredWidth: w.horiz ? Math.round(w.dayColW) : -1
                        Layout.fillHeight: !w.horiz
                    }
                }
            }
        }

        // Refresh — a real touch target in its own cell, so it can never sit on
        // top of the forecast (it used to be a 36px circle anchored over the
        // bottom-right of a body that had no bottom content; now it does).
        Item {
            visible: !w.micro
            Layout.preferredHeight: theme.touchTertiary
            Layout.preferredWidth: w.horiz ? theme.touchTertiary : -1
            Layout.fillWidth: !w.horiz
            Layout.alignment: w.horiz ? Qt.AlignVCenter : Qt.AlignRight
            Rectangle {
                id: refreshCompact
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: theme.touchTertiary; height: theme.touchTertiary; radius: width / 2
                color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b,
                               refMA.pressed ? 0.32 : (refMA.containsMouse ? 0.22 : 0.14))
                Text { anchors.centerIn: parent; text: "⟳"; font.pixelSize: 22; color: w.effAccent }
                MouseArea {
                    id: refMA; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: w.refresh()
                }
            }
        }
    }

    // ── Expanded (the overlay) ───────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: w.expanded
        spacing: w.expanded ? 12 : 4

        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingMd
            Text { text: w.loaded ? w.weatherGlyph(w.curCode) : "…"; font.pixelSize: w.expanded ? 72 : 34 }
            ColumnLayout {
                spacing: 0
                Text { text: (w.loaded && !w.errorText.length) ? Math.round(w.curTemp) + w.degSym : (w.errorText.length ? "-" : "…")
                    font.pixelSize: w.expanded ? 64 : 28; font.bold: true; color: theme.textPrimary }
                Text { visible: w.expanded && w.loaded; text: "Feels " + Math.round(w.feels) + w.degSym + "  ·  " + w.place
                    font.pixelSize: 14; color: theme.textSecondary }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight               // S12: long place/error must not overflow the tile
            // Compact: place (or the error). Expanded: surface the error reason too
            // (otherwise the big "-" gives no hint why there's no data).
            visible: !w.expanded || w.errorText.length > 0
            text: w.errorText.length ? w.errorText : w.place
            font.pixelSize: w.expanded && w.errorText.length ? 15 : 12
            color: w.errorText.length ? theme.warning : theme.textSecondary
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded && w.loaded; spacing: theme.spacingXl
            Repeater {
                model: w.days.slice(1)
                delegate: ColumnLayout {
                    required property var modelData; spacing: 2
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.day; font.pixelSize: 13; color: theme.textSecondary }
                    Text { Layout.alignment: Qt.AlignHCenter; text: w.weatherGlyph(modelData.code); font.pixelSize: 26 }
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.max + w.degSym + " / " + modelData.min + w.degSym
                        font.pixelSize: 13; color: theme.textPrimary
                        // S12: shrink-to-fit the day's hi/lo so a wide 7-day °F row
                        // (e.g. "108°F / -12°F") never clips the panel.
                        fontSizeMode: Text.HorizontalFit; minimumPixelSize: 9; elide: Text.ElideRight }
                }
            }
        }
        Item { Layout.fillHeight: true; visible: w.expanded }
        RowLayout {
            Layout.fillWidth: true; visible: w.expanded; spacing: theme.spacingSm
            TextField {
                id: cityField; Layout.fillWidth: true; Layout.preferredHeight: theme.touchSecondary
                placeholderText: "Search a city…"; placeholderTextColor: theme.textTertiary
                color: theme.textPrimary; font.pixelSize: 15
                background: Rectangle { radius: theme.radiusSm; color: theme.backgroundColor
                    border.color: cityField.activeFocus ? w.effAccent : theme.cardBorder; border.width: 1 }
                onAccepted: w.geocode(text)
            }
            PillButton { label: w.geocoding ? "…" : "Set location"; glyph: "📍"; primary: true; tint: w.effAccent
                onClicked: w.geocode(cityField.text) }
        }
    }

}
