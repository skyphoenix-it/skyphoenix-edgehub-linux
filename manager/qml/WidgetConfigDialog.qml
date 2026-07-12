import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// WidgetConfigDialog — a professional, schema-driven per-widget config editor
// with a LIVE preview of the real widget that updates as you edit. Resolves
// store/catalog/theme/media/backend/m from the Manager scope (instantiated
// inline there). Open with open(id, type).
Dialog {
    id: dlg
    property string wId: ""
    property string wType: ""
    property var schema: schemaReg.schemaFor(wType)
    property string geoStatus: ""

    function openFor(id, type) { wId = id; wType = type; geoStatus = ""; open() }

    anchors.centerIn: parent
    width: 960; height: 680
    modal: true
    standardButtons: Dialog.Close
    background: Rectangle { color: m.bg; radius: m.radius; border.width: 1; border.color: m.border }

    WidgetConfigSchema { id: schemaReg }

    // Live feeds for the preview widget.
    property int tick: 0
    property var metricsObj: ({})
    Timer { interval: 1000; running: dlg.visible; repeat: true; onTriggered: dlg.tick++ }
    Timer { interval: 2000; running: dlg.visible; repeat: true; triggeredOnStart: true
        onTriggered: { try { dlg.metricsObj = JSON.parse(backend.metricsJson() || "{}") } catch (e) { dlg.metricsObj = ({}) } } }

    function wsrc(type) { var s = catalog.source(type); return s ? s.replace("qrc:/qml/", "qrc:/manager/") : "" }
    function inject(item) {
        if (!item) return
        store.ensureSettings(dlg.wId, catalog.defaults(dlg.wType))
        item.instanceId = dlg.wId
        item.store = store
        item.expanded = false
        if (item.hasOwnProperty("active")) item.active = true
        item.metrics = Qt.binding(function () { return dlg.metricsObj })
        if (item.hasOwnProperty("titleOverride"))
            item.titleOverride = Qt.binding(function () { store.revision; var s = store.settingsFor(dlg.wId); return (s && s.title) ? s.title : "" })
        if (item.hasOwnProperty("tick")) item.tick = Qt.binding(function () { return dlg.tick })
    }

    function doAction(action) {
        if (action === "geocode") {
            var place = store.settingsFor(wId).place || ""
            if (!place.trim().length) { geoStatus = "Type a place name first"; return }
            geoStatus = "Searching…"
            var xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                try {
                    var d = JSON.parse(xhr.responseText)
                    if (d && d.results && d.results.length) {
                        var r = d.results[0]
                        var label = r.name + (r.country_code ? ", " + r.country_code : "")
                        store.patchSettings(wId, { lat: r.latitude, lon: r.longitude, place: label })
                        dlg.geoStatus = "✓ Set to " + label
                    } else dlg.geoStatus = "City not found"
                } catch (e) { dlg.geoStatus = "Lookup failed" }
            }
            xhr.open("GET", "https://geocoding-api.open-meteo.com/v1/search?count=1&name=" + encodeURIComponent(place.trim()))
            xhr.send()
        }
    }

    header: Rectangle {
        color: "transparent"; implicitHeight: 74
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; spacing: 14
            AppIcon { name: dlg.wType; size: 32; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
            ColumnLayout {
                spacing: 1; Layout.fillWidth: true
                Text { text: catalog.title(dlg.wType) + " — Configure"; color: m.textPrimary; font.pixelSize: 20; font.bold: true }
                Text { text: catalog.desc(dlg.wType); color: m.textSecondary; font.pixelSize: 12
                    elide: Text.ElideRight; Layout.fillWidth: true }
            }
        }
    }

    contentItem: RowLayout {
        spacing: 18

        // ── Live preview ──
        ColumnLayout {
            Layout.preferredWidth: 300; Layout.maximumWidth: 300; Layout.fillHeight: true; spacing: 10
            Text { text: "Live preview"; color: m.textSecondary; font.pixelSize: 13; font.bold: true }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 300
                radius: 18; color: theme.backgroundColor; border.width: 2; border.color: "#000"; clip: true
                Rectangle {
                    anchors.fill: parent; anchors.margins: 10; radius: 12; clip: true
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: theme.backgroundColor }
                        GradientStop { position: 1.0; color: theme.backgroundColor3 }
                    }
                    Loader {
                        anchors.fill: parent; anchors.margins: 10
                        source: dlg.wsrc(dlg.wType)
                        onLoaded: dlg.inject(item)
                    }
                }
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: "Changes apply instantly to the Edge."
                color: m.textSecondary; font.pixelSize: 12
            }
            Item { Layout.fillHeight: true }
            Button {
                text: "Reset to defaults"; Layout.fillWidth: true
                onClicked: {
                    var defs = catalog.defaults(dlg.wType)
                    var clean = {}
                    for (var k in defs) clean[k] = defs[k]
                    store.setSetting(dlg.wId, "__noop", 0)   // ensure map exists
                    // Replace the whole settings object with defaults.
                    var s = store.settingsFor(dlg.wId)
                    for (var kk in s) delete s[kk]
                    for (var d in defs) s[d] = defs[d]
                    store._touchSettings()
                }
            }
        }

        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: m.border }

        // ── Form (shared panel — identical rendering to the on-device config) ──
        WidgetConfigPanel {
            Layout.fillWidth: true; Layout.fillHeight: true
            schema: dlg.schema
            store: store
            instanceId: dlg.wId
            col: m
            statusText: dlg.wType === "weather" ? dlg.geoStatus : ""
            onActionRequested: (a) => dlg.doAction(a)
        }
    }
}
