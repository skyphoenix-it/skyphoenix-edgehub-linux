import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ─────────────────────────────────────────────────────────────────────────
// Dashboard — iCUE-style square-tile layout for the Xeneon Edge.
//
// Every widget is rendered inside the shared WidgetChrome (glass card, accent
// glow, uniform header) so the whole experience has one consistent visual
// thread. Tiles are glanceable previews; tapping a tile expands it full-screen
// for interaction. Layout is data-driven (see `pages`) and pages are grouped
// by category: System · Focus · Info · Play · Ambient.
// ─────────────────────────────────────────────────────────────────────────
Item {
    id: dashboard
    anchors.fill: parent

    // 1 Hz tick used to refresh time-based widgets.
    property int _tick: 0

    // Parsed live metrics from C++ (single parse, shared by all widgets).
    property var metrics: {
        try { return JSON.parse(metricsJson || "{}"); } catch (e) { return {}; }
    }

    property bool isLandscape: width > height

    // Currently expanded widget (null = none).
    property var expandComp: null
    property string expandTitle: ""
    property string expandIcon: ""
    property color expandColor: theme.accent

    // StackView that hosts this page (for opening Diagnostics/Settings).
    property var host: StackView.view

    function fmtBytes(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB"
        if (b >= 1048576) return (b / 1048576).toFixed(0) + " MB"
        return (b / 1024).toFixed(0) + " KB"
    }

    // Animated background — subtle gradient tinted by the accent.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: theme.backgroundColor }
            GradientStop { position: 1.0; color: theme.backgroundColor2 }
        }
    }
    Rectangle {
        anchors.fill: parent
        opacity: 0.06
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: theme.accent }
            GradientStop { position: 0.5; color: "transparent" }
            GradientStop { position: 1.0; color: theme.accent2 }
        }
    }

    // Master tick (paused when the app is not active to save CPU).
    Timer { interval: 1000; running: Qt.application.active; repeat: true; onTriggered: dashboard._tick++ }

    // ═══════════════════════════════════════════════════════════════════
    //  Widget registry — inline components keyed by id, each wrapped in
    //  WidgetChrome for a uniform look.
    // ═══════════════════════════════════════════════════════════════════

    // ── SYSTEM ────────────────────────────────────────────────────────
    Component {
        id: clockComp
        WidgetChrome {
            id: clk
            title: "Clock"; icon: "🕐"; accentColor: theme.catSystem
            status: (dashboard._tick, Qt.formatDate(new Date(), "ddd"))
            ColumnLayout { anchors.centerIn: parent; spacing: clk.big ? 6 : 0
                Text { Layout.alignment: Qt.AlignHCenter
                    text: (dashboard._tick, Qt.formatTime(new Date(), "HH:mm"))
                    font.pixelSize: clk.big ? 128 : (clk.height < 150 ? 32 : 52); font.bold: true
                    font.family: theme.fontMono; color: theme.textPrimary }
                Text { Layout.alignment: Qt.AlignHCenter; visible: clk.big
                    text: (dashboard._tick, Qt.formatTime(new Date(), "ss")) + " sec"
                    font.pixelSize: 18; font.family: theme.fontMono; color: theme.accent }
                Text { Layout.alignment: Qt.AlignHCenter
                    text: (dashboard._tick, Qt.formatDate(new Date(), clk.big ? "dddd, MMMM d" : "MMM d"))
                    font.pixelSize: clk.big ? 22 : 12; color: theme.textSecondary }
            }
        }
    }

    Component {
        id: cpuComp
        WidgetChrome {
            id: cw
            title: "CPU"; icon: "🖥"; accentColor: theme.catSystem
            property real v: dashboard.metrics.cpu_usage_percent || 0
            property real temp: dashboard.metrics.cpu_temp_celsius || -1
            status: temp > 0 ? temp.toFixed(0) + "°C" : ""
            statusColor: temp > 80 ? theme.error : temp > 65 ? theme.warning : theme.textSecondary
            function col(p) { return p > 80 ? theme.error : p > 50 ? theme.warning : theme.catSystem }
            ColumnLayout { anchors.centerIn: parent; spacing: cw.big ? 12 : 4; width: cw.width * 0.85
                Text { Layout.alignment: Qt.AlignHCenter; text: cw.v.toFixed(0) + "%"
                    font.pixelSize: cw.big ? 96 : (cw.height < 150 ? 28 : 42); font.bold: true; font.family: theme.fontMono; color: cw.col(cw.v) }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: cw.big ? 12 : 6; radius: height / 2; color: theme.cardBorder
                    Rectangle { height: parent.height; radius: height / 2; width: parent.width * Math.min(cw.v / 100, 1); color: cw.col(cw.v)
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } } }
                Text { Layout.alignment: Qt.AlignHCenter; visible: cw.big
                    text: "Load " + (dashboard.metrics.load_avg_1 !== undefined ? dashboard.metrics.load_avg_1.toFixed(2) : "—")
                    font.pixelSize: 15; color: theme.textSecondary }
            }
        }
    }

    Component {
        id: ramComp
        WidgetChrome {
            id: rw
            title: "Memory"; icon: "🧠"; accentColor: theme.catSystem
            property real v: dashboard.metrics.ram_usage_percent || 0
            function col(p) { return p > 90 ? theme.error : p > 70 ? theme.warning : theme.catSystem }
            ColumnLayout { anchors.centerIn: parent; spacing: rw.big ? 12 : 4; width: rw.width * 0.85
                Text { Layout.alignment: Qt.AlignHCenter; text: rw.v.toFixed(0) + "%"
                    font.pixelSize: rw.big ? 96 : (rw.height < 150 ? 28 : 42); font.bold: true; font.family: theme.fontMono; color: rw.col(rw.v) }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: rw.big ? 12 : 6; radius: height / 2; color: theme.cardBorder
                    Rectangle { height: parent.height; radius: height / 2; width: parent.width * Math.min(rw.v / 100, 1); color: rw.col(rw.v)
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } } } }
                Text { Layout.alignment: Qt.AlignHCenter
                    text: dashboard.fmtBytes(dashboard.metrics.ram_used_bytes || 0) + " / " + dashboard.fmtBytes(dashboard.metrics.ram_total_bytes || 0)
                    font.pixelSize: rw.big ? 16 : 10; color: theme.textSecondary }
            }
        }
    }

    Component {
        id: sensorsComp
        WidgetChrome {
            id: sw
            title: "Sensors"; icon: "📊"; accentColor: theme.catSystem
            property real cpu: dashboard.metrics.cpu_usage_percent || 0
            property real ram: dashboard.metrics.ram_usage_percent || 0
            property real temp: dashboard.metrics.cpu_temp_celsius || -1
            ColumnLayout { anchors.fill: parent; spacing: big ? 12 : 6
                Repeater {
                    model: [
                        { lbl: "CPU", val: sw.cpu, max: 100, unit: "%", col: theme.catSystem },
                        { lbl: "RAM", val: sw.ram, max: 100, unit: "%", col: theme.catProductivity },
                        { lbl: "TEMP", val: sw.temp > 0 ? sw.temp : 0, max: 100, unit: "°C", col: theme.warning }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: theme.spacingSm
                        Text { text: modelData.lbl; font.pixelSize: big ? 15 : 10; font.family: theme.fontMono; color: theme.textSecondary; Layout.preferredWidth: big ? 60 : 40 }
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: big ? 10 : 5; radius: height / 2; color: theme.cardBorder
                            Rectangle { height: parent.height; radius: height / 2; color: modelData.col
                                width: parent.width * Math.min(modelData.val / modelData.max, 1)
                                Behavior on width { NumberAnimation { duration: 400 } } } }
                        Text { text: modelData.val.toFixed(0) + modelData.unit; font.pixelSize: big ? 15 : 10; font.family: theme.fontMono; color: theme.textPrimary; Layout.preferredWidth: big ? 60 : 44; horizontalAlignment: Text.AlignRight }
                    }
                }
            }
        }
    }

    Component {
        id: networkComp
        WidgetChrome {
            title: "Network"; icon: "📡"; accentColor: theme.catServices
            Canvas { id: cv; anchors.fill: parent; anchors.topMargin: 4
                onPaint: {
                    var ctx = getContext('2d'); ctx.clearRect(0, 0, width, height)
                    var grad = ctx.createLinearGradient(0, 0, 0, height)
                    grad.addColorStop(0, theme.catServices); grad.addColorStop(1, "transparent")
                    var mid = height * 0.55
                    var pts = []
                    for (var i = 0; i < 32; i++) {
                        var x = i * width / 31
                        var y = mid + Math.sin(i * 0.6 + Date.now() * 0.001) * (height * 0.14)
                              + Math.sin(i * 1.3 + Date.now() * 0.002) * (height * 0.07)
                        pts.push({x: x, y: y})
                    }
                    ctx.beginPath(); ctx.moveTo(0, height)
                    for (var k = 0; k < pts.length; k++) ctx.lineTo(pts[k].x, pts[k].y)
                    ctx.lineTo(width, height); ctx.closePath()
                    ctx.fillStyle = grad; ctx.globalAlpha = 0.35; ctx.fill(); ctx.globalAlpha = 1
                    ctx.beginPath()
                    for (var j = 0; j < pts.length; j++) j === 0 ? ctx.moveTo(pts[j].x, pts[j].y) : ctx.lineTo(pts[j].x, pts[j].y)
                    ctx.strokeStyle = theme.catServices; ctx.lineWidth = 2.5; ctx.stroke()
                }
                Timer { interval: 250; running: Qt.application.active; repeat: true; onTriggered: cv.requestPaint() }
            }
        }
    }

    // ── FOCUS (ADHD-friendly) ───────────────────────────────────────────
    Component {
        id: pomodoroComp
        WidgetChrome {
            title: "Focus Timer"; icon: "🎯"; accentColor: theme.catProductivity
            showHeader: big
            FocusTimer { anchors.fill: parent; big: parent.big }
        }
    }

    Component {
        id: checklistComp
        WidgetChrome {
            id: clw
            title: "Tasks"; icon: "✅"; accentColor: theme.catProductivity
            property var items: ["Review PRs", "Update docs", "Standup sync", "Deploy build", "Clear inbox"]
            property var checked: [false, false, false, false, false]
            status: checked.filter(function(c){return c}).length + "/" + items.length
            ColumnLayout { anchors.fill: parent; spacing: big ? 6 : 2
                Repeater { model: clw.items
                    delegate: Item { required property int index; required property var modelData
                        Layout.fillWidth: true; Layout.preferredHeight: big ? 46 : 22
                        Rectangle { anchors.fill: parent; radius: theme.radiusSm
                            color: clw.checked[index] ? Qt.rgba(theme.catProductivity.r, theme.catProductivity.g, theme.catProductivity.b, 0.10) : "transparent" }
                        RowLayout { anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; spacing: theme.spacingSm
                            Rectangle { Layout.preferredWidth: big ? 28 : 16; Layout.preferredHeight: big ? 28 : 16; radius: 7
                                color: clw.checked[index] ? theme.catProductivity : "transparent"
                                border.width: 2; border.color: clw.checked[index] ? theme.catProductivity : theme.cardBorder
                                Text { anchors.centerIn: parent; visible: clw.checked[index]; text: "✓"; font.pixelSize: big ? 16 : 10; color: "#0D1117"; font.bold: true } }
                            Text { text: modelData; font.pixelSize: big ? 18 : 11; Layout.fillWidth: true; elide: Text.ElideRight
                                font.strikeout: clw.checked[index]
                                color: clw.checked[index] ? theme.textTertiary : theme.textPrimary } }
                        MouseArea { anchors.fill: parent; enabled: big
                            onClicked: { var c = clw.checked.slice(); c[index] = !c[index]; clw.checked = c } }
                    }
                }
            }
        }
    }

    Component {
        id: habitsComp
        WidgetChrome {
            id: hw
            title: "Habit Streak"; icon: "🔥"; accentColor: theme.catProductivity
            property int streak: new Date().getDate() % 12 + 3
            status: big ? "" : hw.streak + "🔥"
            ColumnLayout { anchors.centerIn: parent; spacing: big ? 10 : 4
                Text { Layout.alignment: Qt.AlignHCenter; visible: big; text: hw.streak + " day streak 🔥"
                    font.pixelSize: 20; font.bold: true; color: theme.catProductivity }
                GridLayout { Layout.alignment: Qt.AlignHCenter; columns: 7; rowSpacing: big ? 6 : 3; columnSpacing: big ? 6 : 3
                    Repeater { model: 28
                        delegate: Rectangle { required property int index
                            property int cell: big ? 26 : 13; width: cell; height: cell; radius: 5
                            property bool done: index < new Date().getDate()
                            color: done ? Qt.rgba(theme.catProductivity.r, theme.catProductivity.g, theme.catProductivity.b, 0.35 + (index % 4) * 0.15) : theme.cardBorder
                            border.width: index === new Date().getDate() - 1 ? 2 : 0; border.color: theme.catProductivity } }
                }
            }
        }
    }

    Component {
        id: waterComp
        WidgetChrome {
            id: ww
            title: "Hydration"; icon: "💧"; accentColor: theme.catInfo
            property int glasses: 3; property int goal: 8
            status: ww.glasses + "/" + ww.goal
            ColumnLayout { anchors.centerIn: parent; spacing: big ? 14 : 6; width: parent.width * 0.9
                RowLayout { Layout.alignment: Qt.AlignHCenter; spacing: 4
                    Repeater { model: ww.goal
                        delegate: Text { required property int index; text: index < ww.glasses ? "💧" : "○"
                            font.pixelSize: big ? 26 : 14; opacity: index < ww.glasses ? 1 : 0.4 } }
                }
                RowLayout { Layout.alignment: Qt.AlignHCenter; visible: big; spacing: theme.spacingMd
                    PillButton { label: "−"; onClicked: ww.glasses = Math.max(0, ww.glasses - 1) }
                    PillButton { label: "+ Glass"; primary: true; tint: theme.catInfo; onClicked: ww.glasses = Math.min(ww.goal, ww.glasses + 1) }
                }
                Text { Layout.alignment: Qt.AlignHCenter; visible: !big; text: ww.glasses + " of " + ww.goal + " glasses"; font.pixelSize: 11; color: theme.textSecondary }
            }
        }
    }

    // ── INFORMATION ─────────────────────────────────────────────────────
    Component {
        id: moonComp
        WidgetChrome {
            id: mw
            title: "Moon Phase"; icon: "🌙"; accentColor: theme.catInfo; showHeader: big
            property var phases: ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]
            property var names: ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous", "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
            property int idx: {
                var lp = 2551443, now = new Date().getTime() / 1000
                var since = now - new Date(2000, 0, 6, 18, 14).getTime() / 1000
                return Math.floor(((since % lp) / lp) * 8 + 0.5) % 8
            }
            ColumnLayout { anchors.centerIn: parent; spacing: big ? 12 : 2
                Text { Layout.alignment: Qt.AlignHCenter; text: mw.phases[mw.idx]; font.pixelSize: big ? 120 : 44 }
                Text { Layout.alignment: Qt.AlignHCenter; text: mw.names[mw.idx]; font.pixelSize: big ? 22 : 11; color: theme.textSecondary }
                Text { Layout.alignment: Qt.AlignHCenter; visible: big
                    text: Math.round((1 - Math.abs(4 - mw.idx) / 4) * 100) + "% illuminated"; font.pixelSize: 15; color: theme.textTertiary }
            }
        }
    }

    Component {
        id: quoteComp
        WidgetChrome {
            id: qw
            title: "Daily Quote"; icon: "💬"; accentColor: theme.catInfo; showHeader: big
            property var quotes: [
                { t: "Simplicity is the soul of efficiency.", a: "Austin Freeman" },
                { t: "Make it work, make it right, make it fast.", a: "Kent Beck" },
                { t: "The best way out is always through.", a: "Robert Frost" },
                { t: "Focus is saying no to a thousand good ideas.", a: "Steve Jobs" },
                { t: "Well done is better than well said.", a: "Ben Franklin" },
                { t: "Discipline equals freedom.", a: "Jocko Willink" }
            ]
            property var q: quotes[new Date().getDate() % quotes.length]
            ColumnLayout { anchors.centerIn: parent; width: parent.width * 0.9; spacing: big ? 14 : 4
                Text { Layout.alignment: Qt.AlignHCenter; text: "“"; font.pixelSize: big ? 60 : 26; color: theme.catInfo; font.bold: true }
                Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: qw.q.t; font.pixelSize: big ? 26 : 13; font.italic: true; color: theme.textPrimary }
                Text { Layout.alignment: Qt.AlignHCenter; text: "— " + qw.q.a; font.pixelSize: big ? 16 : 10; color: theme.textSecondary }
            }
        }
    }

    Component {
        id: countdownComp
        WidgetChrome {
            id: cdw
            title: "Countdown"; icon: "🎯"; accentColor: theme.catInfo; showHeader: big
            property var target: new Date("2026-12-25")
            property string label: "Christmas"
            property int days: Math.max(0, Math.ceil((cdw.target - new Date()) / 86400000))
            ColumnLayout { anchors.centerIn: parent; spacing: big ? 8 : 2
                Text { Layout.alignment: Qt.AlignHCenter; text: cdw.days > 0 ? cdw.days : "🎉"
                    font.pixelSize: big ? 120 : 44; font.bold: true; font.family: theme.fontMono; color: theme.catInfo }
                Text { Layout.alignment: Qt.AlignHCenter; text: cdw.days > 0 ? "days until " + cdw.label : "Merry " + cdw.label + "!"
                    font.pixelSize: big ? 22 : 11; color: theme.textSecondary }
            }
        }
    }

    Component {
        id: eodComp
        WidgetChrome {
            id: ew
            title: "End of Day"; icon: "🌆"; accentColor: theme.catInfo
            property real frac: {
                dashboard._tick
                var n = new Date(), s = new Date(n); s.setHours(9, 0, 0, 0)
                var e = new Date(n); e.setHours(17, 0, 0, 0)
                return Math.max(0, Math.min(1, (n - s) / (e - s)))
            }
            property string remaining: {
                dashboard._tick
                var n = new Date(), e = new Date(n); e.setHours(17, 0, 0, 0)
                var d = (e - n) / 1000
                return d > 0 ? Math.floor(d / 3600) + "h " + Math.floor((d % 3600) / 60) + "m" : "Done! 🎉"
            }
            ColumnLayout { anchors.centerIn: parent; spacing: big ? 12 : 4; width: parent.width * 0.85
                Text { Layout.alignment: Qt.AlignHCenter; text: ew.remaining
                    font.pixelSize: big ? 72 : 24; font.bold: true; font.family: theme.fontMono; color: theme.catInfo }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: big ? 10 : 6; radius: height / 2; color: theme.cardBorder
                    Rectangle { height: parent.height; radius: height / 2; width: parent.width * ew.frac; color: theme.catInfo
                        Behavior on width { NumberAnimation { duration: 500 } } } }
                Text { Layout.alignment: Qt.AlignHCenter; visible: big; text: Math.round(ew.frac * 100) + "% of workday complete"; font.pixelSize: 14; color: theme.textSecondary }
            }
        }
    }

    Component {
        id: weatherComp
        WidgetChrome {
            id: wtw
            title: "Weather"; icon: "⛅"; accentColor: theme.catInfo
            // Sample data; a real forecast can be wired via XMLHttpRequest (Open-Meteo).
            property var days: [
                { d: "Now", t: 21, i: "☀️" }, { d: "Mon", t: 19, i: "⛅" },
                { d: "Tue", t: 17, i: "🌧" }, { d: "Wed", t: 22, i: "☀️" }
            ]
            ColumnLayout { anchors.fill: parent; spacing: big ? 10 : 4
                RowLayout { Layout.alignment: Qt.AlignHCenter; spacing: theme.spacingMd
                    Text { text: wtw.days[0].i; font.pixelSize: big ? 64 : 30 }
                    ColumnLayout { spacing: 0
                        Text { text: wtw.days[0].t + "°"; font.pixelSize: big ? 56 : 26; font.bold: true; color: theme.textPrimary }
                        Text { text: "Feels 19°"; font.pixelSize: big ? 14 : 9; color: theme.textSecondary; visible: big } } }
                RowLayout { Layout.alignment: Qt.AlignHCenter; visible: big; spacing: theme.spacingLg
                    Repeater { model: wtw.days.slice(1)
                        delegate: ColumnLayout { required property var modelData; spacing: 2
                            Text { Layout.alignment: Qt.AlignHCenter; text: modelData.d; font.pixelSize: 12; color: theme.textSecondary }
                            Text { Layout.alignment: Qt.AlignHCenter; text: modelData.i; font.pixelSize: 22 }
                            Text { Layout.alignment: Qt.AlignHCenter; text: modelData.t + "°"; font.pixelSize: 14; color: theme.textPrimary } } }
                }
            }
        }
    }

    // ── ENTERTAINMENT ───────────────────────────────────────────────────
    Component {
        id: mediaComp
        WidgetChrome {
            id: med
            title: "Now Playing"; icon: "🎵"; accentColor: theme.catEntertainment
            property bool playing: true
            property real pos: 0.42
            ColumnLayout { anchors.fill: parent; spacing: big ? 10 : 4
                RowLayout { Layout.fillWidth: true; spacing: theme.spacingMd
                    Rectangle { Layout.preferredWidth: big ? 72 : 40; Layout.preferredHeight: big ? 72 : 40; radius: theme.radiusSm
                        gradient: Gradient { GradientStop { position: 0; color: theme.catEntertainment } GradientStop { position: 1; color: theme.accent } }
                        Text { anchors.centerIn: parent; text: "♪"; font.pixelSize: big ? 34 : 20; color: "#fff" } }
                    ColumnLayout { Layout.fillWidth: true; spacing: 2
                        Text { text: "Midnight City"; font.pixelSize: big ? 20 : 12; font.bold: true; color: theme.textPrimary; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: "M83"; font.pixelSize: big ? 15 : 10; color: theme.textSecondary; elide: Text.ElideRight; Layout.fillWidth: true } } }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 5; radius: 3; color: theme.cardBorder
                    Rectangle { height: parent.height; radius: 3; width: parent.width * med.pos; color: theme.catEntertainment } }
                RowLayout { Layout.alignment: Qt.AlignHCenter; visible: big; spacing: theme.spacingLg
                    Text { text: "⏮"; font.pixelSize: 26; color: theme.textPrimary; MouseArea { anchors.fill: parent } }
                    Rectangle { Layout.preferredWidth: 56; Layout.preferredHeight: 56; radius: 28; color: theme.catEntertainment
                        Text { anchors.centerIn: parent; text: med.playing ? "⏸" : "▶"; font.pixelSize: 24; color: "#0D1117" }
                        MouseArea { anchors.fill: parent; onClicked: med.playing = !med.playing } }
                    Text { text: "⏭"; font.pixelSize: 26; color: theme.textPrimary; MouseArea { anchors.fill: parent } } }
            }
        }
    }

    Component {
        id: diceComp
        WidgetChrome {
            id: dw
            title: "Dice Roller"; icon: "🎲"; accentColor: theme.catEntertainment; showHeader: big
            property int sides: 6; property int last: 0
            property bool rolling: false
            function roll() { rolling = true; rollAnim.n = 0; rollAnim.restart() }
            Timer { id: rollAnim; interval: 60; repeat: true; running: dw.rolling; property int n: 0
                onTriggered: { dw.last = Math.floor(Math.random() * dw.sides) + 1; n++; if (n > 8) { dw.rolling = false } } }
            ColumnLayout { anchors.centerIn: parent; spacing: big ? 16 : 4
                Rectangle { Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: big ? 130 : 60; Layout.preferredHeight: big ? 130 : 60; radius: theme.radiusLg
                    gradient: Gradient { GradientStop { position: 0; color: theme.catEntertainment } GradientStop { position: 1; color: theme.accent } }
                    Text { anchors.centerIn: parent; text: dw.last > 0 ? dw.last : "🎲"
                        font.pixelSize: big ? 64 : 28; font.bold: true; color: "#fff" }
                    scale: dw.rolling ? 1.08 : 1.0; Behavior on scale { NumberAnimation { duration: 60 } } }
                Text { Layout.alignment: Qt.AlignHCenter; visible: !big; text: "d" + dw.sides; font.pixelSize: 12; color: theme.textSecondary }
                RowLayout { Layout.alignment: Qt.AlignHCenter; visible: big; spacing: theme.spacingSm
                    Repeater { model: [4, 6, 8, 10, 12, 20]
                        delegate: Rectangle { required property var modelData
                            Layout.preferredWidth: theme.touchTertiary; Layout.preferredHeight: theme.touchTertiary; radius: theme.radiusSm
                            color: dw.sides === modelData ? theme.catEntertainment : theme.cardBackgroundAlt
                            Text { anchors.centerIn: parent; text: "d" + modelData; font.pixelSize: 13; color: dw.sides === modelData ? "#0D1117" : theme.textSecondary }
                            MouseArea { anchors.fill: parent; onClicked: { dw.sides = modelData; dw.last = 0 } } } } }
                PillButton { Layout.alignment: Qt.AlignHCenter; visible: big; label: "Roll"; glyph: "🎲"; primary: true; tint: theme.catEntertainment; implicitWidth: 160; onClicked: dw.roll() }
            }
            MouseArea { anchors.fill: parent; enabled: !big; onClicked: dw.roll() }
        }
    }

    Component {
        id: doodleComp
        WidgetChrome {
            id: dpw
            title: "Doodle Pad"; icon: "✏️"; accentColor: theme.catEntertainment
            headerRightItem: Text { text: "Clear"; font.pixelSize: 11; color: theme.accent
                MouseArea { anchors.fill: parent; onClicked: { doodle.getContext('2d').clearRect(0,0,doodle.width,doodle.height); doodle.requestPaint() } } }
            Rectangle { anchors.fill: parent; radius: theme.radiusSm; color: Qt.rgba(0,0,0,0.25); clip: true
                Canvas { id: doodle; anchors.fill: parent; property real lx: -1; property real ly: -1
                    onPaint: {} }
                MouseArea { anchors.fill: parent
                    onPressed: function(m) { doodle.lx = m.x; doodle.ly = m.y }
                    onPositionChanged: function(m) {
                        var ctx = doodle.getContext('2d')
                        ctx.strokeStyle = theme.accent; ctx.lineWidth = 3; ctx.lineCap = "round"
                        ctx.beginPath(); ctx.moveTo(doodle.lx, doodle.ly); ctx.lineTo(m.x, m.y); ctx.stroke()
                        doodle.lx = m.x; doodle.ly = m.y; doodle.requestPaint()
                    } }
            }
        }
    }

    // ── GAMING ──────────────────────────────────────────────────────────
    Component {
        id: fpsComp
        WidgetChrome {
            id: fw
            title: "FPS / GPU"; icon: "🎮"; accentColor: theme.catGaming
            property real fps: 60 + Math.round(Math.sin(dashboard._tick * 0.5) * 30 + 90)
            property real gpu: dashboard.metrics.gpu_usage_percent || (40 + Math.round(Math.abs(Math.sin(dashboard._tick * 0.3)) * 50))
            ColumnLayout { anchors.centerIn: parent; spacing: big ? 12 : 4; width: parent.width * 0.85
                Text { Layout.alignment: Qt.AlignHCenter; text: fw.fps + " FPS"
                    font.pixelSize: big ? 84 : 30; font.bold: true; font.family: theme.fontMono
                    color: fw.fps >= 120 ? theme.success : fw.fps >= 60 ? theme.catGaming : theme.warning }
                RowLayout { Layout.fillWidth: true; spacing: theme.spacingSm; visible: big
                    Text { text: "GPU"; font.pixelSize: 14; color: theme.textSecondary; Layout.preferredWidth: 50 }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 8; radius: 4; color: theme.cardBorder
                        Rectangle { height: parent.height; radius: 4; width: parent.width * Math.min(fw.gpu / 100, 1); color: theme.catGaming } }
                    Text { text: fw.gpu.toFixed(0) + "%"; font.pixelSize: 14; font.family: theme.fontMono; color: theme.textPrimary } }
            }
        }
    }

    Component {
        id: f1Comp
        WidgetChrome {
            id: f1w
            title: "Next Race"; icon: "🏁"; accentColor: theme.catGaming; showHeader: big
            property var target: new Date("2026-07-26T14:00:00")
            property int days: Math.max(0, Math.ceil((f1w.target - new Date()) / 86400000))
            ColumnLayout { anchors.centerIn: parent; spacing: big ? 8 : 2
                Text { Layout.alignment: Qt.AlignHCenter; text: "🏎"; font.pixelSize: big ? 56 : 26 }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Belgian GP"; font.pixelSize: big ? 24 : 12; font.bold: true; color: theme.textPrimary }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Spa-Francorchamps"; font.pixelSize: big ? 15 : 9; color: theme.textSecondary; visible: big }
                Text { Layout.alignment: Qt.AlignHCenter; text: f1w.days + " days"; font.pixelSize: big ? 40 : 16; font.bold: true; font.family: theme.fontMono; color: theme.catGaming }
            }
        }
    }

    // ── AMBIENT ─────────────────────────────────────────────────────────
    Component {
        id: analogComp
        WidgetChrome {
            title: "Analog"; icon: "🕰"; accentColor: theme.catSystem; showHeader: big
            Canvas { id: cv; anchors.fill: parent; anchors.margins: theme.spacingSm
                onPaint: {
                    var ctx = getContext('2d'); var cx = width / 2, cy = height / 2, rad = Math.min(cx, cy) - 6
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = theme.cardBorder; ctx.lineWidth = Math.max(4, rad * 0.05)
                    ctx.beginPath(); ctx.arc(cx, cy, rad, 0, 2 * Math.PI); ctx.stroke()
                    for (var t = 0; t < 12; t++) {
                        var ta = t * Math.PI / 6
                        ctx.strokeStyle = theme.textTertiary; ctx.lineWidth = 2
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(ta) * rad * 0.88, cy + Math.sin(ta) * rad * 0.88)
                        ctx.lineTo(cx + Math.cos(ta) * rad * 0.96, cy + Math.sin(ta) * rad * 0.96)
                        ctx.stroke()
                    }
                    var now = new Date(), h = now.getHours() % 12, m = now.getMinutes(), s = now.getSeconds()
                    var ha = (h + m / 60) * Math.PI / 6 - 1.57, ma = (m + s / 60) * Math.PI / 30 - 1.57, sa = s * Math.PI / 30 - 1.57
                    ctx.strokeStyle = theme.textPrimary; ctx.lineWidth = Math.max(3, rad * 0.045); ctx.lineCap = "round"
                    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(ha) * rad * 0.5, cy + Math.sin(ha) * rad * 0.5); ctx.stroke()
                    ctx.lineWidth = Math.max(2, rad * 0.03)
                    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(ma) * rad * 0.72, cy + Math.sin(ma) * rad * 0.72); ctx.stroke()
                    ctx.strokeStyle = theme.accent; ctx.lineWidth = Math.max(1, rad * 0.02)
                    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(sa) * rad * 0.82, cy + Math.sin(sa) * rad * 0.82); ctx.stroke()
                    ctx.fillStyle = theme.accent; ctx.beginPath(); ctx.arc(cx, cy, rad * 0.05, 0, 2 * Math.PI); ctx.fill()
                }
                Timer { interval: 1000; running: Qt.application.active; repeat: true; onTriggered: cv.requestPaint() }
                Component.onCompleted: cv.requestPaint()
            }
        }
    }

    property var registry: ({
        "clock": clockComp, "cpu": cpuComp, "ram": ramComp, "sensors": sensorsComp, "network": networkComp,
        "pomodoro": pomodoroComp, "checklist": checklistComp, "habits": habitsComp, "water": waterComp,
        "moon": moonComp, "quote": quoteComp, "countdown": countdownComp, "eod": eodComp, "weather": weatherComp,
        "media": mediaComp, "dice": diceComp, "doodle": doodleComp,
        "fps": fpsComp, "f1": f1Comp, "analog": analogComp
    })
    property var titles: ({
        "clock": "Clock", "cpu": "CPU", "ram": "Memory", "sensors": "Sensors", "network": "Network",
        "pomodoro": "Focus Timer", "checklist": "Tasks", "habits": "Habit Streak", "water": "Hydration",
        "moon": "Moon Phase", "quote": "Daily Quote", "countdown": "Countdown", "eod": "End of Day", "weather": "Weather",
        "media": "Now Playing", "dice": "Dice Roller", "doodle": "Doodle Pad",
        "fps": "FPS / GPU", "f1": "Next Race", "analog": "Analog Clock"
    })
    property var icons: ({
        "clock": "🕐", "cpu": "🖥", "ram": "🧠", "sensors": "📊", "network": "📡",
        "pomodoro": "🎯", "checklist": "✅", "habits": "🔥", "water": "💧",
        "moon": "🌙", "quote": "💬", "countdown": "🎯", "eod": "🌆", "weather": "⛅",
        "media": "🎵", "dice": "🎲", "doodle": "✏️",
        "fps": "🎮", "f1": "🏁", "analog": "🕰"
    })
    property var colors: ({
        "clock": theme.catSystem, "cpu": theme.catSystem, "ram": theme.catSystem, "sensors": theme.catSystem, "network": theme.catServices,
        "pomodoro": theme.catProductivity, "checklist": theme.catProductivity, "habits": theme.catProductivity, "water": theme.catInfo,
        "moon": theme.catInfo, "quote": theme.catInfo, "countdown": theme.catInfo, "eod": theme.catInfo, "weather": theme.catInfo,
        "media": theme.catEntertainment, "dice": theme.catEntertainment, "doodle": theme.catEntertainment,
        "fps": theme.catGaming, "f1": theme.catGaming, "analog": theme.catSystem
    })

    // ═══════════════════════════════════════════════════════════════════
    //  Layout model — 3 square slots per page, grouped by category.
    // ═══════════════════════════════════════════════════════════════════
    property var pages: [
        { name: "System",  slots: [ { w: "clock" }, { split: true, top: "cpu", bottom: "ram" }, { split: true, top: "network", bottom: "sensors" } ] },
        { name: "Focus",   slots: [ { w: "pomodoro" }, { w: "checklist" }, { split: true, top: "habits", bottom: "water" } ] },
        { name: "Info",    slots: [ { w: "weather" }, { split: true, top: "moon", bottom: "eod" }, { split: true, top: "countdown", bottom: "quote" } ] },
        { name: "Play",    slots: [ { w: "media" }, { split: true, top: "dice", bottom: "f1" }, { split: true, top: "fps", bottom: "doodle" } ] },
        { name: "Ambient", slots: [ { w: "analog" }, { w: "clock" }, { w: "quote" } ] }
    ]

    // Reusable tile frame. `tileId` provided by the loading Loader.
    Component {
        id: tileComp
        Item {
            id: tile
            scale: tileMA.pressed ? 0.985 : 1.0
            Behavior on scale { NumberAnimation { duration: theme.motionFast; easing.type: Easing.OutCubic } }

            Loader { anchors.fill: parent; sourceComponent: dashboard.registry[tileId] }

            Text { anchors.right: parent.right; anchors.top: parent.top; anchors.margins: theme.spacingMd
                text: "⤢"; font.pixelSize: 16; color: dashboard.colors[tileId]
                opacity: tileMA.containsMouse ? 0.95 : 0.35; z: 20
                Behavior on opacity { NumberAnimation { duration: theme.motionFast } } }

            MouseArea { id: tileMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                propagateComposedEvents: true
                onClicked: {
                    dashboard.expandComp = dashboard.registry[tileId]
                    dashboard.expandTitle = dashboard.titles[tileId]
                    dashboard.expandIcon = dashboard.icons[tileId]
                    dashboard.expandColor = dashboard.colors[tileId]
                }
            }
        }
    }

    Component { id: fullSlot
        Loader { anchors.fill: parent; sourceComponent: tileComp; property string tileId: slotData.w }
    }
    Component { id: splitSlot
        ColumnLayout { anchors.fill: parent; spacing: theme.spacingMd
            Loader { Layout.fillWidth: true; Layout.fillHeight: true; sourceComponent: tileComp; property string tileId: slotData.top }
            Loader { Layout.fillWidth: true; Layout.fillHeight: true; sourceComponent: tileComp; property string tileId: slotData.bottom }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Page container
    // ═══════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: theme.spacingMd
        spacing: theme.spacingSm

        SwipeView {
            id: swipeView
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true

            Repeater {
                model: dashboard.pages
                delegate: Item {
                    required property int index
                    property var pageData: dashboard.pages[index]

                    GridLayout {
                        anchors.fill: parent
                        rows: dashboard.isLandscape ? 1 : 3
                        columns: dashboard.isLandscape ? 3 : 1
                        rowSpacing: theme.spacingMd
                        columnSpacing: theme.spacingMd

                        Repeater {
                            model: pageData.slots
                            delegate: Loader {
                                required property var modelData
                                property var slotData: modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                sourceComponent: modelData.split ? splitSlot : fullSlot
                            }
                        }
                    }
                }
            }
        }

        // Bottom bar: page label + indicator + settings
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: theme.touchSecondary
            spacing: theme.spacingMd

            Text {
                Layout.preferredWidth: theme.touchSecondary * 2
                text: dashboard.pages[swipeView.currentIndex].name
                font.pixelSize: theme.fontLabel; font.weight: Font.DemiBold
                font.family: theme.fontDisplay; color: theme.textSecondary
                verticalAlignment: Text.AlignVCenter
            }

            PageIndicator {
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: true
                count: swipeView.count
                currentIndex: swipeView.currentIndex
                interactive: true
                onCurrentIndexChanged: swipeView.currentIndex = currentIndex

                delegate: Rectangle {
                    implicitWidth: index === swipeView.currentIndex ? 22 : 10
                    implicitHeight: 10; radius: 5
                    color: theme.accent
                    opacity: index === swipeView.currentIndex ? 0.95 : 0.3
                    Behavior on implicitWidth { NumberAnimation { duration: theme.motionFast } }
                    Behavior on opacity { NumberAnimation { duration: theme.motionFast } }
                }
            }

            // Appearance settings
            Rectangle {
                Layout.preferredWidth: theme.touchSecondary
                Layout.preferredHeight: theme.touchSecondary
                radius: theme.radiusMd
                color: gearMA.containsMouse ? theme.cardBackground : "transparent"
                border.width: 1; border.color: theme.cardBorder
                Text { anchors.centerIn: parent; text: "🎨"; font.pixelSize: 20 }
                MouseArea { id: gearMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: settings.shown = true }
            }

            // Diagnostics
            Rectangle {
                Layout.preferredWidth: theme.touchSecondary
                Layout.preferredHeight: theme.touchSecondary
                radius: theme.radiusMd
                color: diagMA.containsMouse ? theme.cardBackground : "transparent"
                border.width: 1; border.color: theme.cardBorder
                Text { anchors.centerIn: parent; text: "⚙"; font.pixelSize: 22; color: theme.textSecondary }
                MouseArea {
                    id: diagMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (dashboard.host)
                            dashboard.host.push("qrc:/qml/Diagnostics.qml", {
                                "metricsJson": Qt.binding(function () { return metricsJson }),
                                "screensData": screensData
                            })
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  Expanded widget overlay
    // ═══════════════════════════════════════════════════════════════════
    ExpandedWidget {
        id: overlay
        shown: dashboard.expandComp !== null
        widgetTitle: dashboard.expandTitle
        widgetIcon: dashboard.expandIcon
        accentColor: dashboard.expandColor
        widgetContent: dashboard.expandComp
        onCloseRequested: { dashboard.expandComp = null; dashboard.expandTitle = "" }
    }

    // Appearance / settings overlay
    SettingsPanel {
        id: settings
        onCloseRequested: shown = false
    }
}
