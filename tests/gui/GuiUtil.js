// Shared helpers for the visible GUI test suite (tests/gui/). Pure JS - no
// grabImage here (that is a TestCase method; call it in the test and pass the
// result to snap()). These walk the live scene graph of a REAL rendered window.

// Walk every node under `node` exactly ONCE, calling fn(n). Return true from fn
// to stop the walk early.
//
// The visited-set is not an optimisation, it is a correctness requirement. A
// node is reachable through BOTH `children` and `data` (and via sibling
// subtrees that share a control's contentItem/background), so without memoing
// we re-walk the same subtree once per distinct path. On the real Manager tree
// that is 1,701 unique nodes but >2,000,000 visits - the blow-up that drove
// qmltestrunner to 18.8 GB RSS and tripped the kernel OOM killer (2026-07-19).
// Keep the seen-set. Do not "simplify" it away.
function eachItem(node, fn) {
    _walk(node, fn, new Set())
}

function _walk(node, fn, seen) {
    if (!node || seen.has(node)) return false
    seen.add(node)
    if (fn(node) === true) return true
    var kids = node.children
    if (kids) for (var i = 0; i < kids.length; i++)
        if (_walk(kids[i], fn, seen)) return true
    // Also walk `data` to catch non-visual children (Dialogs, ListModels,
    // Repeater-created popups) that aren't in `children` - the Manager keeps
    // dialogs and its imagesModel there. `seen` handles the children/data
    // overlap, so no indexOf filtering is needed here.
    var d = node.data
    if (d && d !== kids) for (var j = 0; j < d.length; j++)
        if (_walk(d[j], fn, seen)) return true
    // QQC2 Control/Popup content axes. A Dialog's visible content is NOT in its
    // `children` or `data` - it hangs off the `contentItem`/`header`/`footer`
    // PROPERTIES, and for a Popup the item is reparented into the window
    // overlay. Without these, searching from a Dialog object finds the dialog
    // and nothing inside it, which is why 20 dialog assertions failed while
    // `d.opened` passed on the line right above them.
    //
    // Descending extra axes is only safe BECAUSE of the `seen` set above: these
    // overlap heavily with `children` (a Control's contentItem is usually also
    // one of its children), and that overlap is precisely what made the
    // unmemoised walk exponential. Do not add axes without the seen-set.
    var extra = [node.contentItem, node.header, node.footer]
    for (var k = 0; k < extra.length; k++)
        if (extra[k] && _walk(extra[k], fn, seen)) return true
    return false
}

// Visit accounting, so a regression test can prove the traversal stays linear.
// `calls`  - how many times eachItem invoked the callback.
// `unique` - how many distinct nodes are actually reachable.
// The invariant that must hold is calls === unique. The pre-fix walk reported
// calls >> unique (exponential in depth); that is the OOM regression.
function walkStats(node) {
    var calls = 0
    var seen = new Set()
    eachItem(node, function (n) { calls++; seen.add(n) })
    return { calls: calls, unique: seen.size }
}

function findPred(node, pred) {
    var found = null
    eachItem(node, function (n) { if (pred(n)) { found = n; return true } })
    return found
}

function collectPred(node, pred) {
    var out = []
    eachItem(node, function (n) { if (pred(n)) out.push(n) })
    return out
}

function byObjName(node, name) {
    return findPred(node, function (n) { return n && n.objectName === name })
}

function allByObjName(node, name) {
    return collectPred(node, function (n) { return n && n.objectName === name })
}

function byProp(node, prop) {
    return findPred(node, function (n) { try { return n && n[prop] !== undefined } catch (e) { return false } })
}

function allByProp(node, prop) {
    return collectPred(node, function (n) { try { return n && n[prop] !== undefined } catch (e) { return false } })
}

// First visible Text whose text contains `sub` (case-insensitive).
function byText(node, sub) {
    var s = ("" + sub).toLowerCase()
    return findPred(node, function (n) {
        try { return n && n.text !== undefined && ("" + n.text).toLowerCase().indexOf(s) >= 0 && n.visible }
        catch (e) { return false }
    })
}

// A MouseArea/Control that is actually hittable (visible, sized, enabled).
function isLive(n) {
    try { return n && n.visible && n.width > 0 && n.height > 0 && (n.enabled === undefined || n.enabled) }
    catch (e) { return false }
}

// Type test for a MouseArea (its toString is "QQuickMouseArea..." / "MouseArea_QMLTYPE..").
function isMouseArea(n) {
    try { return n && ("" + n).indexOf("MouseArea") >= 0 } catch (e) { return false }
}

