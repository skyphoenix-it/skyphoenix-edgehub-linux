import QtQuick

// BackdropLayer — picks the active animated background style. `running` toggles
// motion (off for reduce-motion → the style renders static). "none"/"gradient"
// load nothing (the theme gradient shows through). Styles are declared in
// ui/qml/BackgroundCatalog.qml (keep this map in sync with it).
Loader {
    id: bl
    property string style: "orbs"
    property bool running: true

    readonly property var _map: ({
        "orbs": orbsC, "waves": wavesC, "stars": starsC,
        "mesh": meshC, "aurora": auroraC, "bokeh": bokehC, "grid": gridC
    })
    active: style !== "none" && style !== "gradient" && _map[style] !== undefined
    sourceComponent: _map[style] || null
    onLoaded: if (item) item.active = Qt.binding(function () { return bl.running })

    Component { id: orbsC;   AnimatedBackground { } }
    Component { id: wavesC;  WavesBackground { } }
    Component { id: starsC;  StarfieldBackground { } }
    Component { id: meshC;   MeshGradientBackground { } }
    Component { id: auroraC; AuroraBackground { } }
    Component { id: bokehC;  BokehBackground { } }
    Component { id: gridC;   GridBackground { } }
}
