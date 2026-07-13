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
    // Test seam: when set, called instead of `new XMLHttpRequest()` so a FakeXHR
    // can be injected. null in production → real XHR (behaviour unchanged).
    property var xhrFactory: null

    function openFor(id, type) {
        wId = id; wType = type; geoStatus = ""
        store.ensureSettings(id, catalog.defaults(type))   // seed defaults before the form/preview bind
        open()
    }

    anchors.centerIn: parent
    // Responsive: use most of the window (capped) so the form isn't cramped/clipped.
    width: Math.min(parent ? parent.width * 0.92 : 960, 1200)
    height: Math.min(parent ? parent.height * 0.9 : 680, 900)
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
        item.expanded = true                       // show the full, interactive layout
        if (item.hasOwnProperty("showHeader")) item.showHeader = false
        if (item.hasOwnProperty("active")) item.active = true
        item.metrics = Qt.binding(function () { return dlg.metricsObj })
        if (item.hasOwnProperty("titleOverride"))
            item.titleOverride = Qt.binding(function () { store.revision; var s = store.settingsFor(dlg.wId); return (s && s.title) ? s.title : "" })
        if (item.hasOwnProperty("accentName"))
            item.accentName = Qt.binding(function () { store.revision; var s = store.settingsFor(dlg.wId); return (s && s.accent) ? s.accent : "" })
        if (item.hasOwnProperty("cardBackdrop"))
            item.cardBackdrop = Qt.binding(function () { store.revision; var s = store.settingsFor(dlg.wId); return (s && s.cardBackdrop) ? s.cardBackdrop : "none" })
        if (item.hasOwnProperty("tick")) item.tick = Qt.binding(function () { return dlg.tick })
    }

    // In-flight geocode request, so a new lookup aborts the previous one
    // (re-entrancy guard) and closing the dialog cancels a pending request.
    property var _geoXhr: null
    function _cancelGeo() { if (_geoXhr) { try { _geoXhr.abort() } catch (e) {} _geoXhr = null } }

    function doAction(action) {
        if (action === "geocode") {
            var place = store.settingsFor(wId).place || ""
            if (!place.trim().length) { geoStatus = "Type a place name first"; return }
            dlg._cancelGeo()                       // supersede any in-flight lookup
            geoStatus = "Searching…"
            var xhr = (dlg.xhrFactory ? dlg.xhrFactory() : new XMLHttpRequest())
            dlg._geoXhr = xhr
            xhr.timeout = 8000
            xhr.ontimeout = function () {
                if (dlg._geoXhr !== xhr) return
                dlg._geoXhr = null; dlg.geoStatus = "Lookup timed out — try again"
            }
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                if (dlg._geoXhr !== xhr) return     // superseded or aborted
                dlg._geoXhr = null
                if (xhr.status === 0) return         // aborted / network down
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

    onClosed: dlg._cancelGeo()

    // Confirm before wiping a widget's settings back to defaults.
    Dialog {
        id: resetConfirm
        anchors.centerIn: parent
        modal: true; title: "Reset this widget?"
        standardButtons: Dialog.Yes | Dialog.No
        background: Rectangle { color: m.panel; radius: m.radius; border.width: 1; border.color: m.border }
        contentItem: Text {
            text: "Reset " + catalog.title(dlg.wType) + " to its default settings? This can't be undone."
            color: m.textPrimary; wrapMode: Text.WordWrap; padding: 14; font.pixelSize: 14
        }
        onAccepted: store.resetSettings(dlg.wId, catalog.defaults(dlg.wType))
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

        // ── Live, interactive preview ──
        ColumnLayout {
            Layout.preferredWidth: 340; Layout.maximumWidth: 340; Layout.fillHeight: true; spacing: 10
            Text { text: "Live preview"; color: m.textSecondary; font.pixelSize: 13; font.bold: true }
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                radius: 18; color: theme.backgroundColor; border.width: 2; border.color: "#000"; clip: true
                Rectangle {
                    anchors.fill: parent; anchors.margins: 10; radius: 12; clip: true
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: theme.backgroundColor }
                        GradientStop { position: 1.0; color: theme.backgroundColor3 }
                    }
                    Loader {
                        id: previewLoader
                        anchors.fill: parent; anchors.margins: 10
                        // Recreate the tile body on every open so reopening for a DIFFERENT
                        // instance of the same type reloads and re-seeds against the new
                        // instanceId — otherwise the source is unchanged, the Loader never
                        // reloads, onLoaded never fires, and the previous instance's body
                        // (with its stale instanceId) lingers (split-brain preview).
                        active: dlg.visible
                        source: dlg.wsrc(dlg.wType)
                        onLoaded: dlg.inject(item)
                    }
                }
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: "Live & interactive — changes apply instantly to the Edge."
                color: m.textSecondary; font.pixelSize: 12
            }
            Button {
                text: "Reset to defaults"; Layout.fillWidth: true
                onClicked: resetConfirm.open()
            }
        }

        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: m.border }

        // ── Form (shared panel — identical rendering to the on-device config) ──
        WidgetConfigPanel {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: 320
            schema: dlg.schema
            store: store
            instanceId: dlg.wId
            col: m
            statusText: dlg.wType === "weather" ? dlg.geoStatus : ""
            onActionRequested: (a) => dlg.doAction(a)
        }
    }
}
