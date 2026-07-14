import QtQuick

// ─────────────────────────────────────────────────────────────────────────
// WidgetCatalog — the registry of available widgets.
//
// Each entry is defined ONCE here and reused everywhere: the dashboard grid,
// the expanded overlay, and the edit-mode "add widget" picker. `source` is the
// qrc path to the widget's QML file (all widgets live under qrc:/qml/ via
// qml.qrc aliases). `defaults` seeds a fresh instance's persisted settings.
// ─────────────────────────────────────────────────────────────────────────
QtObject {
    id: catalog

    // `category` groups the picker; icons are SVGs resolved by `type` via AppIcon.
    property var items: [
        // System / hardware (real metrics from the Rust core)
        { type: "cpu",     title: "CPU",      category: "System", source: "qrc:/qml/CpuWidget.qml",     defaults: {} },
        { type: "gpu",     title: "GPU",      category: "System", source: "qrc:/qml/GpuWidget.qml",     defaults: {} },
        { type: "ram",     title: "Memory",   category: "System", source: "qrc:/qml/RamWidget.qml",     defaults: {} },
        { type: "net",     title: "Network",  category: "System", source: "qrc:/qml/NetWidget.qml",     defaults: {} },
        { type: "disk",    title: "Disk",     category: "System", source: "qrc:/qml/DiskWidget.qml",    defaults: {} },
        { type: "sensors", title: "Sensors",  category: "System", source: "qrc:/qml/SensorsWidget.qml", defaults: {} },

        // Time / ambient
        { type: "clock",   title: "Clock",       category: "Time", source: "qrc:/qml/ClockWidget.qml",   defaults: {} },
        { type: "analog",  title: "Analog Clock",category: "Time", source: "qrc:/qml/AnalogClockWidget.qml", defaults: {} },
        { type: "moon",    title: "Moon Phase",  category: "Time", source: "qrc:/qml/MoonWidget.qml",    defaults: {} },

        // Focus / productivity (persisted user data)
        { type: "focus",    title: "Focus Timer", category: "Focus", source: "qrc:/qml/FocusWidget.qml",    defaults: { preset: "classic", phase: "work", running: false, endEpoch: 0, pausedRemaining: 1500, doneToday: 0, day: "" } },
        { type: "tasks",    title: "Tasks",       category: "Focus", source: "qrc:/qml/TasksWidget.qml",    defaults: { items: [] } },
        { type: "rightnow", title: "Right Now",   category: "Focus", source: "qrc:/qml/RightNowWidget.qml", defaults: { text: "" } },
        { type: "notes",    title: "Quick Note",  category: "Focus", source: "qrc:/qml/NotesWidget.qml",    defaults: { text: "" } },
        { type: "habit",    title: "Habit Streak",category: "Focus", source: "qrc:/qml/HabitWidget.qml",     defaults: { checkins: [] } },
        { type: "hydration",title: "Hydration",   category: "Focus", source: "qrc:/qml/HydrationWidget.qml", defaults: { goal: 8, count: 0, day: "" } },
        { type: "break",    title: "Break Reminder", category: "Focus", source: "qrc:/qml/BreakWidget.qml",  defaults: { intervalMin: 30 } },

        // Media
        { type: "media",    title: "Now Playing", category: "Media", source: "qrc:/qml/MediaWidget.qml", defaults: {} },

        // Data (generic, connect-anything primitives — devs, homelab, enterprise)
        { type: "httpjson", title: "HTTP / JSON", category: "Data", source: "qrc:/qml/HttpJsonWidget.qml",
          defaults: { url: "", jsonPath: "", pollSec: 60, mode: "value", unit: "", gaugeMax: 100, listMax: 5, authToken: "", warnAt: "", critAt: "" } },
        { type: "kpi",      title: "KPI",         category: "Data", source: "qrc:/qml/KpiWidget.qml",
          defaults: { source: "http", url: "", filePath: "", jsonPath: "", label: "", unit: "", pollSec: 60, authToken: "", invert: false, warnAt: "", critAt: "" } },

        // Info
        { type: "calendar", title: "Calendar",    category: "Info", source: "qrc:/qml/CalendarWidget.qml",  defaults: { url: "" } },
        { type: "weather",  title: "Weather",     category: "Info", source: "qrc:/qml/WeatherWidget.qml",  defaults: { lat: 52.52, lon: 13.405, place: "Berlin" } },
        { type: "countdown",title: "Countdown",   category: "Info", source: "qrc:/qml/CountdownWidget.qml", defaults: { label: "", date: "", repeatYearly: false } },
        { type: "eod",      title: "End of Day",  category: "Info", source: "qrc:/qml/EndOfDayWidget.qml",  defaults: { startHour: 9, endHour: 17, progressStyle: "bar" } },
        { type: "quote",    title: "Daily Quote", category: "Info", source: "qrc:/qml/QuoteWidget.qml",    defaults: { category: "focus", customText: "" } }
    ]

    // One-line descriptions shown in the expanded (full-screen) view header.
    readonly property var _desc: ({
        "cpu": "Live processor load and temperature, straight from the kernel.",
        "gpu": "Discrete GPU utilization and temperature (AMD Radeon).",
        "ram": "How much system memory is in use right now.",
        "net": "Live upload and download throughput across your network interfaces.",
        "disk": "How full your root filesystem is.",
        "sensors": "CPU, GPU, memory, disk and temperatures together at a glance.",
        "clock": "The current time and date.",
        "analog": "A classic analog clock face.",
        "moon": "Tonight's moon phase and how illuminated it is.",
        "focus": "A Pomodoro focus timer with work and break cycles. Pick a preset and press Start — it keeps running even if you close this view.",
        "tasks": "A simple checklist. Type a task and press Add; tap the circle to complete, ✕ to remove.",
        "rightnow": "The single most important thing you're doing right now. Type it and press Save.",
        "notes": "A quick scratchpad — type anything and it saves automatically.",
        "habit": "Build a daily streak. Press Check in each day you do the habit.",
        "hydration": "Count glasses of water toward a daily goal; use − / + to adjust.",
        "break": "A repeating reminder to take a break. Set the interval with − / +.",
        "httpjson": "Poll any URL and show a value from its JSON — as a number, a gauge, or a list. Colour-codes against thresholds.",
        "kpi": "One headline number from a URL or a local file, with a label, unit and colour-coded thresholds.",
        "calendar": "Upcoming events from a calendar you subscribe to. Paste an ICS URL to connect it.",
        "weather": "Current conditions and a multi-day forecast. Type a city and look up its coordinates.",
        "countdown": "Counts the days to a date you choose. Set a label and date below.",
        "eod": "How much of your workday is left. Adjust your start and end hours.",
        "media": "Now Playing — controls Spotify, YouTube Music, or any player on this machine.",
        "quote": "A fresh bit of motivation each day."
    })

    function def(type) {
        for (var i = 0; i < items.length; i++)
            if (items[i].type === type) return items[i]
        return null
    }
    function source(type) { var d = def(type); return d ? d.source : "" }
    function title(type)  { var d = def(type); return d ? d.title : type }
    function desc(type)   { return _desc[type] || "" }
    // Deep clone so callers can freely mutate the seed without aliasing the
    // catalog's live object (or every future instance seeded from it).
    function defaults(type) { var d = def(type); return d ? JSON.parse(JSON.stringify(d.defaults)) : ({}) }

    // Distinct category names, in declaration order.
    function categories() {
        var seen = [], out = []
        for (var i = 0; i < items.length; i++) {
            if (seen.indexOf(items[i].category) === -1) { seen.push(items[i].category); out.push(items[i].category) }
        }
        return out
    }
    function inCategory(cat) {
        var out = []
        for (var i = 0; i < items.length; i++) if (items[i].category === cat) out.push(items[i])
        return out
    }
}
