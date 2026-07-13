import QtQuick

// WidgetConfigSchema — declarative config schema per widget type, shared by the
// on-device (hub) config view and the desktop Manager. The config renderer turns
// these into a professional, sectioned form. Field types:
//   text | textarea | number | slider | toggle | segmented | date | hour |
//   tasks | action | info | accent
// Fields may carry `help` (a one-line hint under the label). Every widget gets a
// "General" section (custom title) and an "About" section describing it.
//
// IMPORTANT: every option here is honoured by the corresponding widget — nothing
// is decorative. Keep keys in sync with the widget's `cfg` reads + catalog defaults.
QtObject {
    id: sc

    function titleSection(def) {
        return { title: "General", cols: 1, fields: [
            { key: "title", label: "Custom title", type: "text", placeholder: def,
              help: "Shown in the widget header. Leave blank for the default." } ] }
    }
    function about(text) {
        return { title: "About this widget", cols: 1, fields: [ { type: "info", text: text } ] }
    }
    // Universal per-widget appearance — added to EVERY widget so any of them can
    // be given its own accent + an animated in-card backdrop to stand out.
    function appearanceSection() {
        return { title: "Widget appearance", cols: 1,
            desc: "Give this widget its own look so it stands out.", fields: [
            { key: "accent", label: "Accent colour", type: "accent", dflt: "",
              help: "Recolours this widget's icon, glow and highlights." },
            { key: "cardBackdrop", label: "Card backdrop", type: "segmented", dflt: "none",
              help: "A subtle animated backdrop inside this widget's card.", options: [
                { value: "none", label: "None" }, { value: "orbs", label: "Orbs" },
                { value: "mesh", label: "Mesh" }, { value: "aurora", label: "Aurora" },
                { value: "waves", label: "Waves" }, { value: "stars", label: "Stars" },
                { value: "bokeh", label: "Bokeh" }, { value: "grid", label: "Grid" } ] } ] }
    }

    // Public entry: the per-type schema PLUS the universal appearance section.
    function schemaFor(type) {
        var s = _schemaFor(type)
        if (s && s.sections)
            s.sections.push(appearanceSection())
        return s
    }

    function _schemaFor(type) {
        switch (type) {

        case "clock": return { sections: [
            { title: "Display", cols: 1, fields: [
                { key: "format24", label: "24-hour clock", type: "toggle", dflt: false },
                { key: "showSeconds", label: "Show seconds", type: "toggle", dflt: false },
                { key: "showDate", label: "Show the date", type: "toggle", dflt: true },
                { key: "dateStyle", label: "Date style", type: "segmented", dflt: "full", options: [
                    { value: "full",  label: "Weekday, 5 Jan" },
                    { value: "short", label: "05/01" } ] } ] },
            { title: "Time zone (world clock)", cols: 1,
              desc: "Show another city's time instead of your local time.", fields: [
                { key: "customZone", label: "Use a specific time zone", type: "toggle", dflt: false },
                { key: "zoneLabel", label: "Zone name", type: "text", placeholder: "New York", dflt: "",
                  help: "A label shown above the time (e.g. the city)." },
                { key: "utcOffset", label: "UTC offset", type: "slider", min: -12, max: 14, step: 0.5, suffix: " h", dflt: 0,
                  help: "Hours from UTC (½-hour steps for zones like India +5:30). A fixed offset, so it doesn't follow daylight-saving changes." } ] },
            titleSection("Clock"),
            about("A digital clock. Choose 12/24-hour, seconds, and how the date is shown.") ] }

        case "analog": return { sections: [
            { title: "Display", cols: 1, fields: [
                { key: "showSeconds", label: "Show the second hand", type: "toggle", dflt: true },
                { key: "showNumerals", label: "Show hour numerals", type: "toggle", dflt: false } ] },
            titleSection("Analog Clock"),
            about("A classic analog clock face.") ] }

        case "moon": return { sections: [
            { title: "Location", cols: 1, fields: [
                { key: "hemisphere", label: "Hemisphere", type: "segmented", dflt: "north",
                  help: "Flips the illuminated side to match your sky.", options: [
                    { value: "north", label: "Northern" },
                    { value: "south", label: "Southern" } ] } ] },
            titleSection("Moon Phase"),
            about("Tonight's moon phase and how illuminated it is.") ] }

        case "cpu": return { sections: [
            { title: "Display", cols: 1, fields: [
                { key: "showTemp", label: "Show temperature", type: "toggle", dflt: true },
                { key: "showHistory", label: "Show the history graph", type: "toggle", dflt: true },
                { key: "warnTemp", label: "Warn above", type: "slider", min: 60, max: 100, step: 1, suffix: " °C", dflt: 85,
                  help: "The reading turns amber above this temperature." } ] },
            titleSection("CPU"),
            about("Live processor load and temperature, straight from the kernel.") ] }

        case "gpu": return { sections: [
            { title: "Display", cols: 1, fields: [
                { key: "showTemp", label: "Show temperature", type: "toggle", dflt: true },
                { key: "showHistory", label: "Show the history graph", type: "toggle", dflt: true },
                { key: "warnTemp", label: "Warn above", type: "slider", min: 60, max: 110, step: 1, suffix: " °C", dflt: 90,
                  help: "The reading turns amber above this temperature." } ] },
            titleSection("GPU"),
            about("Discrete GPU utilization and temperature.") ] }

        case "ram": return { sections: [
            { title: "Display", cols: 1, fields: [
                { key: "unit", label: "Center reading", type: "segmented", dflt: "percent", options: [
                    { value: "percent", label: "Percent" },
                    { value: "gb", label: "GB used" } ] },
                { key: "showHistory", label: "Show the history graph", type: "toggle", dflt: true } ] },
            titleSection("Memory"),
            about("How much system memory is in use right now.") ] }

        case "net": return { sections: [
            { title: "Display", cols: 1, fields: [
                { key: "showHistory", label: "Show the throughput graph", type: "toggle", dflt: true },
                { key: "unit", label: "Units", type: "segmented", dflt: "bytes", options: [
                    { value: "bytes", label: "MB/s" },
                    { value: "bits",  label: "Mbps" } ] } ] },
            titleSection("Network"),
            about("Live upload and download throughput across your network interfaces.") ] }

        case "disk": return { sections: [
            { title: "Display", cols: 1, fields: [
                { key: "warnPercent", label: "Warn above", type: "slider", min: 50, max: 99, step: 1, suffix: " %", dflt: 90,
                  help: "The ring turns amber above this fill level." } ] },
            titleSection("Disk"),
            about("How full your root filesystem is.") ] }

        case "sensors": return { sections: [
            { title: "Rows to show", cols: 1, fields: [
                { key: "showCpu", label: "CPU load", type: "toggle", dflt: true },
                { key: "showGpu", label: "GPU load", type: "toggle", dflt: true },
                { key: "showRam", label: "Memory", type: "toggle", dflt: true },
                { key: "showDisk", label: "Disk usage", type: "toggle", dflt: true },
                { key: "showTemps", label: "Temperatures", type: "toggle", dflt: true,
                  help: "CPU and GPU temperature bars (colour-coded by how hot they are)." } ] },
            titleSection("Sensors"),
            about("CPU, GPU, memory, disk and temperatures together at a glance.") ] }

        case "weather": return { sections: [
            { title: "Location", cols: 1, fields: [
                { key: "place", label: "Place name", type: "text", placeholder: "Vienna, AT" },
                { type: "action", actionLabel: "Look up this city and set coordinates", action: "geocode" } ] },
            { title: "Coordinates", cols: 2, fields: [
                { key: "lat", label: "Latitude", type: "number", min: -90, max: 90, step: 0.01, dflt: 52.52 },
                { key: "lon", label: "Longitude", type: "number", min: -180, max: 180, step: 0.01, dflt: 13.405 } ] },
            { title: "Units & forecast", cols: 1, fields: [
                { key: "units", label: "Temperature", type: "segmented", dflt: "celsius", options: [
                    { value: "celsius", label: "°C" },
                    { value: "fahrenheit", label: "°F" } ] },
                { key: "forecastDays", label: "Forecast days", type: "slider", min: 3, max: 7, step: 1, suffix: " days", dflt: 4 } ] },
            titleSection("Weather"),
            about("Current conditions and a multi-day forecast from Open-Meteo (free, no API key).") ] }

        case "focus": return { sections: [
            { title: "Custom lengths", cols: 2, desc: "Used when you pick the “Custom” preset on the timer.", fields: [
                { key: "workMin", label: "Focus", type: "number", min: 1, max: 180, step: 1, suffix: " min", dflt: 25 },
                { key: "breakMin", label: "Break", type: "number", min: 1, max: 60, step: 1, suffix: " min", dflt: 5 } ] },
            { title: "Behaviour", cols: 1, fields: [
                { key: "autoStartBreak", label: "Auto-start the break", type: "toggle", dflt: false } ] },
            { title: "Momentum (ADHD-friendly)", cols: 1,
              desc: "Small wins to keep you going.", fields: [
                { key: "dailyGoal", label: "Daily focus goal", type: "number", min: 1, max: 16, step: 1, suffix: " sessions", dflt: 4,
                  help: "Progress toward this shows on the timer; hitting it triggers a bigger celebration." },
                { key: "celebrate", label: "Celebrate finished sessions", type: "toggle", dflt: true,
                  help: "A burst of colour + a “nice!” when a focus session completes — a little dopamine hit." },
                { key: "rewardPoints", label: "Earn reward points", type: "toggle", dflt: true,
                  help: "Rack up points per session (bonus for hitting your goal)." },
                { key: "showNudges", label: "Show encouraging nudges", type: "toggle", dflt: true },
                { key: "breakSuggestions", label: "Suggest a break activity", type: "toggle", dflt: true } ] },
            titleSection("Focus Timer"),
            about("A Pomodoro focus timer. Pick a preset or set custom lengths; it keeps running even when this view is closed.") ] }

        case "tasks": return { sections: [
            { title: "Tasks", cols: 1, fields: [ { key: "items", label: "", type: "tasks" } ] },
            { title: "Display", cols: 1, fields: [
                { key: "hideCompleted", label: "Hide completed tasks", type: "toggle", dflt: false },
                { key: "celebrate", label: "Celebrate clearing the list", type: "toggle", dflt: true,
                  help: "A little burst when you check off the last task." } ] },
            titleSection("Tasks"),
            about("A simple checklist. Add tasks here or on the Edge; tap the circle to complete.") ] }

        case "hydration": return { sections: [
            { title: "Goal", cols: 1, fields: [
                { key: "goal", label: "Daily goal", type: "number", min: 1, max: 20, step: 1, suffix: " glasses", dflt: 8 },
                { key: "glassMl", label: "Glass size", type: "number", min: 100, max: 1000, step: 50, suffix: " ml", dflt: 250,
                  help: "Used to show your total volume for the day." } ] },
            titleSection("Hydration"),
            about("Count glasses of water toward a daily goal; use −/+ on the Edge to log a glass.") ] }

        case "break": return { sections: [
            { title: "Reminder", cols: 1, fields: [
                { key: "intervalMin", label: "Remind me every", type: "slider", min: 5, max: 120, step: 5, suffix: " min", dflt: 30 },
                { key: "message", label: "Reminder message", type: "text", placeholder: "Time to stretch!", dflt: "" },
                { key: "showSuggestion", label: "Suggest a break activity", type: "toggle", dflt: true,
                  help: "Shows a small “try this” idea when a break is due." } ] },
            titleSection("Break Reminder"),
            about("A repeating nudge to take a break.") ] }

        case "countdown": return { sections: [
            { title: "Event", cols: 2, fields: [
                { key: "label", label: "Label", type: "text", placeholder: "Vacation" },
                { key: "date", label: "Date", type: "date" } ] },
            { title: "Behaviour", cols: 1, fields: [
                { key: "repeatYearly", label: "Repeats every year", type: "toggle", dflt: false,
                  help: "For birthdays and anniversaries — counts down to the next occurrence and never shows “passed”." } ] },
            titleSection("Countdown"),
            about("Counts the days to a date you choose.") ] }

        case "eod": return { sections: [
            { title: "Work hours", cols: 2, fields: [
                { key: "startHour", label: "Start hour", type: "hour", min: 0, max: 23, step: 1, dflt: 9 },
                { key: "endHour", label: "End hour", type: "hour", min: 0, max: 23, step: 1, dflt: 17 } ] },
            { title: "Display", cols: 1, fields: [
                { key: "progressStyle", label: "Progress style", type: "segmented", dflt: "bar", options: [
                    { value: "bar", label: "Bar" },
                    { value: "ring", label: "Ring" } ] },
                { key: "showPercent", label: "Show percent complete", type: "toggle", dflt: true } ] },
            titleSection("End of Day"),
            about("How much of your workday is left.") ] }

        case "habit": return { sections: [
            { title: "Habit", cols: 1, fields: [
                { key: "name", label: "Habit name", type: "text", placeholder: "Meditate", dflt: "",
                  help: "What you're building a streak for." } ] },
            titleSection("Habit"),
            about("Build a daily streak. Press Check-in on the Edge each day you do the habit.") ] }

        case "rightnow": return { sections: [
            { title: "Your one thing", cols: 1, fields: [
                { key: "text", label: "", type: "text", placeholder: "Finish the report" } ] },
            titleSection("Right Now"),
            about("The single most important thing you're doing right now.") ] }

        case "notes": return { sections: [
            { title: "Note", cols: 1, fields: [
                { key: "text", label: "", type: "textarea", placeholder: "Type anything…" } ] },
            titleSection("Quick Note"),
            about("A quick scratchpad — saves automatically.") ] }

        case "calendar": return { sections: [
            { title: "Subscription", cols: 1, fields: [
                { key: "url", label: "ICS calendar URL", type: "text", placeholder: "https://…/basic.ics" },
                { type: "info", text: "Paste the secret iCal/ICS URL from Google, Outlook or Nextcloud." } ] },
            { title: "Display", cols: 1, fields: [
                { key: "maxEvents", label: "Events to show", type: "number", min: 1, max: 12, step: 1, dflt: 5 } ] },
            titleSection("Calendar"),
            about("Upcoming events from a calendar you subscribe to.") ] }

        case "media": return { sections: [
            titleSection("Now Playing"),
            about("Controls whatever is playing on the Edge's machine (Spotify, YouTube Music, …). No configuration needed.") ] }

        case "quote": return { sections: [
            { title: "Source", cols: 1, fields: [
                { key: "category", label: "Category", type: "segmented", dflt: "focus", options: [
                    { value: "focus", label: "Focus" },
                    { value: "stoic", label: "Stoic" },
                    { value: "humor", label: "Humour" },
                    { value: "kindness", label: "Kindness" },
                    { value: "custom", label: "My own" } ] },
                { key: "customText", label: "Your own quotes", type: "textarea",
                  placeholder: "One per line — add “ — Author” for attribution",
                  help: "Used when the category is “My own”. One quote per line." } ] },
            titleSection("Daily Quote"),
            about("A fresh bit of motivation each day. Pick a category or add your own; Shuffle grabs another.") ] }

        default: return { sections: [ titleSection(type) ] }
        }
    }
}
