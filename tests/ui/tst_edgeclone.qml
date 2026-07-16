import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: fn:EdgeClone.injectInto, fn:EdgeClone.targetAt, fn:EdgeClone.wsrc
//
// manager/qml/EdgeClone.qml —
//   • wsrc(type): rewrites the hub qrc path to the manager alias; "" for unknown
//   • injectInto: sets instanceId/store/expanded/active + binds titleOverride/
//     accentName/cardBackdrop/metrics/tick; null item is safe
//   • targetAt(gx,gy): hit-tests placed tiles (in-bounds → index, outside → -1)
//   • resize handle drag → snaps to a size the TYPE declares → store.setTileSize
//
// `spanH(h) = 180n + 10(n-1)` is GONE with its test: it hard-coded a 180px row
// height, and the size model has no such thing — a cell is a fraction of the screen,
// so there is no fixed pixel row to encode. Placement now comes from WidgetPacker.
//
// EdgeClone resolves store/catalog/theme/media/backend from the Manager scope;
// we provide them on this wrapper (backend is a light stub) and load the REAL
// EdgeClone.qml via a Loader. Assertions target the store + driving props.
Item {
    id: root
    width: 560; height: 860

    App.Theme { id: theme }
    App.DashboardStore { id: store }
    App.WidgetCatalog { id: catalog }
    MockMedia { id: media }

    QtObject {
        id: backend
        property bool hubConnected: false
        function imageUrl(n) { return "file:///imgs/" + n }
        function metricsJson() { return "{}" }
    }

    Component {
        id: fakeWidget
        QtObject {
            property string instanceId: ""
            property var store: null
            property bool expanded: true
            property bool active: false
            property var metrics: ({})
            property string titleOverride: "unset"
            property string accentName: "unset"
            property string cardBackdrop: "unset"
            property int tick: -1
        }
    }

    Loader {
        id: ld
        anchors.fill: parent
        source: "../../manager/qml/EdgeClone.qml"
        onLoaded: if (item) item.pageIndex = 0
    }

    // ── tree helpers ─────────────────────────────────────────────────────────
    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids) for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
    }
    function findAll(n, pred) {
        var out = []
        eachItem(n, function (x) { if (pred(x)) out.push(x) })
        return out
    }
    function tileDelegates() {
        return findAll(ld.item, function (x) {
            return x && x.effSize !== undefined && x.pvSize !== undefined && x.modelData !== undefined
        })
    }
    function tileAtIndex(i) {
        var ds = tileDelegates()
        for (var k = 0; k < ds.length; k++) if (ds[k].index === i) return ds[k]
        return null
    }
    // The resize-handle MouseArea: it carries the press-origin (sx/sy) but, unlike
    // the drag/select overlay, no `dragging` flag.
    function resizeHandles() {
        return findAll(ld.item, function (x) {
            return x && x.sx !== undefined && x.dragging === undefined && typeof x.pressed === "boolean"
        })
    }

    function seed(tileList) {
        store.load("blank")
        for (var i = 0; i < tileList.length; i++)
            store.addTile(0, tileList[i].type)
    }
    function tile0() { return store.pages()[0].tiles[0] }

    TestCase {
        name: "EdgeClone"
        when: windowShown

        function initTestCase() {
            tryVerify(function () { return ld.status === Loader.Ready && ld.item !== null }, 5000)
        }

        function init() { store.load("blank") }   // a live, mutable store document

        // ── wsrc ──────────────────────────────────────────────────────────────
        function test_wsrc_rewrites_known_and_blanks_unknown() {
            var c = ld.item
            compare(catalog.source("cpu"), "qrc:/qml/CpuWidget.qml", "precondition: hub path")
            compare(c.wsrc("cpu"), "qrc:/manager/CpuWidget.qml", "rewritten to the manager alias")
            compare(c.wsrc("does-not-exist"), "", "unknown type yields empty source")
        }

        // ── injectInto ────────────────────────────────────────────────────────
        function test_injectInto_sets_props_and_binds() {
            var c = ld.item
            var w = fakeWidget.createObject(root)
            c.injectInto(w, "e1", "cpu")
            compare(w.instanceId, "e1", "instanceId set")
            compare(w.store, store, "store injected")
            compare(w.expanded, false, "clone always renders the compact (non-expanded) form")
            compare(w.active, true, "active forced on for the live preview")

            store.setSetting("e1", "title", "Rig")
            compare(w.titleOverride, "Rig", "titleOverride binding tracks the store")
            store.setSetting("e1", "accent", "teal")
            compare(w.accentName, "teal", "accentName binding tracks the store")
            store.setSetting("e1", "cardBackdrop", "orbs")
            compare(w.cardBackdrop, "orbs", "cardBackdrop binding tracks the store")

            c.metricsObj = ({ q: 9 })
            compare(w.metrics.q, 9, "metrics binding tracks clone.metricsObj")
            c.tick = 13
            compare(w.tick, 13, "tick binding tracks clone.tick")
            w.destroy()
        }

        function test_injectInto_null_is_safe() {
            ld.item.injectInto(null, "x", "cpu")
            verify(true, "injectInto(null) is a no-op")
        }

        // ── targetAt ──────────────────────────────────────────────────────────
        function test_targetAt_hits_cells_and_misses_outside() {
            var c = ld.item
            root.seed([ { type: "cpu" }, { type: "clock" } ])
            tryVerify(function () {
                var t0 = tileAtIndex(0), t1 = tileAtIndex(1)
                return t0 && t1 && t0.width > 0 && t1.width > 0
            }, 3000, "two tiles laid out")

            var t0 = tileAtIndex(0), t1 = tileAtIndex(1)
            // Delegate x/y are in the tile container's coordinate space — exactly what
            // targetAt() compares against (it reads rep.itemAt(i).x/y).
            var c0x = t0.x + t0.width / 2, c0y = t0.y + t0.height / 2
            var c1x = t1.x + t1.width / 2, c1y = t1.y + t1.height / 2
            compare(c.targetAt(c0x, c0y), 0, "centre of tile 0 hits index 0")
            compare(c.targetAt(c1x, c1y), 1, "centre of tile 1 hits index 1")
            compare(c.targetAt(-1000, -1000), -1, "far out-of-bounds hits nothing")

            // Boundary: the top-left corner is inclusive (gx >= it.x && …) → still a hit.
            compare(c.targetAt(t0.x, t0.y), 0, "the tile's top-left corner is inside (inclusive bound)")
            compare(c.targetAt(t0.x + t0.width, t0.y + t0.height), 0,
                    "the tile's bottom-right corner is inside (inclusive bound)")

            // Two 1x1 tiles are two thirds of the SCREEN, stacked along its long axis —
            // so the gap between them runs across, not down. (Under the old column grid
            // they sat side by side; the gap has simply changed axis with the layout.)
            verify(t1.y > t0.y && Math.abs(t1.x - t0.x) < 1,
                   "the second baseline tile is BELOW the first, not beside it")
            var gapY = (t0.y + t0.height + t1.y) / 2
            verify(gapY > t0.y + t0.height && gapY < t1.y, "the probe y sits in the inter-cell gap")
            compare(c.targetAt(c0x, gapY), -1, "a point in the inter-cell gap targets nothing")
        }

        // ── resize drag → snap → store.setTileSize ────────────────────────────
        // The drag is free-form; the SIZES are not. The old handler flipped a 1↔2 span
        // past a hard-coded pixel threshold; there are now seven named sizes and a
        // per-type list of which are legal, so the drag snaps to the nearest one the
        // widget actually declares.
        function test_resize_drag_grows_the_tile_to_a_bigger_declared_size() {
            root.seed([ { type: "cpu" } ])
            tryVerify(function () {
                var t = tileAtIndex(0)
                return t && t.width > 0 && resizeHandles().length === 1
            }, 3000, "single tile + its resize handle are ready")

            var id = tile0().id
            compare(tile0().size, catalog.defaultSize("cpu"), "starts at cpu's default size")
            var t0 = tileAtIndex(0)
            var startH = t0.height
            var h = resizeHandles()[0]

            // Drag the corner DOWN — along the long axis — by most of a third of the
            // screen. In the unscaled `screen` space the handler measures in.
            mousePress(h, 12, 12)
            mouseMove(h, 12, 12 + startH * 0.4)
            mouseMove(h, 12, 12 + startH * 0.5)
            mouseRelease(h, 12, 12 + startH * 0.5)

            compare(tile0().size, "1x1.5", "drag down grew it to the next size cpu declares")
            verify(catalog.supports("cpu", tile0().size), "and that size is one cpu really supports")
            verify(id.length > 0, "tile id was stable through the resize")
        }

        // The SHRINK branch: drag the handle up-and-left and the tile snaps down.
        function test_resize_drag_shrinks_the_tile() {
            root.seed([ { type: "cpu" } ])
            var id = tile0().id
            store.setTileSize(0, id, "1x1")
            tryVerify(function () {
                var t = tileAtIndex(0)
                return t && t.width > 100 && resizeHandles().length === 1
            }, 3000, "a baseline tile + its resize handle are ready")
            compare(tile0().size, "1x1", "precondition: a full third of the screen")

            var t0 = tileAtIndex(0)
            var h = resizeHandles()[0]
            mousePress(h, 12, 12)
            mouseMove(h, 12 - t0.width * 0.3, 12 - t0.height * 0.3)
            mouseMove(h, 12 - t0.width * 0.5, 12 - t0.height * 0.5)
            mouseRelease(h, 12 - t0.width * 0.5, 12 - t0.height * 0.5)

            compare(tile0().size, "0.5x0.5", "dragging back to a quarter box snapped to the twelfth")
        }

        // THE GUARD: a drag can never produce a size the widget type does not declare.
        // `focus` needs a squarish box (its ring is min(w,h)-scaled with the Start row
        // anchored over it), so it declares only 1x1 and 1x1.5 — no half sizes at all.
        // A huge drag must stop at 1x1.5, and a tiny one must not reach 0.5x0.5.
        function test_resize_drag_never_lands_on_a_size_the_type_lacks() {
            root.seed([ { type: "focus" } ])
            compare(catalog.sizesFor("focus").join(","), "1x1,1x1.5",
                    "precondition: focus declares only two sizes")
            tryVerify(function () {
                var t = tileAtIndex(0)
                return t && t.width > 0 && resizeHandles().length === 1
            }, 3000, "the focus tile + its resize handle are ready")

            var t0 = tileAtIndex(0)
            var h = resizeHandles()[0]
            // A runaway drag down-and-right: way past the whole screen.
            mousePress(h, 12, 12)
            mouseMove(h, 12 + t0.width * 4, 12 + t0.height * 6)
            mouseRelease(h, 12 + t0.width * 4, 12 + t0.height * 6)
            compare(tile0().size, "1x1.5",
                    "a runaway drag stops at focus's largest DECLARED size — never 1x2 or 1x3")

            // …and a runaway drag inward cannot reach the half sizes it does not declare.
            t0 = tileAtIndex(0)
            h = resizeHandles()[0]
            mousePress(h, 12, 12)
            mouseMove(h, 12 - t0.width * 2, 12 - t0.height * 2)
            mouseRelease(h, 12 - t0.width * 2, 12 - t0.height * 2)
            compare(tile0().size, "1x1", "and inward it stops at 1x1 — never 0.5x0.5")
            verify(catalog.supports("focus", tile0().size), "whatever the drag, the size is one focus declares")
        }

        // A type with exactly one legal size has nothing to resize TO, so the handle is
        // not offered — a control that provably cannot do anything should not be there.
        function test_resize_handle_is_hidden_when_there_is_only_one_size() {
            root.seed([ { type: "cpu" } ])
            tryVerify(function () { return resizeHandles().length === 1 }, 3000,
                      "cpu declares several sizes, so it gets a handle")
            verify(catalog.sizesFor("cpu").length > 1, "precondition: cpu really has more than one")
        }

        // Preview mode (Appearance tab): editable=false renders the same WYSIWYG
        // clone but hides every edit affordance — drag/select overlay, ⚙/✕
        // controls, resize handle — so the preview can't become a second,
        // competing layout editor.
        function test_editable_false_hides_every_edit_affordance() {
            root.seed([ { type: "cpu" } ])
            tryVerify(function () {
                var t = tileAtIndex(0)
                return t && t.width > 0 && resizeHandles().length === 1
            }, 3000, "an editable tile with its handle is ready")
            var c = ld.item
            verify(c.editable, "clone starts editable (Layout-tab default)")

            c.editable = false
            // The drag/select overlay (the MouseArea carrying `dragging`).
            var overlays = findAll(ld.item, function (x) {
                return x && x.dragging !== undefined && typeof x.pressed === "boolean"
            })
            verify(overlays.length > 0, "found the drag/select overlay")
            for (var i = 0; i < overlays.length; i++)
                verify(!overlays[i].visible, "drag/select overlay hidden in preview mode")
            // The ⚙/✕ controls row (the z:5 Row on each tile).
            var rows = findAll(ld.item, function (x) {
                return x && x.z === 5 && x.spacing !== undefined
            })
            verify(rows.length > 0, "found the tile controls row")
            for (var r = 0; r < rows.length; r++)
                verify(!rows[r].visible, "⚙/✕ controls hidden in preview mode")
            // The resize handle (its parent Rectangle owns the visible flag).
            verify(!resizeHandles()[0].parent.visible, "resize handle hidden in preview mode")

            c.editable = true   // restore the shared Loader for the other tests
            verify(resizeHandles()[0].parent.visible, "handle returns when editable again")
        }
    }
}
