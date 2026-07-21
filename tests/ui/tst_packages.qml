import QtQuick
import QtTest
import "../../ui/qml" as App

// COVERS: schema:showDistro

// PackagesWidget - the installed-package count.
//
// The widget reads a C++ bridge (`distro`) that does not exist in this harness,
// which is the point of two of these cases: with no bridge it must render a
// waiting state, never "0 packages". Everything else injects a FAKE probe via
// `distroOverride`, so the numbers here are pinned rather than whatever the box
// running the suite happens to have installed.
Item {
    id: root
    width: 420; height: 320

    // The shape the real DistroBridge exposes: `ready` + `info`.
    function fakeDistro(info) { return { ready: true, info: info } }
    function archInfo(count) {
        return { id: "arch", name: "Arch Linux", family: "arch", packageCount: count,
                 unsupportedReason: null, updates: null, installEpoch: 1709251200 }
    }

    WidgetHarness { id: h; anchors.fill: parent; widgetFile: "PackagesWidget.qml" }
    App.WidgetConfigSchema { id: sc }

    TestCase {
        name: "PackagesWidget"
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

        // No bridge (this harness, and any host that fails to register it): the
        // widget must say "we don't know yet", NOT "you have 0 packages".
        function test_degrades_when_the_bridge_is_absent() {
            var w = h.item
            verify(w !== null, "widget loaded with no `distro` context property")
            compare(w.loading, true, "no bridge -> loading")
            compare(w.counted, false, "no bridge -> nothing counted")
            compare(w.distroName, "", "no bridge -> no distro name")
        }

        // A bridge that exists but has not answered yet is still "loading".
        function test_unready_bridge_is_still_loading() {
            var w = h.item
            w.distroOverride = { ready: false, info: ({}) }
            compare(w.loading, true, "ready:false -> loading")
            compare(w.counted, false)
        }

        function test_shows_a_real_count() {
            var w = h.item
            w.distroOverride = fakeDistro(archInfo(1461))
            compare(w.loading, false)
            compare(w.counted, true)
            compare(w.count, 1461)
            compare(w.distroName, "Arch Linux")
        }

        // Zero is a REAL answer (a scratch chroot) and must not be confused with
        // "unknown" - this is the whole reason the core sends null, not 0.
        function test_zero_packages_is_a_real_count_not_unknown() {
            var w = h.item
            w.distroOverride = fakeDistro(archInfo(0))
            compare(w.counted, true, "0 is counted")
            compare(w.count, 0)
            compare(w.loading, false)
        }

        // The documented RPM outcome: no number, and the reason is surfaced
        // rather than swallowed.
        function test_unsupported_family_shows_a_reason_not_a_number() {
            var w = h.item
            w.distroOverride = fakeDistro({
                id: "fedora", name: "Fedora Linux 40", family: "rpm",
                packageCount: null, updates: null, installEpoch: null,
                unsupportedReason: "RPM systems need librpm to read the package database; this build does not shell out to rpm."
            })
            compare(w.counted, false, "null count -> not counted")
            compare(w.loading, false, "we DID get an answer; it just isn't a number")
            verify(w.reason.indexOf("librpm") >= 0, "the reason is shown verbatim")
            compare(w.distroName, "Fedora Linux 40")
        }

        // Grouped with a THIN SPACE (U+2009) - a comma or a point means different
        // things either side of the Atlantic. Written as an escape, not a literal:
        // the separator is invisible in source, and asserting it with a plain
        // ASCII space would "fail" against correct output for reasons no one could
        // see in the diff.
        function test_group_digits() {
            var w = h.item
            var sep = "\u2009"
            compare(w.groupDigits(0), "0")
            compare(w.groupDigits(7), "7")
            compare(w.groupDigits(999), "999", "no separator below 1000")
            compare(w.groupDigits(1461), "1" + sep + "461")
            compare(w.groupDigits(12345), "12" + sep + "345")
            compare(w.groupDigits(1234567), "1" + sep + "234" + sep + "567")
            // It is a thin space, NOT an ASCII space.
            verify(w.groupDigits(1461).indexOf(" ") < 0, "must not use an ASCII space")
        }

        // The option must actually change what's rendered - no decorative toggles.
        function test_showDistro_controls_the_header_status() {
            var w = h.item
            w.distroOverride = fakeDistro(archInfo(1461))
            set("showDistro", true)
            compare(w.showDistro, true)
            compare(w.status, "Arch Linux", "the distro name rides in the header")
            set("showDistro", false)
            compare(w.showDistro, false)
            compare(w.status, "", "toggled off -> no name in the header")
        }

        // Defaults must match the schema's `dflt`, or a fresh tile and its config
        // form disagree about what is on.
        function test_defaults_match_the_schema() {
            var w = h.item
            compare(w.showDistro, true, "default matches schema dflt")
            var fields = sc.schemaFor("packages").sections[0].fields
            compare(fields[0].key, "showDistro")
            compare(fields[0].dflt, true)
        }

        function test_renders_expanded_without_errors() {
            var w = h.item
            w.distroOverride = fakeDistro(archInfo(1461))
            h.expanded = true
            wait(0)
            compare(w.count, 1461, "count survives the expanded relayout")
            compare(w.status, "", "expanded hides the header status")
        }
    }
}
