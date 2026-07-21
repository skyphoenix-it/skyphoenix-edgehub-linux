import QtQuick
import QtQuick.Layouts

// Now Playing - real MPRIS control via the `media` bridge (Spotify, YouTube
// Music in a browser, any MPRIS player). Shows a genuine "nothing playing"
// state rather than fabricated data.
//
// Sizing (W1 wave 3): layout keys off the injected `sizeClass`. The old tile was
// ONE 46px-thumbnail row for every size - a 696x819 box rendered a 46px cover
// and 13px type. The content set now follows the room:
//   • 0.5x0.5 (micro) - headerless: art, the title, and ONE play target. The
//     half-cell (423x306 landscape) cannot hold prev/next + a progress bar and
//     still leave a real hit area, so it carries the readout and hands the rest
//     to the overlay rather than shrinking a button.
//   • 1x1 (baseline)  - art + title/artist + progress + the full transport.
//   • wide            - a genuinely HORIZONTAL variant: art BESIDE the
//     metadata + transport. The vertical stack (art + title + bar + transport)
//     is ~420px of content and the wide projections are 409px (1x0.5 portrait)
//     and 306px (0.5x1 landscape) tall - it simply does not fit.
//   • tall            - the vertical stack, with the art taking the height.
//   • full (overlay)  - unchanged shape (album line, centred type, big
//     transport); its art is size-derived now too.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    // accentColor MUST be a concrete colour: effAccent falls back to accentColor
    // (WidgetChrome), so `accentColor: effAccent` was a binding loop → the play
    // glyph/art rendered black. Content still uses w.effAccent (resolves the
    // per-widget accent preset, else this base).
    title: "Now Playing"; iconName: "media"; accentColor: theme.catEntertainment
    showHeader: !micro

    property bool avail: (typeof media !== "undefined") && media && media.available
    status: avail ? media.playerName : ""

    // ── Per-size layout (sizeClass injected by Dashboard) ────────────────────
    readonly property bool horiz: sizeClass === "wide"
    readonly property bool tallish: sizeClass === "tall" || sizeClass === "large"
    // Everything past "art + title + play" is gated on having more than a
    // half-cell. `micro` is chrome's half-cell footprint - not re-derived here.
    readonly property bool rich: !micro

    // The album art is a square DERIVED FROM THE BOX. It used to be
    // min(width*0.5, 260), a portrait-shaped assumption: in the 846x306
    // landscape projection of 0.5x1 that is a 260px square under a title under a
    // 52px transport row - ~420px of content in a 306px box.
    readonly property real artSize: {
        if (w.horiz)
            // Side-by-side: bounded by the height, and capped at ~2/5 of the
            // width so the metadata keeps the majority.
            return Math.max(40, Math.min(w.height * 0.80, w.width * 0.42))
        // Stacked: the art may take a chunk of the height, never so much that
        // the transport row is pushed out of the box.
        return Math.max(40, Math.min(w.width * 0.72, w.height * 0.45,
                                     w.expanded ? 420 : 100000))
    }
    // The width the metadata actually gets - what its type is sized against.
    readonly property real infoW: w.horiz
        ? Math.max(80, w.width - w.artSize - theme.spacingMd)
        : Math.max(80, w.width)
    // Type scales with the box and clamps. The horizontal projections are short,
    // so their height budget is a bigger share of a smaller number.
    readonly property real titlePx: Math.max(12, Math.min(w.infoW * 0.075,
                                     w.height * (w.horiz ? 0.10 : 0.06), 28))
    readonly property real artistPx: Math.max(11, Math.round(w.titlePx * 0.66))
    // Tile transport: play is the primary target, prev/next the secondary ones.
    readonly property real playSize: w.micro ? theme.touchTertiary : theme.touchSecondary

    // Nothing-playing placeholder (accurate state, not fake content). This is
    // what a media tile shows most of the day, so it scales with the box like
    // any other content instead of floating a 34px glyph in a 819px tile.
    ColumnLayout {
        anchors.centerIn: parent; visible: !w.avail; spacing: theme.spacingXs
        Text { Layout.alignment: Qt.AlignHCenter; text: "🎧"; opacity: 0.5
            font.pixelSize: Math.max(20, Math.min(w.width * 0.28, w.height * 0.28,
                                                  w.expanded ? 96 : 72)) }
        Text { Layout.alignment: Qt.AlignHCenter; text: "Nothing playing"
            Layout.preferredWidth: Math.max(60, w.width - 2 * theme.spacingMd)
            horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 9; elide: Text.ElideRight
            color: theme.textSecondary
            font.pixelSize: Math.max(11, Math.min(w.width * 0.05, w.height * 0.05,
                                                  w.expanded ? 20 : 16)) }
    }

    // ── Tile (every non-overlay size) ────────────────────────────────────────
    GridLayout {
        anchors.fill: parent
        visible: w.avail && !w.expanded
        // Wide reflows the SAME children into two columns: art beside the
        // metadata, which is the only shape that fits a 306px-tall box.
        columns: w.horiz ? 2 : 1
        rowSpacing: theme.spacingSm
        columnSpacing: theme.spacingMd

        // Stacked: split the slack above/below so the block sits centred rather
        // than jammed against the top edge. Invisible items are skipped by
        // GridLayout, so these never consume a cell in the 2-column arrangement.
        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: !w.horiz }

        Rectangle {
            id: artTile
            Layout.alignment: Qt.AlignCenter
            Layout.preferredWidth: Math.round(w.artSize)
            Layout.preferredHeight: Math.round(w.artSize)
            radius: theme.radiusMd; clip: true
            gradient: Gradient { GradientStop { position: 0; color: w.effAccent } GradientStop { position: 1; color: Qt.darker(w.effAccent, 1.5) } }
            Image { id: artC; anchors.fill: parent; source: w.avail && media.artUrl ? media.artUrl : ""
                fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
                visible: status === Image.Ready }
            // The fallback glyph is the art at this size - scale it with the box.
            Text { anchors.centerIn: parent; text: "♪"; color: "#fff"
                font.pixelSize: Math.max(14, w.artSize * 0.42)
                visible: artC.status !== Image.Ready }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: w.horiz
            // Released explicitly: a nested Layout inherits an implicit
            // maximumWidth from a child that sets Layout.alignment (the transport
            // row), which would cap this column at the transport's own width and
            // strand the metadata against the art.
            Layout.maximumWidth: Number.POSITIVE_INFINITY
            spacing: theme.spacingXs

            // Centre the metadata against the art when side-by-side.
            Item { Layout.fillHeight: true; visible: w.horiz }

            Text { text: w.avail ? media.title : ""; color: theme.textPrimary
                font.pixelSize: w.titlePx; font.bold: true
                horizontalAlignment: w.horiz ? Text.AlignLeft : Text.AlignHCenter
                elide: Text.ElideRight; Layout.fillWidth: true }
            Text { visible: w.rich; text: w.avail ? media.artist : ""
                color: theme.textSecondary; font.pixelSize: w.artistPx
                horizontalAlignment: w.horiz ? Text.AlignLeft : Text.AlignHCenter
                elide: Text.ElideRight; Layout.fillWidth: true }

            // Progress - the half-cell has no room for it.
            Rectangle {
                visible: w.rich
                Layout.fillWidth: true; Layout.topMargin: theme.spacingXs
                Layout.preferredHeight: 6; radius: 3; color: theme.cardBorder
                Rectangle { height: parent.height; radius: 3; color: w.effAccent
                    width: parent.width * Math.max(0, Math.min(1, w.avail ? media.position : 0))
                    Behavior on width { NumberAnimation { duration: theme.motionValue; easing.type: Easing.OutCubic } } }
            }

            // Transport. Micro keeps ONLY play - at a full-size hit area.
            RowLayout {
                Layout.alignment: w.horiz ? Qt.AlignLeft : Qt.AlignHCenter
                Layout.topMargin: theme.spacingXs
                spacing: theme.spacingMd
                Rectangle {
                    visible: w.rich
                    Layout.preferredWidth: theme.touchTertiary; Layout.preferredHeight: theme.touchTertiary
                    radius: width / 2
                    color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b, prevTMA.pressed ? 0.30 : 0.14)
                    border.width: 1; border.color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b, 0.5)
                    AppIcon { anchors.centerIn: parent; name: "ui-skip-back"; size: 22; color: theme.textPrimary }
                    MouseArea { id: prevTMA; anchors.fill: parent; onClicked: if (w.avail) media.previous() }
                }
                Rectangle {
                    Layout.preferredWidth: w.playSize; Layout.preferredHeight: w.playSize
                    radius: width / 2; color: w.effAccent
                    scale: ppMA.pressed ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: theme.motionFast } }
                    AppIcon { anchors.centerIn: parent
                        name: (w.avail && media.playing) ? "ui-pause" : "ui-play"
                        size: Math.round(w.playSize * 0.42); color: "#0D1117" }
                    MouseArea { id: ppMA; anchors.fill: parent; onClicked: if (w.avail) media.playPause() }
                }
                Rectangle {
                    visible: w.rich
                    Layout.preferredWidth: theme.touchTertiary; Layout.preferredHeight: theme.touchTertiary
                    radius: width / 2
                    color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b, nextTMA.pressed ? 0.30 : 0.14)
                    border.width: 1; border.color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b, 0.5)
                    AppIcon { anchors.centerIn: parent; name: "ui-skip-fwd"; size: 22; color: theme.textPrimary }
                    MouseArea { id: nextTMA; anchors.fill: parent; onClicked: if (w.avail) media.next() }
                }
            }

            Item { Layout.fillHeight: true; visible: w.horiz }
        }

        Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: !w.horiz }
    }

    // Expanded
    ColumnLayout {
        anchors.fill: parent; anchors.margins: theme.spacingLg
        visible: w.avail && w.expanded; spacing: theme.spacingMd
        Item { Layout.fillHeight: true }
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            // Size-derived like the tile's, rather than a flat 260px cap that
            // ignored the box (the overlay is a whole 2560x720 / 720x2560 panel).
            Layout.preferredWidth: Math.round(w.artSize); Layout.preferredHeight: Math.round(w.artSize)
            radius: theme.radiusLg; clip: true
            gradient: Gradient { GradientStop { position: 0; color: w.effAccent } GradientStop { position: 1; color: Qt.darker(w.effAccent, 1.5) } }
            Image { id: artE; anchors.fill: parent; source: w.avail && media.artUrl ? media.artUrl : ""
                fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
                visible: status === Image.Ready }
            Text { anchors.centerIn: parent; text: "♪"; color: "#fff"
                font.pixelSize: Math.max(14, w.artSize * 0.42)
                visible: artE.status !== Image.Ready }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: w.avail ? media.title : ""; font.pixelSize: 26; font.bold: true
                color: theme.textPrimary; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                // Join artist + album with a middot, but omit the separator (and any
                // stray leading " · ") when either side is empty (podcasts/streams).
                text: w.avail
                    ? (media.artist
                        ? (media.artist + (media.album ? "  ·  " + media.album : ""))
                        : (media.album || ""))
                    : ""
                font.pixelSize: 15; color: theme.textSecondary; elide: Text.ElideRight }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.preferredHeight: 6; radius: 3; color: theme.cardBorder
            Rectangle { height: parent.height; radius: 3; color: w.effAccent
                width: parent.width * Math.max(0, Math.min(1, w.avail ? media.position : 0))
                // Honor reduce-motion: snap instead of a 400ms sweep.
                Behavior on width { NumberAnimation { duration: theme.motionValue; easing.type: Easing.OutCubic } } }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingXl
            // Prev - matching circular touch button (was a bare 36px glyph).
            Rectangle {
                Layout.preferredWidth: theme.touchSecondary; Layout.preferredHeight: theme.touchSecondary
                radius: width / 2
                color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b, prevMA.pressed ? 0.30 : 0.14)
                border.width: 1; border.color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b, 0.5)
                AppIcon { anchors.centerIn: parent; name: "ui-skip-back"; size: 24; color: theme.textPrimary }
                MouseArea { id: prevMA; anchors.fill: parent; onClicked: if (w.avail) media.previous() }
            }
            Rectangle {
                Layout.preferredWidth: theme.touchPrimary; Layout.preferredHeight: theme.touchPrimary
                radius: width / 2; color: w.effAccent
                scale: playMA.pressed ? 0.95 : 1.0
                Behavior on scale { NumberAnimation { duration: theme.motionFast } }
                AppIcon { anchors.centerIn: parent; name: (w.avail && media.playing) ? "ui-pause" : "ui-play"
                    size: 30; color: "#0D1117" }
                MouseArea { id: playMA; anchors.fill: parent; onClicked: if (w.avail) media.playPause() }
            }
            // Next - matching circular touch button.
            Rectangle {
                Layout.preferredWidth: theme.touchSecondary; Layout.preferredHeight: theme.touchSecondary
                radius: width / 2
                color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b, nextMA.pressed ? 0.30 : 0.14)
                border.width: 1; border.color: Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b, 0.5)
                AppIcon { anchors.centerIn: parent; name: "ui-skip-fwd"; size: 24; color: theme.textPrimary }
                MouseArea { id: nextMA; anchors.fill: parent; onClicked: if (w.avail) media.next() }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
