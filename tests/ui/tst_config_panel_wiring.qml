import QtQuick
import QtQuick.Controls
import QtTest
import "../../ui/qml" as App
import "../../ui/qml/widgets" as Widgets

// Regression gate for the WidgetConfigPanel store-wiring self-binding trap.
//
// WidgetConfigPanel's store property is named `st` (not `store`) on purpose: the
// product call sites (WidgetConfigDialog.qml, Dashboard.qml) pass the Manager/hub
// store which is an `id: store`. If the panel property were named `store`, the
// binding `store: store` would resolve the RHS to the panel's OWN null property
// (QML self-binding trap) - severing the ENTIRE config form from the store: every
// field showed its default, the date showed an empty mask, and edits were silently
// dropped. This test uses `st: store` where `store` is an id, so it reproduces the
// exact call-site shape and FAILS if the property is ever renamed back to `store`.
Item {
    id: root; width: 1000; height: 800
    property var m: ({ textPrimary:"#E6EDF3", textSecondary:"#8B949E", bg:"#0D1117",
        accent:"#F26D6D", border:"#30363D", panel:"#161B22", panelAlt:"#1C222B", radius:12 })
    App.Theme { id: theme }
    App.DashboardStore { id: store }
    App.WidgetConfigSchema { id: sc }

    property bool ready: false
    Component.onCompleted: {
        store.load("blank")
        // Value PRESENT before the form renders (the real "open config for an
        // existing tile" case), including a segmented field (cardBackdrop).
        store.patchSettings("countdown-15",
            { label:"Vacation", date:"2026-08-07", repeatYearly:false, cardBackdrop:"mesh" })
        ready = true
    }

    Loader {
        id: ld; active: root.ready; anchors.fill: parent
        // NB: `st: store` - the call-site shape that would self-bind if the panel
        // property were `store`.
        sourceComponent: Widgets.WidgetConfigPanel {
            schema: sc.schemaFor("countdown")
            st: store
            instanceId: "countdown-15"
            col: root.m
        }
    }

    function findAll(node, pred, acc) {
        acc = acc || []; if (!node) return acc
        if (pred(node)) acc.push(node)
        var kids = node.children
        for (var i=0; kids && i<kids.length; i++) findAll(kids[i], pred, acc)
        return acc
    }
    function fieldWrap(key) {
        var w = findAll(ld.item, function(n){ return n.objectName === "field-" + key })
        return w.length === 1 ? w[0] : null
    }
    function editable(node) {
        var e = findAll(node, function(n){
            return n.hasOwnProperty("cursorPosition") && n.hasOwnProperty("readOnly") })
        return e.length ? e[0] : null
    }

    TestCase {
        name: "ConfigPanelStoreWiring"; when: windowShown

        // QtTest runs test functions alphabetically, so re-seed known values before
        // each one (the edit test mutates the shared store). Clear focus first so the
        // fields' "don't clobber while typing" guard lets the re-seed re-assert.
        function init() {
            var lbl = editable(fieldWrap("label"))
            if (lbl) lbl.focus = false
            store.patchSettings("countdown-15",
                { label:"Vacation", date:"2026-08-07", repeatYearly:false, cardBackdrop:"mesh" })
        }

        function test_panel_reaches_the_store() {
            verify(ld.item, "panel loaded")
            var date = fieldWrap("date")
            verify(date, "date field rendered")
            // The ConfigField root exposes cur() reading through its `st`.
            compare(date.st, store, "field.st must be the passed-in store (not a self-bound null)")
        }

        function test_text_field_shows_stored_value() {
            var lbl = editable(fieldWrap("label"))
            verify(lbl, "label editable exists")
            compare(lbl.text, "Vacation", "text field shows the stored value")
        }

        function test_masked_date_field_shows_stored_value() {
            var d = editable(fieldWrap("date"))
            verify(d, "date editable exists")
            compare(d.text, "2026-08-07", "masked date field shows the stored value, not an empty mask")
        }

        function test_segmented_field_shows_stored_selection() {
            // cardBackdrop is a segmented field in the "Widget appearance" section;
            // the "mesh" option must render selected (sel === true), not the default.
            var wrap = fieldWrap("cardBackdrop")
            verify(wrap, "cardBackdrop field rendered")
            var selected = findAll(wrap, function(n){ return n.hasOwnProperty("sel") && n.sel === true })
            compare(selected.length, 1, "exactly one backdrop option is selected")
            // and it must be the stored one - find the label text under the selected chip
            var lbls = findAll(selected[0], function(n){ return n.hasOwnProperty("text") && ("" + n.text).toLowerCase() === "mesh" })
            verify(lbls.length >= 1, "the SELECTED backdrop is 'mesh' (the stored value), not the default")
        }

        function test_editing_writes_back_to_store() {
            var lbl = editable(fieldWrap("label"))
            lbl.forceActiveFocus()
            lbl.text = "Trip"
            lbl.editingFinished()   // commit
            compare(store.settingsFor("countdown-15").label, "Trip",
                    "editing a field must write through to the store (st non-null)")
        }
    }
}
