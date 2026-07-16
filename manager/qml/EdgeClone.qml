import QtQuick

// EdgeClone — a live WYSIWYG "clone" of the Xeneon Edge. Renders the REAL widgets
// of the current page in a device frame, placed by the SAME WidgetPacker the hub
// uses, so the clone is one layout viewed twice rather than a second opinion.
// Interactions:
//   • drag a tile onto another  → reorder (commit on drop)
//   • drag the corner handle    → resize, snapping to the nearest size the widget
//                                 type actually supports
//   • ⚙ configure   ✕ remove
// All edits go through the shared store → persist + push live to a running hub.
// Resolves store/catalog/theme/media/backend from the Manager scope.
Item {
    id: clone
    property int pageIndex: 0
    // false = pure live preview (Appearance tab): the same WYSIWYG render with
    // every edit affordance (drag, resize, ⚙, ✕) hidden, so "what does this
    // setting change?" can be answered next to the setting without also
    // offering a second, competing place to edit the layout.
    property bool editable: true
    signal configRequested(string tileId, string tileType)

    WidgetSizes { id: sizes }
    WidgetPacker { id: packer }

    // Structural list → key on structureRevision, NOT revision, so a settings
    // keystroke (title/accent/…) doesn't rebuild every tile Loader (flicker/reload).
    property var tiles: {
        store.structureRevision
        var p = store.pages()[pageIndex]
        return p ? (p.tiles || []) : []
    }
    // The page's placement, in semantic space — the hub's own packing, byte for byte
    // (same packer, same input, no orientation), which is what makes this a clone.
    property var placements: {
        store.structureRevision
        return packer.pack(clone.tiles)
    }
    // The clone draws the Edge UPRIGHT (long axis vertical). The hub picks its
    // orientation from the panel sensor; the Manager runs on a desktop and has no
    // panel, so it shows the one orientation a still picture can honestly claim, and
    // the semantic packing is identical in the other one anyway.
    readonly property bool landscape: false
    // How long the device drawn here must be, in half-cells: a full screen (6), or
    // the page if it is longer. An over-long page is shown WHOLE — a taller device
    // scaled down — rather than clipped: the Manager is where you see that a page
    // runs past the screen, so hiding it here would defeat the tool.
    property int longExtent: Math.max(sizes.longHalves, packer.longExtent(clone.placements))

    // ── The tile Repeater's model ────────────────────────────────────────────
    // `placements` is a fresh JS array every time it re-packs, and a Repeater handed
    // a new array resets its whole delegate model: every tile was destroyed and
    // rebuilt for a single reorder, so there was nothing left alive to animate and
    // the replacement was simply already at the destination. That is the teleport.
    //
    // This ListModel is SYNCED to `placements` by id instead: a tile that still
    // exists keeps its row, so it keeps its delegate, so it keeps its loaded widget
    // — and its new slot arrives as a property change it can EASE to (see animS/animL
    // on the cell). Dragging a tile is exactly where a teleport reads worst, which is
    // why the clone needs this at least as much as the hub does.
    //
    // Row order carries no meaning: a cell is positioned absolutely from its own
    // (s, l) and the packer never overlaps two tiles, so rows are patched in place
    // rather than moved — the minimum churn that still expresses the edit. Nothing
    // downstream may assume row order IS tile order; see `targetAt`.
    ListModel { id: placementModel }

    // One packer placement → one model row. The string roles are coerced because a
    // ListModel FIXES each role's type on the first append: a tile reaching the clone
    // without a `type` would otherwise seed the role as `undefined`, and "" is the
    // value `wsrc`/`catalog.title`/`catalog.sizesFor` already treat as "no such type".
    //
    // The extent (the packer's es/el) is deliberately NOT a role: the cell derives its
    // extent from `effSize`, which the resize drag previews live, so a role here would
    // be a second and staler copy of `semiUnits(size)` — the identical fact.
    function _row(p) {
        return ({ tileId: p.id || "", tileType: p.type || "", tileSize: p.size || "",
                  tileIdx: p.idx, ps: p.s, pl: p.l })
    }
    // Reconciles the model to the current packing. Returns the row count — one per
    // PLACED tile — so the caller and the tests can check the sync against it.
    function _syncPlacements() {
        var ps = clone.placements || []
        var byId = Object.create(null)
        for (var i = 0; i < ps.length; i++) byId[ps[i].id] = ps[i]

        // Gone → drop the row (backwards: remove() shifts the tail).
        for (var r = placementModel.count - 1; r >= 0; r--)
            if (byId[placementModel.get(r).tileId] === undefined)
                placementModel.remove(r)

        // Survivors → patch in place. THIS is the move: same row, same delegate
        // object, new slot. set() only touches rows that actually differ, so an
        // unmoved tile is not even notified.
        var seen = Object.create(null)
        for (var r2 = 0; r2 < placementModel.count; r2++) {
            var row = placementModel.get(r2)
            var p = byId[row.tileId]
            seen[row.tileId] = true
            if (row.ps !== p.s || row.pl !== p.l || row.tileIdx !== p.idx
                || row.tileSize !== p.size || row.tileType !== p.type)
                placementModel.set(r2, clone._row(p))
        }

        // Genuinely new tiles → append. A new delegate is born at its final slot (a
        // Behavior does not fire on initial binding), so an add slides its NEIGHBOURS
        // and never itself.
        for (var k = 0; k < ps.length; k++)
            if (seen[ps[k].id] === undefined)
                placementModel.append(clone._row(ps[k]))

        return placementModel.count
    }
    // onPlacementsChanged alone is not enough: a property change signal is not
    // guaranteed for the binding's FIRST evaluation. Both paths are idempotent.
    onPlacementsChanged: clone._syncPlacements()
    Component.onCompleted: clone._syncPlacements()

    // ── Page background (mirrors Dashboard.qml so the clone is truly WYSIWYG:
    //    animated style OR wallpaper, per-page override → global default) ──
    property var pageBg: {
        store.revision
        var pages = store.pages()
        var p = (pageIndex >= 0 && pageIndex < pages.length) ? pages[pageIndex] : ({})
        var pbg = p.bg || ({})
        var a = store.appearance() || ({})
        if (pbg.wallpaper) return { wallpaper: pbg.wallpaper, style: pbg.style || a.bgStyle || "orbs" }
        if (pbg.style)     return { wallpaper: "", style: pbg.style }
        return { wallpaper: a.wallpaper || "", style: a.bgStyle || "orbs" }
    }
    // Wallpapers are stored as file:// URLs into the Manager's images dir. Re-derive
    // a properly percent-encoded URL from the basename via backend.imageUrl(name) so
    // names with spaces / non-ASCII characters load (mirrors the hub, fixes raw paths).
    property string wallpaperSource: {
        var wp = clone.pageBg.wallpaper
        if (!wp || !wp.length) return ""
        var s = String(wp)
        var name = s.substring(s.lastIndexOf("/") + 1)
        return name.length ? backend.imageUrl(name) : ""
    }
    property bool animatedBg: {
        store.revision
        var a = store.appearance() || ({})
        return a.animatedBg === undefined ? true : a.animatedBg
    }
    // effectiveReduceMotion (not the raw store flag): the theme folds in the OS
    // reduce-motion probe, so the preview stills exactly when the hub would.
    property bool reduceMotion: theme.effectiveReduceMotion

    property int tick: 0
    property var metricsObj: ({})
    Timer { interval: 1000; running: true; repeat: true; onTriggered: clone.tick++ }
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            try { clone.metricsObj = JSON.parse(backend.metricsJson() || "{}") }
            catch (e) { clone.metricsObj = ({}) }
        }
    }

    function wsrc(type) {
        var s = catalog.source(type)
        return s ? s.replace("qrc:/qml/", "qrc:/manager/") : ""
    }
    // Same derivation as Dashboard.sizeClassFor, portrait projection — the clone
    // is a portrait mirror of the panel. Without this the preview fell back to
    // WidgetChrome's height heuristic, so a 1x1 disk showed the TALL layout in
    // the Manager but the compact one on the hub: the preview lied.
    function sizeClassFor(size) {
        var u = sizes.halfUnits(size, false)
        if (!u) return "compact"
        if (u.w * u.h >= 8) return "large"
        if (u.w > u.h) return "wide"
        if (u.h > u.w) return "tall"
        return "compact"
    }

    function injectInto(item, id, type, sizeFn) {
        if (!item) return
        store.ensureSettings(id, catalog.defaults(type))
        item.instanceId = id
        item.store = store
        item.expanded = false
        // Bound, not read once: a resize PREVIEW (pvSize) must reflow the widget
        // live, exactly as committing the size would on the hub.
        if (item.hasOwnProperty("sizeClass") && sizeFn)
            item.sizeClass = Qt.binding(sizeFn)
        if (item.hasOwnProperty("active")) item.active = true
        item.metrics = Qt.binding(function () { return clone.metricsObj })
        if (item.hasOwnProperty("titleOverride"))
            item.titleOverride = Qt.binding(function () {
                store.revision; var s = store.settingsFor(id); return (s && s.title) ? s.title : ""
            })
        if (item.hasOwnProperty("accentName"))
            item.accentName = Qt.binding(function () {
                store.revision; var s = store.settingsFor(id); return (s && s.accent) ? s.accent : ""
            })
        if (item.hasOwnProperty("cardBackdrop"))
            item.cardBackdrop = Qt.binding(function () {
                store.revision; var s = store.settingsFor(id); return (s && s.cardBackdrop) ? s.cardBackdrop : "none"
            })
        if (item.hasOwnProperty("tick"))
            item.tick = Qt.binding(function () { return clone.tick })
    }

    // ── Drag-move state ──
    // These are indices into the STORE's tile array (the placement's `idx`) — the
    // thing moveTile addresses and the thing `tiles` is indexed by. They are NOT
    // Repeater row numbers: rows are patched in place by _syncPlacements, so after
    // one reorder row order is no longer tile order, and the two would silently
    // disagree. Naming them `Idx` matches the `idx` the packer and store already use.
    property int dragIdx: -1
    property int targetIdx: -1
    property real dragX: 0
    property real dragY: 0

    // The STORE tile index of the delegate under (gx, gy), in the tile container's
    // coordinates; -1 for a miss. Iterates the Repeater's own rows — the delegates
    // that actually exist — and reads each one's `tileIdx`, rather than assuming a
    // row number is a tile number. (`tiles` is one per stored tile and an unplaceable
    // one has no delegate, so counting tiles here would walk past the end.)
    function targetAt(gx, gy) {
        for (var r = 0; r < rep.count; r++) {
            var it = rep.itemAt(r)
            if (!it) continue
            if (gx >= it.x && gx <= it.x + it.width && gy >= it.y && gy <= it.y + it.height)
                return it.tileIdx
        }
        return -1
    }

    // ── Device frame — the WHOLE page, scaled to fit (no scrolling) ──
    Rectangle {
        id: frame
        anchors.centerIn: parent
        transformOrigin: Item.Center
        width: 420
        height: screen.height + 16
        // Scale the entire device so the full page is visible at once. Capped so a
        // short page doesn't upscale to blurriness.
        scale: Math.min(clone.width / width, clone.height / height, 1.6)
        radius: 26; color: "#050507"; border.width: 2; border.color: "#000000"
        Behavior on scale { NumberAnimation { duration: 150 } }

        Rectangle {
            id: screen
            anchors.centerIn: parent
            width: parent.width - 16
            // The Edge's real 2560x720 aspect, extended when the page runs longer
            // than one screen. `_deviceAspect` is what makes a cell here the same
            // SHAPE as a cell on the panel — a size's aspect is the one thing a clone
            // at a different pixel scale can still get wrong, and it is exactly what
            // the widget authors judge their `sizes` declarations against.
            readonly property real _deviceAspect: 2560 / 720
            // Cells derive from ONE SCREEN, never from the content — the same rule as
            // the hub, and the reason a 0.5x0.5 is a twelfth here too. The frame then
            // grows to whatever the page needs.
            readonly property real cellShort: width / sizes.shortHalves
            readonly property real cellLong: (width * _deviceAspect) / sizes.longHalves
            height: cellLong * clone.longExtent
            radius: 20; clip: true
            gradient: Gradient {
                GradientStop { position: 0.0; color: theme.backgroundColor }
                GradientStop { position: 0.55; color: theme.backgroundColor2 }
                GradientStop { position: 1.0; color: theme.backgroundColor3 }
            }

            // Animated backdrop (orbs / waves / stars / …) — shown when no wallpaper
            // is set, mirroring the hub so the "Animated background" toggle + style
            // choice preview live. Declared before the grid so it sits underneath.
            BackdropLayer {
                anchors.fill: parent
                visible: clone.wallpaperSource === "" && theme.decorative
                style: clone.pageBg.style
                accent: theme.accent
                running: clone.animatedBg && !clone.reduceMotion
            }
            Image {
                id: cloneWall
                anchors.fill: parent
                source: clone.wallpaperSource
                visible: source != ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; cache: true
            }
            Rectangle {
                anchors.fill: parent; visible: cloneWall.visible
                color: Qt.rgba(theme.backgroundColor.r, theme.backgroundColor.g, theme.backgroundColor.b, 0.28)
            }

            Item {
                id: grid
                anchors.fill: parent

                    Repeater {
                        id: rep
                        model: placementModel
                        delegate: Item {
                            id: tile
                            // The placement's roles. `tileIdx` — NOT the Repeater's row
                            // number — is what every store call here addresses.
                            required property string tileId
                            required property string tileType
                            required property string tileSize
                            required property int tileIdx
                            required property int ps
                            required property int pl
                            // Live preview during a resize drag: the size the drag has
                            // snapped to, "" when not dragging. Only the dragged tile's
                            // own box previews — the page re-packs on commit, because a
                            // repack per mouse-move would shuffle the neighbours under
                            // the cursor the drag is aimed at.
                            property string pvSize: ""
                            readonly property string effSize: tile.pvSize !== "" ? tile.pvSize : tile.tileSize

                            // ── The move ──────────────────────────────────────
                            // The eased mirror of the semantic ORIGIN. Easing the SLOT
                            // rather than x/y keeps the ease attached to the one thing
                            // that means "this tile moved", so a structure edit glides
                            // and nothing else has to opt out. No flag, no settling
                            // timer — the distinction is structural, so it cannot drift.
                            //
                            // The hub eases the EXTENT here too, and separates the ease
                            // from ROTATION that way (a turn re-projects the slot, so it
                            // stays instant). Neither half of that carries over:
                            //   • the clone is always upright (`landscape: false`) and
                            //     the cell grid is a CONSTANT — the frame is a fixed 420
                            //     wide and fits to view by scaling as a whole, so
                            //     cellShort/cellLong never change. There is no
                            //     projection change to keep instant.
                            //   • the thing that must stay instant here is the resize
                            //     PREVIEW. A reorder never changes an extent; only a
                            //     resize does, and here a resize is a live corner DRAG
                            //     (on the hub it is a discrete button). The previewed box
                            //     has to sit under the cursor, so easing the extent would
                            //     put the tile 250ms behind the hand sizing it.
                            // So the extent stays direct, and no animation can fight a
                            // drag: a move drag re-packs nothing until the drop (by which
                            // point dragIdx is already cleared, so the tile glides home at
                            // full opacity), and a resize drag never moves an origin.
                            //
                            // REDUCE MOTION: the duration token does the real work —
                            // motionPage is 0, and a 0ms Behavior lands its end value
                            // synchronously on write. The `enabled` gate is the explicit
                            // statement of intent, and skips building an animation per
                            // tile per edit for a value that cannot move — it is not the
                            // mechanism. Smooth is not more motion.
                            property real animS: tile.ps
                            property real animL: tile.pl
                            Behavior on animS { enabled: theme.motionPage > 0
                                NumberAnimation { duration: theme.motionPage; easing.type: Easing.OutCubic } }
                            Behavior on animL { enabled: theme.motionPage > 0
                                NumberAnimation { duration: theme.motionPage; easing.type: Easing.OutCubic } }

                            // The (eased) origin, re-extended to whatever the drag is
                            // previewing. The ORIGIN stays put during a preview (only a
                            // commit re-packs), so this is the placement with a swapped
                            // extent. `semiUnits(size)` IS the packer's (es, el) — the
                            // same derivation, evaluated on the previewed size.
                            readonly property var _u: sizes.semiUnits(tile.effSize)
                            readonly property var _r: packer.rect(
                                { s: tile.animS, l: tile.animL, es: _u.s, el: _u.l },
                                clone.landscape, screen.cellShort, screen.cellLong, 10)
                            x: _r.x; y: _r.y
                            width: _r.width; height: _r.height
                            opacity: clone.dragIdx === tile.tileIdx ? 0.3 : 1.0

                            Rectangle {   // placeholder / loading
                                anchors.fill: parent; radius: theme.radiusLg
                                color: theme.cardFill(); border.width: 1; border.color: theme.cardBorder
                                visible: wl.status !== Loader.Ready
                                Column {
                                    anchors.centerIn: parent; spacing: 6
                                    AppIcon { anchors.horizontalCenter: parent.horizontalCenter
                                        name: tile.tileType; size: 28; color: theme.textSecondary }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter
                                        text: catalog.title(tile.tileType); color: theme.textSecondary; font.pixelSize: 12 }
                                }
                            }
                            Loader {
                                id: wl
                                anchors.fill: parent
                                property string wId: tile.tileId
                                source: clone.wsrc(tile.tileType)
                                onLoaded: clone.injectInto(item, tile.tileId, tile.tileType,
                                                           function () { return clone.sizeClassFor(tile.effSize) })
                            }

                            // Drop-target highlight.
                            Rectangle {
                                anchors.fill: parent; radius: theme.radiusLg
                                color: "transparent"; border.width: 3; border.color: theme.accent
                                visible: clone.dragIdx >= 0 && clone.targetIdx === tile.tileIdx
                                         && clone.dragIdx !== tile.tileIdx
                            }

                            // Drag / select overlay.
                            MouseArea {
                                id: ma
                                visible: clone.editable
                                anchors.fill: parent
                                anchors.rightMargin: 26; anchors.bottomMargin: 26   // leave the corner handle
                                cursorShape: clone.dragIdx === tile.tileIdx ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                preventStealing: true
                                property real sx: 0; property real sy: 0
                                property bool dragging: false
                                onPressed: (mouse) => { ma.sx = mouse.x; ma.sy = mouse.y; ma.dragging = false }
                                onPositionChanged: (mouse) => {
                                    if (!ma.dragging && (Math.abs(mouse.x - ma.sx) > 8 || Math.abs(mouse.y - ma.sy) > 8)) {
                                        ma.dragging = true; clone.dragIdx = tile.tileIdx
                                    }
                                    if (ma.dragging) {
                                        var g = tile.mapToItem(grid, mouse.x, mouse.y)
                                        var c = tile.mapToItem(clone, mouse.x, mouse.y)
                                        clone.dragX = c.x; clone.dragY = c.y
                                        clone.targetIdx = clone.targetAt(g.x, g.y)
                                    }
                                }
                                onReleased: {
                                    if (ma.dragging) {
                                        // Both are STORE tile indices — targetAt reports the
                                        // hit delegate's own `tileIdx` — so they address
                                        // moveTile directly. There is no longer a placement
                                        // array to index through, which is what kept this
                                        // correct only for as long as row order happened to
                                        // equal tile order.
                                        var to = clone.targetIdx
                                        var from = tile.tileIdx
                                        // Clear the drag state (which hides the floating
                                        // name-tag) BEFORE moveTile: a reset placed after it
                                        // may never execute if this handler's delegate dies,
                                        // leaving the name-tag stuck in air. The delegate now
                                        // SURVIVES a reorder, so this is belt-and-braces —
                                        // but it is also what lets the dragged tile glide
                                        // home at full opacity instead of being animated
                                        // while still visibly held.
                                        ma.dragging = false
                                        clone.dragIdx = -1; clone.targetIdx = -1
                                        if (to >= 0 && to !== from)
                                            store.moveTile(clone.pageIndex, from, to)
                                    } else {
                                        clone.configRequested(tile.tileId, tile.tileType)
                                    }
                                }
                            }

                            // Top-right controls.
                            Row {
                                visible: clone.editable
                                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 8
                                spacing: 6; z: 5
                                Rectangle {
                                    width: 32; height: 32; radius: 16; color: Qt.rgba(0, 0, 0, 0.55)
                                    AppIcon { anchors.centerIn: parent; name: "ui-settings"; color: "#fff"; size: 16 }
                                    MouseArea { anchors.fill: parent
                                        onClicked: clone.configRequested(tile.tileId, tile.tileType) }
                                }
                                Rectangle {
                                    width: 32; height: 32; radius: 16
                                    color: Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.7)
                                    AppIcon { anchors.centerIn: parent; name: "ui-close"; color: "#fff"; size: 15 }
                                    MouseArea { anchors.fill: parent
                                        onClicked: store.removeTile(clone.pageIndex, tile.tileId) }
                                }
                            }

                            // Corner resize handle. The drag is free-form but the sizes
                            // are not: the dragged box is SNAPPED to the nearest size the
                            // widget type actually declares, so an illegal shape is never
                            // offered rather than being offered and then corrected. There
                            // is deliberately no fixed pixel "flip threshold" any more —
                            // the old one hard-coded a 180px row height, which is not a
                            // thing the size model has. Previews live; commits on release.
                            Rectangle {
                                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 5
                                width: 24; height: 24; radius: 7; z: 6
                                visible: clone.editable && catalog.sizesFor(tile.tileType).length > 1
                                color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.75)
                                AppIcon { anchors.centerIn: parent; name: "ui-resize"; color: "#0D1117"; size: 15 }
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -8
                                    cursorShape: Qt.SizeFDiagCursor
                                    preventStealing: true
                                    property real sx: 0; property real sy: 0
                                    // Work in the UNSCALED content ("screen") space so the drag
                                    // distance needed to reach a size matches the visible tile
                                    // edge regardless of the device frame's fit-to-view scale.
                                    onPressed: (mp) => {
                                        var c = mapToItem(screen, mp.x, mp.y)
                                        sx = c.x; sy = c.y
                                        tile.pvSize = tile.tileSize
                                    }
                                    onPositionChanged: (mp) => {
                                        var c = mapToItem(screen, mp.x, mp.y)
                                        // The box the cursor is describing, resolved onto the
                                        // SEMANTIC axes — so this reads identically whichever
                                        // way the device is turned.
                                        var pxW = tile.width + (c.x - sx), pxH = tile.height + (c.y - sy)
                                        var pxShort = clone.landscape ? pxH : pxW
                                        var pxLong = clone.landscape ? pxW : pxH
                                        var snapped = packer.snap(catalog.sizesFor(tile.tileType),
                                                                  pxShort, pxLong,
                                                                  screen.cellShort, screen.cellLong)
                                        if (snapped !== "") tile.pvSize = snapped
                                    }
                                    onReleased: {
                                        var next = tile.pvSize
                                        tile.pvSize = ""
                                        // setTileSize is the gate, not this handler: `snap`
                                        // only ever proposes a supported size, and the store
                                        // still refuses anything else.
                                        if (next !== "") store.setTileSize(clone.pageIndex, tile.tileId, next)
                                    }
                                }
                            }
                        }
                    }
                }

            Text {
                anchors.centerIn: parent
                visible: clone.tiles.length === 0
                text: "This page is empty.\nUse “Add widget”."
                horizontalAlignment: Text.AlignHCenter
                color: theme.textTertiary; font.pixelSize: 15
            }
        }
    }

    // Floating drag ghost — tracks the cursor (both axes) and stays on-screen.
    // `dragIdx` indexes `tiles` directly and correctly: it is the store tile index,
    // which is exactly what `tiles` is ordered by. (It used to be a placement/row
    // number that indexed `tiles` anyway, and agreed only while no tile was ever
    // skipped by the packer.)
    Rectangle {
        id: dragGhost
        visible: clone.dragIdx >= 0 && clone.dragIdx < clone.tiles.length
        width: 210; height: 46; radius: 12; z: 100
        x: Math.max(6, Math.min(clone.width - width - 6, clone.dragX + 18))
        y: Math.max(6, Math.min(clone.height - height - 6, clone.dragY - height / 2))
        color: theme.cardBackgroundAlt; border.width: 1; border.color: theme.accent
        Row {
            anchors.centerIn: parent; spacing: 10
            AppIcon { anchors.verticalCenter: parent.verticalCenter; size: 22; color: theme.textPrimary
                name: clone.dragIdx >= 0 && clone.dragIdx < clone.tiles.length
                      ? clone.tiles[clone.dragIdx].type : "" }
            Text { text: clone.dragIdx >= 0 && clone.dragIdx < clone.tiles.length
                ? catalog.title(clone.tiles[clone.dragIdx].type) : ""
                color: theme.textPrimary; font.pixelSize: 15 }
        }
    }
}
