import QtQuick

// ─────────────────────────────────────────────────────────────────────────
// WidgetPacker - decides WHERE a page's tiles sit. The one placement authority,
// shared by the hub's Dashboard and the Manager's EdgeClone so the clone is
// genuinely WYSIWYG rather than a second opinion.
//
// It replaced GridLayout, which cannot express the size model at all. Measured:
// three `1x1` tiles on a 1200px page render at exactly 400px each (correct - which
// is why nothing looks broken today), but a `0.5x0.5` beside a `1x1` renders at
// 600px - half the screen, when it must be a twelfth (200px). GridLayout sizes a
// row by what is IN it and collapses empty/span-only rows, so a tile's size depends
// on what else is on the page. A size is a fraction of the SCREEN, so it may not.
// (`uniformCellHeights` does not fix it.) Here the cell grid is derived from the
// screen and nothing else, and tiles are positioned absolutely into it.
//
// PACKING HAPPENS IN SEMANTIC (short, long) SPACE - never physical. Orientation is
// not an input to `pack`; it enters only in `project`/`rect`, as a pure projection.
// Measured on an exhaustive sweep: packing in physical coordinates scrambles 99.2%
// of 5-tile pages when the panel rotates (the grid transposes 2x6 -> 6x2, so a
// re-pack lands somewhere else and a tile teleports across the screen because the
// panel turned). Packing semantically scrambles 0% - there is exactly ONE packing
// and the dashboard turns WITH the panel. See WidgetSizes.semiUnits.
//
// The algorithm is FIRST FIT: scan long-major from the origin, take the first slot
// that fits. It is deterministic (same tiles in, same placement out - no
// orientation, no randomness, no dependence on the previous packing) and it is
// never worse than today's append-only GridLayout, because "the first slot that
// fits" is by construction at or before "the next free slot at the end". Its value
// is backfill: a `0.5`-wide tile leaves half a row free, and first fit puts the
// next small tile THERE instead of starting a new row. All 15 shipped presets are
// full-width, so it produces 0 holes on every one of them today - it is insurance
// that arrives with the half-width sizes rather than a change to what ships.
// ─────────────────────────────────────────────────────────────────────────
QtObject {
    id: packer

    property QtObject sizes: WidgetSizes {}

    // ── The occupancy grid ───────────────────────────────────────────────────
    // { cols: <short halves>, rows: [ [cell, …], … ] } - `cols` is the SHORT axis
    // (always 2), and rows run along the LONG axis and are UNBOUNDED. The 6 long
    // halves in WidgetSizes size the SCREEN; they do not cap the page. See
    // Dashboard.qml for why a longer page scrolls rather than being refused.
    function _grid() { return ({ cols: packer.sizes.shortHalves, rows: [] }) }

    // Is the es × el box at (s, l) free? A PROBE - it must never grow the grid,
    // because first fit calls it past the end while scanning for a slot; rows that
    // do not exist yet are simply empty.
    function _free(grid, s, l, es, el) {
        for (var j = l; j < l + el; j++) {
            var row = grid.rows[j]
            if (!row) continue
            for (var i = s; i < s + es; i++)
                if (row[i] !== null && row[i] !== undefined) return false
        }
        return true
    }

    function _fill(grid, s, l, es, el, id) {
        while (grid.rows.length < l + el) {
            var fresh = []
            for (var c = 0; c < grid.cols; c++) fresh.push(null)
            grid.rows.push(fresh)
        }
        for (var j = l; j < l + el; j++)
            for (var i = s; i < s + es; i++) grid.rows[j][i] = id
    }

    // The first free es × el slot, scanning long-major from the origin. TOTAL by
    // construction: if nothing fits among the rows already in use, the space past
    // them is empty, so appending there always fits - no runaway guard needed.
    function _firstFit(grid, es, el) {
        var end = grid.rows.length
        for (var l = 0; l < end; l++)
            for (var s = 0; s + es <= grid.cols; s++)
                if (packer._free(grid, s, l, es, el)) return ({ s: s, l: l })
        return ({ s: 0, l: end })
    }

    // Place a page's tiles. Input: the store's tile objects ({ id, type, size, … }).
    // Output: one placement per PLACEABLE tile, in tile order -
    //   { id, type, size, idx, s, l, es, el }
    // where (s, l) is the origin and (es, el) the extent, all in SEMANTIC half-cells,
    // and `idx` is the tile's index in the source array (the store's tile ORDER is
    // what moveTile/removeTile address, and packing order is not it).
    //
    // A tile whose size is unknown is SKIPPED, not defaulted: `semiUnits` returns
    // null precisely so a bad value stays visible. In practice the store gives every
    // tile a legal, type-supported size before it reaches `data`, so this is the
    // boundary being defensive, not an expected path.
    function pack(tiles) {
        var list = tiles || []
        var grid = packer._grid()
        var out = []
        for (var i = 0; i < list.length; i++) {
            var t = list[i]
            var u = t ? packer.sizes.semiUnits(t.size) : null
            if (!u) continue
            var p = packer._firstFit(grid, u.s, u.l)
            packer._fill(grid, p.s, p.l, u.s, u.l, t.id)
            out.push({ id: t.id, type: t.type, size: t.size, idx: i,
                       s: p.s, l: p.l, es: u.s, el: u.l })
        }
        return out
    }

    // How far the packing reaches along the long axis, in half-cells. 6 fills the
    // screen exactly; more than 6 means the page is longer than the display.
    function longExtent(placements) {
        var ps = placements || []
        var max = 0
        for (var i = 0; i < ps.length; i++) max = Math.max(max, ps[i].l + ps[i].el)
        return max
    }

    // A placement PROJECTED onto physical axes - { x, y, w, h } in half-cells.
    // Mirrors WidgetSizes.halfUnits for the extent and applies the SAME projection
    // to the origin, which is the whole reason a rotation cannot reshuffle a page:
    //   portrait : short = x, long = y
    //   landscape: short = y, long = x   (the screen is transposed)
    function project(p, landscape) {
        return landscape ? ({ x: p.l, y: p.s, w: p.el, h: p.es })
                         : ({ x: p.s, y: p.l, w: p.es, h: p.el })
    }

    // The placement's pixel rect, given the cell size along each SEMANTIC axis.
    // `gap` is inset out of the tile (gap/2 per edge) rather than added between
    // cells: the cell grid must stay exactly screen/(2 x 6) whatever the gap is, so
    // the gap comes out of the tile and never out of the geometry. Neighbours
    // therefore sit a full gap apart and the page edge gets half of one.
    function rect(p, landscape, cellShort, cellLong, gap) {
        var u = packer.project(p, landscape)
        var pxX = landscape ? cellLong : cellShort
        var pxY = landscape ? cellShort : cellLong
        var g = (gap || 0) / 2
        return ({ x: u.x * pxX + g, y: u.y * pxY + g,
                  width: u.w * pxX - 2 * g, height: u.h * pxY - 2 * g })
    }

    // The size a pixel box means, restricted to what the TYPE actually supports.
    // Used by the Manager's corner drag: a free-form drag has to land on one of the
    // seven names, and it must never land on a shape the widget was never built to
    // render - so an illegal size is not corrected afterwards, it is never offered.
    // Distance is measured in the SEMANTIC axes, so the drag behaves identically
    // however the panel is turned. Ties keep the SMALLER size: `sizesFor` is ordered
    // smallest-first and the scan is a strict `<`, so a drag that lands exactly
    // between two sizes does not silently claim more of the screen. Returns "" when
    // the type supports nothing (an unknown type) - callers must then not resize.
    function snap(legalSizes, pxShort, pxLong, cellShort, cellLong) {
        var legal = legalSizes || []
        var best = "", bestD = Infinity
        for (var i = 0; i < legal.length; i++) {
            var u = packer.sizes.semiUnits(legal[i])
            if (!u) continue
            var d = Math.abs(u.s * cellShort - pxShort) + Math.abs(u.l * cellLong - pxLong)
            if (d < bestD) { bestD = d; best = legal[i] }
        }
        return best
    }
}
