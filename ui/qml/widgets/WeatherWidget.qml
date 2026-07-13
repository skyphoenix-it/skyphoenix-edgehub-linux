import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Weather — real forecast from Open-Meteo (free, no API key). Location comes
// from the instance settings (lat/lon/place). Degrades gracefully offline.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Weather"; iconName: "weather"; accentColor: theme.catInfo
    big: expanded

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
    property var _fxhr: null
    property var _gxhr: null
    Component.onDestruction: { if (_fxhr) _fxhr.abort(); if (_gxhr) _gxhr.abort() }

    function refresh() {
        var fdays = Math.max(1, Math.min(16, w.forecastDays + 1))
        var url = "https://api.open-meteo.com/v1/forecast?latitude=" + w.lat + "&longitude=" + w.lon
                + "&current=temperature_2m,apparent_temperature,weather_code"
                + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
                + (w.units === "fahrenheit" ? "&temperature_unit=fahrenheit" : "")
                + "&timezone=auto&forecast_days=" + fdays
        if (w._fxhr) w._fxhr.abort()
        var xhr = new XMLHttpRequest()
        w._fxhr = xhr
        xhr.timeout = 8000
        xhr.ontimeout = function () { if (w._fxhr === xhr) { w._fxhr = null; if (!w.loaded) w.errorText = "Timed out" } }
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (w._fxhr !== xhr) return   // superseded by a newer request
            w._fxhr = null
            // On any failure, stop presenting the last reading as if it were live
            // (curTemp/days still hold the previous city's numbers — clear `loaded`).
            if (xhr.status !== 200) { w.loaded = false; w.errorText = "Offline"; return }
            try {
                var d = JSON.parse(xhr.responseText)
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
        try { xhr.open("GET", url); xhr.send() } catch (e) { w._fxhr = null; w.errorText = "Offline" }
    }

    // Look up a city name → lat/lon via Open-Meteo's geocoding API, then persist.
    property bool geocoding: false
    function geocode(name) {
        if (!name || !name.trim().length) return
        geocoding = true
        var url = "https://geocoding-api.open-meteo.com/v1/search?count=1&name=" + encodeURIComponent(name.trim())
        if (w._gxhr) w._gxhr.abort()
        var xhr = new XMLHttpRequest()
        w._gxhr = xhr
        xhr.timeout = 8000
        xhr.ontimeout = function () { if (w._gxhr === xhr) { w._gxhr = null; w.geocoding = false; w.errorText = "Lookup timed out" } }
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (w._gxhr !== xhr) return
            w._gxhr = null
            w.geocoding = false
            try {
                var d = JSON.parse(xhr.responseText)
                if (d && d.results && d.results.length) {
                    var r = d.results[0]
                    var region = r.admin1 ? ", " + r.admin1 : ""
                    var label = r.name + region + (r.country_code ? ", " + r.country_code : "")
                    if (w.store) w.store.patchSettings(w.instanceId, { "lat": r.latitude, "lon": r.longitude, "place": label })
                } else {
                    w.errorText = "City not found"
                }
            } catch (e) { w.errorText = "Lookup failed" }
        }
        try { xhr.open("GET", url); xhr.send() } catch (e) { w._gxhr = null; geocoding = false }
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

    ColumnLayout {
        anchors.fill: parent
        spacing: w.expanded ? 12 : 4

        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingMd
            Text { text: w.loaded ? w.weatherGlyph(w.curCode) : "…"; font.pixelSize: w.expanded ? 72 : 34 }
            ColumnLayout {
                spacing: 0
                Text { text: (w.loaded && !w.errorText.length) ? Math.round(w.curTemp) + w.degSym : (w.errorText.length ? "—" : "…")
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
            // (otherwise the big "—" gives no hint why there's no data).
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
