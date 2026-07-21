import QtQuick

// BackdropLayer - picks the active animated background style. `running` toggles
// motion (off for reduce-motion → the style renders static). "none"/"gradient"
// load nothing (the theme gradient shows through). Styles are declared in
// ui/qml/BackgroundCatalog.qml (keep this map in sync with it).
//
// The seven original styles live in their own ui/qml/widgets/*Background.qml
// files. The three character styles below (peaks/loops/ribbons) are INLINE
// components instead: a separate file is only reachable at runtime once it is
// aliased in BOTH ui/qml.qrc and manager/manager.qrc, and this file is already in
// both - so inlining is what makes them ship to the hub and the Manager together,
// with no chance of a file/resource drift.
//
// Every style is tinted from `accent` (+ other theme tokens), never from a fixed
// palette, so each one works under ANY theme. The motifs are original geometry -
// they gesture at a distribution's shape language, they do not reproduce anyone's
// mark.
//
// QML does not allow nested inline components, so each style's building block
// (PeakRidge / LightRibbon) is declared at the top level here and takes its motion
// gate as an explicit `running` property rather than reading the enclosing style's
// id.
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
        "mesh": meshC, "aurora": auroraC, "bokeh": bokehC, "grid": gridC,
        "arch": peaksC, "fedora": loopsC, "aubergine": ribbonsC
    })
    // Gate on `visible` too: when a wallpaper is set (or High-Contrast hides the
    // backdrop) the host sets visible:false - without this the chosen backdrop
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
    Component { id: peaksC;   PeaksBackground { } }
    Component { id: loopsC;   LoopsBackground { } }
    Component { id: ribbonsC; RibbonsBackground { } }

    // ── Peaks building block ─────────────────────────────────────────────────
    // One parallax ridgeline: drawn ONCE into a Canvas one full period wider than
    // the viewport, then scrolled by exactly that period. No per-frame repaint.
    component PeakRidge: Item {
        id: rg
        property bool running: true
        property color tint: "#ffffff"
        property real period: 520      // horizontal repeat distance
        property real amp: 90
        property real baseY: 0.72      // fraction of height the ridge sits at
        property real speed: 40000
        property real op: 0.3
        property real seed: 0
        anchors.fill: parent
        // The silhouette + its tint are baked into the Canvas texture, so a
        // theme/accent change needs an explicit repaint - a colour binding would
        // never reach the cached pixels.
        onTintChanged: rc.requestPaint()
        onOpChanged: rc.requestPaint()

        function tri(t) { var f = t - Math.floor(t); return 1 - Math.abs(2 * f - 1) }
        // Two triangle waves whose frequencies are both whole multiples of one
        // `period`, so height(x) === height(x + period) exactly. That identity is
        // what lets the scroll below wrap without a visible seam.
        function ridgeY(x) {
            var u = x / rg.period
            return 0.62 * tri(u * 2 + rg.seed) + 0.38 * tri(u * 5 + rg.seed * 1.7)
        }

        Canvas {
            id: rc
            height: parent.height
            width: rg.period + parent.width + 4
            onPaint: {
                var ctx = getContext('2d')
                ctx.clearRect(0, 0, width, height)
                if (width <= 0 || height <= 0) return
                var by = height * rg.baseY, x
                ctx.beginPath()
                ctx.moveTo(0, height)
                for (x = 0; x <= width; x += 4)
                    ctx.lineTo(x, by - rg.ridgeY(x) * rg.amp)
                ctx.lineTo(width, height)
                ctx.closePath()
                var g = ctx.createLinearGradient(0, by - rg.amp, 0, height)
                g.addColorStop(0, Qt.rgba(rg.tint.r, rg.tint.g, rg.tint.b, rg.op))
                g.addColorStop(1, Qt.rgba(rg.tint.r, rg.tint.g, rg.tint.b, rg.op * 0.15))
                ctx.fillStyle = g
                ctx.fill()
                // A brighter crest line - without it the layers read as flat blobs
                // rather than peaks once they overlap.
                ctx.beginPath()
                for (x = 0; x <= width; x += 4) {
                    var cy = by - rg.ridgeY(x) * rg.amp
                    if (x === 0) ctx.moveTo(x, cy); else ctx.lineTo(x, cy)
                }
                ctx.lineWidth = 1.5
                ctx.strokeStyle = Qt.rgba(rg.tint.r, rg.tint.g, rg.tint.b, Math.min(1, rg.op * 2.2))
                ctx.stroke()
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
            // Scroll by exactly one period → seamless loop (see ridgeY).
            NumberAnimation on x {
                running: rg.running; loops: Animation.Infinite
                from: 0; to: -rg.period; duration: rg.speed; easing.type: Easing.Linear
            }
        }
    }

    // ── Ribbons building block ───────────────────────────────────────────────
    // One soft band of light on a shallow diagonal: drawn ONCE, scrolled by one
    // wavelength on the GPU. No per-frame repaint.
    component LightRibbon: Item {
        id: rn
        property bool running: true
        property color tint: "#ffffff"
        property real wavelength: 700
        property real amp: 55
        property real band: 24         // ribbon half-thickness
        property real baseY: 0.5
        property real speed: 30000
        property real op: 0.3
        property real tilt: -8
        // Oversized + centred so the tilt can never swing an unpainted corner of
        // the canvas into view.
        anchors.centerIn: parent
        width: parent ? parent.width * 1.5 : 0
        height: parent ? parent.height * 1.5 : 0
        rotation: tilt
        onTintChanged: rc.requestPaint()
        onOpChanged: rc.requestPaint()

        Canvas {
            id: rc
            height: rn.height
            width: rn.wavelength + rn.width + 4
            onPaint: {
                var ctx = getContext('2d')
                ctx.clearRect(0, 0, width, height)
                if (width <= 0 || height <= 0) return
                var by = height * rn.baseY
                ctx.lineCap = 'round'
                ctx.lineJoin = 'round'
                // Canvas cannot gradient-fill along a stroke, so softness comes
                // from over-stroking the same path with widening, fading passes.
                // It is a one-off cost, paid once per resize - hence enough passes
                // to read as a smooth falloff; at 5 the steps were visible as
                // contour lines inside each ribbon.
                var passes = 16
                for (var p = passes; p >= 1; p--) {
                    ctx.beginPath()
                    for (var x = 0; x <= width; x += 8) {
                        // Both terms have period `wavelength`, so the scroll below
                        // wraps seamlessly.
                        var yv = by + Math.sin((x / rn.wavelength) * 2 * Math.PI) * rn.amp
                                    + Math.sin((x / rn.wavelength) * 4 * Math.PI + 1.1) * rn.amp * 0.22
                        if (x === 0) ctx.moveTo(x, yv); else ctx.lineTo(x, yv)
                    }
                    ctx.lineWidth = rn.band * (p / passes) * 2.2
                    ctx.strokeStyle = Qt.rgba(rn.tint.r, rn.tint.g, rn.tint.b, rn.op / passes)
                    ctx.stroke()
                }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
            NumberAnimation on x {
                running: rn.running; loops: Animation.Infinite
                from: 0; to: -rn.wavelength; duration: rn.speed; easing.type: Easing.Linear
            }
        }
    }

    // ── Peaks ────────────────────────────────────────────────────────────────
    // Parallax ridgelines receding into haze. Cost: one Canvas paint per ridge per
    // resize; while running, four GPU translates and zero repaints.
    component PeaksBackground: Item {
        id: pk
        property bool active: true
        property color accent: theme.accent
        clip: true

        // Far ridges are paler and slower - depth comes from parallax, not blur.
        PeakRidge { running: pk.active; tint: pk.accent;         baseY: 0.56; amp: 130; period: 620; speed: 96000; op: 0.15; seed: 0.0 }
        PeakRidge { running: pk.active; tint: theme.accent2;     baseY: 0.69; amp: 100; period: 480; speed: 64000; op: 0.21; seed: 0.35 }
        PeakRidge { running: pk.active; tint: pk.accent;         baseY: 0.81; amp: 78;  period: 380; speed: 44000; op: 0.29; seed: 0.7 }
        PeakRidge { running: pk.active; tint: theme.catServices; baseY: 0.93; amp: 58;  period: 300; speed: 30000; op: 0.35; seed: 0.15 }
    }

    // ── Loops ────────────────────────────────────────────────────────────────
    // Concentric rings swelling out of the centre and burning off at the rim.
    // Cost: no Canvas at all; 9 rounded Rectangles whose geometry updates each
    // frame. That is a QSGNode geometry rebuild rather than a pure transform -
    // chosen deliberately: driving `scale` instead would shrink border.width with
    // it and make the inner rings sub-pixel and shimmery. Nine nodes per frame is
    // far below any repaint-based approach.
    component LoopsBackground: Item {
        id: lp
        property bool active: true
        property color accent: theme.accent
        clip: true

        readonly property int count: 9
        readonly property real maxD: Math.max(1, Math.hypot(width, height)) * 1.05

        Repeater {
            model: lp.count
            delegate: Rectangle {
                required property int index
                // Phase, not a from/to animation: when `active` goes false the
                // phase simply holds and the rings stay standing at their distinct
                // radii - i.e. the static frame still reads as concentric loops.
                property real phase: 0.0
                readonly property real f: ((index / lp.count) + phase) % 1.0

                color: "transparent"
                antialiasing: true
                border.width: 1.6
                border.color: index % 3 === 0 ? lp.accent
                            : index % 3 === 1 ? theme.accent2
                            : theme.catServices
                width: lp.maxD * (0.05 + f * 0.95)
                height: width
                radius: width / 2
                x: lp.width / 2 - width / 2
                y: lp.height / 2 - height / 2
                // Fade in near the centre AND out at the rim, so the wrap from f=1
                // back to f=0 is never visible as a pop.
                opacity: Math.min(1, f * 7) * (1 - f) * 0.8

                NumberAnimation on phase {
                    running: lp.active; loops: Animation.Infinite
                    from: 0.0; to: 1.0; duration: 26000; easing.type: Easing.Linear
                }
            }
        }
    }

    // ── Ribbons ──────────────────────────────────────────────────────────────
    // Soft sinuous bands of light crossing on a shallow diagonal. Cost: one Canvas
    // paint per ribbon per resize; while running, four GPU translates and zero
    // repaints.
    component RibbonsBackground: Item {
        id: rb
        property bool active: true
        property color accent: theme.accent
        clip: true

        LightRibbon { running: rb.active; tint: rb.accent;             baseY: 0.30; amp: 46; band: 20; wavelength: 760; speed: 31000; op: 0.34; tilt: -7 }
        LightRibbon { running: rb.active; tint: theme.catProductivity; baseY: 0.48; amp: 62; band: 28; wavelength: 620; speed: 39000; op: 0.30; tilt: -11 }
        LightRibbon { running: rb.active; tint: theme.accent2;         baseY: 0.62; amp: 38; band: 16; wavelength: 880; speed: 27000; op: 0.26; tilt: 6 }
        LightRibbon { running: rb.active; tint: theme.catGaming;       baseY: 0.78; amp: 54; band: 24; wavelength: 700; speed: 35000; op: 0.28; tilt: 9 }
    }
}
