import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: wizard
    anchors.fill: parent

    property int currentStep: 0
    property var selectedScreen: null
    property string selectedLayout: "productivity"

    Rectangle {
        anchors.fill: parent
        color: theme.backgroundColor
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.85, 800)
        spacing: 24

        // Step 0: Welcome
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: welcomeContent.height
            visible: currentStep === 0

            ColumnLayout {
                id: welcomeContent
                width: parent.width
                spacing: 20

                Item { Layout.preferredHeight: 40 }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "🖥️"
                    font.pixelSize: 64
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Welcome to Xeneon Edge Linux Hub"
                    font.pixelSize: 28
                    font.bold: true
                    color: theme.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: parent.width * 0.8
                    text: "Set up your secondary touchscreen dashboard in just a few taps."
                    font.pixelSize: 16
                    color: theme.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }

        // Step 1: Display Selection
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: currentStep === 1

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                Text {
                    text: "Select Your Dashboard Display"
                    font.pixelSize: 22
                    font.bold: true
                    color: theme.textPrimary
                }

                Text {
                    text: "Choose the display where your dashboard will appear.\nDisplays matching the Xeneon Edge are highlighted."
                    font.pixelSize: 14
                    color: theme.textSecondary
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Parse screens from the C++ context property directly (the old
                // wizard.parent.parent traversal was fragile and could resolve to
                // the wrong object, leaving the list empty).
                property var screensList: {
                    try {
                        return JSON.parse(_screens || "[]");
                    } catch(e) {
                        return [];
                    }
                }

                ListView {
                    id: screenList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: parent.screensList
                    spacing: 8

                    delegate: Rectangle {
                        width: screenList.width
                        height: 80
                        radius: 12
                        color: modelData.likelyXeneonEdge ? "#1A3A2A" : theme.cardBackground
                        border.width: selectedScreen && selectedScreen.name === modelData.name ? 2 : 1
                        border.color: selectedScreen && selectedScreen.name === modelData.name ? theme.accent : theme.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    spacing: 8
                                    Text {
                                        text: modelData.model || "Unknown Display"
                                        font.pixelSize: 16
                                        font.bold: true
                                        color: theme.textPrimary
                                    }
                                    Rectangle {
                                        visible: modelData.likelyXeneonEdge
                                        color: theme.success
                                        radius: 4
                                        width: detectedLabel.width + 8
                                        height: detectedLabel.height + 4
                                        Text {
                                            id: detectedLabel
                                            anchors.centerIn: parent
                                            text: "⭐ Detected"
                                            font.pixelSize: 11
                                            color: "#000000"
                                        }
                                    }
                                }

                                Text {
                                    text: (modelData.manufacturer || "") + " • " +
                                          modelData.size.width + "×" + modelData.size.height + " • " +
                                          modelData.name
                                    font.pixelSize: 13
                                    color: theme.textSecondary
                                }
                            }

                            Button {
                                text: selectedScreen && selectedScreen.name === modelData.name ? "✓ Selected" : "Select"
                                flat: selectedScreen && selectedScreen.name === modelData.name
                                onClicked: selectedScreen = modelData
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: selectedScreen = modelData
                        }
                    }
                }

                Text {
                    visible: screenList.count === 0
                    text: "No displays detected. Please connect a display and restart."
                    color: theme.warning
                    font.pixelSize: 14
                }
            }
        }

        // Step 2: Choose Layout
        Item {
            Layout.fillWidth: true
            visible: currentStep === 2

            ColumnLayout {
                width: parent.width
                spacing: 16

                Text {
                    text: "Choose a Starter Layout"
                    font.pixelSize: 22
                    font.bold: true
                    color: theme.textPrimary
                }

                Text {
                    text: "You can customize everything later."
                    font.pixelSize: 14
                    color: theme.textSecondary
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Repeater {
                        model: [
                            { id: "productivity", name: "Productivity", desc: "Clock, CPU, RAM, focus timer, goals, media", icon: "📋" },
                            { id: "gaming", name: "Gaming", desc: "CPU/GPU temps, FPS, RAM, media, system metrics", icon: "🎮" },
                            { id: "minimal", name: "Minimal", desc: "Clock and media controls only", icon: "✨" },
                        ]

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 140
                            radius: 12
                            color: selectedLayout === modelData.id ? Qt.lighter(theme.cardBackground, 1.15) : theme.cardBackground
                            border.width: selectedLayout === modelData.id ? 2 : 1
                            border.color: selectedLayout === modelData.id ? theme.accent : theme.cardBorder

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 8

                                Text {
                                    text: modelData.icon + "  " + modelData.name
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: theme.textPrimary
                                }
                                Text {
                                    text: modelData.desc
                                    font.pixelSize: 13
                                    color: theme.textSecondary
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: selectedLayout = modelData.id
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    radius: 12
                    color: selectedLayout === "blank" ? Qt.lighter(theme.cardBackground, 1.15) : theme.cardBackground
                    border.width: selectedLayout === "blank" ? 2 : 1
                    border.color: selectedLayout === "blank" ? theme.accent : theme.cardBorder

                    Text {
                        anchors.centerIn: parent
                        text: "Or start with a blank dashboard"
                        font.pixelSize: 16
                        color: theme.textPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: selectedLayout = "blank"
                    }
                }
            }
        }

        // Step 3: Options & Finish
        Item {
            Layout.fillWidth: true
            visible: currentStep === 3

            ColumnLayout {
                width: parent.width
                spacing: 20

                Text {
                    text: "Almost Done!"
                    font.pixelSize: 22
                    font.bold: true
                    color: theme.textPrimary
                }

                ColumnLayout {
                    spacing: 12

                    RowLayout {
                        CheckBox {
                            id: autostartCheck
                            checked: true
                        }
                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: "Start automatically when I log in"
                                font.pixelSize: 16
                                color: theme.textPrimary
                            }
                            Text {
                                text: "Adds to system autostart"
                                font.pixelSize: 13
                                color: theme.textSecondary
                            }
                        }
                    }

                    RowLayout {
                        CheckBox {
                            id: reconnectCheck
                            checked: true
                        }
                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: "Reopen dashboard when display is reconnected"
                                font.pixelSize: 16
                                color: theme.textPrimary
                            }
                            Text {
                                text: "Recommended"
                                font.pixelSize: 13
                                color: theme.textSecondary
                            }
                        }
                    }

                    RowLayout {
                        CheckBox {
                            id: notifyCheck
                            checked: true
                        }
                        ColumnLayout {
                            spacing: 2
                            Text {
                                text: "Show notification when display is disconnected"
                                font.pixelSize: 16
                                color: theme.textPrimary
                            }
                        }
                    }
                }
            }
        }

        // Navigation buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8

            Button {
                text: "← Back"
                visible: currentStep > 0
                flat: true
                onClicked: currentStep--
            }

            Item { Layout.fillWidth: true }

            // Step indicators
            Row {
                Layout.alignment: Qt.AlignCenter
                spacing: 8
                Repeater {
                    model: 4
                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: wizard.currentStep === index ? theme.accent : theme.cardBorder
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: currentStep === 0 ? "Get Started →" :
                      currentStep === 3 ? "Finish Setup" : "Next →"
                onClicked: {
                    if (currentStep === 1 && !selectedScreen) {
                        // Require selection
                        return;
                    }
                    if (currentStep === 3) {
                        // Save configuration
                        wizardCompleted(selectedScreen, selectedLayout, autostartCheck.checked);
                    } else {
                        currentStep++;
                    }
                }
            }
        }
    }

    function wizardCompleted(screen, layout, autostart) {
        console.log("Wizard complete. Selected:", screen ? screen.model : "none",
                    "Layout:", layout, "Autostart:", autostart);

        // Persist all wizard choices via WizardBridge → Rust config
        var ok = wizardBridge.completeWizard(
            screen ? (screen.edidHash || "") : "",
            screen ? (screen.name || "") : "",
            screen ? (screen.model || "") : "",
            layout,
            "dark",           // themeMode — default dark
            "#58A6FF",        // themeAccent
            autostart,
            reconnectCheck.checked,
            notifyCheck.checked
        );

        if (ok) {
            console.log("Wizard complete, navigating to dashboard");
            var sv = wizard.StackView.view;
            if (sv) {
                sv.replace("qrc:/qml/Dashboard.qml");
            }
        } else {
            console.error("WizardBridge.completeWizard failed");
        }
    }
}
