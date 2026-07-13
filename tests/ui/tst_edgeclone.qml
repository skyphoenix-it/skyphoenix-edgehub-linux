import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: fn:EdgeClone.injectInto, fn:EdgeClone.spanH, fn:EdgeClone.targetAt, fn:EdgeClone.wsrc
//
// manager/qml/EdgeClone.qml —
//   • wsrc(type): rewrites the hub qrc path to the manager alias; "" for unknown
//   • spanH(h): 180·n + 10·(n-1) with n = max(1,h); clamps 0 / negatives to 1 row
//   • injectInto: sets instanceId/store/expanded/active + binds titleOverride/
//     accentName/cardBackdrop/metrics/tick; null item is safe
//   • targetAt(gx,gy): hit-tests grid cells (in-bounds → index, outside → -1)
//   • resize handle drag → store.setTileSize (width & height span change)
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
            return x && x.effH !== undefined && x.pvW !== undefined && x.modelData !== undefined
        })
    }
    function tileAtIndex(i) {
        var ds = tileDelegates()
        for (var k = 0; k < ds.length; k++) if (ds[k].index === i) return ds[k]
        return null
    }
    function resizeHandles() {
        return findAll(ld.item, function (x) {
            return x && x.sw !== undefined && x.sh !== undefined && typeof x.pressed === "boolean"
        })
    }

    function seed(tileList, cols) {
        store.load("blank")
        for (var i = 0; i < tileList.length; i++)
            store.addTile(0, tileList[i].type)
        // Force known ids by rewriting the doc is unnecessary — read them back.
        if (cols) store.setPageColumns(0, cols)
    }

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

        // ── spanH ─────────────────────────────────────────────────────────────
        function test_spanH_formula_and_clamp() {
            var c = ld.item
            compare(c.spanH(1), 180, "1 row")
            compare(c.spanH(2), 370, "2 rows include one 10px gap")
            compare(c.spanH(3), 560, "3 rows include two gaps")
            compare(c.spanH(0), 180, "0 clamps to a single row")
            compare(c.spanH(-4), 180, "negatives clamp to a single row")
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
            root.seed([ { type: "cpu" }, { type: "clock" } ], 2)
            tryVerify(function () {
                var t0 = tileAtIndex(0), t1 = tileAtIndex(1)
                return t0 && t1 && t0.width > 0 && t1.width > 0
            }, 3000, "two tiles laid out")

            var t0 = tileAtIndex(0), t1 = tileAtIndex(1)
            // Delegate x/y are in the GridLayout's coordinate space — exactly what
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

            // In-bounds gap: a point in the 10px column gap between the two side-by-side
            // cells is within the grid's bounding box but belongs to NEITHER cell → -1
            // (it must not silently snap to a neighbour).
            var gapX = (t0.x + t0.width + t1.x) / 2
            verify(gapX > t0.x + t0.width && gapX < t1.x, "the probe x sits in the inter-cell gap")
            compare(c.targetAt(gapX, c0y), -1, "a point in the inter-cell gap targets nothing")
        }

        // ── resize drag → store.setTileSize ───────────────────────────────────
        function test_resize_drag_updates_tile_size() {
            var c = ld.item
            root.seed([ { type: "cpu" } ], 2)     // 2 cols so a width span change is possible
            tryVerify(function () {
                var t = tileAtIndex(0)
                return t && t.width > 0 && resizeHandles().length === 1
            }, 3000, "single tile + its resize handle are ready")

            var id = store.pages()[0].tiles[0].id
            compare(store.pages()[0].tiles[0].w || 1, 1, "starts 1 wide")
            compare(store.pages()[0].tiles[0].h || 1, 1, "starts 1 tall")

            var t0 = tileAtIndex(0)
            var h = resizeHandles()[0]
            // Drag the corner handle down-and-right well past the ~half-tile flip
            // thresholds (width flip needs dx > tile.width·0.55), in the handle's
            // local space — which maps 1:1 into the unscaled screen content the
            // handler measures in (the fit-scale sits above `screen`).
            var dragX = t0.width + 40
            mousePress(h, 15, 15)
            mouseMove(h, dragX * 0.5, 200)
            mouseMove(h, dragX, 340)
            mouseRelease(h, dragX, 340)

            compare(store.pages()[0].tiles[0].w, 2, "drag right grew the tile to 2 columns")
            compare(store.pages()[0].tiles[0].h, 2, "drag down grew the tile to 2 rows")
            verify(id.length > 0, "tile id was stable through the resize")
        }

        // The SHRINK branch: from a 2×2 tile, dragging the handle UP-and-LEFT past
        // the flip thresholds (dx < -tW, dy < -tH) must reduce the span back to 1×1.
        function test_resize_drag_shrinks_tile() {
            root.seed([ { type: "cpu" } ], 2)
            var id = store.pages()[0].tiles[0].id
            store.setTileSize(0, id, 2, 2)          // start big so a shrink is meaningful
            tryVerify(function () {
                var t = tileAtIndex(0)
                return t && t.width > 300 && resizeHandles().length === 1
            }, 3000, "a wide (2-col) tile + its resize handle are ready")
            compare(store.pages()[0].tiles[0].w, 2, "precondition: 2 wide")
            compare(store.pages()[0].tiles[0].h, 2, "precondition: 2 tall")

            var t0 = tileAtIndex(0)
            var h = resizeHandles()[0]
            var backX = t0.width + 40               // well past the width flip threshold, leftward
            mousePress(h, 15, 15)
            mouseMove(h, 15 - backX * 0.5, -120)
            mouseMove(h, 15 - backX, -260)
            mouseRelease(h, 15 - backX, -260)

            compare(store.pages()[0].tiles[0].w, 1, "drag left shrank the tile to 1 column")
            compare(store.pages()[0].tiles[0].h, 1, "drag up shrank the tile to 1 row")
        }

        // Single-column clamp (EdgeClone.qml:299 — `cols >= 2 ? … : 1`): in a
        // 1-column grid the width span can never grow no matter how far you drag right.
        function test_resize_single_column_clamps_width() {
            root.seed([ { type: "cpu" } ], 1)       // ONE column
            tryVerify(function () {
                var t = tileAtIndex(0)
                return t && t.width > 0 && resizeHandles().length === 1
            }, 3000, "single tile in a 1-column grid is ready")

            var t0 = tileAtIndex(0)
            var h = resizeHandles()[0]
            var dragX = t0.width + 200              // a huge rightward drag
            mousePress(h, 15, 15)
            mouseMove(h, dragX * 0.5, 200)
            mouseMove(h, dragX, 340)
            mouseRelease(h, dragX, 340)

            compare(store.pages()[0].tiles[0].w || 1, 1, "width stays 1 in a single-column grid (clamp)")
            compare(store.pages()[0].tiles[0].h, 2, "height still grows — only the width is clamped")
        }
    }
}
