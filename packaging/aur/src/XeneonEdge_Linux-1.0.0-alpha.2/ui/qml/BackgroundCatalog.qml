import QtQuick

// BackgroundCatalog — the list of animated background styles, shared by the hub's
// SettingsPanel, the Manager's pickers, and BackdropLayer's style→component map.
// `v` is the persisted value (appearance.bgStyle / page.bg.style); `l` the label.
QtObject {
    readonly property var styles: [
        { v: "none",   l: "Gradient" },
        { v: "orbs",   l: "Aurora Orbs" },
        { v: "mesh",   l: "Mesh" },
        { v: "aurora", l: "Aurora Curtains" },
        { v: "waves",  l: "Waves" },
        { v: "stars",  l: "Starfield" },
        { v: "bokeh",  l: "Bokeh" },
        { v: "grid",   l: "Neon Grid" },

        // Character styles. Each is ORIGINAL abstract geometry that gestures at a
        // distribution's shape language — none reproduces, traces or approximates
        // anyone's logo, and all of them take their colour from the theme accent
        // rather than a distributor's palette, so they work under any theme.
        // Names are nominative where that is uncontroversial, and evocative for
        // the one whose owner enforces hardest.
        //
        // A particle-spiral ("vortex") motif was prototyped and dropped: however
        // it was tuned, the wound core kept reading as a swirl device, which is
        // exactly the shape language these styles must stay clear of.
        { v: "arch",      l: "Arch Peaks" },
        { v: "fedora",    l: "Fedora Loops" },
        { v: "aubergine", l: "Aubergine Ribbons" }
    ]
}
