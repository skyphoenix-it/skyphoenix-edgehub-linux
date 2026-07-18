import QtQuick
import QtQuick.Layouts

// How long this system has been installed, derived from the package manager's
// own history (the first `installed` line in pacman.log, or the installer's
// timestamp on a dpkg system) — resolved by the Rust core, probed off-thread.
//
// It measures what it can actually see: on a system whose package log has been
// rotated away, that is the age of the LOG. The expanded view says so rather
// than presenting a confident wrong number.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    title: "System Age"; iconName: "sinceinstall"; accentColor: theme.catSystem

    // Resolved from CONTEXT as `distro`. NOT declared as `property var distro`:
    // an object property shadows the context property of the same name, and
    // Dashboard.injectWidget never assigns this one — so a declared `distro`
    // would stay null forever in the real app. See PackagesWidget for the full
    // note. Tests inject via `distroOverride`.
    property var distroOverride: null

    readonly property var probe: {
        var d = w.distroOverride ? w.distroOverride
                                 : ((typeof distro !== "undefined") ? distro : null)
        if (!d || !d.ready) return null
        return d.info
    }

    // Three states, kept apart on purpose (see PackagesWidget): unknown-yet,
    // cannot-know, and a real epoch. `installEpoch` is null — never 0 — when
    // absent, so a missing date can never render as "installed in 1970".
    readonly property bool loading: w.probe === null
    readonly property bool known: !w.loading && w.probe.installEpoch !== null
                                  && w.probe.installEpoch !== undefined
    readonly property real installEpoch: w.known ? w.probe.installEpoch : 0
    readonly property string distroName: w.probe ? (w.probe.name || "") : ""
    readonly property string reason: (w.probe && w.probe.unsupportedReason)
                                     ? w.probe.unsupportedReason : ""

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    // Same defaults as the schema `dflt`.
    readonly property string ageUnit: cfg.ageUnit !== undefined ? cfg.ageUnit : "auto"
    readonly property bool showDate: cfg.showDate !== undefined ? cfg.showDate : true

    // Whole days since install. `tick` keeps it current across midnight without a
    // per-widget timer. Clamped at 0: a clock skew that puts the install slightly
    // in the future must read "today", not "-1 days".
    readonly property int days: {
        w.tick
        if (!w.known) return 0
        var secs = (Date.now() / 1000) - w.installEpoch
        return Math.max(0, Math.floor(secs / 86400))
    }

    // The headline value. "auto" promotes days → months → years once the smaller
    // unit stops being readable; "days" pins it, because "1 461 days" IS the flex
    // for some people.
    //
    // 365.25 and 30.44 (not 365/30): over a multi-year age the drift from ignoring
    // leap years is a visible number of days, and this is the kind of widget
    // people check against `uptime`-style facts.
    readonly property string valueText: {
        if (w.loading) return "…"
        if (!w.known) return "-"
        if (w.ageUnit === "days") return "" + w.days
        if (w.days < 60) return "" + w.days
        if (w.days < 730) return "" + Math.floor(w.days / 30.44)
        return (w.days / 365.25).toFixed(1)
    }
    readonly property string unitText: {
        if (w.loading) return "Reading install history…"
        if (!w.known) return "Install date unavailable"
        if (w.ageUnit === "days" || w.days < 60)
            return (w.days === 1 ? "day since install" : "days since install")
        if (w.days < 730) {
            var m = Math.floor(w.days / 30.44)
            return (m === 1 ? "month since install" : "months since install")
        }
        return "years since install"
    }

    // The install date itself, in the user's locale.
    readonly property string dateText: {
        if (!w.known) return ""
        return Qt.formatDate(new Date(w.installEpoch * 1000), Qt.DefaultLocaleShortDate)
    }

    status: (w.showDate && !w.expanded && w.known) ? w.dateText : ""

    ColumnLayout {
        anchors.centerIn: parent
        spacing: w.expanded ? 8 : 2

        Text {
            Layout.alignment: Qt.AlignHCenter
            // preferredWidth so HorizontalFit has a fixed box to shrink into —
            // see the same note in PackagesWidget.
            Layout.preferredWidth: w.width - 2 * w.contentMargins
            Layout.maximumWidth: w.width - 2 * w.contentMargins
            horizontalAlignment: Text.AlignHCenter
            text: w.valueText
            font.pixelSize: w.expanded ? 120 : Math.max(30, Math.min(w.width * 0.34, 68))
            fontSizeMode: Text.HorizontalFit; minimumPixelSize: 12; elide: Text.ElideRight
            font.bold: true; font.family: theme.fontMono
            color: w.known ? w.effAccent : theme.textTertiary
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: w.width * 0.9
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: w.unitText
            font.pixelSize: w.expanded ? 22 : 12
            color: theme.textSecondary
        }

        // Expanded: the exact date + the distro, since the header hides `status`.
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: w.expanded && w.showDate && w.known
            text: w.distroName.length ? (w.distroName + " · " + w.dateText) : w.dateText
            font.pixelSize: 26; font.family: theme.fontDisplay
            color: theme.textPrimary
            elide: Text.ElideRight
            Layout.preferredWidth: w.width * 0.9
            horizontalAlignment: Text.AlignHCenter
        }

        // Say what was actually measured. On a rotated log this age is the log's,
        // not the system's, and quietly implying otherwise would be the one real
        // dishonesty available to this widget.
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: w.width * 0.9
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: w.expanded
            text: w.reason.length > 0 ? w.reason
                                      : "Measured from the first install recorded in your package "
                                        + "manager's log. If that log has been rotated away, this "
                                        + "is the age of the log."
            font.pixelSize: 14; color: theme.textTertiary
        }
    }
}
