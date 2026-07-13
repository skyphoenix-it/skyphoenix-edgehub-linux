import QtQuick

// BackdropLayer — picks the active animated background style. `running` toggles
// motion (off for reduce-motion → the style renders static). "none"/"gradient"
// load nothing (the theme gradient shows through). Styles are declared in
// ui/qml/BackgroundCatalog.qml (keep this map in sync with it).
Loader {
    id: bl
    property string style: "orbs"
    property bool running: true
    // Optional accent override (S7): threaded into the loaded backdrop so a
    // per-widget/per-page accent recolours the backdrop's primary tint. Defaults
    // to theme.accent, so an unset override leaves every style's look unchanged.
    property color accent: theme.accent

    readonly property var _map: ({
        "orbs": orbsC, "waves": wavesC, "stars": starsC,
        "mesh": meshC, "aurora": auroraC, "bokeh": bokehC, "grid": gridC
    })
    // Gate on `visible` too: when a wallpaper is set (or High-Contrast hides the
    // backdrop) the host sets visible:false — without this the chosen backdrop
    // would stay LOADED and keep animating invisibly, burning GPU for nothing.
    active: visible && style !== "none" && style !== "gradient" && _map[style] !== undefined
    sourceComponent: _map[style] || null
    onLoaded: {
        if (item) {
            item.active = Qt.binding(function () { return bl.running })
            item.accent = Qt.binding(function () { return bl.accent })
        }
    }

    Component { id: orbsC;   AnimatedBackground { } }
    Component { id: wavesC;  WavesBackground { } }
    Component { id: starsC;  StarfieldBackground { } }
    Component { id: meshC;   MeshGradientBackground { } }
    Component { id: auroraC; AuroraBackground { } }
    Component { id: bokehC;  BokehBackground { } }
    Component { id: gridC;   GridBackground { } }
}
