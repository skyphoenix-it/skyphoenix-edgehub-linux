import QtQuick
import QtQuick.Layouts

// MetricGauge — the shared visual for the system metric tiles (CPU/GPU/RAM).
// A large ring gauge with the value in the centre + a live sparkline, so the
// tile fills its box richly instead of floating a lone number.
//
// Sizing (W1 wave 2a): the host widget keys the knobs below off its injected
// `sizeClass`; the defaults reproduce the original stacked layout, so existing
// consumers (HttpJsonWidget) render unchanged.
//   • showSpark:false  — micro (0.5x0.5): the ring IS the tile; no sparkline
//     slot is reserved at all.
//   • horizontal:true  — wide: ring beside the sparkline, which finally gets
//     real width instead of a 30px strip under the ring.
//   • sparkFrac        — tall: the sparkline's share of the box; tall tiles
//     raise it so the history earns genuine height.
Item {
    id: g
    property real value: 0          // 0..1 for the ring
    property string big: ""         // centre value, e.g. "42%"
    property string sub: ""         // supporting line, e.g. "avg 34% · peak 87%"
    property color color: theme.accent
    property var history: []        // 0..1 samples for the sparkline
    property bool expanded: false
    property bool ok: true          // false → dim (e.g. GPU N/A)

    // Per-size layout knobs (see header note). Defaults = the original layout.
    property bool showSpark: true
    property bool horizontal: false
    property real sparkFrac: 0.17
    // Tall tiles: pin the ring to a square cell at the top and hand the
    // sparkline ALL the remaining height — history earns the height, and the
    // ring no longer floats in a stretched void. Only meaningful stacked.
    property bool sparkFills: false
    // Cap for the centre value font when collapsed (micro tiles raise it so the
    // one number actually fills its headerless box).
    property real bigMax: 60

    // Threshold escalation (accent → warning → error) cross-fades the ring, the
    // big number and the sparkline together instead of hard-cutting all three.
    // Collapses to an instant cut under reduce-motion (motionValue token → 0).
    Behavior on color { ColorAnimation { duration: theme.motionValue } }

    // ring.width is 0 until the layout settles; fall back to the gauge's own
    // size so centre text is never rendered at 0px (invisible) on the 1st frame.
    readonly property real _ringW: ring.width > 0 ? ring.width : Math.min(g.width, g.height)

    GridLayout {
        anchors.fill: parent
        anchors.margins: g.expanded ? theme.spacingMd : theme.spacingXs
        columns: g.horizontal ? 2 : 1
        rowSpacing: g.expanded ? theme.spacingMd : theme.spacingSm
        columnSpacing: theme.spacingMd

        // Ring + centred value fills the bulk of the tile (all of it at micro).
        Item {
            id: ringCell
            readonly property bool square: g.sparkFills && !g.horizontal && g.showSpark
            Layout.fillWidth: !g.horizontal
            Layout.fillHeight: !square
            // Side-by-side: the ring takes a square cell sized by the box height
            // (capped at ~2/5 of the width so the sparkline keeps the majority).
            Layout.preferredWidth: g.horizontal ? Math.round(Math.min(g.height, g.width * 0.42)) : -1
            // Tall: a square cell up top; the sparkline below takes the rest.
            Layout.preferredHeight: square ? Math.round(Math.min(g.width, g.height * 0.62)) : -1
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
                    // Cap the value to the ring's INNER diameter and shrink to fit.
                    // The system tiles only ever pass short readings ("42%", "N/A"),
                    // which never reach the cap; an HTTP/JSON gauge shows arbitrary
                    // values ("128ms"), which used to spill out over the ring.
                    Layout.maximumWidth: Math.max(24, g._ringW - 2 * ring.thickness - 8)
                    font.pixelSize: Math.min(g._ringW * 0.34, g.expanded ? 108 : g.bigMax)
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
                    Layout.maximumWidth: Math.max(24, g._ringW - 2 * ring.thickness - 8)
                    // Scale gently with the ring so a big tall-tile ring doesn't
                    // caption itself in 14px dust.
                    font.pixelSize: g.expanded ? 20 : Math.max(12, Math.min(g._ringW * 0.075, 18))
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 9
                    elide: Text.ElideRight
                    color: theme.textSecondary
                }
            }
        }

        // History sparkline — under the ring (stacked) or beside it (wide). The
        // stacked slot always reserves its height (even while the sparkline
        // itself is hidden) so the fillHeight ring above does not visibly shrink
        // when the sparkline pops in at the 2nd sample.
        Item {
            visible: g.showSpark
            Layout.fillWidth: true
            Layout.fillHeight: g.horizontal || (g.sparkFills && !g.horizontal)
            Layout.preferredHeight: (g.horizontal || g.sparkFills) ? -1
                                  : (g.expanded ? 110 : Math.max(30, g.height * g.sparkFrac))
            Sparkline {
                anchors.fill: parent
                values: g.history
                color: g.color
                visible: g.ok && g.history && g.history.length > 1
            }
        }
    }
}
