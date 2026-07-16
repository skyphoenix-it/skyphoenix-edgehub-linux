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
    function injectInto(item, id, type) {
        if (!item) return
        store.ensureSettings(id, catalog.defaults(type))
        item.instanceId = id
        item.store = store
        item.expanded = false
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
    property int dragIndex: -1
    property int targetIndex: -1
    property real dragX: 0
    property real dragY: 0

    // Which delegate is under (gx, gy), in the tile container's coordinates.
    // Iterates `placements` — the Repeater's ACTUAL model. `tiles` is one per stored
    // tile, and an unplaceable one has no delegate, so counting tiles here would walk
    // past the end of the Repeater.
    function targetAt(gx, gy) {
        for (var i = 0; i < placements.length; i++) {
            var it = rep.itemAt(i)
            if (!it) continue
            if (gx >= it.x && gx <= it.x + it.width && gy >= it.y && gy <= it.y + it.height)
                return i
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
                        model: clone.placements
                        delegate: Item {
                            id: tile
                            required property int index
                            required property var modelData   // a WidgetPacker placement
                            // Live preview during a resize drag: the size the drag has
                            // snapped to, "" when not dragging. Only the dragged tile's
                            // own box previews — the page re-packs on commit, because a
                            // repack per mouse-move would shuffle the neighbours under
                            // the cursor the drag is aimed at.
                            property string pvSize: ""
                            readonly property string effSize: tile.pvSize !== "" ? tile.pvSize : tile.modelData.size
                            // The packed slot, re-extended to whatever the drag is
                            // previewing. The ORIGIN stays put (only a commit re-packs),
                            // so this is the placement with a swapped extent.
                            readonly property var _u: sizes.semiUnits(tile.effSize)
                            readonly property var _r: packer.rect(
                                { s: modelData.s, l: modelData.l, es: _u.s, el: _u.l },
                                clone.landscape, screen.cellShort, screen.cellLong, 10)
                            x: _r.x; y: _r.y
                            width: _r.width; height: _r.height
                            opacity: clone.dragIndex === tile.index ? 0.3 : 1.0

                            Rectangle {   // placeholder / loading
                                anchors.fill: parent; radius: theme.radiusLg
                                color: theme.cardFill(); border.width: 1; border.color: theme.cardBorder
                                visible: wl.status !== Loader.Ready
                                Column {
                                    anchors.centerIn: parent; spacing: 6
                                    AppIcon { anchors.horizontalCenter: parent.horizontalCenter
                                        name: tile.modelData.type; size: 28; color: theme.textSecondary }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter
                                        text: catalog.title(tile.modelData.type); color: theme.textSecondary; font.pixelSize: 12 }
                                }
                            }
                            Loader {
                                id: wl
                                anchors.fill: parent
                                source: clone.wsrc(tile.modelData.type)
                                onLoaded: clone.injectInto(item, tile.modelData.id, tile.modelData.type)
                            }

                            // Drop-target highlight.
                            Rectangle {
                                anchors.fill: parent; radius: theme.radiusLg
                                color: "transparent"; border.width: 3; border.color: theme.accent
                                visible: clone.dragIndex >= 0 && clone.targetIndex === tile.index
                                         && clone.dragIndex !== tile.index
                            }

                            // Drag / select overlay.
                            MouseArea {
                                id: ma
                                visible: clone.editable
                                anchors.fill: parent
                                anchors.rightMargin: 26; anchors.bottomMargin: 26   // leave the corner handle
                                cursorShape: clone.dragIndex === tile.index ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                preventStealing: true
                                property real sx: 0; property real sy: 0
                                property bool dragging: false
                                onPressed: (mouse) => { ma.sx = mouse.x; ma.sy = mouse.y; ma.dragging = false }
                                onPositionChanged: (mouse) => {
                                    if (!ma.dragging && (Math.abs(mouse.x - ma.sx) > 8 || Math.abs(mouse.y - ma.sy) > 8)) {
                                        ma.dragging = true; clone.dragIndex = tile.index
                                    }
                                    if (ma.dragging) {
                                        var g = tile.mapToItem(grid, mouse.x, mouse.y)
                                        var c = tile.mapToItem(clone, mouse.x, mouse.y)
                                        clone.dragX = c.x; clone.dragY = c.y
                                        clone.targetIndex = clone.targetAt(g.x, g.y)
                                    }
                                }
                                onReleased: {
                                    if (ma.dragging) {
                                        var to = clone.targetIndex
                                        var from = tile.index
                                        // Clear the drag state (which hides the floating
                                        // name-tag) BEFORE moveTile: moveTile reorders the
                                        // model and can destroy THIS delegate — and its
                                        // running handler — so a reset placed after it may
                                        // never execute, leaving the name-tag stuck in air.
                                        ma.dragging = false
                                        clone.dragIndex = -1; clone.targetIndex = -1
                                        // Delegate indices count PLACEMENTS; moveTile
                                        // addresses the store's tile array. `idx` is the
                                        // bridge — they coincide only by luck.
                                        if (to >= 0 && to !== from)
                                            store.moveTile(clone.pageIndex, clone.placements[from].idx,
                                                           clone.placements[to].idx)
                                    } else {
                                        clone.configRequested(tile.modelData.id, tile.modelData.type)
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
                                        onClicked: clone.configRequested(tile.modelData.id, tile.modelData.type) }
                                }
                                Rectangle {
                                    width: 32; height: 32; radius: 16
                                    color: Qt.rgba(theme.error.r, theme.error.g, theme.error.b, 0.7)
                                    AppIcon { anchors.centerIn: parent; name: "ui-close"; color: "#fff"; size: 15 }
                                    MouseArea { anchors.fill: parent
                                        onClicked: store.removeTile(clone.pageIndex, tile.modelData.id) }
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
                                visible: clone.editable && catalog.sizesFor(tile.modelData.type).length > 1
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
                                        tile.pvSize = tile.modelData.size
                                    }
                                    onPositionChanged: (mp) => {
                                        var c = mapToItem(screen, mp.x, mp.y)
                                        // The box the cursor is describing, resolved onto the
                                        // SEMANTIC axes — so this reads identically whichever
                                        // way the device is turned.
                                        var pxW = tile.width + (c.x - sx), pxH = tile.height + (c.y - sy)
                                        var pxShort = clone.landscape ? pxH : pxW
                                        var pxLong = clone.landscape ? pxW : pxH
                                        var snapped = packer.snap(catalog.sizesFor(tile.modelData.type),
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
                                        if (next !== "") store.setTileSize(clone.pageIndex, tile.modelData.id, next)
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
    Rectangle {
        id: dragGhost
        visible: clone.dragIndex >= 0 && clone.dragIndex < clone.tiles.length
        width: 210; height: 46; radius: 12; z: 100
        x: Math.max(6, Math.min(clone.width - width - 6, clone.dragX + 18))
        y: Math.max(6, Math.min(clone.height - height - 6, clone.dragY - height / 2))
        color: theme.cardBackgroundAlt; border.width: 1; border.color: theme.accent
        Row {
            anchors.centerIn: parent; spacing: 10
            AppIcon { anchors.verticalCenter: parent.verticalCenter; size: 22; color: theme.textPrimary
                name: clone.dragIndex >= 0 && clone.dragIndex < clone.tiles.length
                      ? clone.tiles[clone.dragIndex].type : "" }
            Text { text: clone.dragIndex >= 0 && clone.dragIndex < clone.tiles.length
                ? catalog.title(clone.tiles[clone.dragIndex].type) : ""
                color: theme.textPrimary; font.pixelSize: 15 }
        }
    }
}