// Anything a real click lands on: a MouseArea, an AbstractButton, or a control
// exposing a `clicked` signal. Combine with isLive() before clicking.
function isClickable(n) {
    try {
        if (!n) return false
        if (isMouseArea(n)) return true
        return n.width !== undefined && n.clicked !== undefined
    } catch (e) { return false }
}

// Live clickable targets under a node (visible, sized, clickable), in tree order.
function liveClickables(node) {
    return collectPred(node, function (n) { return isClickable(n) && isLive(n) })
}

// True if a grabImage result looks non-blank: samples a grid and requires that
// not every sample equals the corner (background) colour.
function looksRendered(img) {
    if (!img || img.width < 2 || img.height < 2) return false
    var bg = "" + img.pixel(1, 1)
    var w = img.width, h = img.height, diff = 0
    for (var yi = 1; yi < 5; yi++) for (var xi = 1; xi < 5; xi++) {
        var px = Math.floor(w * xi / 5), py = Math.floor(h * yi / 5)
        if (("" + img.pixel(px, py)) !== bg) diff++
    }
    return diff > 0
}

// ─────────────────────────────────────────────────────────────────────────
// grabItem - a POSITION-AWARE replacement for TestCase.grabImage(item).
//
// READ THIS BEFORE USING grabImage(item) ANYWHERE IN THIS SUITE.
//
// Qt's `TestCase.grabImage(item)` grabs the whole WINDOW and then crops to a
// rect at (0,0) sized to the item - it never maps the item's POSITION. So for
// any item that is not at the window origin it returns the wrong pixels: the
// top-left corner of the window, at that item's dimensions.
//
// Measured on the Manager (2026-07-20): the Look tab's preview clone sits at
// x=264, so `grabImage(lookClone())` returned the nav sidebar. The sidebar does
// not change when the Edge theme changes, so `maxChDist(before, after)` was
// exactly 0 and all 20 rows of `test_D6_free_theme_applies` failed - reporting
// a product bug ("preview backdrop repainted") that did not exist. Sampling the
// same clone through this helper gives a distance of 404.75. The preview had
// been repainting correctly the whole time.
//
// This also explains the suite's damage distribution: the `tst_gui_w_*` widget
// files host their harness at the window origin, so the broken crop happens to
// be correct there and they pass. Manager and shell tests target offset items,
// and that is exactly where the failures concentrated.
//
// The returned object mimics the QtTest image API used by this suite
// (width/height/red/green/blue/pixel/save), so it is a drop-in swap.
//
// `save()` writes the FULL window frame, not the crop - QtTest image objects
// cannot be cropped. That is deliberate: the evidence PNG showing the whole
// window with the item in context is more useful than a lie about the API.
//
// Usage, from inside a TestCase:
//     var img = G.grabItem(this, someItem, win.contentItem)
function grabItem(tc, item, rootItem) {
    var img = tc.grabImage(rootItem)          // rootItem is at (0,0) → crop is correct
    var p = item.mapToItem(rootItem, 0, 0)
    var ox = Math.round(p.x), oy = Math.round(p.y)
    return {
        width: Math.round(item.width),
        height: Math.round(item.height),
        _img: img, _ox: ox, _oy: oy,
        red:   function (x, y) { return img.red(ox + x, oy + y) },
        green: function (x, y) { return img.green(ox + x, oy + y) },
        blue:  function (x, y) { return img.blue(ox + x, oy + y) },
        alpha: function (x, y) { return img.alpha(ox + x, oy + y) },
        pixel: function (x, y) { return img.pixel(ox + x, oy + y) },
        save:  function (f) { return img.save(f) }
    }
}

// Max per-pixel channel distance between two grabs over a sampled grid.
// Both must be the same logical size (two grabs of the SAME item).
function maxChDist(a, b) {
    var w = Math.min(a.width, b.width), h = Math.min(a.height, b.height), mx = 0
    for (var yi = 1; yi < 6; yi++) for (var xi = 1; xi < 6; xi++) {
        var x = Math.floor(w * xi / 6), y = Math.floor(h * yi / 6)
        var dr = a.red(x, y) - b.red(x, y)
        var dg = a.green(x, y) - b.green(x, y)
        var db = a.blue(x, y) - b.blue(x, y)
        var d = Math.sqrt(dr * dr + dg * dg + db * db)
        if (d > mx) mx = d
    }
    return mx
}

// Distance between two "#rrggbb" colour strings (0..~441).
function colorDist(a, b) {
    function ch(s, i) { return parseInt(("" + s).substr(1 + i * 2, 2), 16) || 0 }
    var dr = ch(a, 0) - ch(b, 0), dg = ch(a, 1) - ch(b, 1), db = ch(a, 2) - ch(b, 2)
    return Math.sqrt(dr * dr + dg * dg + db * db)
}
