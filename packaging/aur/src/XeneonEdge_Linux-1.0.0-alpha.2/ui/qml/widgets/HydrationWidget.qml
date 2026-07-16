import QtQuick
import QtQuick.Layouts

// Hydration — count glasses toward a daily goal. Persisted; auto-resets daily.
WidgetChrome {
    id: w
    property var metrics: ({})
    property bool expanded: false
    property bool active: true
    property var store: null
    property string instanceId: ""
    property int tick: 0

    // Water-teal accent, deliberately distinct from theme.success: the count text
    // recolours to `success` when the goal is reached, so the resting accent must
    // differ or that reward is invisible (catInfo happens to equal success).
    title: "Hydration"; iconName: "hydration"; accentColor: theme.catServices

    readonly property var cfg: {
        var _ = store ? store.revision : 0
        return (store && instanceId) ? JSON.parse(JSON.stringify(store.settingsFor(instanceId))) : ({})
    }
    property int goal: cfg.goal || 8
    readonly property int glassMl: cfg.glassMl !== undefined ? cfg.glassMl : 250
    property string todayKey: (w.tick, Qt.formatDate(new Date(), "yyyy-MM-dd"))
    property int count: cfg.day === todayKey ? (cfg.count || 0) : 0
    status: count + "/" + goal

    // Live goal streak: only counts if the last goal-day is today or yesterday,
    // otherwise the streak has lapsed (shown as 0 until you hit the goal again).
    function _yesterdayKey() { var d = new Date(); d.setDate(d.getDate() - 1); return Qt.formatDate(d, "yyyy-MM-dd") }
    readonly property int streakDisplay: {
        var lg = cfg.lastGoalDay
        return (lg === todayKey || lg === _yesterdayKey()) ? (cfg.streak || 0) : 0
    }

    // Total volume drunk today (count × per-glass size), shown as L when ≥ 1000 ml.
    function volumeText() {
        var ml = w.count * w.glassMl
        return ml >= 1000 ? (ml / 1000).toFixed(1) + " L" : ml + " ml"
    }

    // Overfilling past the goal is allowed (extra-credit dopamine); capped only to
    // keep the glass grid sane.
    // Credit today's goal attainment into `patch` (streak + lastGoalDay) and
    // celebrate — but only the FIRST time the goal is reached today. Re-crossing
    // the same day keeps the streak and does not replay the celebration.
    function _creditGoalReached(patch) {
        var firstToday = cfg.lastGoalDay !== todayKey
        var s
        if (cfg.lastGoalDay === todayKey) s = cfg.streak || 1
        else s = (cfg.lastGoalDay === _yesterdayKey()) ? (cfg.streak || 0) + 1 : 1
        patch.streak = s; patch.lastGoalDay = todayKey
        if (firstToday) celebrateNow("🎉 Goal reached!")
    }
    function set(n) {
        if (!store) return
        var v = Math.max(0, Math.min(50, n))
        var was = w.count
        var patch = { "day": todayKey, "count": v }
        // First crossing of the goal today → bump the streak + celebrate.
        if (was < goal && v >= goal) _creditGoalReached(patch)
        store.patchSettings(instanceId, patch)
    }
    function setGoal(g) {
        if (!store) return
        var ng = Math.max(1, Math.min(20, g))
        var patch = { "goal": ng }
        // Lowering the goal to at/below the current count meets it just like a
        // glass tap would — credit the streak (only if it wasn't already met).
        if (w.count < w.goal && w.count >= ng) _creditGoalReached(patch)
        store.patchSettings(instanceId, patch)
    }

    // Celebration pop (mirrors FocusWidget).
    property string celebrateMsg: ""
    function celebrateNow(msg) { celebrateMsg = msg; celebrateAnim.restart(); flash.restart() }
    Rectangle {
        anchors.fill: parent; radius: theme.radiusLg; color: w.effAccent; opacity: 0; z: 5
        SequentialAnimation on opacity {
            id: flash; running: false
            NumberAnimation { to: 0.32; duration: 130 }
            NumberAnimation { to: 0.0; duration: 520 }
        }
    }
    Text {
        id: celebrateLabel; anchors.centerIn: parent; z: 20
        text: w.celebrateMsg; opacity: 0
        font.pixelSize: w.expanded ? 40 : 20; font.bold: true; font.family: theme.fontDisplay
        color: w.effAccent; horizontalAlignment: Text.AlignHCenter
        SequentialAnimation {
            id: celebrateAnim; running: false
            PropertyAction { target: celebrateLabel; property: "scale"; value: 0.6 }
            ParallelAnimation {
                NumberAnimation { target: celebrateLabel; property: "opacity"; from: 0; to: 1; duration: 180 }
                NumberAnimation { target: celebrateLabel; property: "scale"; to: 1.12
                    duration: 260; easing.type: theme.reduceMotion ? Easing.Linear : Easing.OutBack }
            }
            PauseAnimation { duration: 900 }
            NumberAnimation { target: celebrateLabel; property: "opacity"; to: 0; duration: 500 }
        }
    }

    // ── Compact tile ──
    ColumnLayout {
        anchors.centerIn: parent; visible: !w.expanded; width: parent.width * 0.92; spacing: 6
        Flow {
            Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; spacing: 4
            Repeater {
                model: w.goal
                delegate: Text { required property int index
                    text: index < w.count ? "💧" : "○"
                    opacity: index < w.count ? 1 : 0.35; font.pixelSize: 16 }
            }
        }
        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
            text: w.count + " of " + w.goal + " glasses"; elide: Text.ElideRight
            font.pixelSize: 12; color: theme.textSecondary }
        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
            visible: w.streakDisplay > 1; elide: Text.ElideRight
            text: "🔥 " + w.streakDisplay + "-day streak"; font.pixelSize: 11; color: theme.textTertiary }
        // Compact −1 / +1 — bounded touch targets (each ≥44px via PillButton) so
        // quick logging works right in the tile. Both call the existing set();
        // the pair stays narrow (~128px) to fit even a 1x1 tile.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: theme.spacingSm
            PillButton {
                label: "−"; tint: w.effAccent
                enabledState: w.count > 0
                onClicked: w.set(w.count - 1)
            }
            PillButton {
                label: "+1"; glyph: "💧"; primary: true; tint: w.effAccent
                onClicked: w.set(w.count + 1)
            }
        }
    }

    // ── Expanded: one large, centered, cohesive block ──
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width, 600)
        visible: w.expanded
        spacing: theme.spacingXl

        Text { Layout.alignment: Qt.AlignHCenter; text: w.count + " / " + w.goal
            font.pixelSize: 110; font.bold: true; font.family: theme.fontMono
            color: w.count >= w.goal ? theme.success : w.effAccent }
        Text { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: -theme.spacingMd
            text: w.count > w.goal ? ("Overachiever! +" + (w.count - w.goal) + " 💪")
                  : (w.count === w.goal ? "Daily goal reached! 🎉" : "glasses of water today")
            font.pixelSize: 20; color: theme.textSecondary }
        Text { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: -theme.spacingLg
            text: w.volumeText() + " today" + (w.streakDisplay > 1 ? "   ·   🔥 " + w.streakDisplay + "-day streak" : "")
            font.pixelSize: 16; color: theme.textTertiary }

        Flow {
            Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true
            spacing: theme.spacingMd
            Repeater {
                // Render goal cells, plus any extra "bonus" glasses when overfilled.
                model: Math.max(w.goal, w.count)
                delegate: Rectangle {
                    required property int index
                    readonly property bool filled: index < w.count
                    readonly property bool bonus: index >= w.goal
                    width: 88; height: 88; radius: theme.radiusMd
                    color: filled ? Qt.rgba(w.effAccent.r, w.effAccent.g, w.effAccent.b, bonus ? 0.28 : 0.18) : "transparent"
                    border.width: 2
                    border.color: filled ? (bonus ? theme.success : w.effAccent) : theme.cardBorder
                    Text { anchors.centerIn: parent; text: filled ? "💧" : "○"
                        font.pixelSize: 42; opacity: filled ? 1 : 0.4 }
                    MouseArea { anchors.fill: parent; onClicked: w.set(index + 1) }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: theme.spacingMd; spacing: theme.spacingLg
            PillButton { label: "Remove"; glyph: "−"; implicitWidth: 170; onClicked: w.set(w.count - 1) }
            PillButton { label: "Add a glass"; glyph: "💧"; primary: true; tint: w.effAccent
                implicitWidth: 240; onClicked: w.set(w.count + 1) }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingMd
            Text { text: "Daily goal:"; color: theme.textSecondary; font.pixelSize: 16; Layout.alignment: Qt.AlignVCenter }
            PillButton { label: "−"; onClicked: w.setGoal(w.goal - 1) }
            Text { text: w.goal + " glasses"; color: theme.textPrimary; font.pixelSize: 16
                Layout.alignment: Qt.AlignVCenter; Layout.preferredWidth: 100; horizontalAlignment: Text.AlignHCenter }
            PillButton { label: "+"; onClicked: w.setGoal(w.goal + 1) }
        }
    }
}
