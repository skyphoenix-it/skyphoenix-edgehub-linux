import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: schema:zoneId

// ClockWidget — verifies every config option actually changes what's shown:
// 12/24-hour, seconds, date visibility + style, and the world clock (real IANA
// zones with daylight-saving, plus the legacy fixed-offset model).
//
// The zone instants below are PINNED, never `new Date()`: a DST test that runs
// against "today" asserts nothing for 10 months of the year. Expected offsets are
// ground truth from the IANA database (cross-checked with Python zoneinfo).
Item {
    width: 420; height: 300
    WidgetHarness { id: h; anchors.fill: parent; widgetFile: "ClockWidget.qml"; expanded: true }
    App.WidgetConfigSchema { id: sc }

    TestCase {
        name: "ClockWidget"
        when: windowShown

        function init() {
            tryVerify(function () { return h.ready }, 3000)
            var s = h.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            h.storeCtl._touchSettings()
        }
        function set(k, v) { h.storeCtl.setSetting("test-instance", k, v) }

        function test_12h_vs_24h() {
            var w = h.item
            set("format24", false)
            verify(w.timeFmt.indexOf("h:mm") >= 0, "12h uses h:mm")
            verify(w.timeFmt.indexOf("AP") >= 0, "12h shows AM/PM")
            verify(w.timeFmt.indexOf("HH") < 0)
            set("format24", true)
            verify(w.timeFmt.indexOf("HH:mm") >= 0, "24h uses HH:mm")
            verify(w.timeFmt.indexOf("AP") < 0, "24h has no AM/PM")
        }

        function test_show_seconds() {
            var w = h.item
            set("showSeconds", false)
            verify(w.timeFmt.indexOf("ss") < 0, "no seconds by default")
            set("showSeconds", true)
            verify(w.timeFmt.indexOf("ss") >= 0, "seconds added to the format")
        }

        function test_date_style() {
            var w = h.item
            set("dateStyle", "short")
            compare(w.dateFmt, "dd/MM", "short date style")
            set("dateStyle", "full")
            verify(w.dateFmt.indexOf("MMM") >= 0, "full date style uses a month name")
        }

        // The bug this epic exists for: a fixed offset cannot follow daylight saving,
        // so a "New York" clock built from utcOffset:-5 is an hour wrong for ~8 months.
        // A real zone must report DIFFERENT offsets in winter and summer.
        function test_dst_zone_offset_follows_the_season() {
            var w = h.item
            var jan = new Date(Date.UTC(2026, 0, 15, 12, 0, 0))
            var jul = new Date(Date.UTC(2026, 6, 15, 12, 0, 0))

            compare(w.zoneOffsetAt("America/New_York", jan), -5, "New York is UTC-5 in January (EST)")
            compare(w.zoneOffsetAt("America/New_York", jul), -4, "New York is UTC-4 in July (EDT)")
            verify(w.zoneOffsetAt("America/New_York", jan) !== w.zoneOffsetAt("America/New_York", jul),
                   "a DST zone's offset is not constant across the year")

            compare(w.zoneOffsetAt("Europe/London", jan), 0, "London is UTC+0 in January (GMT)")
            compare(w.zoneOffsetAt("Europe/London", jul), 1, "London is UTC+1 in July (BST)")

            // Southern hemisphere: DST is INVERTED — summer is January.
            compare(w.zoneOffsetAt("Australia/Sydney", jan), 11, "Sydney is UTC+11 in January (AEDT)")
            compare(w.zoneOffsetAt("Australia/Sydney", jul), 10, "Sydney is UTC+10 in July (AEST)")
            compare(w.zoneOffsetAt("Pacific/Auckland", jan), 13, "Auckland is UTC+13 in January (NZDT)")
            compare(w.zoneOffsetAt("Pacific/Auckland", jul), 12, "Auckland is UTC+12 in July (NZST)")

            // Zones with no DST law must stay put across the same instants.
            compare(w.zoneOffsetAt("Asia/Tokyo", jan), 9, "Tokyo has no DST")
            compare(w.zoneOffsetAt("Asia/Tokyo", jul), 9, "Tokyo has no DST")
            compare(w.zoneOffsetAt("Asia/Kolkata", jan), 5.5, "Mumbai is a half-hour zone, no DST")
            compare(w.zoneOffsetAt("Asia/Kolkata", jul), 5.5, "Mumbai is a half-hour zone, no DST")
        }

        // The switchover must land on the exact tzdata instant, not merely somewhere
        // in the right month — an off-by-one-week rule is invisible to a season test.
        // US law: 2nd Sunday March 02:00 local → 1st Sunday November 02:00 local.
        function test_dst_transition_instants_are_exact() {
            var w = h.item
            var z = "America/New_York"
            compare(w.zoneOffsetAt(z, new Date(Date.UTC(2026, 2, 8, 6, 59, 59))), -5, "still EST one second before spring-forward")
            compare(w.zoneOffsetAt(z, new Date(Date.UTC(2026, 2, 8, 7, 0, 0))), -4, "EDT exactly at spring-forward (07:00 UTC)")
            compare(w.zoneOffsetAt(z, new Date(Date.UTC(2026, 10, 1, 5, 59, 59))), -4, "still EDT one second before fall-back")
            compare(w.zoneOffsetAt(z, new Date(Date.UTC(2026, 10, 1, 6, 0, 0))), -5, "EST exactly at fall-back (06:00 UTC)")
            // The rule is a law, not a 2026 lookup: a different year moves the date.
            compare(w.zoneOffsetAt(z, new Date(Date.UTC(2027, 2, 14, 6, 59, 59))), -5, "2027 spring-forward is a week later (Mar 14)")
            compare(w.zoneOffsetAt(z, new Date(Date.UTC(2027, 2, 14, 7, 0, 0))), -4, "2027 spring-forward at 07:00 UTC")
            // EU law differs from US: last Sunday, and at 01:00 UTC everywhere.
            compare(w.zoneOffsetAt("Europe/Berlin", new Date(Date.UTC(2026, 2, 29, 0, 59, 59))), 1, "Berlin CET until 01:00 UTC")
            compare(w.zoneOffsetAt("Europe/Berlin", new Date(Date.UTC(2026, 2, 29, 1, 0, 0))), 2, "Berlin CEST at 01:00 UTC, last Sunday March")
        }

        // A saved config predates zoneId, so it carries ONLY customZone/utcOffset.
        // It must keep meaning exactly what it meant: a fixed offset.
        function test_legacy_fixed_offset_config_still_honoured() {
            var w = h.item
            set("customZone", true)
            set("utcOffset", 5.5)
            compare(w.zoneId, "", "a legacy config has no zoneId")
            var jan = new Date(Date.UTC(2026, 0, 15, 12, 0, 0))
            var jul = new Date(Date.UTC(2026, 6, 15, 12, 0, 0))
            compare(w.effectiveOffsetAt(jan), 5.5, "legacy offset honoured, not reinterpreted")
            compare(w.effectiveOffsetAt(jul), 5.5, "a fixed offset stays fixed all year (the old contract)")
        }

        // A picked zone must WIN over any stale utcOffset left in the same config.
        function test_zone_id_overrides_the_legacy_offset() {
            var w = h.item
            set("customZone", true)
            set("utcOffset", -5)
            set("zoneId", "America/New_York")
            compare(w.zoneId, "America/New_York", "zoneId is read from config")
            compare(w.effectiveOffsetAt(new Date(Date.UTC(2026, 6, 15, 12, 0, 0))), -4,
                    "the real zone's summer offset wins over the stale -5")
        }

        // A zone this build cannot map (a newer build's config) must fall back to the
        // user's own offset rather than silently snapping the clock to UTC.
        function test_unknown_zone_falls_back_to_the_offset() {
            var w = h.item
            set("customZone", true)
            set("utcOffset", 3)
            set("zoneId", "Mars/Olympus_Mons")
            compare(w.zoneOffsetAt("Mars/Olympus_Mons", new Date(Date.UTC(2026, 0, 15))), undefined, "unknown zone has no offset")
            compare(w.effectiveOffsetAt(new Date(Date.UTC(2026, 0, 15))), 3, "falls back to the configured offset")
        }

        // Every city offered in the config form must be a zone the widget can map,
        // otherwise picking it would silently fall back to the fixed offset.
        function test_every_schema_zone_is_known_to_the_widget() {
            var w = h.item
            var schema = sc.schemaFor("clock")
            var field = null
            for (var s = 0; s < schema.sections.length; s++) {
                var fields = schema.sections[s].fields || []
                for (var f = 0; f < fields.length; f++)
                    if (fields[f].key === "zoneId") field = fields[f]
            }
            verify(field !== null, "the clock schema offers a zoneId field")
            verify(field.options.length > 1, "it offers cities, not just the fixed-offset entry")
            for (var i = 0; i < field.options.length; i++) {
                var v = field.options[i].value
                if (v === "") continue
                verify(w.zoneTable.hasOwnProperty(v), "schema city '" + v + "' exists in the widget's zone table")
            }
        }

        // The wall clock shown must actually be the zone's, not just the offset maths.
        function test_zoned_time_renders_the_target_wall_clock() {
            var w = h.item
            set("customZone", true)
            set("zoneId", "America/New_York")
            // 2026-07-15 16:30 UTC is 12:30 in New York (EDT, UTC-4).
            var t = new Date(Date.UTC(2026, 6, 15, 16, 30, 0))
            compare(Qt.formatTime(w.zonedAt(t), "HH:mm"), "12:30", "renders New York's wall clock in July")
            // The same instant in January (16:30 UTC) is 11:30 EST — one hour earlier.
            var winter = new Date(Date.UTC(2026, 0, 15, 16, 30, 0))
            compare(Qt.formatTime(w.zonedAt(winter), "HH:mm"), "11:30", "and its winter wall clock")
            // Local mode is untouched by any of this.
            set("customZone", false)
            compare(w.zonedAt(t).getTime(), t.getTime(), "local mode returns the instant unchanged")
        }

        // Rendering shifts the instant and lets Qt format it in LOCAL time, so the
        // shift can jump across the HOST's own DST switch and print an hour out.
        // Asserted against the host's real transitions, whatever zone CI runs in:
        // the wall clock must be the target's at every hour around each local switch.
        function test_rendering_survives_the_hosts_own_dst_switch() {
            var w = h.item
            set("customZone", true)
            set("zoneId", "Asia/Tokyo") // always UTC+9, so any error is the host's doing
            function localOffMs(ms) { return -new Date(ms).getTimezoneOffset() * 60000 }
            // The host's own 2026 transitions, discovered from its offset.
            var switches = []
            for (var t = Date.UTC(2026, 0, 1); t < Date.UTC(2027, 0, 1); t += 3600000)
                if (localOffMs(t) !== localOffMs(t - 3600000)) switches.push(t)
            // A UTC host has no switches; the July probe then covers the flat case.
            var probes = switches.concat([Date.UTC(2026, 6, 15)])
            var asserted = 0
            for (var s = 0; s < probes.length; s++) {
                for (var k = -14; k <= 14; k++) {
                    var at = new Date(probes[s] + k * 3600000)
                    // Wall clock the tile must show, as an "as-if-UTC" epoch.
                    var wall = at.getTime() + 9 * 3600000
                    // Skip only a wall time the host CANNOT represent: its spring-forward
                    // gap. Derived from the host's transitions, never from whether the
                    // assertion happens to fail (that would hide the very bug this guards).
                    var inGap = false
                    for (var g = 0; g < switches.length; g++) {
                        var before = localOffMs(switches[g] - 1000), after = localOffMs(switches[g])
                        if (after <= before) continue // fall-back: no gap
                        var gapStart = switches[g] + before
                        if (wall >= gapStart && wall < gapStart + (after - before)) inGap = true
                    }
                    if (inGap) continue
                    var exp = new Date(wall)
                    compare(Qt.formatTime(w.zonedAt(at), "HH:mm"),
                            ("0" + exp.getUTCHours()).slice(-2) + ":" + ("0" + exp.getUTCMinutes()).slice(-2),
                            "Tokyo wall clock at " + at.toISOString() + " (near the host's DST switch)")
                    asserted++
                }
            }
            verify(asserted >= 29, "the probe actually asserted (got " + asserted + ")")
        }

        // The label falls back to the picked zone's city, so a tile is never a
        // nameless foreign time; the offset chip tracks DST.
        function test_zone_city_and_offset_label() {
            var w = h.item
            set("customZone", true)
            set("zoneId", "Asia/Tokyo")
            compare(w.zoneCity(), "Tokyo", "city derived from the zone id")
            compare(w.offsetLabel(new Date(Date.UTC(2026, 0, 15))), "UTC+9", "Tokyo is always UTC+9")
            set("zoneId", "America/New_York")
            compare(w.offsetLabel(new Date(Date.UTC(2026, 0, 15))), "UTC-5", "New York reads UTC-5 in winter")
            compare(w.offsetLabel(new Date(Date.UTC(2026, 6, 15))), "UTC-4", "and UTC-4 in summer")
            set("zoneId", "Asia/Kolkata")
            compare(w.offsetLabel(new Date(Date.UTC(2026, 0, 15))), "UTC+5:30", "half-hour zones keep their minutes")
        }

        function test_world_clock_offset() {
            var w = h.item
            set("customZone", false)
            // local: zonedNow ≈ now
            verify(Math.abs(w.zonedNow().getTime() - Date.now()) < 2000, "local mode = now")
            set("customZone", true)
            set("utcOffset", 5)
            var local = new Date()
            var utcMs = local.getTime() + local.getTimezoneOffset() * 60000
            var expected = utcMs + 5 * 3600000
            verify(Math.abs(w.zonedNow().getTime() - expected) < 2000,
                   "world-clock time equals UTC+5")
            // A different offset gives a different time.
            set("utcOffset", -8)
            var expected2 = utcMs - 8 * 3600000
            verify(Math.abs(w.zonedNow().getTime() - expected2) < 2000, "UTC-8 differs correctly")
        }

        function test_zone_label_default() {
            var w = h.item
            set("customZone", true)
            compare(w.zoneLabel, "", "no label by default")
            verify(w.offsetLabel().indexOf("UTC") >= 0, "falls back to a UTC offset label")
            set("zoneLabel", "Tokyo")
            compare(w.zoneLabel, "Tokyo")
        }
    }
}
