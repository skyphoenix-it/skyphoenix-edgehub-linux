import QtQuick

// WallpaperCatalog - the set of bundled "standard" page backgrounds that ship
// with the app (720×2560, tuned to the built-in themes). Shared by the hub's
// SettingsPanel and the Manager so both offer the same list. User-uploaded
// images (via the Manager) are listed separately by the Manager itself.
QtObject {
    readonly property var items: [
        { name: "midnight", label: "Midnight", source: "qrc:/wallpapers/midnight.png",
          recommendedThemes: ["midnight", "tokyonight"] },
        { name: "nebula", label: "Nebula", source: "qrc:/wallpapers/nebula.png",
          recommendedThemes: ["nebula", "synthwave"] },
        { name: "aurora", label: "Aurora", source: "qrc:/wallpapers/aurora.png",
          recommendedThemes: ["aurora", "matrix"] },
        { name: "ocean", label: "Ocean", source: "qrc:/wallpapers/ocean.png",
          recommendedThemes: ["deep_ocean", "solarized", "fedora"] },
        { name: "teal", label: "Teal", source: "qrc:/wallpapers/teal.png",
          recommendedThemes: ["deep_forest", "cyberpunk"] },
        { name: "sunset", label: "Sunset", source: "qrc:/wallpapers/sunset.png",
          recommendedThemes: ["sunset", "aubergine"] },
        { name: "ember", label: "Ember", source: "qrc:/wallpapers/ember.png",
          recommendedThemes: ["ember", "gruvbox"] },
        { name: "grape", label: "Grape", source: "qrc:/wallpapers/grape.png",
          recommendedThemes: ["dracula", "catppuccin", "vaporwave"] },
        { name: "blossom", label: "Blossom", source: "qrc:/wallpapers/blossom.png",
          recommendedThemes: ["rose_gold", "debian"] },
        { name: "graphite", label: "Graphite", source: "qrc:/wallpapers/graphite.png",
          recommendedThemes: ["dark", "oled", "high_contrast", "arch"] },
        { name: "slate", label: "Slate", source: "qrc:/wallpapers/slate.png",
          recommendedThemes: ["nord", "cachyos"] },
        { name: "daylight", label: "Daylight", source: "qrc:/wallpapers/daylight.png",
          recommendedThemes: ["light"] },
        // Xeneon-suited graphics: dark, sleek, gaming-tech. Center/diagonal-composed
        // so they crop well in both 720x2560 and 2560x720.
        { name: "edge-cyan", label: "Cyan Edge", source: "qrc:/wallpapers/edge-cyan.png",
          recommendedThemes: ["cyberpunk"] },
        { name: "edge-ember", label: "Ember Edge", source: "qrc:/wallpapers/edge-ember.png",
          recommendedThemes: ["crimson", "popos"] },
        { name: "aurora-veil", label: "Aurora Veil", source: "qrc:/wallpapers/aurora-veil.png",
          recommendedThemes: ["aurora", "vaporwave"] },
        { name: "grid-horizon", label: "Grid Horizon", source: "qrc:/wallpapers/grid-horizon.png",
          recommendedThemes: ["fedora", "tokyonight"] },
        { name: "techdots", label: "Tech Grid", source: "qrc:/wallpapers/techdots.png",
          recommendedThemes: ["arch", "cachyos", "matrix"] },
        { name: "prism", label: "Prism", source: "qrc:/wallpapers/prism.png",
          recommendedThemes: ["catppuccin", "synthwave"] }
    ]
}
