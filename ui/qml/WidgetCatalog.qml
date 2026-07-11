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

    // category is used to group the picker. icon is an emoji glyph.
    property var items: [
        // System / hardware (real metrics from the Rust core)
        { type: "cpu",     title: "CPU",      icon: "🖥", category: "System", source: "qrc:/qml/CpuWidget.qml",     defaults: {} },
        { type: "gpu",     title: "GPU",      icon: "🎮", category: "System", source: "qrc:/qml/GpuWidget.qml",     defaults: {} },
        { type: "ram",     title: "Memory",   icon: "🧠", category: "System", source: "qrc:/qml/RamWidget.qml",     defaults: {} },
        { type: "net",     title: "Network",  icon: "📡", category: "System", source: "qrc:/qml/NetWidget.qml",     defaults: {} },
        { type: "disk",    title: "Disk",     icon: "💽", category: "System", source: "qrc:/qml/DiskWidget.qml",    defaults: {} },
        { type: "sensors", title: "Sensors",  icon: "📊", category: "System", source: "qrc:/qml/SensorsWidget.qml", defaults: {} },

        // Time / ambient
        { type: "clock",   title: "Clock",       icon: "🕐", category: "Time", source: "qrc:/qml/ClockWidget.qml",   defaults: {} },
        { type: "analog",  title: "Analog Clock",icon: "🕰", category: "Time", source: "qrc:/qml/AnalogClockWidget.qml", defaults: {} },
        { type: "moon",    title: "Moon Phase",  icon: "🌙", category: "Time", source: "qrc:/qml/MoonWidget.qml",    defaults: {} },

        // Focus / productivity (persisted user data)
        { type: "focus",    title: "Focus Timer", icon: "🎯", category: "Focus", source: "qrc:/qml/FocusWidget.qml",    defaults: { preset: "classic", phase: "work", running: false, endEpoch: 0, pausedRemaining: 1500, doneToday: 0, day: "" } },
        { type: "tasks",    title: "Tasks",       icon: "✅", category: "Focus", source: "qrc:/qml/TasksWidget.qml",    defaults: { items: [] } },
        { type: "rightnow", title: "Right Now",   icon: "🎈", category: "Focus", source: "qrc:/qml/RightNowWidget.qml", defaults: { text: "" } },
        { type: "notes",    title: "Quick Note",  icon: "📝", category: "Focus", source: "qrc:/qml/NotesWidget.qml",    defaults: { text: "" } },
        { type: "habit",    title: "Habit Streak",icon: "🔥", category: "Focus", source: "qrc:/qml/HabitWidget.qml",     defaults: { checkins: [] } },
        { type: "hydration",title: "Hydration",   icon: "💧", category: "Focus", source: "qrc:/qml/HydrationWidget.qml", defaults: { goal: 8, count: 0, day: "" } },
        { type: "break",    title: "Break Reminder", icon: "☕", category: "Focus", source: "qrc:/qml/BreakWidget.qml",  defaults: { intervalMin: 30 } },

        // Media
        { type: "media",    title: "Now Playing", icon: "🎵", category: "Media", source: "qrc:/qml/MediaWidget.qml", defaults: {} },

        // Info
        { type: "calendar", title: "Calendar",    icon: "📅", category: "Info", source: "qrc:/qml/CalendarWidget.qml",  defaults: { url: "" } },
        { type: "weather",  title: "Weather",     icon: "⛅", category: "Info", source: "qrc:/qml/WeatherWidget.qml",  defaults: { lat: 52.52, lon: 13.405, place: "Berlin" } },
        { type: "countdown",title: "Countdown",   icon: "⏳", category: "Info", source: "qrc:/qml/CountdownWidget.qml", defaults: { label: "", date: "" } },
        { type: "eod",      title: "End of Day",  icon: "🌆", category: "Info", source: "qrc:/qml/EndOfDayWidget.qml",  defaults: { startHour: 9, endHour: 17 } },
        { type: "quote",    title: "Daily Quote", icon: "💬", category: "Info", source: "qrc:/qml/QuoteWidget.qml",    defaults: {} }
    ]

    function def(type) {
        for (var i = 0; i < items.length; i++)
            if (items[i].type === type) return items[i]
        return null
    }
    function source(type) { var d = def(type); return d ? d.source : "" }
    function title(type)  { var d = def(type); return d ? d.title : type }
    function icon(type)   { var d = def(type); return d ? d.icon : "❓" }
    function defaults(type) { var d = def(type); return d ? d.defaults : ({}) }

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
