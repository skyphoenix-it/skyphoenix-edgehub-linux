import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: schema:ageUnit, schema:showDate

// SinceInstallWidget — how long the system has been installed.
//
// Every age below is computed from an epoch pinned RELATIVE TO NOW (now - N
// days), never from a hard-coded date: an absolute epoch would silently change
// meaning every day the suite runs, and the unit thresholds (60 days, 730 days)
// are exactly where that would bite.
Item {
    id: root
    width: 420; height: 320

    function fakeDistro(info) { return { ready: true, info: info } }
    // An arch probe whose install date is `days` ago.
    function agedInfo(days) {
        return { id: "arch", name: "Arch Linux", family: "arch", packageCount: 1461,
                 unsupportedReason: null, updates: null,
                 // Push the epoch 60s FURTHER back, so elapsed time is a hair OVER
                 // days*86400 and floor() lands on `days`. Landing exactly on the
                 // boundary would floor to days-1 the moment the clock ticked
                 // between building this fixture and reading it.
                 installEpoch: Math.floor(Date.now() / 1000) - (days * 86400) - 60 }
    }

    WidgetHarness { id: h; anchors.fill: parent; widgetFile: "SinceInstallWidget.qml" }
    App.WidgetConfigSchema { id: sc }

    TestCase {
        name: "SinceInstallWidget"
        when: windowShown

        function init() {
            tryVerify(function () { return h.ready }, 3000)
            var s = h.storeCtl.settingsFor("test-instance")
            for (var k in s) delete s[k]
            h.storeCtl._touchSettings()
            h.item.distroOverride = null
            h.expanded = false
        }
        function set(k, v) { h.storeCtl.setSetting("test-instance", k, v) }

        function test_degrades_when_the_bridge_is_absent() {
            var w = h.item
            verify(w !== null, "widget loaded with no `distro` context property")
            compare(w.loading, true, "no bridge -> loading")
            compare(w.known, false, "no bridge -> no install date")
            compare(w.valueText, "…", "a placeholder, never a number")
            compare(w.dateText, "", "no date to show")
        }

        // installEpoch null must never become "installed 1 Jan 1970" — the reason
        // the core sends null rather than a 0 sentinel.
        function test_missing_install_date_is_unknown_not_the_epoch() {
            var w = h.item
            w.distroOverride = fakeDistro({
                id: "fedora", name: "Fedora Linux 40", family: "rpm",
                packageCount: null, updates: null, installEpoch: null,
                unsupportedReason: "RPM systems need librpm to read the package database; this build does not shell out to rpm."
            })
            compare(w.known, false)
            compare(w.loading, false, "we got an answer; it has no date")
            compare(w.valueText, "-")
            compare(w.dateText, "", "no date rendered at all")
            verify(w.unitText.indexOf("unavailable") >= 0)
        }

        function test_days_for_a_fresh_system() {
            var w = h.item
            w.distroOverride = fakeDistro(agedInfo(4))
            compare(w.known, true)
            compare(w.days, 4)
            compare(w.valueText, "4")
            compare(w.unitText, "days since install")
        }

        // A clock skew that puts the install slightly in the future must read
        // "today", not "-1 days".
        function test_a_future_install_date_clamps_to_zero() {
            var w = h.item
            w.distroOverride = fakeDistro(agedInfo(-3))
            compare(w.days, 0, "clamped, never negative")
            compare(w.valueText, "0")
        }

        function test_singular_day() {
            var w = h.item
            w.distroOverride = fakeDistro(agedInfo(1))
            compare(w.days, 1)
            compare(w.unitText, "day since install", "singular at exactly 1")
        }

        // "auto" promotes days -> months -> years as the smaller unit stops being
        // readable. The boundaries are asserted from both sides.
        function test_ageUnit_auto_promotes_through_the_units() {
            var w = h.item
            set("ageUnit", "auto")
            compare(w.ageUnit, "auto")

            w.distroOverride = fakeDistro(agedInfo(59))
            compare(w.valueText, "59", "under 60 days -> days")
            compare(w.unitText, "days since install")

            w.distroOverride = fakeDistro(agedInfo(60))
            compare(w.valueText, "1", "at 60 days -> months (60/30.44 = 1)")
            compare(w.unitText, "month since install", "singular month")

            w.distroOverride = fakeDistro(agedInfo(365))
            compare(w.valueText, "11", "365/30.44 = 11 months")
            compare(w.unitText, "months since install")

            w.distroOverride = fakeDistro(agedInfo(730))
            compare(w.valueText, "2.0", "at 730 days -> years, one decimal")
            compare(w.unitText, "years since install")

            w.distroOverride = fakeDistro(agedInfo(1461))
            compare(w.valueText, "4.0", "1461/365.25 = exactly 4.0 — leap years counted")
        }

        // "days" pins the unit: 1461 days IS the flex for some people.
        function test_ageUnit_days_pins_the_unit() {
            var w = h.item
            set("ageUnit", "days")
            compare(w.ageUnit, "days")
            w.distroOverride = fakeDistro(agedInfo(1461))
            compare(w.valueText, "1461", "no promotion to years")
            compare(w.unitText, "days since install")
        }

        // The option must actually change what's rendered.
        function test_showDate_controls_the_header_status() {
            var w = h.item
            w.distroOverride = fakeDistro(agedInfo(10))
            set("showDate", true)
            compare(w.showDate, true)
            verify(w.status.length > 0, "the install date rides in the header")
            compare(w.status, w.dateText)
            set("showDate", false)
            compare(w.showDate, false)
            compare(w.status, "", "toggled off -> no date in the header")
        }

        // With no date there is nothing to put in the header, whatever the toggle.
        function test_showDate_shows_nothing_when_the_date_is_unknown() {
            var w = h.item
            set("showDate", true)
            compare(w.status, "", "no bridge -> no date in the header")
        }

        function test_defaults_match_the_schema() {
            var w = h.item
            compare(w.ageUnit, "auto", "default matches schema dflt")
            compare(w.showDate, true, "default matches schema dflt")
            var fields = sc.schemaFor("sinceinstall").sections[0].fields
            compare(fields[0].key, "ageUnit")
            compare(fields[0].dflt, "auto")
            compare(fields[1].key, "showDate")
            compare(fields[1].dflt, true)
        }

        function test_renders_expanded_without_errors() {
            var w = h.item
            w.distroOverride = fakeDistro(agedInfo(4))
            h.expanded = true
            wait(0)
            compare(w.days, 4, "age survives the expanded relayout")
            compare(w.status, "", "expanded hides the header status")
        }
    }
}
