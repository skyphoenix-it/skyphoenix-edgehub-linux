import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ─────────────────────────────────────────────────────────────────────────
// PresetPicker — the post-setup "Screens" surface (W5 finding 3).
//
// The curated 15-preset library used to be reachable exactly once, in the
// first-run wizard; a user who finished setup could never apply a preset
// again (the only route was the --reset-wizard CLI flag). This full-screen
// overlay reopens the same library from the Settings sheet.
//
// Selecting a card only ARMS it — applying replaces the current pages, so an
// explicit confirm bar (with honest scope copy: layout is replaced, the
// user's theme/appearance stay) stands between a tap and the reset. The
// apply itself is emitted upward (applyRequested) and performed by the
// Dashboard through the store's normal seed path, so this stays a dumb
// surface with no store access of its own.
//
// Org policy (E9): under a forced preset (`lockToPreset`) the surface is
// ABSENT, not greyed out — `locked` gates visibility outright, so a managed
// device never advertises a choice its user cannot make. The Dashboard's
// applyPreset() guards independently, so even a stray signal cannot bypass
// the policy.
// ─────────────────────────────────────────────────────────────────────────
Rectangle {
    id: picker
    anchors.fill: parent
    z: 210
    color: Qt.rgba(0, 0, 0, 0.6)

    property bool shown: false
    // Org-forced preset active → this surface does not exist for the user.
    property bool locked: false
    // A PresetCatalog instance (injected by the Dashboard).
    property var catalog: null
    // The card awaiting confirmation ("" = nothing armed).
    property string pendingId: ""

    signal applyRequested(string presetId)
    signal closeRequested()

    readonly property string pendingTitle: {
        if (pendingId === "blank") return "a blank dashboard"
        var d = (catalog && pendingId !== "") ? catalog.def(pendingId) : null
        return d ? "“" + d.title + "”" : ""
    }

    visible: (shown && !locked) || opacity > 0.01
    opacity: (shown && !locked) ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: theme.motionFast } }
    // A fresh open never inherits a half-armed confirm from last time.
    onShownChanged: pendingId = ""

    // Scrim click closes (same behaviour as the add-widget picker/settings).
    MouseArea { anchors.fill: parent; onClicked: picker.closeRequested() }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.92, 1500)
        height: Math.min(parent.height * 0.9, 2200)
        radius: theme.radiusXl
        color: theme.backgroundColor
        border.width: 1; border.color: theme.cardBorder
        // Same entrance as every modal in the hub (instant under reduce-motion).
        scale: picker.shown ? 1.0 : 0.96
        Behavior on scale { NumberAnimation { duration: theme.motionPage; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent } // swallow clicks

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: theme.spacingLg
            spacing: theme.spacingMd

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: theme.spacingMd
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "Screens"
                        font.pixelSize: 22; font.bold: true; font.family: theme.fontDisplay
                        color: theme.textPrimary
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Ready-made layouts from setup. Applying one replaces your pages — your theme, accent and appearance settings stay."
                        font.pixelSize: theme.fontCaption; color: theme.textSecondary
                        wrapMode: Text.WordWrap
                    }
                }
                Rectangle {
                    objectName: "presetPickerClose"
                    Layout.preferredWidth: theme.touchSecondary
                    Layout.preferredHeight: theme.touchSecondary
                    Layout.alignment: Qt.AlignTop
                    radius: width / 2; color: theme.cardBackgroundAlt
                    AppIcon { anchors.centerIn: parent; name: "ui-close"; size: theme.iconSm; color: theme.textPrimary }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: picker.closeRequested() }
                }
            }

            // The library grid — the wizard's card design, reused.
            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                contentHeight: presetGrid.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                GridLayout {
                    id: presetGrid
                    width: parent.width
                    columns: width > 1360 ? 3 : (width > 700 ? 2 : 1)
                    columnSpacing: theme.spacingMd; rowSpacing: theme.spacingMd

                    Repeater {
                        model: picker.catalog ? picker.catalog.list() : []
                        delegate: Rectangle {
                            id: presetCard
                            required property var modelData
                            objectName: "presetCard-" + modelData.id
                            property bool sel: picker.pendingId === modelData.id
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.max(120, cardCol.implicitHeight + 28)
                            radius: theme.radiusLg
                            color: sel ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.14)
                                       : (cardMA.pressed ? theme.cardBackgroundAlt : theme.cardBackground)
                            border.width: sel ? 2 : 1
                            border.color: sel ? theme.accent : theme.cardBorder

                            ColumnLayout {
                                id: cardCol
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: presetCard.modelData.icon + "  " + presetCard.modelData.title
                                    font.pixelSize: 17; font.bold: true; font.family: theme.fontDisplay
                                    color: theme.textPrimary; elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    text: presetCard.modelData.blurb
                                    font.pixelSize: 13; color: theme.textSecondary
                                    wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                                }
                            }
                            MouseArea {
                                id: cardMA
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: picker.pendingId = presetCard.modelData.id
                            }
                        }
                    }

                    // Blank slate, same as the wizard offers.
                    Rectangle {
                        objectName: "presetCard-blank"
                        property bool sel: picker.pendingId === "blank"
                        Layout.fillWidth: true
                        Layout.columnSpan: presetGrid.columns
                        Layout.preferredHeight: theme.touchSecondary
                        radius: theme.radiusMd
                        color: sel ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.14)
                                   : theme.cardBackground
                        border.width: sel ? 2 : 1
                        border.color: sel ? theme.accent : theme.cardBorder
                        Text {
                            anchors.centerIn: parent
                            text: "Or start from a blank dashboard"
                            font.pixelSize: theme.fontLabel; color: theme.textPrimary
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: picker.pendingId = "blank" }
                    }
                }
            }

            // Confirm bar — armed by a selection. Applying replaces the layout,
            // so it never happens on the first tap.
            Rectangle {
                objectName: "presetConfirmBar"
                Layout.fillWidth: true
                visible: picker.pendingId !== ""
                radius: theme.radiusMd
                color: theme.cardBackgroundAlt
                border.width: 1; border.color: theme.cardBorder
                implicitHeight: confirmRow.implicitHeight + theme.spacingMd * 2

                RowLayout {
                    id: confirmRow
                    anchors.fill: parent
                    anchors.margins: theme.spacingMd
                    spacing: theme.spacingMd

                    Text {
                        Layout.fillWidth: true
                        text: "Replace your current pages with " + picker.pendingTitle
                              + "? Your theme and appearance settings stay."
                        color: theme.textPrimary; font.pixelSize: theme.fontLabel
                        wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        objectName: "presetConfirmCancel"
                        Layout.preferredWidth: Math.max(cancelLbl.implicitWidth + 34, theme.touchPrimary)
                        Layout.preferredHeight: theme.touchSecondary
                        radius: theme.radiusMd
                        color: cancelMA.pressed ? theme.cardBackground : theme.backgroundColor
                        border.width: 1; border.color: theme.cardBorder
                        Text { id: cancelLbl; anchors.centerIn: parent; text: "Cancel"
                            color: theme.textPrimary; font.pixelSize: theme.fontLabel }
                        MouseArea { id: cancelMA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: picker.pendingId = "" }
                    }
                    Rectangle {
                        objectName: "presetConfirmApply"
                        Layout.preferredWidth: applyLbl.implicitWidth + 34
                        Layout.preferredHeight: theme.touchSecondary
                        radius: theme.radiusMd
                        color: applyMA.pressed ? Qt.darker(theme.accent, 1.2) : theme.accent
                        Text { id: applyLbl; anchors.centerIn: parent; text: "Replace layout"
                            color: theme.backgroundColor; font.pixelSize: theme.fontLabel; font.bold: true }
                        MouseArea { id: applyMA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: if (picker.pendingId !== "") picker.applyRequested(picker.pendingId) }
                    }
                }
            }
        }
    }
}
