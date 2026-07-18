import QtQuick
import QtQuick.Layouts

// BackgroundPicker — ONE control for choosing a background, so the scattered
// "animated style" / "wallpaper" / "set as wallpaper" options collapse into a
// single, obvious, mutually-exclusive choice. Works for the GLOBAL default
// (pageIndex < 0) or a PER-PAGE override (pageIndex >= 0), which makes the
// precedence explicit ("Use global" vs a specific pick for this page).
//
// Required: store, col (tokens: textPrimary/textSecondary/panel/panelAlt/border/
// accent/radius), bgCatalog (BackgroundCatalog), wpCatalog (WallpaperCatalog).
// Optional: uploadedImages = [{ label, source }] to include the user's images.
Item {
    id: bp
    property var store
    property int pageIndex: -1          // <0 = global default; >=0 = that page
    property var col
    property var bgCatalog
    property var wpCatalog
    property var uploadedImages: []

    // Hover-preview hooks for animated styles (the host — e.g. the Manager — wires
    // these to a live preview without committing). Unconnected in the hub, which is
    // harmless.
    signal previewStyle(string v)
    signal previewEnded()

    implicitHeight: col2.implicitHeight

    // Text legible on an accent fill — prefer a theme token so a dark accent can't
    // make the selected chip's label vanish; fall back to the historic literal.
    function onAccent() { return (col && col.textOnAccent) ? col.textOnAccent : "#0D1117" }

    // ── Current selection (reactive on store.revision) ──
    // Returns { kind: "global"|"style"|"wallpaper", val }.
    function current() {
        if (!store) return { kind: "global" }   // before the store is wired in
        store.revision
        if (pageIndex < 0) {
            var a = store.appearance() || ({})
            if (a.wallpaper) return { kind: "wallpaper", val: a.wallpaper }
            return { kind: "style", val: a.bgStyle || "orbs" }
        }
        var p = store.pageBackground(pageIndex) || ({})
        if (p.wallpaper) return { kind: "wallpaper", val: p.wallpaper }
        if (p.style) return { kind: "style", val: p.style }
        return { kind: "global" }
    }
    function selStyle(v) { var c = current(); return c.kind === "style" && c.val === v }
    function selWall(s) { var c = current(); return c.kind === "wallpaper" && c.val === s }
    function selGlobal() { return current().kind === "global" }

    // ── Mutually-exclusive writes ──
    function pickStyle(v) {
        if (pageIndex < 0) { store.setAppearance("bgStyle", v); store.setAppearance("wallpaper", "") }
        else { store.setPageBackground(pageIndex, "style", v); store.setPageBackground(pageIndex, "wallpaper", "") }
    }
    function pickWallpaper(src) {
        if (pageIndex < 0) store.setAppearance("wallpaper", src)
        else store.setPageBackground(pageIndex, "wallpaper", src)
    }
    function useGlobal() {   // pages only: drop the override
        store.setPageBackground(pageIndex, "style", "")
        store.setPageBackground(pageIndex, "wallpaper", "")
    }

    ColumnLayout {
        id: col2
        width: bp.width
        spacing: 10

        // Animated styles (+ "Use global" for pages).
        Flow {
            Layout.fillWidth: true; spacing: 8
            // "Use global" — only meaningful for a page override.
            Rectangle {
                id: globalChip
                visible: bp.pageIndex >= 0
                width: gLbl.implicitWidth + 22; height: 44; radius: bp.col.radius
                property bool sel: bp.selGlobal()
                color: sel ? bp.col.accent : bp.col.panelAlt
                border.width: sel ? 2 : 1; border.color: sel ? bp.col.accent : bp.col.border
                // Reference the chip's `sel` via its id — this Rectangle is NOT a
                // delegate/component root, so a bare `sel` in the child Text doesn't
                // resolve (it threw "sel is not defined").
                Text { id: gLbl; anchors.centerIn: parent; text: "Use global"
                    color: globalChip.sel ? bp.onAccent() : bp.col.textPrimary; font.pixelSize: 13 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bp.useGlobal() }
            }
            Repeater {
                model: bp.bgCatalog ? bp.bgCatalog.styles : []
                delegate: Rectangle {
                    required property var modelData
                    width: sLbl.implicitWidth + 22; height: 44; radius: bp.col.radius
                    property bool sel: bp.selStyle(modelData.v)
                    color: sel ? bp.col.accent : bp.col.panelAlt
                    border.width: sel ? 2 : 1; border.color: sel ? bp.col.accent : bp.col.border
                    Text { id: sLbl; anchors.centerIn: parent; text: modelData.l
                        color: sel ? bp.onAccent() : bp.col.textPrimary; font.pixelSize: 13 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onContainsMouseChanged: containsMouse ? bp.previewStyle(modelData.v) : bp.previewEnded()
                        onClicked: { bp.pickStyle(modelData.v); bp.previewEnded() } }
                }
            }
        }

        Text { text: "…or a wallpaper (replaces the animation):"; color: bp.col.textSecondary; font.pixelSize: 12 }

        // Wallpaper thumbnails: bundled + the user's uploaded images.
        Flow {
            Layout.fillWidth: true; spacing: 8
            Repeater {
                model: (bp.wpCatalog ? bp.wpCatalog.items : []).concat(bp.uploadedImages)
                delegate: Rectangle {
                    required property var modelData
                    width: 64; height: 88; radius: bp.col.radius; clip: true
                    property bool sel: bp.selWall(modelData.source)
                    color: bp.col.panel; border.width: sel ? 3 : 1
                    border.color: sel ? bp.col.accent : bp.col.border
                    Image { anchors.fill: parent; anchors.margins: 2; source: modelData.source
                        fillMode: Image.PreserveAspectCrop; asynchronous: true }
                    Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                        height: 18; color: Qt.rgba(0, 0, 0, 0.5)
                        Text { anchors.centerIn: parent; text: modelData.label + (parent.parent.sel ? " ✓" : "")
                            color: "#fff"; font.pixelSize: 9; elide: Text.ElideRight; width: parent.width - 4
                            horizontalAlignment: Text.AlignHCenter } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: bp.pickWallpaper(modelData.source) }
                }
            }
        }
    }
}
