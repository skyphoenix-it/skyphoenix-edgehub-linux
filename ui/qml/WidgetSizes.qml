import QtQuick

// ─────────────────────────────────────────────────────────────────────────
// WidgetSizes — the fixed set of widget sizes, and the ONLY place their
// geometry is defined.
//
// A size is NOT "width × height". It is (short, long):
//   • `short` — a fraction of the SHORT screen axis: 0.5 or 1
//   • `long`  — a count of THIRDS along the LONG screen axis: 0.5 … 3
// so `1x1` = the full short axis by one third of the long axis = 1/3 of the
// screen, and three of them fill it. That is the baseline layout.
//
// Why short/long instead of width/height: the Edge ROTATES, and main.qml swaps
// the container's width/height so the dashboard genuinely re-lays-out for the new
// aspect (it is a reflow, not a rotated picture). "Three widgets, each a third of
// the screen" must stay true in both orientations — so the three run down the
// screen in portrait and across it in landscape. Pinning the names to width/height
// would make `1x3` mean "full height" in portrait and "a 720px-tall sliver" in
// landscape. The physical axis is resolved at layout time by `halfUnits()`.
//
// A CONSEQUENCE, deliberately surfaced: the same size has a different aspect per
// orientation. `0.5x1` is tall-and-narrow in portrait and wide-and-short in
// landscape. A widget that declares a size must work as BOTH — that judgement lives
// in the widget, which is why there is no aspect helper here: a half-cell is not
// square (~348x409 portrait, ~423x306 landscape), so cell counts alone do not tell
// you how a box feels, and a helper that pretended otherwise would mislead.
//
// Everything is expressed in HALF-UNITS because 0.5 exists: the grid is 2 × 6
// half-cells (transposed in landscape), and Qt's Layout.columnSpan/rowSpan are
// integers.
// ─────────────────────────────────────────────────────────────────────────
QtObject {
    id: sizes

    // The 7 legal sizes. Adding one here is the ONLY way to add one.
    readonly property var table: ({
        "0.5x0.5": { short: 0.5, long: 0.5 },   // 1/12 of the screen
        "0.5x1":   { short: 0.5, long: 1   },   // 1/6
        "1x0.5":   { short: 1,   long: 0.5 },   // 1/6
        "1x1":     { short: 1,   long: 1   },   // 1/3  ← the baseline
        "1x1.5":   { short: 1,   long: 1.5 },   // 1/2
        "1x2":     { short: 1,   long: 2   },   // 2/3
        "1x3":     { short: 1,   long: 3   }    // the whole screen
    })

    readonly property string baseline: "1x1"

    // The grid is 2 half-cells across the short axis × 6 along the long axis.
    readonly property int shortHalves: 2
    readonly property int longHalves: 6

    function isLegal(size) { return sizes.table.hasOwnProperty(size) }

    // All legal names, ordered smallest → largest by area (so pickers and tests
    // present them predictably rather than in object-key order).
    function all() {
        var out = []
        for (var k in sizes.table) out.push(k)
        out.sort(function (a, b) {
            var d = sizes.area(a) - sizes.area(b)
            return d !== 0 ? d : (a < b ? -1 : 1)
        })
        return out
    }

    // Fraction of the screen this size covers (1x1 → 1/3). The long axis is
    // measured in thirds, hence the /3.
    function area(size) {
        var s = sizes.table[size]
        return s ? s.short * s.long / 3 : 0
    }

    // The size in GRID half-cells, resolved onto physical axes.
    //   portrait : short = width,  long = height
    //   landscape: short = height, long = width   (the screen is transposed)
    // → { w, h } in half-cells. Null for an unknown size — callers must treat that
    // as "fall back", never as 1x1, so a bad value is visible rather than silently
    // normal.
    function halfUnits(size, landscape) {
        var s = sizes.table[size]
        if (!s) return null
        var sh = Math.round(s.short * 2)
        var lo = Math.round(s.long * 2)
        return landscape ? ({ w: lo, h: sh }) : ({ w: sh, h: lo })
    }

    // Grid dimensions in half-cells for an orientation.
    function gridColumns(landscape) { return landscape ? sizes.longHalves : sizes.shortHalves }
    function gridRows(landscape)    { return landscape ? sizes.shortHalves : sizes.longHalves }

    // Does this size occupy the whole screen?
    function isFullScreen(size) { return sizes.area(size) >= 0.999 }
}
