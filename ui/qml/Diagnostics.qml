import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: diag
    anchors.fill: parent

    property string metricsJson: ""
    property string configJson: ""
    property string screensData: ""
    property int currentPage: 0

    // Parse the metrics ONCE per push (guarded), instead of re-parsing inside every
    // Overview card's text binding (6× per second, unguarded → a malformed payload
    // blanked the whole grid).
    readonly property var parsedMetrics: {
        try { return JSON.parse(metricsJson || "{}") } catch (e) { return {} }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Diagnostics"
                color: theme.accent
                font.pixelSize: 22
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Button {
                text: "← Back"
                onClicked: stackView.pop()
                flat: true
                leftPadding: 18; rightPadding: 18; topPadding: 14; bottomPadding: 14
                contentItem: Text {
                    text: "← Back"
                    color: theme.textSecondary
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: parent.down ? theme.cardBackgroundAlt : (parent.hovered ? Qt.lighter(theme.cardBackground, 1.1) : "transparent")
                    radius: 6
                }
            }
        }

        // Tab bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: ["Overview", "Config", "Screens", "Log"]
                Button {
                    text: modelData; flat: true; checked: diag.currentPage === index
                    checkable: true; autoExclusive: true
                    onClicked: diag.currentPage = index
                    leftPadding: 16; rightPadding: 16; topPadding: 14; bottomPadding: 14
                    contentItem: Text {
                        text: modelData
                        color: parent.checked ? theme.textPrimary : theme.textSecondary
                        font.weight: parent.checked ? Font.Bold : Font.Normal
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: parent.checked ? Qt.lighter(theme.cardBackground, 1.1) : "transparent"
                        radius: 6
                        Rectangle {
                            anchors.bottom: parent.bottom; width: parent.width; height: 2
                            color: parent.parent.checked ? theme.accent : "transparent"
                        }
                    }
                }
            }
        }

        // Page content
        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: diag.currentPage

            // Page 0: Overview
            Item {
                Flickable {
                    anchors.fill: parent; contentHeight: overviewCol.implicitHeight; clip: true
                    ColumnLayout {
                    id: overviewCol
                    width: parent.width; spacing: 10
                    Text { text: "System Overview"; color: theme.textPrimary; font.pixelSize: 16; font.bold: true }
                    GridLayout {
                        columns: 3; columnSpacing: 12; rowSpacing: 12; Layout.fillWidth: true
                        Repeater {
                            model: [
                                { label: "CPU Usage", key: "cpu_usage_percent", unit: "%", color: theme.success },
                                { label: "CPU Temp", key: "cpu_temp_celsius", unit: "°C", color: theme.warning },
                                { label: "RAM Usage", key: "ram_usage_percent", unit: "%", color: theme.accent },
                                { label: "RAM Total", key: "ram_total_bytes", unit: "GB", color: theme.textSecondary, fmt: "bytes_to_gb" },
                                { label: "RAM Used", key: "ram_used_bytes", unit: "GB", color: theme.error, fmt: "bytes_to_gb" },
                                { label: "CPU Cores", key: "cpu_core_count", unit: "", color: theme.catProductivity }
                            ]
                            Rectangle {
                                Layout.fillWidth: true; height: 80; radius: 8
                                color: theme.cardBackground; border.color: theme.cardBorder
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: 4
                                    Text { text: modelData.label; color: theme.textSecondary; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                                    Text {
                                        text: {
                                            var val = diag.parsedMetrics[modelData.key];
                                            if (val === undefined || val === null) return "N/A";
                                            if (modelData.fmt === "bytes_to_gb") return (val/(1024*1024*1024)).toFixed(1)+" "+modelData.unit;
                                            if (typeof val === "number") return val.toFixed(1)+modelData.unit;
                                            return val+modelData.unit;
                                        }
                                        color: modelData.color
                                        font.pixelSize: 20; font.bold: true; Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true; height: 100; radius: 8
                        color: theme.backgroundColor; border.color: theme.cardBorder
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 4
                            Text { text: "Xeneon Edge Linux Hub v0.1.0"; color: theme.textPrimary; font.pixelSize: 14; font.bold: true }
                            Text { text: "Qt: "+Qt.platform.os+" | Rust core: 0.1.0"; color: theme.textSecondary; font.pixelSize: 12 }
                            Text { text: "Build: Debug | "+new Date().toISOString().slice(0,10); color: theme.textSecondary; font.pixelSize: 12 }
                        }
                    }
                    }
                }
            }

            // Page 1: Config
            Item {
                Flickable {
                    anchors.fill: parent; contentHeight: configCol.implicitHeight+20; clip: true
                    ColumnLayout {
                        id: configCol; width: parent.width; spacing: 8
                        Text { text: "Configuration"; color: theme.textPrimary; font.pixelSize: 16; font.bold: true }
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: configText.implicitHeight+24; radius: 8
                            color: theme.backgroundColor; border.color: theme.cardBorder
                            Text {
                                id: configText; anchors.fill: parent; anchors.margins: 12
                                text: diag.configJson || "Loading..."; color: theme.textPrimary
                                font.family: theme.fontMono; font.pixelSize: 11; wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }

            // Page 2: Screens
            Item {
                Flickable {
                    anchors.fill: parent; contentHeight: screensCol.implicitHeight+20; clip: true
                    ColumnLayout {
                        id: screensCol; width: parent.width; spacing: 12
                        Text { text: "Connected Displays"; color: theme.textPrimary; font.pixelSize: 16; font.bold: true }
                        Repeater {
                            model: { try { return JSON.parse(diag.screensData||"[]") } catch(e) { return [] } }
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 160; radius: 8
                                color: theme.cardBackground
                                border.color: modelData.likelyXeneonEdge ? theme.success : theme.cardBorder
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 12; spacing: 4
                                    RowLayout {
                                        Text { text: modelData.model||"Unknown"; color: theme.textPrimary; font.pixelSize: 14; font.bold: true }
                                        Rectangle {
                                            visible: modelData.likelyXeneonEdge
                                            color: theme.success; radius: 4
                                            implicitWidth: badgeText.implicitWidth+12; implicitHeight: 20
                                            Text { id: badgeText; anchors.centerIn: parent; text: "XENEON EDGE"; color: theme.backgroundColor; font.pixelSize: 9; font.bold: true }
                                        }
                                        Rectangle {
                                            visible: modelData.isPrimary
                                            color: theme.accent; radius: 4
                                            implicitWidth: primaryText.implicitWidth+12; implicitHeight: 20
                                            Text { id: primaryText; anchors.centerIn: parent; text: "PRIMARY"; color: theme.backgroundColor; font.pixelSize: 9; font.bold: true }
                                        }
                                    }
                                    Text { text: (modelData.geometry?modelData.geometry.width+"×"+modelData.geometry.height:"?")+" @ "+(modelData.refreshRate?modelData.refreshRate.toFixed(0):"?")+"Hz | "+(modelData.orientation||"?"); color: theme.textSecondary; font.pixelSize: 12 }
                                    Text { text: "DPI: "+(modelData.logicalDpi?modelData.logicalDpi.toFixed(0):"?")+" logical / "+(modelData.physicalDpi?modelData.physicalDpi.toFixed(0):"?")+" physical"; color: theme.textSecondary; font.pixelSize: 12 }
                                    Text { text: "Connector: "+(modelData.name||"?"); color: theme.textSecondary; font.pixelSize: 12 }
                                    Text { text: "EDID Hash: "+(modelData.edidHash||"N/A"); color: theme.textSecondary; font.family: theme.fontMono; font.pixelSize: 9; elide: Text.ElideMiddle; Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }
            }

            // Page 3: Log
            Item {
                ColumnLayout {
                    anchors.fill: parent; spacing: 8
                    Text { text: "Log Output"; color: theme.textPrimary; font.pixelSize: 16; font.bold: true }
                    Text {
                        text: "Logs are written to stdout/stderr via the Rust tracing subscriber.\nUse --diagnostics to view live logs, or check journal/syslog."
                        color: theme.textSecondary; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 8
                        color: theme.backgroundColor; border.color: theme.cardBorder
                        Text {
                            anchors.fill: parent; anchors.margins: 12
                            text: "Run with RUST_LOG=debug for detailed logs.\n\nConfig dir: "+_configDir
                            color: theme.textPrimary; font.family: theme.fontMono; font.pixelSize: 11; wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }
    }
}
