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
        // When tinting, the raw white glyph is hidden; the MultiEffect renders it.
        visible: !(root.tint && root.iconSource == "")
    }
    MultiEffect {
        anchors.fill: img
        source: img
        visible: root.tint && root.iconSource == ""
        colorization: 1.0
        colorizationColor: root.color
    }
}
