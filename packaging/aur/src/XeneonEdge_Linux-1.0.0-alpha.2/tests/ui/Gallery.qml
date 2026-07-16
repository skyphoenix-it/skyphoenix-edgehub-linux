import QtQuick

// Visual gallery: renders a selection of widgets (compact + expanded) at
// Edge-like tile sizes and grabs the result to a PNG, so the redesign can be
// eyeballed without a full C++ build. Run with the `qml` runtime; it writes the
// image and quits.
Rectangle {
    id: root
    width: 1500
    height: 940
    color: "#0D1117"

    property string outFile: Qt.resolvedUrl("gallery_out.png")

    Row {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // Column 1: compact tiles
        Grid {
            columns: 2
            spacing: 16
            Repeater {
                model: [
                    { f: "MediaWidget.qml", track: true },
                    { f: "FocusWidget.qml" },
                    { f: "BreakWidget.qml" },
                    { f: "HydrationWidget.qml" },
                    { f: "TasksWidget.qml", tasks: true },
                    { f: "WeatherWidget.qml" },
                    { f: "CpuWidget.qml" },
                    { f: "HabitWidget.qml" }
                ]
                delegate: WidgetHarness {
                    required property var modelData
                    width: 330; height: 200
                    widgetFile: modelData.f
                    expanded: false
                    metricsJson: '{"cpu_usage_percent":42.5,"cpu_temp_celsius":55,"ram_usage_percent":63,"cpu_core_count":16}'
                    Component.onCompleted: seed()
                    function seed() {
                        if (modelData.track && mediaCtl) mediaCtl.loadTrack("Midnight City", "M83")
                        if (modelData.tasks && storeCtl) {
                            storeCtl.patchSettings(instanceId, { items: [
                                { text: "Ship the redesign", done: true },
                                { text: "Write GUI tests", done: false },
                                { text: "Build companion app", done: false } ] })
                        }
                    }
                }
            }
        }

        // Column 2: expanded views
        Column {
            spacing: 16
            WidgetHarness {
                width: 700; height: 440
                widgetFile: "MediaWidget.qml"; expanded: true
                Component.onCompleted: if (mediaCtl) mediaCtl.loadTrack("Midnight City", "M83")
            }
            WidgetHarness {
                width: 700; height: 440
                widgetFile: "FocusWidget.qml"; expanded: true
            }
        }
    }

    Timer {
        interval: 900; running: true; repeat: false
        onTriggered: root.grabToImage(function (result) {
            result.saveToFile(root.outFile)
            Qt.callLater(Qt.quit)
        }, Qt.size(root.width, root.height))
    }
}
