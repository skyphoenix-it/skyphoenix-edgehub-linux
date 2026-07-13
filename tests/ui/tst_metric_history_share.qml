import QtQuick
import QtTest
import "../../ui/qml" as App

// Gate for S5: the RAM and GPU widgets must mirror their sparkline history into
// the shared DashboardStore (keyed by instanceId), the way CpuWidget/NetWidget
// already do, so the expanded overlay — a SEPARATE widget instance bound to the
// same instanceId — opens with the same graph instead of an empty one.
//
// Each case drives samples into a "primary" widget, then loads a "overlay" widget
// with the SAME store + instanceId and asserts it reads the same non-empty
// history from the store. A widget with a DIFFERENT instanceId starts empty.
Item {
    id: root
    width: 400; height: 300

    // Globals the widgets resolve by name through the QML scope chain (exactly
    // how WidgetHarness provides them).
    property alias theme: _theme
    App.Theme { id: _theme }
    App.DashboardStore { id: store }
    MockMedia { id: media }

    property bool _seeded: false
    Component.onCompleted: { store.load("blank"); _seeded = true }

    // ── RAM: primary + overlay (same id) + a fresh id (contrast) ─────────────
    Loader {
        id: ramPrimary
        active: root._seeded
        source: "../../ui/qml/widgets/RamWidget.qml"
        onLoaded: { item.store = store; item.instanceId = "ram-A"; item.active = true }
    }
    property bool _ramOverlayOn: false
    Loader {
        id: ramOverlay
        active: root._seeded && root._ramOverlayOn
        source: "../../ui/qml/widgets/RamWidget.qml"
        onLoaded: { item.store = store; item.instanceId = "ram-A"; item.active = false; item.expanded = true }
    }
    property bool _ramFreshOn: false
    Loader {
        id: ramFresh
        active: root._seeded && root._ramFreshOn
        source: "../../ui/qml/widgets/RamWidget.qml"
        onLoaded: { item.store = store; item.instanceId = "ram-Z"; item.active = false }
    }

    // ── GPU: primary + overlay (same id) + a fresh id (contrast) ─────────────
    Loader {
        id: gpuPrimary
        active: root._seeded
        source: "../../ui/qml/widgets/GpuWidget.qml"
        onLoaded: { item.store = store; item.instanceId = "gpu-A"; item.active = true }
    }
    property bool _gpuOverlayOn: false
    Loader {
        id: gpuOverlay
        active: root._seeded && root._gpuOverlayOn
        source: "../../ui/qml/widgets/GpuWidget.qml"
        onLoaded: { item.store = store; item.instanceId = "gpu-A"; item.active = false; item.expanded = true }
    }
    property bool _gpuFreshOn: false
    Loader {
        id: gpuFresh
        active: root._seeded && root._gpuFreshOn
        source: "../../ui/qml/widgets/GpuWidget.qml"
        onLoaded: { item.store = store; item.instanceId = "gpu-Z"; item.active = false }
    }

    TestCase {
        name: "MetricHistoryShare"
        when: windowShown

        function initTestCase() {
            tryVerify(function () { return ramPrimary.item && gpuPrimary.item }, 3000)
        }

        // ── RAM ──────────────────────────────────────────────────────────────
        function test_ram_history_shared_via_store() {
            var p = ramPrimary.item
            p.hist = []
            // Drive several real samples; RAM reads usage straight from `metrics`
            // in onMetricsChanged, so each assignment records one sample.
            var vals = [40, 45, 50, 55, 60]
            for (var i = 0; i < vals.length; i++)
                p.metrics = { ram_usage_percent: vals[i] }

            verify(p.hist.length >= vals.length,
                   "primary accumulated history (" + p.hist.length + ")")

            // The store carries the mirrored history under the instance id.
            var s = store.settingsFor("ram-A")
            verify(s.hist !== undefined && s.hist.length === p.hist.length,
                   "history mirrored into the shared store")

            // Now open the expanded overlay: a second instance, same id.
            root._ramOverlayOn = true
            tryVerify(function () { return ramOverlay.item !== null }, 3000)
            var o = ramOverlay.item

            verify(o.hist.length > 0, "overlay opens with a non-empty graph")
            compare(o.hist.length, p.hist.length,
                    "overlay reads the SAME history length from the store")
            compare(o.hist[o.hist.length - 1], p.hist[p.hist.length - 1],
                    "overlay's newest sample matches the primary's")
        }

        function test_ram_fresh_instance_starts_empty() {
            root._ramFreshOn = true
            tryVerify(function () { return ramFresh.item !== null }, 3000)
            compare(ramFresh.item.hist.length, 0,
                    "a widget with a different instanceId does NOT inherit history")
        }

        // ── GPU ──────────────────────────────────────────────────────────────
        function test_gpu_history_shared_via_store() {
            var p = gpuPrimary.item
            p.hist = []
            // GPU's accumulator reads the derived `avail`/`v` bindings, which settle
            // a tick after the assignment, so feed each value twice to flush it.
            var vals = [10, 20, 30, 40]
            for (var i = 0; i < vals.length; i++) {
                p.metrics = { gpu_usage_percent: vals[i] }
                p.metrics = { gpu_usage_percent: vals[i] }
            }

            verify(p.hist.length > 0, "primary accumulated GPU history (" + p.hist.length + ")")

            var s = store.settingsFor("gpu-A")
            verify(s.hist !== undefined && s.hist.length === p.hist.length,
                   "GPU history mirrored into the shared store")

            root._gpuOverlayOn = true
            tryVerify(function () { return gpuOverlay.item !== null }, 3000)
            var o = gpuOverlay.item

            verify(o.hist.length > 0, "GPU overlay opens with a non-empty graph")
            compare(o.hist.length, p.hist.length,
                    "GPU overlay reads the SAME history length from the store")
            compare(o.hist[o.hist.length - 1], p.hist[p.hist.length - 1],
                    "GPU overlay's newest sample matches the primary's")
        }

        function test_gpu_fresh_instance_starts_empty() {
            root._gpuFreshOn = true
            tryVerify(function () { return gpuFresh.item !== null }, 3000)
            compare(gpuFresh.item.hist.length, 0,
                    "a GPU widget with a different instanceId starts empty")
        }
    }
}
