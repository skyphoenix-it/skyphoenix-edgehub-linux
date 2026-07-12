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
        { v: "grid",   l: "Neon Grid" }
    ]
}
