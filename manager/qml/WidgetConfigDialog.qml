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
    // The egress gate. The city lookup below is the only request the Manager makes,
    // and it must be counted and gateable like any widget's, so it routes through
    // NetHub rather than building an XHR here. The Manager has no app-global gate
    // to inject (it does no polling), so the dialog owns one; `netHub` stays
    // injectable so a Manager-global gate can take over without touching this file.
    property var netHub: null
    NetHub { id: _fallbackHub }
    function _hub() { return netHub ? netHub : _fallbackHub }
    // Test seam: a per-request XHR factory handed to the gate, so a FakeXHR can be
    // injected. null in production → the gate builds the real XHR.
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
    background: Rectangle { color: m.bg; radius: m.radius; border.width: 1; border.color: m.border }

    // Custom token footer instead of the default Fusion DialogButtonBox (which
    // renders a pale light-gray Close on the dark UI). A single accent Close button.
    footer: Rectangle {
        color: "transparent"; implicitHeight: 62
        Button {
            id: closeBtn
            objectName: "closeBtn"
            text: "Close"
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 20
            implicitHeight: 40; implicitWidth: 120; hoverEnabled: true
            contentItem: Text {
                text: closeBtn.text; color: m.textOnAccent; font.pixelSize: 14; font.bold: true
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: m.radius
                color: closeBtn.down ? Qt.darker(m.accent, 1.2)
                       : (closeBtn.hovered ? Qt.lighter(m.accent, 1.1) : m.accent)
            }
            onClicked: dlg.close()
        }
    }

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
    // Bumping the sequence is what actually cancels: abort() still delivers one
    // late callback, and the gate answers a refused request synchronously (no XHR
    // to compare against), so the token — not the object — decides who is current.
    property var _geoXhr: null
    property int _geoSeq: 0
    function _cancelGeo() {
        dlg._geoSeq++
        if (_geoXhr) { try { _geoXhr.abort() } catch (e) {} _geoXhr = null }
    }

    function doAction(action) {
        if (action === "geocode") {
            var place = store.settingsFor(wId).place || ""
            if (!place.trim().length) { geoStatus = "Type a place name first"; return }
            dlg._cancelGeo()                       // supersede any in-flight lookup
            geoStatus = "Searching…"
            var seq = ++dlg._geoSeq
            var xhr = dlg._hub().request({
                url: "https://geocoding-api.open-meteo.com/v1/search?count=1&name="
                     + encodeURIComponent(place.trim()),
                timeout: 8000,
                xhrFactory: dlg.xhrFactory,
                onDone: function (status, body) {
                    if (seq !== dlg._geoSeq) return
                    dlg._geoXhr = null
                    try {
                        var d = JSON.parse(body)
                        if (d && d.results && d.results.length) {
                            var r = d.results[0]
                            var label = r.name + (r.country_code ? ", " + r.country_code : "")
                            store.patchSettings(wId, { lat: r.latitude, lon: r.longitude, place: label })
                            dlg.geoStatus = "✓ Set to " + label
                        } else dlg.geoStatus = "City not found"
                    } catch (e) { dlg.geoStatus = "Lookup failed" }
                },
                onError: function (reason) {
                    if (seq !== dlg._geoSeq) return
                    dlg._geoXhr = null
                    dlg.geoStatus = reason === "offline" ? "Offline - lookup unavailable"
                        : reason === "blocked" ? "Lookup host not allowed"
                        : reason === "timeout" ? "Lookup timed out - try again" : "Lookup failed"
                }
            })
            if (seq === dlg._geoSeq) dlg._geoXhr = xhr
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
        // Custom token header (mirrors Manager's confirmDialog): the Fusion title
        // chrome clashed with the dark UI and its label sizing fed the Dialog an
        // implicitWidth binding loop.
        header: Rectangle {
            color: "transparent"; implicitHeight: 52
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18; spacing: 10
                AppIcon { name: "ui-warning"; size: 20; color: m.danger; Layout.alignment: Qt.AlignVCenter }
                Text { text: resetConfirm.title; color: m.textPrimary; font.pixelSize: 17; font.bold: true
                    Layout.fillWidth: true }
            }
        }
        contentItem: Text {
            text: "Reset " + catalog.title(dlg.wType) + " to its default settings? This can't be undone."
            color: m.textPrimary; wrapMode: Text.WordWrap; padding: 14; font.pixelSize: 14
            // Same cap as Manager's confirmDialog: an uncapped Text keeps widening
            // the dialog that sizes it (implicitWidth binding loop).
            width: Math.min(implicitWidth, 360)
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
                Text { text: catalog.title(dlg.wType) + " - Configure"; color: m.textPrimary; font.pixelSize: 20; font.bold: true }
                Text { text: catalog.desc(dlg.wType); color: m.textSecondary; font.pixelSize: 12
                    elide: Text.ElideRight; Layout.fillWidth: true }
            }
            // Scope pill: these settings touch ONE tile, not the widget type —
            // the owner's "which setting changes which behavior" complaint. Label +
            // hover detail come from the Manager's ONE scope vocabulary (win.scopeLabels
            // / win.scopeDetail), so this dialog can't drift from the tabs' wording.
            Rectangle {
                id: scopePill
                objectName: "scopeTag"
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: scopeLbl.implicitWidth + 18; implicitHeight: 24; radius: 12
                color: "transparent"; border.width: 1; border.color: m.accent
                property alias text: scopeLbl.text
                Text { id: scopeLbl; anchors.centerIn: parent; text: win.scopeLabels.widget
                    color: m.accent; font.pixelSize: 11; font.bold: true }
                ToolTip.visible: scopeMA.containsMouse && ToolTip.text !== ""
                ToolTip.delay: 250
                ToolTip.text: win.scopeDetail(scopeLbl.text)
                MouseArea { id: scopeMA; anchors.fill: parent; hoverEnabled: true }
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
                    // WYSIWYG preview. The widget is rendered at the Edge content width
                    // (`logicalW`, ~688px) — the width it was DESIGNED for — inside a
                    // fixed-logical-size scaler, then scaled down to fit this ~300px pane
                    // (the same trick EdgeClone uses on the whole device). Without this the
                    // expanded layout (Focus's 4-button row, Media transport, Countdown's
                    // label+date+Save, Tasks add-row, Hydration) overflows the narrow pane
                    // and is clipped by WidgetChrome.body{clip:true}.
                    Item {
                        id: previewClip
                        objectName: "previewClip"
                        anchors.fill: parent; anchors.margins: 10; clip: true
                        // Edge portrait content width the expanded widgets target.
                        readonly property real logicalW: 688
                        readonly property real fit: width > 0 ? width / logicalW : 1
                        Item {
                            id: previewScaler
                            objectName: "previewScaler"
                            width: previewClip.logicalW
                            // Give the widget a tall logical canvas so that AFTER scaling it
                            // exactly fills the pane's height (fit * height === pane height).
                            height: previewClip.fit > 0 ? previewClip.height / previewClip.fit : previewClip.height
                            transformOrigin: Item.TopLeft
                            scale: previewClip.fit
                            Loader {
                                id: previewLoader
                                anchors.fill: parent
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
                }
            }
            Text {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                // Honest about the commit path: "instantly on the Edge" was shown
                // even while the sidebar said "Hub offline (saved)".
                text: backend.hubConnected
                      ? "Live & interactive - changes apply instantly to the Edge."
                      : "Live preview - changes are saved and appear when the hub starts."
                color: m.textSecondary; font.pixelSize: 12
            }
            // Token-styled (mirrors Manager's MButton) so it matches the dark app
            // palette instead of rendering as a pale default Fusion button.
            Button {
                id: resetBtn
                text: "Reset to defaults"; Layout.fillWidth: true
                implicitHeight: 40; hoverEnabled: true
                contentItem: Text {
                    text: resetBtn.text; color: m.textPrimary; font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: m.radius
                    color: (resetBtn.down || resetBtn.hovered) ? m.panelAlt : m.panel
                    border.width: 1; border.color: m.border
                }
                onClicked: resetConfirm.open()
            }
        }

        Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: m.border }

        // ── Form (shared panel — identical rendering to the on-device config) ──
        WidgetConfigPanel {
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: 320
            schema: dlg.schema
            st: store
            instanceId: dlg.wId
            col: m
            statusText: dlg.wType === "weather" ? dlg.geoStatus : ""
            onActionRequested: (a) => dlg.doAction(a)
        }
    }
}
