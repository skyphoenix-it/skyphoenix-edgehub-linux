import QtQuick

// Tier-0 fixture widget: declares the injected host contract with NO qrc
// imports, because the offscreen suite runs against the source tree where
// qrc:/qml does not exist. (A real user widget would root in WidgetChrome via
// `import "qrc:/qml"` — see docs/widgets/manifest-spec.md.)
Rectangle {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property var netHub: null
    property string sizeClass: "compact"
    color: "transparent"

    // The live-config read pattern from the authoring guide.
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? store.settingsFor(instanceId) : ({})
    }
    readonly property string who: cfg.who !== undefined ? cfg.who : "world"

    Text {
        anchors.centerIn: parent
        text: "Hello, " + w.who + "!"
        color: "white"
    }
}
