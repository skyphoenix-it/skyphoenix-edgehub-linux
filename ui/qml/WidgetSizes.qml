import QtQuick

// ─────────────────────────────────────────────────────────────────────────
// WidgetSizes - the fixed set of widget sizes, and the ONLY place their
// geometry is defined.
//
// A size is NOT "width × height". It is (short, long):
//   • `short` - a fraction of the SHORT screen axis: 0.5 or 1
//   • `long`  - a count of THIRDS along the LONG screen axis: 0.5 … 3
// so `1x1` = the full short axis by one third of the long axis = 1/3 of the
// screen, and three of them fill it. That is the baseline layout.
//
// Why short/long instead of width/height: the Edge ROTATES, and main.qml swaps
// the container's width/height so the dashboard genuinely re-lays-out for the new
// aspect (it is a reflow, not a rotated picture). "Three widgets, each a third of
// the screen" must stay true in both orientations - so the three run down the
// screen in portrait and across it in landscape. Pinning the names to width/height
// would make `1x3` mean "full height" in portrait and "a 720px-tall sliver" in
// landscape. The physical axis is resolved at layout time by `halfUnits()`.
//
// A CONSEQUENCE, deliberately surfaced: the same size has a different aspect per
// orientation. `0.5x1` is tall-and-narrow in portrait and wide-and-short in
// landscape. A widget that declares a size must work as BOTH - that judgement lives
// in the widget.
//
// There is deliberately no ASPECT helper here - a half-cell is not square
// (~348x409 portrait, ~423x306 landscape), so cell counts cannot tell you a box's
// true proportions, and a helper that pretended otherwise would mislead. What does
// live here is `classFor()`, which is a coarser question ("roughly how much room,
// and which way does it run?") that cell counts CAN answer honestly. It is here
// because both renderers need the same answer - see its own comment.
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

    // The size in SEMANTIC half-units - { s, l } on the short and long axes, with
    // NO physical orientation. This is the space LAYOUT AND PACKING MUST WORK IN.
    //
    // It is not a convenience: pack in physical coordinates and rotating the panel
    // re-packs into a *different* layout, because the grid transposes 2x6 -> 6x2.
    // Measured on an exhaustive sweep of every legal page: 99.2% of 5-tile pages
    // scramble that way - a tile teleports across the screen because the panel
    // turned. Pack in semantic space and orientation is not an input, so there is
    // exactly ONE packing and rotation becomes a pure projection: the dashboard
    // turns WITH the panel instead of reshuffling under the user.
    // (This applies to persisted coordinates too - storing physical {x,y} would
    // scramble identically. The lesson is the coordinate space, not the mechanism.)
    function semiUnits(size) {
        var s = sizes.table[size]
        if (!s) return null
        return ({ s: Math.round(s.short * 2), l: Math.round(s.long * 2) })
    }

    // The same size PROJECTED onto physical axes, for rendering only.
    //   portrait : short = width,  long = height
    //   landscape: short = height, long = width   (the screen is transposed)
    // → { w, h } in half-cells. Null for an unknown size - callers must treat that
    // as "fall back", never as 1x1, so a bad value is visible rather than silently
    // normal.
    function halfUnits(size, landscape) {
        var u = sizes.semiUnits(size)
        if (!u) return null
        return landscape ? ({ w: u.l, h: u.s }) : ({ w: u.s, h: u.l })
    }

    // The SIZE CLASS - how much room a widget has and which way it runs, as one of
    // "compact" | "wide" | "tall" | "large". A widget reads this to choose a layout
    // variant (a disk vs a row, a label vs a full readout); it is the vocabulary
    // that lets a widget adapt without knowing pixel dimensions it shouldn't know
    // about.
    //
    // It is judged on the PROJECTED half-cells, so it answers about the shape the
    // widget will actually be handed: a half-cell is roughly square, so counting
    // them is a fair proxy for shape, and the same size honestly reports "tall" in
    // portrait and "wide" in landscape - which is the point of a rotating panel.
    //
    // "large" means the sizes with room to spare: two thirds of the screen or more
    // (>= 8 of the 12 half-cells), i.e. `1x2` and `1x3`. (It was coined for the old
    // span grid, where it meant "doubled on BOTH axes"; the size model has no such
    // shape - the short axis stops at 1 - so under the old rule it would have become
    // unreachable.)
    //
    // WHY IT LIVES HERE, and must stay here: this is the one derivation the hub and
    // the Manager's preview must agree on, and it is the ONLY file both of them
    // instantiate (`manager.qrc` aliases this very file). It used to be copy-pasted
    // into `EdgeClone.qml` with `landscape` hardcoded to false, so in landscape the
    // hub rendered a tile `wide` and the Manager rendered the same tile `tall` - a
    // different layout variant at a different information density. That is the
    // WYSIWYG preview lying about what the hub will show, and it survived because
    // the clone's test compared against a string literal instead of against the
    // hub. Do not re-copy this function; call it, and pass a REAL orientation.
    function classFor(size, landscape) {
        var u = sizes.halfUnits(size, landscape)
        if (!u) return "compact"                      // unknown size → assume the least room
        if (u.w * u.h >= 8) return "large"
        if (u.w > u.h) return "wide"
        if (u.h > u.w) return "tall"
        return "compact"
    }

    // Grid dimensions in half-cells for an orientation.
    function gridColumns(landscape) { return landscape ? sizes.longHalves : sizes.shortHalves }
    function gridRows(landscape)    { return landscape ? sizes.shortHalves : sizes.longHalves }

    // Does this size occupy the whole screen?
    function isFullScreen(size) { return sizes.area(size) >= 0.999 }
}
