import QtQuick
import QtQuick.Layouts

// Weather — real forecast from Open-Meteo (free, no API key). Location comes
// from the instance settings (lat/lon/place). Degrades gracefully offline.
WidgetChrome {
    id: w
    property var metrics: ({})
    property var settings: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Weather"; icon: "⛅"; accentColor: theme.catInfo
    big: expanded

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    property real lat: cfg.lat !== undefined ? cfg.lat : 52.52
    property real lon: cfg.lon !== undefined ? cfg.lon : 13.405
    property string place: cfg.place || "Berlin"

    property bool loaded: false
    property string errorText: ""
    property real curTemp: 0
    property real feels: 0
    property int curCode: 0
    property var days: []   // [{ day, code, min, max }]

    function icon(code) {
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

    function refresh() {
        var url = "https://api.open-meteo.com/v1/forecast?latitude=" + w.lat + "&longitude=" + w.lon
                + "&current=temperature_2m,apparent_temperature,weather_code"
                + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
                + "&timezone=auto&forecast_days=4"
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (!w) return   // widget may have been torn down before the reply
            if (xhr.status !== 200) { w.errorText = "Offline"; return }
            try {
                var d = JSON.parse(xhr.responseText)
                if (!d || !d.current || !d.daily || !d.daily.time) { w.errorText = "No data"; return }
                w.curTemp = d.current.temperature_2m
                w.feels = d.current.apparent_temperature
                w.curCode = d.current.weather_code
                var out = []
                var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                for (var i = 0; i < d.daily.time.length && i < 4; i++) {
                    var dt = new Date(d.daily.time[i])
                    out.push({ day: i === 0 ? "Today" : names[dt.getDay()],
                               code: d.daily.weather_code[i],
                               max: Math.round(d.daily.temperature_2m_max[i]),
                               min: Math.round(d.daily.temperature_2m_min[i]) })
                }
                w.days = out; w.loaded = true; w.errorText = ""
            } catch (e) { w.errorText = "Parse error" }
        }
        xhr.open("GET", url); xhr.send()
    }

    // Debounce: lat and lon both "change" as settings load — coalesce to one fetch.
    property string locKey: lat + "," + lon
    onLocKeyChanged: refreshDebounce.restart()
    Component.onCompleted: refreshDebounce.restart()
    Timer { id: refreshDebounce; interval: 350; onTriggered: w.refresh() }
    Timer { interval: 1800000; repeat: true; running: w.active; onTriggered: w.refresh() }

    ColumnLayout {
        anchors.fill: parent
        spacing: w.expanded ? 12 : 4

        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingMd
            Text { text: w.loaded ? w.icon(w.curCode) : "…"; font.pixelSize: w.expanded ? 72 : 34 }
            ColumnLayout {
                spacing: 0
                Text { text: w.loaded ? Math.round(w.curTemp) + "°" : (w.errorText.length ? "—" : "…")
                    font.pixelSize: w.expanded ? 64 : 28; font.bold: true; color: theme.textPrimary }
                Text { visible: w.expanded && w.loaded; text: "Feels " + Math.round(w.feels) + "°  ·  " + w.place
                    font.pixelSize: 14; color: theme.textSecondary }
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter; visible: !w.expanded
            text: w.errorText.length ? w.errorText : w.place
            font.pixelSize: 11; color: theme.textSecondary
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; visible: w.expanded && w.loaded; spacing: theme.spacingXl
            Repeater {
                model: w.days.slice(1)
                delegate: ColumnLayout {
                    required property var modelData; spacing: 2
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.day; font.pixelSize: 13; color: theme.textSecondary }
                    Text { Layout.alignment: Qt.AlignHCenter; text: w.icon(modelData.code); font.pixelSize: 26 }
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.max + "° / " + modelData.min + "°"
                        font.pixelSize: 13; color: theme.textPrimary }
                }
            }
        }
    }
}
