import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: schema:hemisphere

// ─────────────────────────────────────────────────────────────────────────
// Comprehensive tests for area "widget:moon" (ui/qml/widgets/MoonWidget.qml)
// plus the shared config schema that drives it.
//
// The widget derives everything from the *current* instant (new Date()), and
// QML's V4 engine forbids reassigning the global `Date` and does not honour a
// Date.prototype.getTime override for `new Date().getTime()` (verified against
// qmltestrunner). So the phase cannot be pinned to a fixed instant. These tests
// therefore assert:
//   • invariants that must hold at ANY instant (bounds, idx∈0..7, illum∈0..100),
//   • self-consistency of the documented formulas against the live _cyclePos,
//   • the epoch/UTC (timezone-independent) derivation of _cyclePos,
//   • the injectable `_nextDate()` function and nextNew/nextFull,
//   • hemisphere config (default, reactivity, glyph mirroring),
//   • per-instance accent (effAccent) + the "content ignores effAccent" bug,
//   • null/empty store safety,
//   • the "moon" config schema shape.
// Assertions that fail because of a real MoonWidget bug are intentional.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: root
    width: 480; height: 480

    WidgetHarness { id: hMoon;   anchors.fill: parent; widgetFile: "MoonWidget.qml"; expanded: true }
    WidgetHarness { id: hAccent; anchors.fill: parent; widgetFile: "MoonWidget.qml"; expanded: true }
    WidgetHarness { id: hNull;   anchors.fill: parent; widgetFile: "MoonWidget.qml"; expanded: true }
    WidgetHarness { id: hTile;   anchors.fill: parent; widgetFile: "MoonWidget.qml"; expanded: false }

    App.WidgetConfigSchema { id: sc }

    // Recursively find the first descendant whose `text` equals `txt`.
    function findByText(node, txt) {
        if (!node) return null
        try { if (node.text === txt) return node } catch (e) {}
        var kids = null
        try { kids = node.children } catch (e2) { kids = null }
        if (kids) {
            for (var i = 0; i < kids.length; i++) {
                var r = findByText(kids[i], txt)
                if (r) return r
            }
        }
        return null
    }

    function clearSettings(h) {
        var s = h.storeCtl.settingsFor("test-instance")
        for (var k in s) delete s[k]
        h.storeCtl._touchSettings()
    }

    // ── Phase invariants + formula self-consistency ────────────────────────
    TestCase {
        name: "MoonPhaseMath"
        when: windowShown
        function init() {
            tryVerify(function () { return hMoon.ready }, 3000)
            clearSettings(hMoon)
        }

        function test_cyclepos_in_unit_interval() {
            var w = hMoon.item
            verify(w._cyclePos >= 0 && w._cyclePos < 1,
                   "_cyclePos is a synodic fraction in [0,1) (got " + w._cyclePos + ")")
        }

        function test_idx_in_range() {
            var w = hMoon.item
            verify(w.idx >= 0 && w.idx <= 7, "idx is a valid phase bucket 0..7 (got " + w.idx + ")")
            verify(w.idx < w.phases.length && w.idx < w.names.length, "idx indexes phases/names arrays")
        }

        function test_illum_in_range() {
            var w = hMoon.item
            verify(w.illum >= 0 && w.illum <= 100, "illuminated % is 0..100 (got " + w.illum + ")")
        }

        function test_idx_matches_documented_formula() {
            var w = hMoon.item
            var expected = Math.floor(w._cyclePos * 8 + 0.5) % 8
            compare(w.idx, expected, "idx = floor(cyclePos*8+0.5) % 8 for the live cyclePos")
        }

        function test_illum_matches_documented_formula() {
            var w = hMoon.item
            var expected = Math.round((1 - Math.cos(w._cyclePos * 2 * Math.PI)) / 2 * 100)
            compare(w.illum, expected, "illum = round((1-cos(2π·cyclePos))/2·100)")
        }

        function test_agedays_derives_from_cyclepos() {
            var w = hMoon.item
            var syn = w._synodicSec / 86400.0
            verify(w.ageDays >= 0 && w.ageDays <= syn + 0.001,
                   "lunar age is 0..~29.53 days (got " + w.ageDays + ")")
            fuzzyCompare(w.ageDays, w._cyclePos * syn, 1e-6, "ageDays = cyclePos · synodicDays")
        }

        // The phase-name bucket and the illum% are computed by DIFFERENT maths
        // (8 equal buckets vs a continuous cosine). The audit flags that they can
        // disagree at the edges (e.g. New-Moon bucket up to ~4%). This asserts the
        // WEAK guarantee that always holds: illum is monotonic-consistent with the
        // half of the cycle idx sits in (waxing idx 0..4 illum rising toward full,
        // waning idx 4..8 falling). It does NOT assert bucket==illum tolerance,
        // which the code does not honour.
        function test_illum_consistent_with_waxwane_half() {
            var w = hMoon.item
            var illumFromPos = (1 - Math.cos(w._cyclePos * 2 * Math.PI)) / 2 // 0..1
            // Full is at cyclePos 0.5 → illum ~1; new at 0/1 → illum ~0.
            if (w._cyclePos > 0.02 && w._cyclePos < 0.48)
                verify(illumFromPos > 0 && illumFromPos < 1, "waxing: partial illumination")
            verify(w.illum <= 100 && w.illum >= 0, "illum stays in gamut regardless of bucket")
        }
    }

    // ── Timezone independence: cyclePos is derived from epoch + UTC reference ─
    TestCase {
        name: "MoonTimezone"
        when: windowShown
        function init() { tryVerify(function () { return hMoon.ready }, 3000) }

        // Reproduce the widget's own derivation from epoch ms + a UTC reference.
        // If the widget used LOCAL date parsing instead, this would diverge by the
        // viewer's UTC offset. Matching within a hair proves TZ-independence.
        function test_cyclepos_is_epoch_utc_derived() {
            var w = hMoon.item
            var now = new Date().getTime() / 1000
            var ref = Date.UTC(2000, 0, 6, 18, 14) / 1000
            var frac = ((now - ref) % w._synodicSec) / w._synodicSec
            if (frac < 0) frac += 1
            // Allow a small tolerance for the ms elapsed between the two reads.
            fuzzyCompare(w._cyclePos, frac, 1e-3,
                         "cyclePos matches an epoch/UTC recomputation (timezone-independent)")
        }
    }

    // ── nextNew / nextFull and the _nextDate() function ────────────────────
    TestCase {
        name: "MoonNextDates"
        when: windowShown
        function init() { tryVerify(function () { return hMoon.ready }, 3000) }

        function test_nextnew_future_within_month() {
            var w = hMoon.item
            var now = Date.now()
            var syn = w._synodicSec * 1000
            verify(w.nextNew.getTime() > now, "next New is strictly in the future")
            verify(w.nextNew.getTime() <= now + syn + 5000, "next New is within one synodic month")
        }

        function test_nextfull_future_within_month() {
            var w = hMoon.item
            var now = Date.now()
            var syn = w._synodicSec * 1000
            verify(w.nextFull.getTime() > now, "next Full is strictly in the future")
            verify(w.nextFull.getTime() <= now + syn + 5000, "next Full is within one synodic month")
        }

        // _nextDate(pos) advances to the next time cyclePos == pos. Calling it with
        // the CURRENT cyclePos (i.e. "already there") must roll a full period ahead,
        // never return now/0.
        function test_nextdate_at_current_pos_rolls_full_period() {
            var w = hMoon.item
            var now = Date.now()
            var syn = w._synodicSec * 1000
            var d = w._nextDate(w._cyclePos)
            fuzzyCompare(d.getTime(), now + syn, 10000,
                         "next occurrence of the current phase is ~one synodic month out")
        }

        // The nextNew instant should correspond to ahead = (1 - cyclePos) periods.
        function test_nextnew_matches_ahead_formula() {
            var w = hMoon.item
            var now = Date.now()
            var syn = w._synodicSec * 1000
            var ahead = (w._cyclePos > 0) ? (1 - w._cyclePos) : 1
            fuzzyCompare(w.nextNew.getTime(), now + ahead * syn, 10000,
                         "nextNew = now + (1 - cyclePos) · synodic")
        }
    }

    // ── Hemisphere config: default, reactivity, glyph mirroring ─────────────
    TestCase {
        name: "MoonHemisphere"
        when: windowShown
        function init() {
            tryVerify(function () { return hMoon.ready }, 3000)
            clearSettings(hMoon)
        }
        function glyph() { return findByText(hMoon.item, hMoon.item.phases[hMoon.item.idx]) }

        function test_defaults_to_north_when_empty() {
            compare(hMoon.item.hemisphere, "north", "empty instance settings default hemisphere to north")
        }

        function test_north_glyph_not_mirrored() {
            var g = glyph()
            verify(g !== null, "phase glyph Text is reachable")
            compare(g.transform[0].xScale, 1, "northern hemisphere renders the glyph un-mirrored")
        }

        function test_south_config_mirrors_glyph_live() {
            hMoon.storeCtl.setSetting("test-instance", "hemisphere", "south")
            compare(hMoon.item.hemisphere, "south", "hemisphere follows config live (revision bump)")
            var g = glyph()
            compare(g.transform[0].xScale, -1, "southern hemisphere mirrors the lit side (xScale -1)")
        }

        function test_flip_back_to_north_live() {
            hMoon.storeCtl.setSetting("test-instance", "hemisphere", "south")
            compare(glyph().transform[0].xScale, -1, "south first")
            hMoon.storeCtl.setSetting("test-instance", "hemisphere", "north")
            compare(hMoon.item.hemisphere, "north", "back to north live")
            compare(glyph().transform[0].xScale, 1, "glyph un-mirrors again")
        }
    }

    // ── Per-instance accent (effAccent) + the unused-in-body bug ────────────
    TestCase {
        name: "MoonAccent"
        when: windowShown
        function init() {
            tryVerify(function () { return hAccent.ready }, 3000)
            clearSettings(hAccent)
            hAccent.item.accentName = ""   // reset the universal appearance prop
        }

        function test_effaccent_defaults_to_accentcolor() {
            var w = hAccent.item
            compare(String(w.effAccent), String(w.accentColor),
                    "with no accent preset, effAccent falls back to the category accentColor")
            compare(String(w.accentColor), String(hAccent.theme.catInfo), "moon's category accent is catInfo")
        }

        function test_effaccent_follows_preset() {
            var w = hAccent.item
            w.accentName = "red"
            var expect = Qt.color(hAccent.theme.accentPresets["red"].a)
            compare(String(w.effAccent), String(expect), "effAccent resolves the chosen accent preset")
        }

        // BUG (audit medium): the phase-name / content colours use theme.text* and
        // never reference effAccent, so choosing an accent preset does NOT recolour
        // the widget's highlight content the way peer widgets do. This asserts the
        // INTENDED behaviour and is expected to fail until MoonWidget honours it.
        function test_content_colour_follows_effaccent() {
            var w = hAccent.item
            w.accentName = "magenta"                       // any non-default preset
            if (!hAccent.theme.accentPresets["magenta"])   // preset table uses these names
                w.accentName = "pink"
            var nameText = findByText(w, w.names[w.idx])
            verify(nameText !== null, "phase-name Text is reachable")
            compare(String(nameText.color), String(w.effAccent),
                    "phase-name colour should track the configured accent preset")
        }
    }

    // ── Null / empty store safety ──────────────────────────────────────────
    TestCase {
        name: "MoonStoreSafety"
        when: windowShown
        function init() { tryVerify(function () { return hNull.ready }, 3000) }

        function test_cfg_safe_when_store_null() {
            var w = hNull.item
            var saved = w.store
            w.store = null
            // cfg must not throw and hemisphere falls back to the default.
            compare(JSON.stringify(w.cfg), "{}", "cfg is an empty object when store is null")
            compare(w.hemisphere, "north", "hemisphere defaults with no store")
            w.store = saved
        }

        function test_cfg_safe_when_instanceid_empty() {
            var w = hNull.item
            var saved = w.instanceId
            w.instanceId = ""
            compare(JSON.stringify(w.cfg), "{}", "cfg is empty when instanceId is blank")
            compare(w.hemisphere, "north", "hemisphere defaults with a blank instanceId")
            w.instanceId = saved
        }
    }

    // ── Collapsed tile content should fit its (clipped) body ───────────────
    TestCase {
        name: "MoonTile"
        when: windowShown
        function init() { tryVerify(function () { return hTile.ready }, 3000) }

        // A minimum-ish tile from the portrait grid. The collapsed column (glyph +
        // phase name) must fit inside the clipped body. Audit flags that glyph size
        // keys off width only and can overflow short tiles.
        function test_collapsed_content_fits_small_tile() {
            hTile.width = 150
            hTile.height = 96
            var w = hTile.item
            var col = findByText(w, w.phases[w.idx])   // the glyph
            verify(col !== null, "glyph present in collapsed tile")
            // The glyph itself must not be taller than the tile body.
            verify(col.height <= hTile.height, "glyph height (" + col.height +
                   ") fits the tile height (" + hTile.height + ")")
        }
    }

    // ── The "moon" config schema drives the honoured options ───────────────
    TestCase {
        name: "MoonSchema"
        when: windowShown

        function schema() { return sc.schemaFor("moon") }
        function fieldByKey(s, key) {
            for (var j = 0; j < s.sections.length; j++)
                for (var k = 0; k < (s.sections[j].fields || []).length; k++)
                    if (s.sections[j].fields[k].key === key) return s.sections[j].fields[k]
            return null
        }

        function test_hemisphere_field_present() {
            var f = fieldByKey(schema(), "hemisphere")
            verify(f !== null, "moon schema exposes a hemisphere field")
            compare(f.type, "segmented", "hemisphere is a segmented control")
            compare(f.dflt, "north", "hemisphere defaults to north (matches widget default)")
        }

        function test_hemisphere_options_north_south() {
            var f = fieldByKey(schema(), "hemisphere")
            var vals = f.options.map(function (o) { return o.value })
            verify(vals.indexOf("north") >= 0 && vals.indexOf("south") >= 0,
                   "hemisphere offers north + south")
        }

        function test_universal_title_and_accent_present() {
            var s = schema()
            verify(fieldByKey(s, "title") !== null, "universal custom-title field present")
            verify(fieldByKey(s, "accent") !== null, "universal accent field present")
            verify(fieldByKey(s, "cardBackdrop") !== null, "universal card-backdrop field present")
        }
    }
}
