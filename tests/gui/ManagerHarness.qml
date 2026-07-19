import QtQuick

// ManagerHarness — hosts the REAL manager/qml/Manager.qml window for visible GUI
// tests. The Manager owns its own Theme/DashboardStore/catalogs/MockMedia; the
// only external dependency is the C++ `backend` (ManagerBackend), which we stub
// here as a QtObject in scope so the created window resolves it via the context.
//
// Usage:
//   ManagerHarness { id: mh }
//   ... in a TestCase: mh.create(); tryVerify(function(){ return mh.ready })
//   mh.win is the ApplicationWindow; mh.backend is the stub.
Item {
    id: mh
    property var win: null
    property alias backend: backend
    readonly property bool ready: win !== null && win.visible

    // Stub of the C++ ManagerBackend (superset of tst_manager.qml's stub, plus
    // hubRotation / screensJson / configJson the GUI cases need).
    QtObject {
        id: backend
        property bool hubConnected: false
        property int hubRotation: 0          // auto-provides hubRotationChanged()
        signal imagesChanged()
        signal configChanged()
        signal screensChanged()
        signal licenseChanged()

        property string storedKey: ""
        property var proKeys: ({ "XE1.valid.pro": "Ada Lovelace" })
        function _statusFor(k) {
            if (proKeys[k] !== undefined)
                return JSON.stringify({ state: "licensed", tier: "pro", issuedTo: proKeys[k] })
            return JSON.stringify({ state: "unlicensed", tier: "free" })
        }
        function verifyLicenseCandidate(k) { return _statusFor(k) }
        function licenseStatusJson() { return _statusFor(storedKey) }
        function setLicenseKey(k) { storedKey = k; licenseChanged(); return true }
        function clearLicenseKey() { return setLicenseKey("") }

        property var imagesList: []
        property string lastDeleted: ""
        property string lastImported: ""
        property bool startHubCalled: false
        property bool stopHubCalled: false
        property bool syncCalled: false
        property bool autostart: false
        function imageUrl(n) { return "file:///imgs/" + n }
        function starterLayout() { return "blank" }
        function autoConfig() { return "" }
        function startTab() { return 0 }
        function metricsJson() { return "{}" }
        function screensJson() { return "[]" }
        function configJson() { return "{}" }
        function targetConnector() { return "DP-2" }
        function listImages() { return imagesList }
        function importImage(u) { lastImported = String(u); imagesChanged() }
        function deleteImage(n) { lastDeleted = n; imagesChanged() }
        function setTargetDisplay(a, b) {}
        function isAutostart() { return autostart }
        function setAutostart(v) { autostart = v }
        function syncFromHub() { syncCalled = true }
        function startHub() { startHubCalled = true; return true }
        function stopHub() { stopHubCalled = true }
        function setHubRotation(r) { hubRotation = r; hubRotationChanged() }
    }

    function create() {
        if (win) return win
        var c = Qt.createComponent("../../manager/qml/Manager.qml")
        if (c.status === Component.Error) { console.warn("Manager compile error:", c.errorString()); return null }
        win = c.createObject(mh)
        return win
    }
    function destroyWin() { if (win) { win.destroy(); win = null } }
}
