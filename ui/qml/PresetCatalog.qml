import QtQuick

// ─────────────────────────────────────────────────────────────────────────
// PresetCatalog — the curated library of ready-made "screens".
//
// Mirrors WidgetCatalog: a single registry, reused by the first-run wizard's
// "what is this screen for?" picker and by DashboardStore.seed(). Each preset is
// a DESIGNED layout — a small, purposeful set of widgets (never overloaded), a
// fitting background/motion character, and (optionally) which widget categories
// to feature in the add-picker. `buildDoc(id)` materializes a full ui_state
// document (with fresh tile ids) that the store applies verbatim.
//
// A tile spec is { type, size?, settings? }. `size` is a name from WidgetSizes and
// MUST be one the type declares in WidgetCatalog; omit it for the type's default.
// Appearance only sets the preset's *character* (bgStyle / animatedBg /
// reduceMotion) — never themeMode/accent, so applying a preset preserves the user's
// chosen colours. Every tile `type` MUST exist in WidgetCatalog (a QML test asserts
// both).
//
// EVERY PAGE FITS ON ONE SCREEN. A page's tiles may not exceed
// WidgetSizes.longHalves (6 half-cells) along the long axis — three `1x1` fill a
// screen exactly, and a hero `1x1.5` plus a `1x1.5` companion does too. This is a
// hard product constraint, asserted by tst_preset_catalog against the real
// WidgetPacker, not a style note:
//
//   the scroll axis follows the LONG axis, which in the default 2560x720 landscape
//   is the SAME axis as the SwipeView's page swipe. On an overflowing landscape page
//   the inner Flickable wins the drag and the PageIndicator becomes the only way to
//   change pages. A page that fits never scrolls, so the conflict cannot arise.
//
// The budget is why a preset SPLITS across pages rather than dropping a widget:
// four widgets is two pages, and every widget a preset intends to show still ships.
//
// Data-connected presets (developer, homelab, trading-desk, analyst, enterprise)
// carry HTTP/JSON + KPI tiles with a purposeful `title` but a BLANK url/filePath:
// the endpoint is the one thing only the user can supply, so the tile ships as a
// labelled, self-explaining slot ("CI status" → "Add a URL in settings") rather
// than a wrong guess. Nothing polls until it is connected.
//
// Presets still marked "⟶ enrich" gain tiles from later epics (E5 wellness, and
// the post-1.0 integration packs); today they use the shipping widgets.
// ─────────────────────────────────────────────────────────────────────────
QtObject {
    id: presets

    // Character presets kept DRY.
    readonly property var _calm:  ({ bgStyle: "none",  animatedBg: false, reduceMotion: true,  glow: false })
    readonly property var _ambient: ({ bgStyle: "orbs",  animatedBg: true,  reduceMotion: false, glow: true })
    readonly property var _tech:  ({ bgStyle: "grid",  animatedBg: true,  reduceMotion: false, glow: true })
    readonly property var _soft:  ({ bgStyle: "orbs",  animatedBg: false, reduceMotion: false, glow: true })

    property var items: [
        // `focus` tops out at 1x1.5 — the hero timer is the largest the widget
        // renders, not the largest size there is.
        { id: "calm-focus", title: "Calm Focus", icon: "🧘",
          blurb: "Deep work, quietly. A big timer beside your one thing — with a scratchpad and your streak a swipe away.",
          appearance: _calm, surfaced: ["Focus"],
          pages: [
              { name: "Focus", tiles: [
                  { type: "focus", size: "1x1.5" }, { type: "rightnow", size: "1x1.5" } ] },
              { name: "Notes", tiles: [
                  { type: "notes", size: "1x2" }, { type: "habit", size: "1x1" } ] } ] },

        { id: "home-ambient", title: "Home & Ambient", icon: "🏠",
          blurb: "A beautiful desk companion — the time and the weather up front, what's playing and tonight's moon a swipe away.",
          appearance: _ambient, surfaced: ["Time", "Media", "Info"],
          pages: [
              { name: "Home",    tiles: [
                  { type: "clock", size: "1x1.5" }, { type: "weather", size: "1x1.5" } ] },
              { name: "Ambient", tiles: [
                  { type: "media", size: "1x1.5" }, { type: "moon", size: "1x1" } ] } ] },

        { id: "remote-work", title: "Remote Work", icon: "💼",
          blurb: "Stay on top of the day — the time and your calendar, then today's tasks and how much workday is left.",
          appearance: _calm, surfaced: ["Time", "Info", "Focus"],
          pages: [
              { name: "Work", tiles: [
                  { type: "clock", size: "1x1" }, { type: "calendar", size: "1x2" } ] },
              { name: "Day",  tiles: [
                  { type: "tasks", size: "1x1.5" },
                  { type: "eod", size: "1x1.5", settings: { startHour: 9, endHour: 17, progressStyle: "bar" } } ] } ] },

        { id: "developer", title: "Developer", icon: "💻",
          blurb: "Your build and your box — CI status and a number you watch, with machine health a swipe away.",
          appearance: _tech, surfaced: ["Data", "System"],
          pages: [
              { name: "Dev", tiles: [
                  { type: "httpjson", size: "1x1.5", settings: { title: "CI status", mode: "list", listMax: 5, pollSec: 120 } },
                  { type: "kpi", size: "1x1.5", settings: { title: "Open PRs", label: "Open PRs", pollSec: 300 } } ] },
              // Two half-width gauges pair across the short axis; first fit backfills
              // the second beside the first rather than starting a new row.
              { name: "Box", tiles: [
                  { type: "cpu", size: "0.5x1" }, { type: "ram", size: "0.5x1" },
                  { type: "disk", size: "1x1" } ] } ] },

        { id: "homelab", title: "Homelab Ops", icon: "🖥️",
          blurb: "Watch the lab — service uptime and container health, with CPU, memory, network and disk a swipe away.",
          appearance: _tech, surfaced: ["Data", "System"],
          pages: [
              { name: "Services", tiles: [
                  { type: "httpjson", size: "1x1.5", settings: { title: "Uptime", mode: "list", listMax: 6, pollSec: 60 } },
                  { type: "httpjson", size: "1x1.5", settings: { title: "Containers", mode: "list", listMax: 6, pollSec: 60 } } ] },
              { name: "Machine",  tiles: [
                  { type: "cpu", size: "1x1.5" }, { type: "ram", size: "1x1.5" } ] },
              { name: "Traffic",  tiles: [
                  { type: "net", size: "1x1.5" }, { type: "disk", size: "1x1" } ] } ] },

        { id: "gaming", title: "Gaming Cockpit", icon: "🎮",
          blurb: "Rig telemetry beside your game — the GPU front and centre, CPU and memory, network and temps, and what's playing. ⟶ enrich with FPS & OBS.",
          appearance: _tech, surfaced: ["System", "Media"],
          pages: [
              { name: "GPU",    tiles: [
                  { type: "gpu", size: "1x1.5" },
                  { type: "cpu", size: "0.5x1" }, { type: "ram", size: "0.5x1" } ] },
              { name: "System", tiles: [
                  { type: "net", size: "1x1" }, { type: "sensors", size: "1x1.5" } ] },
              { name: "Play",   tiles: [
                  { type: "clock", size: "1x1" }, { type: "media", size: "1x1.5" } ] } ] },

        { id: "trading-desk", title: "Trading Desk", icon: "📈",
          blurb: "The desk at a glance — your time and the market's beside your P&L, with exposure and what's next a swipe away.",
          appearance: _calm, surfaced: ["Time", "Data", "Info"],
          pages: [
              { name: "Desk", tiles: [
                  // The two zones sit side by side — one glance, two clocks.
                  { type: "clock", size: "0.5x1" },
                  { type: "clock", size: "0.5x1", settings: { title: "New York", customZone: true, zoneId: "America/New_York" } },
                  { type: "kpi", size: "1x1.5", settings: { title: "P&L", label: "P&L", unit: "%", pollSec: 60 } } ] },
              { name: "Next", tiles: [
                  { type: "kpi", size: "1x1", settings: { title: "Exposure", label: "Exposure", pollSec: 60 } },
                  { type: "calendar", size: "1x2" } ] } ] },

        // hydration/break/habit all top out at 1x1 — three of them fill the page
        // exactly, which is the blurb's promise in one screen.
        { id: "health", title: "Health & Routine", icon: "💧",
          blurb: "Gentle nudges toward a good day — water, breaks, and a daily streak, with your one thing a swipe away. ⟶ enrich with meds reminder.",
          appearance: _soft, surfaced: ["Focus"],
          pages: [
              { name: "Health",    tiles: [
                  { type: "hydration", size: "1x1" }, { type: "break", size: "1x1" },
                  { type: "habit", size: "1x1" } ] },
              { name: "Right Now", tiles: [
                  { type: "rightnow", size: "1x1.5" } ] } ] },

        { id: "creator", title: "Creator / Media", icon: "🎬",
          blurb: "For making things — now-playing front and centre and a focus timer, with the time and a spark of inspiration a swipe away.",
          appearance: _ambient, surfaced: ["Media", "Focus"],
          pages: [
              { name: "Studio", tiles: [
                  { type: "media", size: "1x1.5" }, { type: "focus", size: "1x1.5" } ] },
              { name: "Desk",   tiles: [
                  { type: "clock", size: "1x1" }, { type: "quote", size: "1x1.5" } ] } ] },

        { id: "system-monitor", title: "System Monitor", icon: "📊",
          blurb: "The classic — CPU, GPU and memory at a glance, with network, disk and sensors a swipe away.",
          appearance: _tech, surfaced: ["System"],
          pages: [
              { name: "Core", tiles: [
                  { type: "cpu", size: "1x1" }, { type: "gpu", size: "1x1" },
                  { type: "ram", size: "1x1" } ] },
              { name: "I/O",  tiles: [
                  { type: "net", size: "1x1" }, { type: "disk", size: "1x1" },
                  { type: "sensors", size: "1x1" } ] } ] },

        { id: "minimal", title: "Minimalist", icon: "✨",
          blurb: "Almost nothing. A beautiful clock, the weather, and the moon.",
          appearance: _calm, surfaced: ["Time"],
          pages: [ { name: "Home", tiles: [
              { type: "clock", size: "1x1.5" },
              { type: "weather", size: "0.5x1" }, { type: "moon", size: "0.5x1" } ] } ] },

        { id: "analyst", title: "Analyst / Data", icon: "📉",
          blurb: "A calm data corner — two headline numbers and a monitoring feed, with the time and your tasks a swipe away.",
          appearance: _calm, surfaced: ["Data", "Time", "Focus"],
          pages: [
              { name: "Data", tiles: [
                  { type: "kpi", size: "1x1.5", settings: { title: "Headline metric", label: "Headline metric", source: "http", pollSec: 300 } },
                  // The file source reads a local path — a fully offline KPI (no egress).
                  { type: "kpi", size: "0.5x1", settings: { title: "Daily total", label: "Daily total", source: "file", pollSec: 60 } },
                  { type: "httpjson", size: "0.5x1", settings: { title: "Monitoring", mode: "value", pollSec: 120 } } ] },
              { name: "Desk", tiles: [
                  { type: "clock", size: "1x1" }, { type: "tasks", size: "1x1.5" } ] } ] },

        { id: "study", title: "Student / Study", icon: "📚",
          blurb: "Study sessions that stick — a focus timer and your tasks, with a countdown to the exam and your streak a swipe away.",
          appearance: _soft, surfaced: ["Focus", "Info"],
          pages: [
              { name: "Study", tiles: [
                  { type: "focus", size: "1x1.5" }, { type: "tasks", size: "1x1.5" } ] },
              { name: "Goals", tiles: [
                  { type: "countdown", size: "1x1.5", settings: { label: "Exam", date: "", repeatYearly: false } },
                  { type: "habit", size: "1x1" } ] } ] },

        { id: "productivity", title: "Productivity", icon: "✅",
          blurb: "Get things done — focus and tasks, your streak and the day's progress, with system stats a swipe away.",
          appearance: _soft, surfaced: ["Focus", "System", "Time"],
          pages: [
              { name: "Focus",  tiles: [
                  { type: "focus", size: "1x1.5" }, { type: "tasks", size: "1x1.5" } ] },
              { name: "Day",    tiles: [
                  { type: "habit", size: "1x1" }, { type: "eod", size: "1x1.5" } ] },
              { name: "System", tiles: [
                  { type: "cpu", size: "1x1" }, { type: "ram", size: "1x1" },
                  { type: "clock", size: "1x1" } ] } ] },

        { id: "enterprise", title: "Enterprise / Locked", icon: "🔒",
          blurb: "A clean, managed baseline for work — the time and your agenda, with your workday and one approved team number a swipe away.",
          appearance: _calm, surfaced: ["Time", "Info", "Data"],
          pages: [
              { name: "Work", tiles: [
                  { type: "clock", size: "1x1" }, { type: "calendar", size: "1x2" } ] },
              { name: "Team", tiles: [
                  { type: "eod", size: "1x1.5" },
                  // "Approved KPI/monitoring tiles only" — a KPI the org points at its
                  // own endpoint. The egress primitives stay governed by NetHub's
                  // allowlist.
                  { type: "kpi", size: "1x1.5", settings: { title: "Team KPI", label: "Team KPI", pollSec: 300 } } ] } ] }
    ]

    // ── API (mirrors WidgetCatalog) ─────────────────────────────────────────
    function list() { return items }
    function def(id) {
        for (var i = 0; i < items.length; i++) if (items[i].id === id) return items[i]
        return null
    }
    function has(id) { return def(id) !== null }

    // Materialize a preset into a full ui_state document with fresh, unique tile
    // ids. Appearance is the preset's character + a `presetSurface` hint; per-tile
    // `settings` are copied under the generated id. The store's _normaliseDoc
    // hardens the result, so a malformed preset can never corrupt the dashboard.
    //
    // A tile carries its `size` straight through. Presets used to emit the old
    // {w,h} spans and lean on the store's migration to name them, which is lossy by
    // construction (old `h` was a ratio against siblings, a size is a fraction of
    // the screen) — it mapped `h:2` to `1x2` and, for a type that does not declare
    // it, dropped the tile to its default. A preset is authored, not migrated: it
    // names the size it means, and the test asserts the type declares it.
    function buildDoc(id) {
        var p = def(id)
        if (!p) return null
        var seq = 0
        var pages = []
        var settings = ({})
        for (var pi = 0; pi < p.pages.length; pi++) {
            var src = p.pages[pi]
            var tiles = []
            for (var ti = 0; ti < src.tiles.length; ti++) {
                var t = src.tiles[ti]
                var tid = t.type + "-" + (++seq)
                var tile = { "id": tid, "type": t.type }
                if (t.size) tile.size = t.size
                tiles.push(tile)
                if (t.settings) settings[tid] = JSON.parse(JSON.stringify(t.settings))
            }
            pages.push({ "name": src.name, "tiles": tiles })
        }
        var appearance = p.appearance ? JSON.parse(JSON.stringify(p.appearance)) : ({})
        if (p.surfaced && p.surfaced.length) appearance.presetSurface = p.surfaced.slice()
        return { "version": 1, "appearance": appearance, "settings": settings, "pages": pages }
    }
}
