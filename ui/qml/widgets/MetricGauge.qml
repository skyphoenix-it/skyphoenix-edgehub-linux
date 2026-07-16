import QtQuick
import QtQuick.Layouts

// MetricGauge — the shared visual for the system metric tiles (CPU/GPU/RAM/Disk).
// A large ring gauge with the value in the centre + a live sparkline underneath,
// so the tile fills its height richly instead of floating a lone number.
Item {
    id: g
    property real value: 0          // 0..1 for the ring
    property string big: ""         // centre value, e.g. "42%"
    property string sub: ""         // supporting line, e.g. "58°C · 16 cores"
    property color color: theme.accent
    property var history: []        // 0..1 samples for the sparkline
    property bool expanded: false
    property bool ok: true          // false → dim (e.g. GPU N/A)

    // Threshold escalation (accent → warning → error) cross-fades the ring, the
    // big number and the sparkline together instead of hard-cutting all three.
    // Collapses to an instant cut under reduce-motion (motionValue token → 0).
    Behavior on color { ColorAnimation { duration: theme.motionValue } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: g.expanded ? theme.spacingMd : theme.spacingXs
        spacing: g.expanded ? theme.spacingMd : theme.spacingSm

        // Ring + centred value fills the bulk of the tile.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            RingProgress {
                id: ring
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) * 0.96
                height: width
                value: g.ok ? Math.max(0, Math.min(1, g.value)) : 0
                // Metric samples land every ~2s; glide the sweep between them so
                // a CPU/GPU/RAM tick reads as movement, not a redraw. (Instant
                // under reduce-motion via the motionValue token.)
                animateValue: true
                thickness: Math.max(9, width * 0.10)
                progressColor: g.color
                progressColor2: g.color
                trackColor: Qt.rgba(theme.cardBorder.r, theme.cardBorder.g, theme.cardBorder.b, 0.6)
            }
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: g.big
                    // ring.width is 0 until the layout settles; fall back to the
                    // gauge's own size so the number is never rendered at 0px
                    // (invisible) on the first frame.
                    readonly property real _ringW: ring.width > 0 ? ring.width : Math.min(g.width, g.height)
                    // Cap the value to the ring's INNER diameter and shrink to fit.
                    // The system tiles only ever pass short readings ("42%", "N/A"),
                    // which never reach the cap; an HTTP/JSON gauge shows arbitrary
                    // values ("128ms"), which used to spill out over the ring.
                    Layout.maximumWidth: Math.max(24, _ringW - 2 * ring.thickness - 8)
                    font.pixelSize: Math.min(_ringW * 0.34, g.expanded ? 108 : 60)
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 10
                    elide: Text.ElideRight
                    font.bold: true; font.family: theme.fontMono
                    color: g.ok ? g.color : theme.textTertiary
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: g.sub.length > 0
                    text: g.sub
                    font.pixelSize: g.expanded ? 20 : 14
                    color: theme.textSecondary
                }
            }
        }

        // History sparkline hugs the bottom. The slot always reserves its height
        // (even while the sparkline itself is hidden) so the fillHeight ring above
        // does not visibly shrink when the sparkline pops in at the 2nd sample.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: g.expanded ? 110 : Math.max(30, g.height * 0.17)
            Sparkline {
                anchors.fill: parent
                values: g.history
                color: g.color
                visible: g.ok && g.history && g.history.length > 1
            }
        }
    }
}
