import QtQuick
import QtQuick.Effects

// AppIcon — renders a bundled monochrome SVG (qrc:/icons/<name>.svg) tinted to
// `color`, crisp at any size. For a full-colour brand asset (e.g. a game logo)
// set `iconSource` and `tint: false`. Professional, consistent iconography that
// replaces the old emoji glyphs across both apps.
Item {
    id: root
    property string name: ""
    property url iconSource: ""     // full-colour override (skips tinting)
    property color color: "#FFFFFF"
    property real size: 24
    property bool tint: true

    // W5 finding 4: under the SOFTWARE scenegraph (QT_QUICK_BACKEND=software —
    // VMs, remote sessions, no-GL boxes — and headless capture platforms)
    // MultiEffect draws NOTHING: it needs a shader pipeline the software
    // rasterizer does not have, so every tinted icon rendered as an empty
    // square (toolbar, steppers, config icons — all of them). Detect that
    // backend on THIS item (GraphicsInfo is per-window/scenegraph) and fall
    // back to the plain, untinted Image: a white glyph on the wrong surface
    // still beats an invisible one.
    // A plain default-bound property (not readonly) so tests can drive both
    // branches without swapping the scenegraph backend mid-run.
    property bool effectsAvailable: GraphicsInfo.api !== GraphicsInfo.Software

    implicitWidth: size
    implicitHeight: size

    Image {
        id: img
        anchors.fill: parent
        source: root.iconSource != "" ? root.iconSource
                : (root.name ? "qrc:/icons/" + root.name + ".svg" : "")
        sourceSize.width: Math.round(root.size * 2)
        sourceSize.height: Math.round(root.size * 2)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        // When tinting (and the effect can actually render), the raw white
        // glyph is hidden and the MultiEffect draws it. With no effects
        // available the raw glyph IS the icon — the untinted fallback.
        visible: !(root.tint && root.iconSource == "") || !root.effectsAvailable
    }
    MultiEffect {
        anchors.fill: img
        source: img
        visible: root.tint && root.iconSource == "" && root.effectsAvailable
        colorization: 1.0
        colorizationColor: root.color
    }
}
