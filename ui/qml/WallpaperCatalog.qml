import QtQuick

// WallpaperCatalog — the set of bundled "standard" page backgrounds that ship
// with the app (720×2560, tuned to the built-in themes). Shared by the hub's
// SettingsPanel and the Manager so both offer the same list. User-uploaded
// images (via the Manager) are listed separately by the Manager itself.
QtObject {
    readonly property var items: [
        { name: "midnight", label: "Midnight", source: "qrc:/wallpapers/midnight.png" },
        { name: "nebula",   label: "Nebula",   source: "qrc:/wallpapers/nebula.png" },
        { name: "aurora",   label: "Aurora",   source: "qrc:/wallpapers/aurora.png" },
        { name: "ocean",    label: "Ocean",    source: "qrc:/wallpapers/ocean.png" },
        { name: "teal",     label: "Teal",     source: "qrc:/wallpapers/teal.png" },
        { name: "sunset",   label: "Sunset",   source: "qrc:/wallpapers/sunset.png" },
        { name: "ember",    label: "Ember",    source: "qrc:/wallpapers/ember.png" },
        { name: "grape",    label: "Grape",    source: "qrc:/wallpapers/grape.png" },
        { name: "blossom",  label: "Blossom",  source: "qrc:/wallpapers/blossom.png" },
        { name: "graphite", label: "Graphite", source: "qrc:/wallpapers/graphite.png" },
        { name: "slate",    label: "Slate",    source: "qrc:/wallpapers/slate.png" },
        { name: "daylight", label: "Daylight", source: "qrc:/wallpapers/daylight.png" }
    ]
}
