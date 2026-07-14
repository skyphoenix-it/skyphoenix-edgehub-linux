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
// A tile spec is { type, w?, h?, settings? }. Appearance only sets the preset's
// *character* (bgStyle / animatedBg / reduceMotion / gridCols) — never themeMode/
// accent, so applying a preset preserves the user's chosen colours. Every tile
// `type` MUST exist in WidgetCatalog (a QML test asserts it).
//
// Presets marked "⟶ enrich" gain data-connected tiles (HTTP/JSON, KPI, etc.) once
// the v1.0 primitive widgets (E1) and new wellness widgets (E5) land; today they
// are composed from the 22 shipping widgets.
// ─────────────────────────────────────────────────────────────────────────
QtObject {
    id: presets

    // Character presets kept DRY.
    readonly property var _calm:  ({ bgStyle: "none",  animatedBg: false, reduceMotion: true,  glow: false })
    readonly property var _ambient: ({ bgStyle: "orbs",  animatedBg: true,  reduceMotion: false, glow: true })
    readonly property var _tech:  ({ bgStyle: "grid",  animatedBg: true,  reduceMotion: false, glow: true })
    readonly property var _soft:  ({ bgStyle: "orbs",  animatedBg: false, reduceMotion: false, glow: true })

    property var items: [
        { id: "calm-focus", title: "Calm Focus", icon: "🧘",
          blurb: "Deep work, quietly. A big timer, your one thing, and a place to dump distractions.",
          appearance: _calm, surfaced: ["Focus"],
          pages: [ { name: "Focus", tiles: [
              { type: "focus", h: 2 }, { type: "rightnow" }, { type: "notes" }, { type: "habit" } ] } ] },

        { id: "home-ambient", title: "Home & Ambient", icon: "🏠",
          blurb: "A beautiful desk companion — time, weather, what's playing, and tonight's moon.",
          appearance: _ambient, surfaced: ["Time", "Media", "Info"],
          pages: [ { name: "Home", tiles: [
              { type: "clock" }, { type: "weather" }, { type: "media" }, { type: "moon" } ] } ] },

        { id: "remote-work", title: "Remote Work", icon: "💼",
          blurb: "Stay on top of the day — the time, your calendar, today's tasks, and how much workday is left.",
          appearance: _calm, surfaced: ["Time", "Info", "Focus"],
          pages: [ { name: "Work", tiles: [
              { type: "clock" }, { type: "calendar" }, { type: "tasks" },
              { type: "eod", settings: { startHour: 9, endHour: 17, progressStyle: "bar" } } ] } ] },

        { id: "developer", title: "Developer", icon: "💻",
          blurb: "A status column for building — machine health at a glance. ⟶ enrich with CI & HTTP tiles.",
          appearance: _tech, surfaced: ["System"],
          pages: [ { name: "Dev", tiles: [
              { type: "cpu" }, { type: "ram" }, { type: "disk" }, { type: "sensors" } ] } ] },

        { id: "homelab", title: "Homelab Ops", icon: "🖥️",
          blurb: "Watch the lab — CPU, memory, network and disk. ⟶ enrich with uptime & container tiles.",
          appearance: _tech, surfaced: ["System"],
          pages: [ { name: "Ops", tiles: [
              { type: "cpu" }, { type: "ram" }, { type: "net" }, { type: "disk" }, { type: "sensors" } ] } ] },

        { id: "gaming", title: "Gaming Cockpit", icon: "🎮",
          blurb: "Rig telemetry beside your game — GPU/CPU temps, memory, network. ⟶ enrich with FPS & OBS.",
          appearance: _tech, surfaced: ["System", "Media"],
          pages: [
              { name: "System", tiles: [ { type: "gpu" }, { type: "cpu" }, { type: "ram" }, { type: "net" }, { type: "sensors" } ] },
              { name: "Play",   tiles: [ { type: "clock" }, { type: "media" } ] } ] },

        { id: "trading-desk", title: "Trading Desk", icon: "📈",
          blurb: "A glance surface for the desk — time, agenda, and workday. ⟶ enrich with market clocks & KPIs.",
          appearance: _calm, surfaced: ["Time", "Info"],
          pages: [ { name: "Desk", tiles: [
              { type: "clock" }, { type: "calendar" }, { type: "eod" }, { type: "tasks" } ] } ] },

        { id: "health", title: "Health & Routine", icon: "💧",
          blurb: "Gentle nudges toward a good day — water, breaks, and a daily streak. ⟶ enrich with meds reminder.",
          appearance: _soft, surfaced: ["Focus"],
          pages: [ { name: "Health", tiles: [
              { type: "hydration" }, { type: "break" }, { type: "habit" }, { type: "rightnow" } ] } ] },

        { id: "creator", title: "Creator / Media", icon: "🎬",
          blurb: "For making things — now-playing front and centre, a focus timer, and a spark of inspiration.",
          appearance: _ambient, surfaced: ["Media", "Focus"],
          pages: [ { name: "Studio", tiles: [
              { type: "media", h: 2 }, { type: "clock" }, { type: "focus" }, { type: "quote" } ] } ] },

        { id: "system-monitor", title: "System Monitor", icon: "📊",
          blurb: "The classic — every system gauge at a glance: CPU, GPU, memory, network, disk, sensors.",
          appearance: _tech, surfaced: ["System"],
          pages: [ { name: "System", tiles: [
              { type: "cpu" }, { type: "gpu" }, { type: "ram" }, { type: "net" }, { type: "disk" }, { type: "sensors" } ] } ] },

        { id: "minimal", title: "Minimalist", icon: "✨",
          blurb: "Almost nothing. A beautiful clock, the weather, and the moon.",
          appearance: _calm, surfaced: ["Time"],
          pages: [ { name: "Home", tiles: [
              { type: "clock", h: 2 }, { type: "weather" }, { type: "moon" } ] } ] },

        { id: "analyst", title: "Analyst / Data", icon: "📉",
          blurb: "A calm data corner — clock, agenda, workday and tasks. ⟶ enrich with KPI & monitoring tiles.",
          appearance: _calm, surfaced: ["Time", "Info", "Focus"],
          pages: [ { name: "Data", tiles: [
              { type: "clock" }, { type: "calendar" }, { type: "eod" }, { type: "tasks" } ] } ] },

        { id: "study", title: "Student / Study", icon: "📚",
          blurb: "Study sessions that stick — a focus timer, your tasks, a countdown to the exam, and a streak.",
          appearance: _soft, surfaced: ["Focus", "Info"],
          pages: [ { name: "Study", tiles: [
              { type: "focus", h: 2 }, { type: "tasks" },
              { type: "countdown", settings: { label: "Exam", date: "", repeatYearly: false } }, { type: "habit" } ] } ] },

        { id: "productivity", title: "Productivity", icon: "✅",
          blurb: "Get things done — focus, tasks, a habit streak and your day's progress, with system stats a swipe away.",
          appearance: _soft, surfaced: ["Focus", "System", "Time"],
          pages: [
              { name: "Focus",  tiles: [ { type: "focus" }, { type: "tasks" }, { type: "habit" }, { type: "eod" } ] },
              { name: "System", tiles: [ { type: "cpu" }, { type: "ram" }, { type: "clock" } ] } ] },

        { id: "enterprise", title: "Enterprise / Locked", icon: "🔒",
          blurb: "A clean, managed baseline for work — time, agenda, and workday only. Designed for org policy.",
          appearance: _calm, surfaced: ["Time", "Info"],
          pages: [ { name: "Work", tiles: [
              { type: "clock" }, { type: "calendar" }, { type: "eod" } ] } ] }
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
                if (t.w) tile.w = t.w
                if (t.h) tile.h = t.h
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
