import QtQuick
import QtQuick.Layouts

// Installed package count, read from the package manager's own database.
//
// The number is FACTUAL, not decorative: it is a count of real entries in
// /var/lib/pacman/local or /var/lib/dpkg/status, resolved by the Rust core and
// probed off-thread (see app/src/distro_bridge.h). The distro NAME shown beside
// it is whatever /etc/os-release reports about this machine — reported, never
// guessed, and never illustrated with anyone's logo.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""

    title: "Packages"; iconName: "packages"; accentColor: theme.catSystem

    // ── The bridge ───────────────────────────────────────────────────────────
    // Resolved from CONTEXT as `distro` (registered in both main.cpp files).
    //
    // Deliberately NOT declared as `property var distro`: an object property
    // SHADOWS the context property of the same name, so the widget would read its
    // own null forever. Dashboard.injectWidget only assigns the handful of names
    // it knows (metrics/store/timeZones/…), so nothing would ever fill it in.
    // Tests inject through `distroOverride` instead, which cannot collide.
    property var distroOverride: null

    // The probe result, or null when there is no bridge / no answer yet. The
    // binding touches `ready` and `info` directly so it re-evaluates when the
    // C++ side emits infoChanged.
    readonly property var probe: {
        var d = w.distroOverride ? w.distroOverride
                                 : ((typeof distro !== "undefined") ? distro : null)
        if (!d || !d.ready) return null
        return d.info
    }

    // Three distinct states, and conflating any two of them is a lie:
    //   • no bridge / not probed yet  → "…"      (we do not know YET)
    //   • probed, unsupported family  → "—"      (we CANNOT know; reason shown)
    //   • probed, counted             → a number (0 would be a real answer)
    readonly property bool loading: w.probe === null
    readonly property bool counted: !w.loading && w.probe.packageCount !== null
                                    && w.probe.packageCount !== undefined
    readonly property int count: w.counted ? w.probe.packageCount : 0
    readonly property string distroName: w.probe ? (w.probe.name || "") : ""
    readonly property string reason: (w.probe && w.probe.unsupportedReason)
                                     ? w.probe.unsupportedReason : ""

    // Live per-instance config (see WidgetConfigSchema "packages").
    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    // Same defaults as the schema `dflt`.
    readonly property bool showDistro: cfg.showDistro !== undefined ? cfg.showDistro : true

    // Group a big number: 1461 -> "1 461". A thin space, not a comma/point —
    // those mean different things either side of the Atlantic, and this is a
    // count read across a room, not a parsed value.
    function groupDigits(n) {
        var s = "" + Math.max(0, Math.floor(n)), out = ""
        for (var i = 0; i < s.length; i++) {
            if (i > 0 && (s.length - i) % 3 === 0) out += " "
            out += s.charAt(i)
        }
        return out
    }

    // The header carries the distro name, so the count below stays a pure number.
    status: (w.showDistro && !w.expanded) ? w.distroName : ""

    ColumnLayout {
        anchors.centerIn: parent
        spacing: w.expanded ? 8 : 2

        Text {
            Layout.alignment: Qt.AlignHCenter
            // preferredWidth (not merely maximumWidth) so HorizontalFit has a
            // fixed box to shrink into — a bare cap is ignored for an oversized
            // implicitWidth on some Qt versions and the number overflows.
            Layout.preferredWidth: w.width - 2 * w.contentMargins
            Layout.maximumWidth: w.width - 2 * w.contentMargins
            horizontalAlignment: Text.AlignHCenter
            text: w.loading ? "…" : (w.counted ? w.groupDigits(w.count) : "—")
            font.pixelSize: w.expanded ? 120 : Math.max(28, Math.min(w.width * 0.30, 64))
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 12; elide: Text.ElideRight
            font.bold: true; font.family: theme.fontMono
            color: w.counted ? w.effAccent : theme.textTertiary
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: w.width * 0.9
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: w.loading ? "Reading package database…"
                            : (w.counted ? (w.count === 1 ? "package installed" : "packages installed")
                                         : "Package count unavailable")
            font.pixelSize: w.expanded ? 22 : 12
            color: theme.textSecondary
        }

        // The distro name, in the body only when the header isn't showing it
        // (expanded hides `status`) — never both.
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: w.width * 0.9
            horizontalAlignment: Text.AlignHCenter
            visible: w.expanded && w.showDistro && w.distroName.length > 0
            text: w.distroName
            font.pixelSize: 26; font.family: theme.fontDisplay
            color: theme.textPrimary
            elide: Text.ElideRight
        }

        // WHY the number is absent, verbatim from the core — so an RPM user sees
        // "we don't read your package db" instead of a silent dash.
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: w.width * 0.9
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: w.expanded && w.reason.length > 0
            text: w.reason
            font.pixelSize: 14; color: theme.textTertiary
        }
    }
}
