import QtQuick
import QtTest
import "../../ui/qml" as App

// REGRESSION: the floating drag "name-tag" must NOT stay stuck after a
// drag-and-drop reorder in manager/qml/EdgeClone.qml.
// (Prose, not a COVERS claim — the behavior ids this file credits are the
// fn:EdgeClone.* ones asserted below.)
//
// The bug: on drop, EdgeClone reset its drag state (clone.dragIndex = -1) AFTER
// calling store.moveTile(...). moveTile reorders the model, which can destroy the
// dragged delegate and its still-running onReleased handler, so the reset never
// executed and the floating name-tag (the z:100 Rectangle whose `visible` binding
// tracks clone.dragIndex) stayed stranded on screen.
//
// The fix: onReleased now clears ma.dragging=false / clone.dragIndex=-1 /
// clone.targetIndex=-1 BEFORE calling store.moveTile.
//
// EdgeClone resolves store/catalog/theme/media/backend from the Manager scope; we
// provide them on this wrapper (backend is a light stub, copied from tst_manager)
// and load the REAL EdgeClone.qml via a Loader — exactly as tst_edgeclone.qml does.
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

    Loader {
        id: ld
        anchors.fill: parent
        source: "../../manager/qml/EdgeClone.qml"
        onLoaded: if (item) item.pageIndex = 0
    }

    // ── tree helpers (same shape as tst_edgeclone / tst_manager) ──────────────
    function eachItem(node, fn) {
        if (!node) return
        fn(node)
        var kids = node.children
        if (kids) for (var i = 0; i < kids.length; i++) eachItem(kids[i], fn)
    }
    function findPred(n, pred) {
        var f = null
        eachItem(n, function (x) { if (!f && pred(x)) f = x })
        return f
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
    // The drag/select overlay MouseArea (`ma`) carries `dragging`; the resize-handle
    // MouseArea does not — so `dragging !== undefined` disambiguates them.
    function dragMA(i) {
        var t = tileAtIndex(i)
        if (!t) return null
        return findPred(t, function (x) { return x && x.dragging !== undefined && x.sx !== undefined })
    }
    // The floating name-tag: the only z:100 Rectangle in EdgeClone.
    function nameTag() {
        return findPred(ld.item, function (x) { return x && x.z === 100 && x.radius !== undefined })
    }
    function tileIds() {
        var ts = store.pages()[0].tiles
        return ts.map(function (t) { return t.id })
    }

    function seed3() {
        store.load("blank")
        store.addTile(0, "cpu")
        store.addTile(0, "clock")
        store.addTile(0, "focus")
    }

    TestCase {
        name: "EdgeCloneDrag"
        when: windowShown

        function initTestCase() {
            tryVerify(function () { return ld.status === Loader.Ready && ld.item !== null }, 5000)
        }

        // Drag tile 0 onto tile 2 → reorder commits AND the name-tag is cleared on
        // drop. This is the exact regression: pre-fix the name-tag stayed visible
        // because the reset ran after moveTile destroyed the dragged delegate.
        function test_drag_reorders_and_clears_nametag() {
            seed3()
            tryVerify(function () {
                var t0 = tileAtIndex(0), t2 = tileAtIndex(2)
                return t0 && t2 && t0.width > 0 && t2.width > 0 && dragMA(0) !== null
            }, 4000, "three tiles laid out with a drag MouseArea on tile 0")

            var tag = nameTag()
            verify(tag, "found the floating name-tag (z:100)")
            verify(!tag.visible, "name-tag hidden before any drag")

            var before = tileIds()
            compare(before.length, 3, "seeded three tiles")
            var movedId = before[0]                       // the tile we will drag away from index 0
            var draggedType = store.pages()[0].tiles[0].type

            var t0 = tileAtIndex(0), t2 = tileAtIndex(2)
            var ma = dragMA(0)

            // Press near tile-0 centre (in the MouseArea's local space, which shares
            // tile-0's origin — the overlay is anchors.fill).
            var px = t0.width / 2, py = t0.height / 2
            // A point that maps (tile-0 local → grid) onto tile-2's centre, so the
            // handler's targetAt() reports index 2 (grid coords are what it compares).
            var overX = (t2.x + t2.width / 2) - t0.x
            var overY = (t2.y + t2.height / 2) - t0.y

            mousePress(ma, px, py)
            mouseMove(ma, px + 20, py + 20)               // cross the 8px threshold → dragging starts
            mouseMove(ma, overX, overY)                   // hover over tile 2

            // ── during the drag: state is live and the name-tag is showing ──
            compare(ld.item.dragIndex, 0, "dragIndex tracks the dragged tile (0) mid-drag")
            verify(nameTag().visible, "the floating name-tag is visible during the drag")
            var tagText = findPred(nameTag(), function (x) {
                return x && typeof x.text === "string" && x.text.length > 0 })
            verify(tagText, "the name-tag hosts a title Text")
            compare(tagText.text, catalog.title(draggedType),
                    "the name-tag shows the dragged tile's title")
            compare(ld.item.targetIndex, 2, "the drop target resolved to tile 2")

            mouseRelease(ma, overX, overY)

            // ── after drop: the REGRESSION — drag state cleared, name-tag hidden ──
            tryVerify(function () { return ld.item.dragIndex === -1 }, 2000,
                      "dragIndex reset to -1 on drop")
            compare(ld.item.targetIndex, -1, "targetIndex reset to -1 on drop")
            tryVerify(function () { return nameTag().visible === false }, 2000,
                      "BUG GUARD: the floating name-tag is hidden after drop (not stuck on screen)")

            // ── the reorder actually happened: index-0 tile moved later ──
            var after = tileIds()
            compare(after.length, 3, "no tile lost in the reorder")
            verify(after.indexOf(movedId) > 0,
                   "the tile that started at index 0 is now later in page-0 order")
            compare(after[after.length - 1], movedId,
                    "moveTile(0,0,2) placed the dragged tile at the end")
        }

        // A press with movement UNDER the 8px threshold is a click, not a drag:
        // no reorder, and the name-tag never appears.
        function test_subthreshold_is_click_no_reorder() {
            seed3()
            tryVerify(function () {
                var t0 = tileAtIndex(0)
                return t0 && t0.width > 0 && dragMA(0) !== null
            }, 4000, "tiles laid out with a drag MouseArea on tile 0")

            var spy = configSpy
            spy.clear()
            var before = tileIds()
            var t0 = tileAtIndex(0)
            var ma = dragMA(0)
            var px = t0.width / 2, py = t0.height / 2

            mousePress(ma, px, py)
            mouseMove(ma, px + 3, py + 3)                 // 3px — below the 8px threshold
            mouseMove(ma, px + 5, py + 2)                 // still under threshold
            // never entered a drag → name-tag must stay hidden
            compare(ld.item.dragIndex, -1, "no drag started for a sub-threshold move")
            verify(!nameTag().visible, "the name-tag never shows for a click")
            mouseRelease(ma, px + 5, py + 2)

            compare(ld.item.dragIndex, -1, "still no drag after release")
            verify(!nameTag().visible, "name-tag stays hidden after a click release")
            compare(spy.count, 1, "the sub-threshold release was treated as a configure click")

            var after = tileIds()
            compare(after.length, before.length, "tile count unchanged")
            for (var i = 0; i < before.length; i++)
                compare(after[i], before[i], "tile order unchanged by a click at index " + i)
        }
    }

    // Catches EdgeClone.configRequested so the sub-threshold test can prove the
    // release was handled as a click (the else branch of onReleased).
    SignalSpy {
        id: configSpy
        target: ld.item
        signalName: "configRequested"
    }
}
