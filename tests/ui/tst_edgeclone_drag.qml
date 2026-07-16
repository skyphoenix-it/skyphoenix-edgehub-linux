import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: fn:EdgeClone._row, fn:EdgeClone._syncPlacements
//
// REGRESSION 1: the floating drag "name-tag" must NOT stay stuck after a
// drag-and-drop reorder in manager/qml/EdgeClone.qml.
//
// The bug: on drop, EdgeClone reset its drag state (clone.dragIdx = -1) AFTER
// calling store.moveTile(...). moveTile reorders the model, which can destroy the
// dragged delegate and its still-running onReleased handler, so the reset never
// executed and the floating name-tag (the z:100 Rectangle whose `visible` binding
// tracks clone.dragIdx) stayed stranded on screen.
//
// The fix: onReleased now clears ma.dragging=false / clone.dragIdx=-1 /
// clone.targetIdx=-1 BEFORE calling store.moveTile.
//
// REGRESSION 2 (below): a reorder TELEPORTED the tile. `model: clone.placements`
// handed the Repeater a fresh JS array on every re-pack, which resets its whole
// delegate model — so the tile that should have travelled was destroyed and a new
// one appeared already at the destination. Proven before the fix: the identity
// guard failed. The Repeater now takes a ListModel synced by id.
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
            return x && x.effSize !== undefined && x.pvSize !== undefined && x.tileId !== undefined
        })
    }
    // Keyed on the STORE tile index the delegate carries — deliberately not on the
    // Repeater's row number. Rows are patched in place by _syncPlacements, so after a
    // reorder row order is no longer tile order; a helper that assumed otherwise
    // would quietly hand back the wrong tile.
    function tileAtIdx(i) {
        var ds = tileDelegates()
        for (var k = 0; k < ds.length; k++) if (ds[k].tileIdx === i) return ds[k]
        return null
    }
    function tileById(id) {
        var ds = tileDelegates()
        for (var k = 0; k < ds.length; k++) if (ds[k].tileId === id) return ds[k]
        return null
    }
    // The drag/select overlay MouseArea (`ma`) carries `dragging`; the resize-handle
    // MouseArea does not — so `dragging !== undefined` disambiguates them.
    function dragMA(i) {
        var t = tileAtIdx(i)
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
                var t0 = tileAtIdx(0), t2 = tileAtIdx(2)
                return t0 && t2 && t0.width > 0 && t2.width > 0 && dragMA(0) !== null
            }, 4000, "three tiles laid out with a drag MouseArea on tile 0")

            var tag = nameTag()
            verify(tag, "found the floating name-tag (z:100)")
            verify(!tag.visible, "name-tag hidden before any drag")

            var before = tileIds()
            compare(before.length, 3, "seeded three tiles")
            var movedId = before[0]                       // the tile we will drag away from index 0
            var draggedType = store.pages()[0].tiles[0].type

            var t0 = tileAtIdx(0), t2 = tileAtIdx(2)
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
            compare(ld.item.dragIdx, 0, "dragIdx tracks the dragged tile (0) mid-drag")
            verify(nameTag().visible, "the floating name-tag is visible during the drag")
            var tagText = findPred(nameTag(), function (x) {
                return x && typeof x.text === "string" && x.text.length > 0 })
            verify(tagText, "the name-tag hosts a title Text")
            compare(tagText.text, catalog.title(draggedType),
                    "the name-tag shows the dragged tile's title")
            compare(ld.item.targetIdx, 2, "the drop target resolved to tile 2")

            mouseRelease(ma, overX, overY)

            // ── after drop: the REGRESSION — drag state cleared, name-tag hidden ──
            tryVerify(function () { return ld.item.dragIdx === -1 }, 2000,
                      "dragIdx reset to -1 on drop")
            compare(ld.item.targetIdx, -1, "targetIdx reset to -1 on drop")
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

        // ── REGRESSION 2: a reorder MOVES the tile, it does not rebuild it ──────
        // Three 1x1 tiles stack down the clone's long axis at l = 0, 2, 4.
        function _laidOut3() {
            seed3()
            tryVerify(function () {
                var t0 = tileAtIdx(0), t1 = tileAtIdx(1), t2 = tileAtIdx(2)
                return t0 && t1 && t2 && t0.width > 0 && t1.width > 0 && t2.width > 0
            }, 4000, "three tiles laid out")
        }

        // The two halves of the sync asserted directly: `_row` maps one packer
        // placement onto the model's roles, and `_syncPlacements` reconciles the whole
        // model to the current packing — idempotently, because the rows ARE the
        // delegates' identity, so re-running it must churn nothing.
        function test_placement_row_and_sync_map_the_packing_onto_the_model() {
            _laidOut3()
            var c = ld.item
            var placement = { id: "z", type: "cpu", size: "1x1", idx: 2, s: 0, l: 4 }
            compare(c._row(placement).tileId, "z", "_row carries the tile id")
            compare(c._row(placement).tileType, "cpu", "_row carries the type")
            compare(c._row(placement).tileSize, "1x1", "_row carries the size")
            compare(c._row(placement).tileIdx, 2, "_row carries the STORE tile index, not a row number")
            var r = c._row(placement)
            compare(r.ps + "," + r.pl, "0,4", "_row carries the semantic origin")
            // The role types a ListModel fixes on first append: a typeless tile must
            // seed "" (what wsrc/catalog.title already treat as "no such type"), not
            // `undefined`.
            compare(c._row({ id: "q", idx: 0, s: 0, l: 0 }).tileType, "",
                    "a missing type is coerced to \"\", never undefined")

            var a = tileAtIdx(0)
            compare(c._syncPlacements(), 3, "_syncPlacements holds one row per placed tile")
            compare(c._syncPlacements(), 3, "_syncPlacements is idempotent — no duplicate rows")
            verify(tileAtIdx(0) === a, "and it rebuilt nothing: same delegate after two syncs")
        }

        // THE TELEPORT GUARD. Pre-fix this failed: `model: clone.placements` handed the
        // Repeater a fresh array, which reset the whole delegate model.
        function test_reorder_moves_the_same_delegate_instead_of_rebuilding_it() {
            theme.reduceMotionPreference = "off"
            _laidOut3()
            var ids = tileIds()
            var a = tileById(ids[0]), b = tileById(ids[1]), c = tileById(ids[2])
            verify(a && b && c, "all three delegates found")
            compare(b.pl, 2, "precondition: b is the second tile down the long axis")
            // b's widget Loader — the object that OWNS the widget instance's lifetime.
            // (The widget itself cannot be asserted on here: every catalog source is a
            // `qrc:` path and this harness has no compiled resources, so no tile widget
            // ever instantiates offscreen. The Loader surviving with an unchanged `wId`
            // is exactly the condition under which its widget survives — a reload needs
            // either the Loader destroyed or its source key changed.)
            var bLoader = findPred(b, function (x) { return x && x.wId === ids[1] })
            verify(bLoader !== null, "found b's widget Loader")

            store.moveTile(0, 1, 0)
            tryVerify(function () { return tileById(ids[1]).pl === 0 }, 4000,
                      "b's placement moved to the first slot")

            // IDENTITY: a rebuilt delegate would be a different object.
            verify(tileById(ids[1]) === b, "b's tile is the SAME object after the reorder")
            verify(tileById(ids[0]) === a, "a's tile is the SAME object after the reorder")
            verify(tileById(ids[2]) === c, "the untouched tile c is the SAME object too")
            var bLoader2 = findPred(tileById(ids[1]), function (x) { return x && x.wId === ids[1] })
            verify(bLoader2 === bLoader, "b's Loader is the SAME object — its widget was never torn down")
            compare(bLoader2.wId, ids[1], "and its source key never changed, so it never reloaded")
            compare(tileDelegates().length, 3, "still exactly three tiles")
            compare(tileById(ids[1]).tileIdx, 0, "b's store index tracked the reorder")
        }

        // A move EASES: the surviving delegate leaves its old pixels behind gradually.
        // (The eye can only follow a tile it can see travelling — that is the fix.)
        function test_reorder_eases_the_tile_to_its_new_slot() {
            theme.reduceMotionPreference = "off"
            compare(theme.motionPage, 250, "precondition: move easing enabled")
            _laidOut3()
            var ids = tileIds()
            var b = tileById(ids[1])
            var startY = b.y
            compare(b.animL, 2, "precondition: b's eased mirror sits at its real slot")

            store.moveTile(0, 1, 0)

            // Frame 0: the TARGET slot is already the new one, but the eased mirror —
            // and therefore the pixels — have not jumped.
            compare(b.pl, 0, "b's target slot updated immediately")
            verify(b.animL > 0, "but it has NOT teleported: the eased mirror is still en route")
            fuzzyCompare(b.y, startY, 1.0, "and its pixels are still at the old slot on frame 0")

            // …and it does arrive.
            tryVerify(function () { return b.animL === 0 }, 4000, "the eased mirror lands on the new slot")
            verify(b.y < startY - 1, "b ended up further up the page than it started")
        }

        // REDUCE MOTION: smooth is not more motion. The move must be INSTANT — not a
        // 0ms animation that still lands a frame late.
        function test_reduce_motion_makes_a_reorder_instant() {
            theme.reduceMotionPreference = "on"
            compare(theme.motionPage, 0, "precondition: reduce-motion collapses the move token")
            _laidOut3()
            var ids = tileIds()
            var b = tileById(ids[1])
            var startY = b.y

            store.moveTile(0, 1, 0)

            // No tryVerify: with the Behavior disabled the write is direct, so the new
            // slot is already in the pixels on this very line.
            compare(b.pl, 0, "b's target slot updated")
            compare(b.animL, 0, "and the mirror is ALREADY there — no animation ran")
            verify(b.y < startY - 1, "b's pixels moved instantly, in the same event")
            verify(tileById(ids[1]) === b, "instant, but still the same delegate — not a rebuild")
            theme.reduceMotionPreference = "auto"
        }

        // ADD / REMOVE reuse the same machinery: survivors are moved, not rebuilt.
        function test_add_and_remove_keep_the_surviving_delegates() {
            theme.reduceMotionPreference = "off"
            _laidOut3()
            var ids = tileIds()
            var a = tileById(ids[0]), c = tileById(ids[2])

            // Remove the MIDDLE tile — c must slide up, not be reborn there.
            store.removeTile(0, ids[1])
            tryVerify(function () { return tileDelegates().length === 2 }, 4000, "b's tile is gone")
            verify(tileById(ids[1]) === null, "b really is removed")
            verify(tileById(ids[0]) === a, "a survived the removal")
            verify(tileById(ids[2]) === c, "c MOVED into the freed slot — same object, not a rebuild")
            tryVerify(function () { return tileById(ids[2]).pl === 2 }, 4000, "c's placement closed the gap")

            store.addTile(0, "disk")
            tryVerify(function () { return tileDelegates().length === 3 }, 4000, "the new tile is placed")
            verify(tileById(ids[0]) === a, "a survived the add")
            verify(tileById(ids[2]) === c, "and so did c")
        }

        // THE ROW-ORDER GUARD, and the reason `targetAt` reports a tileIdx rather than
        // a row number. _syncPlacements patches rows IN PLACE, so after one reorder row
        // order is no longer tile order. Any code that read `placements[rowNumber]`
        // would now address the wrong tile — silently, and only after the first drag.
        // So: reorder once to desynchronise the rows, then drag and check the RIGHT
        // tile moved.
        function test_a_second_drag_is_correct_after_rows_stop_matching_tile_order() {
            theme.reduceMotionPreference = "on"   // no in-flight geometry to hit-test
            _laidOut3()
            store.moveTile(0, 2, 0)               // rows now disagree with tile order
            tryVerify(function () { return tileAtIdx(0) && tileAtIdx(0).pl === 0 }, 4000,
                      "the page re-packed after the priming reorder")

            // PRECONDITION — without this the test would pass vacuously on the old
            // row==tile assumption and prove nothing.
            var rows = tileDelegates().map(function (d) { return d.tileIdx })
            verify(rows.join(",") !== "0,1,2",
                   "precondition: Repeater row order really is NOT tile order any more")

            var ids = tileIds()
            var t0 = tileAtIdx(0), t2 = tileAtIdx(2)
            var ma = dragMA(0)
            verify(t0 && t2 && ma, "the tile now at store index 0 has a drag overlay")
            var movedId = ids[0]

            var px = t0.width / 2, py = t0.height / 2
            var overX = (t2.x + t2.width / 2) - t0.x
            var overY = (t2.y + t2.height / 2) - t0.y
            mousePress(ma, px, py)
            mouseMove(ma, px + 20, py + 20)
            mouseMove(ma, overX, overY)
            compare(ld.item.dragIdx, 0, "the drag reports the STORE index of the held tile")
            compare(ld.item.targetIdx, 2, "and the drop target resolves to store index 2")
            mouseRelease(ma, overX, overY)

            var after = tileIds()
            compare(after.length, 3, "no tile lost")
            compare(after[2], movedId, "the tile that was at store index 0 landed at index 2")
            theme.reduceMotionPreference = "auto"
        }

        // A press with movement UNDER the 8px threshold is a click, not a drag:
        // no reorder, and the name-tag never appears.
        function test_subthreshold_is_click_no_reorder() {
            seed3()
            tryVerify(function () {
                var t0 = tileAtIdx(0)
                return t0 && t0.width > 0 && dragMA(0) !== null
            }, 4000, "tiles laid out with a drag MouseArea on tile 0")

            var spy = configSpy
            spy.clear()
            var before = tileIds()
            var t0 = tileAtIdx(0)
            var ma = dragMA(0)
            var px = t0.width / 2, py = t0.height / 2

            mousePress(ma, px, py)
            mouseMove(ma, px + 3, py + 3)                 // 3px — below the 8px threshold
            mouseMove(ma, px + 5, py + 2)                 // still under threshold
            // never entered a drag → name-tag must stay hidden
            compare(ld.item.dragIdx, -1, "no drag started for a sub-threshold move")
            verify(!nameTag().visible, "the name-tag never shows for a click")
            mouseRelease(ma, px + 5, py + 2)

            compare(ld.item.dragIdx, -1, "still no drag after release")
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
