import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: dashboard
    anchors.fill: parent

    property int _tick: 0

    // Parsed metrics from C++
    property var metrics: {
        try { return JSON.parse(metricsJson || "{}"); } catch(e) { return {}; }
    }

    // Currently expanded widget
    property string _expandedWidget: ""
    property var _expandedComponent: null

    // Helpers
    function fmtBytes(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB"
        if (b >= 1048576) return (b / 1048576).toFixed(0) + " MB"
        return (b / 1024).toFixed(0) + " KB"
    }

    Rectangle {
        anchors.fill: parent
        color: theme.backgroundColor
    }

    // Top accent bar
    Rectangle {
        anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.5; height: 3; radius: 1.5
        color: theme.accent; opacity: 0.4
    }

    property bool isLandscape: parent.width > parent.height * 1.2

    // --- Expanded widget overlay ---
    ExpandedWidget {
        id: expandedOverlay
        visible: _expandedWidget !== ""
        widgetTitle: _expandedWidget
        widgetContent: _expandedComponent
        onCloseRequested: {
            _expandedWidget = ""
            _expandedComponent = null
        }
    }

    // --- SwipeView Workspaces ---
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        SwipeView {
            id: swipeView
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; interactive: true

            // ═══ WORKSPACE 1: System & Monitoring ═══
            Item {
                GridLayout {
                    anchors.fill: parent; anchors.margins: 6
                    columns: isLandscape ? 4 : 2
                    columnSpacing: 6; rowSpacing: 6

                    // CLOCK — live digital clock
                    WidgetCard { title: "Time"; icon: "🕐"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        Layout.columnSpan: isLandscape ? 1 : 2
                        Text { anchors.centerIn: parent
                            text: Qt.formatTime(new Date(), "HH:mm")
                            font.pixelSize: 52; font.bold: true; font.family: "monospace"
                            color: theme.textPrimary
                        }
                        onTapped: { _expandedWidget = "Clock"; _expandedComponent = clockExp }
                    }

                    // CPU — live usage
                    WidgetCard { title: "CPU"; icon: "🖥"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4; width: parent.width - 8
                            Text { Layout.alignment: Qt.AlignHCenter
                                text: ((dashboard.metrics.cpu_usage_percent||0)).toFixed(0) + "%"
                                font.pixelSize: 44; font.bold: true; font.family: "monospace"
                                color: { var p = dashboard.metrics.cpu_usage_percent||0; return p > 80 ? theme.error : p > 50 ? theme.warning : theme.accent }
                            }
                            Rectangle { Layout.preferredWidth: parent.width; Layout.preferredHeight: 6; radius: 3; color: theme.cardBorder
                                Rectangle { height: parent.height; radius: 3; width: parent.width * Math.min(((dashboard.metrics.cpu_usage_percent||0))/100, 1); color: theme.accent }
                            }
                            Text { Layout.alignment: Qt.AlignHCenter; visible: (dashboard.metrics.cpu_temp_celsius||-1) > 0
                                text: (dashboard.metrics.cpu_temp_celsius||0).toFixed(0) + "°C"; font.pixelSize: 12; color: theme.warning }
                        }
                        onTapped: { _expandedWidget = "CPU"; _expandedComponent = cpuExp }
                    }

                    // RAM — live usage
                    WidgetCard { title: "RAM"; icon: "🧠"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4; width: parent.width - 8
                            Text { Layout.alignment: Qt.AlignHCenter
                                text: ((dashboard.metrics.ram_usage_percent||0)).toFixed(0) + "%"
                                font.pixelSize: 44; font.bold: true; font.family: "monospace"
                                color: { var p = dashboard.metrics.ram_usage_percent||0; return p > 90 ? theme.error : p > 70 ? theme.warning : theme.accent }
                            }
                            Rectangle { Layout.preferredWidth: parent.width; Layout.preferredHeight: 6; radius: 3; color: theme.cardBorder
                                Rectangle { height: parent.height; radius: 3; width: parent.width * Math.min(((dashboard.metrics.ram_usage_percent||0))/100, 1); color: theme.accent }
                            }
                            Text { Layout.alignment: Qt.AlignHCenter
                                text: fmtBytes(dashboard.metrics.ram_used_bytes||0) + " / " + fmtBytes(dashboard.metrics.ram_total_bytes||0)
                                font.pixelSize: 10; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "Memory"; _expandedComponent = ramExp }
                    }

                    // NETWORK — animated graph
                    WidgetCard { title: "Network"; icon: "📡"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        Canvas { anchors.fill: parent; anchors.margins: 4
                            onPaint: {
                                var ctx = getContext('2d'); ctx.clearRect(0,0,width,height)
                                ctx.strokeStyle = '#58A6FF'; ctx.lineWidth = 2; ctx.beginPath()
                                var mid = height/2
                                for (var i=0; i<25; i++) { var x=i*width/24; var y=mid+Math.sin(i*0.6+Date.now()*0.001)*20+Math.sin(i*1.3+Date.now()*0.002)*10
                                    i===0?ctx.moveTo(x,y):ctx.lineTo(x,y) }; ctx.stroke()
                            }
                            Timer { interval: 300; running: Qt.application.active && swipeView.currentIndex === 0; repeat: true; onTriggered: parent.requestPaint() }
                        }
                        onTapped: { _expandedWidget = "Network"; _expandedComponent = pingExp }
                    }

                    // SENSORS
                    WidgetCard { title: "Sensors"; icon: "📊"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 6
                            Text { Layout.alignment: Qt.AlignHCenter; text: "CPU " + ((dashboard.metrics.cpu_usage_percent||0)).toFixed(0) + "%"; font.pixelSize: 18; font.family: "monospace"; color: theme.textPrimary }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "RAM " + ((dashboard.metrics.ram_usage_percent||0)).toFixed(0) + "%"; font.pixelSize: 16; font.family: "monospace"; color: theme.textSecondary }
                            Text { Layout.alignment: Qt.AlignHCenter; visible: (dashboard.metrics.cpu_temp_celsius||-1)>0; text: "🌡 " + (dashboard.metrics.cpu_temp_celsius||0).toFixed(0) + "°C"; font.pixelSize: 14; color: theme.warning }
                        }
                        onTapped: { _expandedWidget = "Sensors"; _expandedComponent = sensorExp }
                    }

                    // END OF DAY
                    WidgetCard { title: "End of Day"; icon: "🏁"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4
                            Text { Layout.alignment: Qt.AlignHCenter
                                text: { var now=new Date(); var eod=new Date(now); eod.setHours(17,0,0,0); var d=(eod-now)/1000; return d>0?Math.floor(d/3600)+"h "+Math.floor((d%3600)/60)+"m":"Done!" }
                                font.pixelSize: 36; font.bold: true; font.family: "monospace"; color: theme.accent }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "until 5 PM"; font.pixelSize: 12; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "Workday"; _expandedComponent = eodExp }
                    }

                    // DAILY QUOTE
                    WidgetCard { title: "Quote"; icon: "💬"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4; width: parent.width - 8
                            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 11; color: theme.textSecondary
                                text: { var q=["The only way to do great work is to love what you do.","Stay hungry, stay foolish.","Code is like humor. When you have to explain it, it's bad.","Simplicity is the soul of efficiency."]; return q[new Date().getDate()%q.length] }
                            }
                        }
                        onTapped: { _expandedWidget = "Daily Quote"; _expandedComponent = quoteExp }
                    }

                    // MOON PHASE
                    WidgetCard { title: "Moon"; icon: "🌙"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4
                            Text { Layout.alignment: Qt.AlignHCenter; font.pixelSize: 36
                                text: { var d=new Date(); var p=d.getDate()/29.53; if(p<0.03)return"🌑";if(p<0.22)return"🌒";if(p<0.28)return"🌓";if(p<0.47)return"🌔";if(p<0.53)return"🌕";if(p<0.72)return"🌖";if(p<0.78)return"🌗";return"🌘" }
                            }
                            Text { Layout.alignment: Qt.AlignHCenter; font.pixelSize: 12; color: theme.textSecondary
                                text: { var p=new Date().getDate()/29.53; return (Math.min(p*100,99.9)).toFixed(0)+"% illuminated" }
                            }
                        }
                        onTapped: { _expandedWidget = "Moon Phase"; _expandedComponent = moonExp }
                    }
                }
            }

            // ═══ WORKSPACE 2: Productivity & Tools ═══
            Item {
                GridLayout {
                    anchors.fill: parent; anchors.margins: 6
                    columns: isLandscape ? 4 : 2
                    columnSpacing: 6; rowSpacing: 6

                    // POMODORO
                    WidgetCard { title: "Focus Timer"; icon: "⏱"
                        Layout.fillWidth: true; Layout.preferredHeight: 175; Layout.columnSpan: isLandscape ? 2 : 2
                        property int pMinutes: 25; property int pSeconds: 0; property bool pRunning: false
                        ColumnLayout { anchors.centerIn: parent; spacing: 6
                            Text { Layout.alignment: Qt.AlignHCenter
                                text: String(parent.parent.pMinutes).padStart(2,'0') + ':' + String(parent.parent.pSeconds).padStart(2,'0')
                                font.pixelSize: 48; font.bold: true; font.family: "monospace"
                                color: parent.parent.pRunning ? theme.accent : theme.textPrimary }
                            Rectangle { Layout.preferredWidth: 100; Layout.preferredHeight: 32; Layout.alignment: Qt.AlignHCenter
                                radius: 8; color: parent.parent.pRunning ? theme.error : theme.accent
                                Text { anchors.centerIn: parent; text: parent.parent.pRunning ? "Stop" : "Start"; font.pixelSize: 13; color: "#fff" }
                                MouseArea { anchors.fill: parent;
                                    onClicked: { parent.parent.parent.pRunning = !parent.parent.parent.pRunning } }
                            }
                            Timer { interval: 1000; repeat: true; running: pRunning
                                onTriggered: { if(pSeconds>0)pSeconds--; else if(pMinutes>0){pMinutes--;pSeconds=59}else pRunning=false }
                            }
                        }
                        onTapped: { _expandedWidget = "Focus Timer"; _expandedComponent = pomoExp }
                    }

                    // CHECKLIST
                    WidgetCard { title: "Checklist"; icon: "✅"
                        Layout.fillWidth: true; Layout.preferredHeight: 175; Layout.columnSpan: isLandscape ? 2 : 2
                        property var items: ["Review PRs","Update docs","Standup","Sync","Deploy"]
                        property var checked: [false,false,false,false,false]
                        ListView { anchors.fill: parent; anchors.margins: 4; model: items; spacing: 3; clip: true
                            delegate: RowLayout { width: ListView.view.width - 8; spacing: 6
                                Rectangle { width: 18; height: 18; radius: 5; color: checked[index] ? theme.accent : theme.cardBorder
                                    Text { anchors.centerIn: parent; visible: checked[index]; text: "✓"; font.pixelSize: 10; color: "#000" } }
                                Text { text: modelData; font.pixelSize: 12; color: checked[index] ? theme.textSecondary : theme.textPrimary; Layout.fillWidth: true; elide: Text.ElideRight }
                                MouseArea { width: parent.width; height: 20
                                    onClicked: { var c=checked; c[index]=!c[index]; checked=c } }
                            }
                        }
                        onTapped: { _expandedWidget = "Checklist"; _expandedComponent = checkExp }
                    }

                    // HABIT CALENDAR
                    WidgetCard { title: "Habits"; icon: "📅"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        GridLayout { anchors.centerIn: parent; anchors.margins: 4
                            columns: 7; rowSpacing: 2; columnSpacing: 2
                            Repeater { model: 28
                                Rectangle { width: 16; height: 16; radius: 4
                                    color: index < new Date().getDate() ? Qt.rgba(0.34,0.65,1,0.3+Math.random()*0.4) : theme.cardBorder }
                            }
                        }
                        onTapped: { _expandedWidget = "Habit Tracker"; _expandedComponent = habitExp }
                    }

                    // COUNTDOWN
                    WidgetCard { title: "Countdown"; icon: "⏳"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4
                            Text { Layout.alignment: Qt.AlignHCenter; font.pixelSize: 40; font.bold: true; font.family: "monospace"; color: theme.accent
                                text: { var now=new Date(); var t=new Date("2026-12-25"); var d=Math.ceil((t-now)/86400000); return d>0?d+"d":"Today!" }
                            }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "until Christmas"; font.pixelSize: 11; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "Countdown"; _expandedComponent = cntExp }
                    }

                    // DICE ROLLER
                    WidgetCard { title: "Dice"; icon: "🎲"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        property int lastRoll: 0; property int sides: 6
                        ColumnLayout { anchors.centerIn: parent; spacing: 6
                            Text { Layout.alignment: Qt.AlignHCenter
                                text: lastRoll>0?"🎲 "+lastRoll:"Roll d"+sides
                                font.pixelSize: lastRoll>0?40:20; font.bold: lastRoll>0; color: theme.textPrimary }
                            RowLayout { Layout.alignment: Qt.AlignHCenter; spacing: 4
                                Repeater { model: [4,6,8,10,12,20]
                                    Rectangle { width: 22; height: 22; radius: 5; color: sides===modelData?theme.accent:theme.cardBorder
                                        Text { anchors.centerIn: parent; text: "d"+modelData; font.pixelSize: 7; color: sides===modelData?"#000":theme.textSecondary }
                                        MouseArea { anchors.fill: parent; onClicked: { sides=modelData; lastRoll=0 } } }
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: { parent.parent.lastRoll=Math.floor(Math.random()*parent.parent.sides)+1 } }
                        }
                        onTapped: { _expandedWidget = "Dice Roller"; _expandedComponent = diceExp }
                    }

                    // LUNCH ROULETTE
                    WidgetCard { title: "Lunch"; icon: "🍔"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        property var options: ["🍕 Pizza","🍣 Sushi","🌮 Tacos","🍜 Ramen","🥗 Salad","🍔 Burger","🥙 Kebab","🍝 Pasta"]
                        property string selected: ""
                        ColumnLayout { anchors.centerIn: parent; spacing: 6
                            Text { Layout.alignment: Qt.AlignHCenter
                                text: selected || "Tap to spin!"
                                font.pixelSize: selected?24:16; font.bold: selected!=""; color: selected?theme.accent:theme.textSecondary }
                            Rectangle { Layout.preferredWidth: 100; Layout.preferredHeight: 30; Layout.alignment: Qt.AlignHCenter
                                radius: 8; color: theme.accent
                                Text { anchors.centerIn: parent; text: "🎰 Spin"; font.pixelSize: 12; color: "#fff" }
                                MouseArea { anchors.fill: parent; onClicked: {
                                    parent.parent.parent.selected = parent.parent.parent.options[Math.floor(Math.random()*parent.parent.parent.options.length)] } }
                            }
                        }
                        onTapped: { _expandedWidget = "Lunch"; _expandedComponent = lunchExp }
                    }

                    // LOSS TRACKER
                    WidgetCard { title: "Tracker"; icon: "📈"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        property int wins: 42; property int losses: 18
                        ColumnLayout { anchors.centerIn: parent; spacing: 6
                            Text { Layout.alignment: Qt.AlignHCenter; font.pixelSize: 36; font.bold: true; color: theme.accent
                                text: (wins/(wins+losses)*100).toFixed(0)+"%" }
                            Text { Layout.alignment: Qt.AlignHCenter; font.pixelSize: 12; color: theme.textSecondary
                                text: wins+"W / "+losses+"L" }
                            RowLayout { Layout.alignment: Qt.AlignHCenter; spacing: 4
                                Rectangle { width: 24; height: 24; radius: 5; color: theme.success
                                    Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; color: "#000" }
                                    MouseArea { anchors.fill: parent; onClicked: { wins=wins+1 } } }
                                Rectangle { width: 24; height: 24; radius: 5; color: theme.error
                                    Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 14; color: "#fff" }
                                    MouseArea { anchors.fill: parent; onClicked: { losses=losses+1 } } }
                            }
                        }
                        onTapped: { _expandedWidget = "Win/Loss"; _expandedComponent = lossExp }
                    }

                    // DOODLE PAD
                    WidgetCard { title: "Doodle"; icon: "✏️"
                        Layout.fillWidth: true; Layout.preferredHeight: 160
                        Canvas { anchors.fill: parent; anchors.margins: 2
                            property var points: []
                            onPaint: { var ctx=getContext('2d'); ctx.fillStyle=theme.cardBackground; ctx.fillRect(0,0,width,height); if(points.length<2)return; ctx.strokeStyle=theme.accent;ctx.lineWidth=3;ctx.lineCap="round";ctx.beginPath();ctx.moveTo(points[0].x,points[0].y);for(var i=1;i<points.length;i++)ctx.lineTo(points[i].x,points[i].y);ctx.stroke() }
                            MouseArea { anchors.fill: parent
                                onPressed: parent.points=[]
                                onPositionChanged: { parent.points.push({x:mouseX,y:mouseY}); parent.requestPaint() } }
                        }
                        onTapped: { _expandedWidget = "Doodle"; _expandedComponent = doodleExp }
                    }
                }
            }

            // ═══ WORKSPACE 3: Info & Sports ═══
            Item {
                GridLayout {
                    anchors.fill: parent; anchors.margins: 6
                    columns: isLandscape ? 4 : 2
                    columnSpacing: 6; rowSpacing: 6

                    WidgetCard { title: "Analog Clock"; icon: "🕰"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        Canvas { anchors.fill: parent; anchors.margins: 8
                            onPaint: { var ctx=getContext('2d'); var cx=width/2,cy=height/2,r=Math.min(cx,cy)-4; ctx.clearRect(0,0,width,height); ctx.strokeStyle=theme.cardBorder;ctx.lineWidth=8;ctx.beginPath();ctx.arc(cx,cy,r,0,2*Math.PI);ctx.stroke(); var now=new Date(); var h=now.getHours()%12,m=now.getMinutes(),s=now.getSeconds(); var ha=(h+m/60)*Math.PI/6-1.57,ma=(m+s/60)*Math.PI/30-1.57; ctx.strokeStyle=theme.textPrimary;ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(cx,cy);ctx.lineTo(cx+Math.cos(ha)*r*0.5,cy+Math.sin(ha)*r*0.5);ctx.stroke(); ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(cx,cy);ctx.lineTo(cx+Math.cos(ma)*r*0.75,cy+Math.sin(ma)*r*0.75);ctx.stroke(); ctx.strokeStyle=theme.accent;ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(cx,cy);ctx.lineTo(cx+Math.cos(s*Math.PI/30-1.57)*r*0.85,cy+Math.sin(s*Math.PI/30-1.57)*r*0.85);ctx.stroke() }
                            Timer { interval: 1000; running: Qt.application.active && swipeView.currentIndex === 2; repeat: true; onTriggered: parent.requestPaint() }
                        }
                        onTapped: { _expandedWidget = "Analog Clock"; _expandedComponent = smokeExp } }

                    WidgetCard { title: "Tourbillon"; icon: "⌚"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 2
                            Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatTime(new Date(),"HH:mm:ss"); font.pixelSize: 28; font.bold: true; font.family: "monospace"; color: theme.accent }
                            Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDate(new Date(),"MMM d"); font.pixelSize: 13; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "Tourbillon"; _expandedComponent = robexExp } }

                    WidgetCard { title: "RSS Feed"; icon: "📰"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4; width: parent.width-4
                            Repeater { model: ["Linux 6.12 released with RT support","Qt 6.8 adds new rendering backend","Rust 1.82 stabilizes new traits"]
                                Text { Layout.fillWidth: true; text: "•  "+modelData; font.pixelSize: 10; elide: Text.ElideRight; color: theme.textSecondary } }
                        }
                        onTapped: { _expandedWidget = "RSS Feed"; _expandedComponent = rssExp } }

                    WidgetCard { title: "Cards"; icon: "💳"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4
                            Text { Layout.alignment: Qt.AlignHCenter; text: "🏦 2% Cashback"; font.pixelSize: 14; font.bold: true; color: theme.accent }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "✈ 3x Travel"; font.pixelSize: 13; color: theme.textSecondary }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "🍽 5x Dining"; font.pixelSize: 13; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "Cards"; _expandedComponent = cardExp } }

                    // Sports scoreboards
                    WidgetCard { title: "MLB"; icon: "⚾"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 2
                            Text { Layout.alignment: Qt.AlignHCenter; text: "LAD 5 - SF 3"; font.pixelSize: 16; font.bold: true; font.family: "monospace"; color: theme.textPrimary }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "NYY 7 - BOS 4"; font.pixelSize: 14; font.family: "monospace"; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "MLB"; _expandedComponent = bbExp } }

                    WidgetCard { title: "NBA"; icon: "🏀"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 2
                            Text { Layout.alignment: Qt.AlignHCenter; text: "LAL 112 - GSW 108"; font.pixelSize: 16; font.bold: true; font.family: "monospace"; color: theme.textPrimary }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "BOS 98 - MIA 95"; font.pixelSize: 14; font.family: "monospace"; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "NBA"; _expandedComponent = bballExp } }

                    WidgetCard { title: "NFL"; icon: "🏈"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 2
                            Text { Layout.alignment: Qt.AlignHCenter; text: "KC 31 - SF 28"; font.pixelSize: 16; font.bold: true; font.family: "monospace"; color: theme.textPrimary }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "DAL 24 - PHI 21"; font.pixelSize: 14; font.family: "monospace"; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "NFL"; _expandedComponent = fbExp } }

                    WidgetCard { title: "NHL"; icon: "🏒"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 2
                            Text { Layout.alignment: Qt.AlignHCenter; text: "TOR 4 - MTL 2"; font.pixelSize: 16; font.bold: true; font.family: "monospace"; color: theme.textPrimary }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "EDM 5 - CGY 3"; font.pixelSize: 14; font.family: "monospace"; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "NHL"; _expandedComponent = hockeyExp } }

                    WidgetCard { title: "F1"; icon: "🏎"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4
                            Text { Layout.alignment: Qt.AlignHCenter; text: "🏁 Silverstone"; font.pixelSize: 16; font.bold: true; color: theme.accent }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "Next: Jul 14"; font.pixelSize: 14; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "Formula 1"; _expandedComponent = f1Exp } }

                    WidgetCard { title: "Soccer"; icon: "⚽"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 2
                            Text { Layout.alignment: Qt.AlignHCenter; text: "ARS 2 - CHE 1"; font.pixelSize: 16; font.bold: true; font.family: "monospace"; color: theme.textPrimary }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "MCI 3 - LIV 3"; font.pixelSize: 14; font.family: "monospace"; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "Matchday"; _expandedComponent = matchExp } }

                    WidgetCard { title: "BART"; icon: "🚇"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4
                            Text { Layout.alignment: Qt.AlignHCenter; text: "SFO → Embarcadero"; font.pixelSize: 13; font.bold: true; color: theme.accent }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "Next: 4 min • 12 min"; font.pixelSize: 16; font.family: "monospace"; color: theme.textPrimary }
                        }
                        onTapped: { _expandedWidget = "BART"; _expandedComponent = bartExp } }

                    WidgetCard { title: "Tube"; icon: "🚆"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4
                            Text { Layout.alignment: Qt.AlignHCenter; text: "🟢 Central"; font.pixelSize: 14; color: "#DC241F" }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "🟡 Circle"; font.pixelSize: 14; color: "#FFD100" }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "🟣 Piccadilly"; font.pixelSize: 14; color: "#0019A8" }
                        }
                        onTapped: { _expandedWidget = "Tube"; _expandedComponent = tubeExp } }

                    WidgetCard { title: "Commute"; icon: "🚗"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4
                            Text { Layout.alignment: Qt.AlignHCenter; text: "🏠 → 🏢"; font.pixelSize: 18; color: theme.textSecondary }
                            Text { Layout.alignment: Qt.AlignHCenter; text: "~22 min"; font.pixelSize: 32; font.bold: true; color: theme.accent }
                        }
                        onTapped: { _expandedWidget = "Commute"; _expandedComponent = commuteExp } }

                    WidgetCard { title: "Reddit"; icon: "💬"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        ColumnLayout { anchors.centerIn: parent; spacing: 4; width: parent.width-4
                            Repeater { model: ["r/linux • 2.4k ↑ • Kernel 6.12","r/rust • 1.8k ↑ • Async traits","r/programming • 892 ↑ • AI coding"]
                                Text { Layout.fillWidth: true; text: modelData; font.pixelSize: 10; elide: Text.ElideRight; color: theme.textSecondary } }
                        }
                        onTapped: { _expandedWidget = "Readit"; _expandedComponent = readitExp } }

                    WidgetCard { title: "Photos"; icon: "🖼"; Layout.fillWidth: true; Layout.preferredHeight: 160
                        Rectangle { anchors.centerIn: parent; width: parent.width*0.85; height: parent.height*0.8; radius: 8; color: theme.cardBorder
                            Text { anchors.centerIn: parent; text: "🖼"; font.pixelSize: 36; color: theme.textSecondary }
                        }
                        onTapped: { _expandedWidget = "Media"; _expandedComponent = scrollitExp } }
                }
            }
        }

        // --- Page Indicator ---
        PageIndicator {
            id: pageIndicator
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 4
            count: swipeView.count
            currentIndex: swipeView.currentIndex
            delegate: Rectangle {
                width: 8; height: 8; radius: 4
                color: index === pageIndicator.currentIndex ? theme.accent : theme.cardBorder
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }
    }

    // Settings gear
    Rectangle {
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 10
        width: 34; height: 34; radius: 10
        color: theme.cardBackground; border.width: 1; border.color: theme.cardBorder
        z: 10
        Text { anchors.centerIn: parent; text: "⚙"; font.pixelSize: 15; color: theme.textSecondary }
        MouseArea { anchors.fill: parent
            onClicked: { var sv = dashboard.StackView.view; if (sv) sv.push("qrc:/qml/Diagnostics.qml", { "metricsJson": dashboard.metricsJson, "screensData": dashboard.screensData }) }
        }
    }

    // Clock tick
    Timer { interval: 1000; running: Qt.application.active; repeat: true; onTriggered: dashboard._tick++ }

    // ═══════════════════════════════
    // Expanded widget components
    // ═══════════════════════════════

    // Clock expanded
    Component { id: clockExp
        Item { anchors.fill: parent
            ColumnLayout { anchors.centerIn: parent; spacing: 16
                Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatTime(new Date(), "HH:mm:ss"); font.pixelSize: 80; font.bold: true; font.family: "monospace"; color: theme.textPrimary }
                Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDate(new Date(), "dddd, MMMM d yyyy"); font.pixelSize: 24; color: theme.textSecondary }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Week " + Math.ceil(new Date().getDate()/7); font.pixelSize: 18; color: theme.accent }
            }
            Timer { interval: 500; running: true; repeat: true; onTriggered: parent.children[0].children[0].text = Qt.formatTime(new Date(), "HH:mm:ss") }
    }}

    // CPU expanded
    Component { id: cpuExp
        Item { anchors.fill: parent
            ColumnLayout { anchors.centerIn: parent; spacing: 20; width: parent.width * 0.8
                Text { Layout.alignment: Qt.AlignHCenter; text: "CPU Usage"; font.pixelSize: 22; color: theme.textSecondary }
                Text { Layout.alignment: Qt.AlignHCenter; text: ((dashboard.metrics.cpu_usage_percent||0)).toFixed(1)+"%"; font.pixelSize: 88; font.bold: true; font.family: "monospace"
                    color: { var p=dashboard.metrics.cpu_usage_percent||0; return p>80?theme.error:p>50?theme.warning:theme.accent } }
                Rectangle { Layout.preferredWidth: parent.width; Layout.preferredHeight: 12; radius: 6; color: theme.cardBorder
                    Rectangle { height: parent.height; radius: 6; width: parent.width*Math.min(((dashboard.metrics.cpu_usage_percent||0))/100,1); color: theme.accent } }
                Text { Layout.alignment: Qt.AlignHCenter; visible: (dashboard.metrics.cpu_temp_celsius||-1)>0; text: "Temperature: "+(dashboard.metrics.cpu_temp_celsius||0).toFixed(0)+"°C"; font.pixelSize: 24; color: theme.warning }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Cores: "+(dashboard.metrics.cpu_core_count||"?"); font.pixelSize: 18; color: theme.textSecondary }
    }}}

    // RAM expanded
    Component { id: ramExp
        Item { anchors.fill: parent
            ColumnLayout { anchors.centerIn: parent; spacing: 20; width: parent.width * 0.8
                Text { Layout.alignment: Qt.AlignHCenter; text: "Memory"; font.pixelSize: 22; color: theme.textSecondary }
                Text { Layout.alignment: Qt.AlignHCenter; text: ((dashboard.metrics.ram_usage_percent||0)).toFixed(1)+"%"; font.pixelSize: 88; font.bold: true; font.family: "monospace"
                    color: { var p=dashboard.metrics.ram_usage_percent||0; return p>90?theme.error:p>70?theme.warning:theme.accent } }
                Rectangle { Layout.preferredWidth: parent.width; Layout.preferredHeight: 12; radius: 6; color: theme.cardBorder
                    Rectangle { height: parent.height; radius: 6; width: parent.width*Math.min(((dashboard.metrics.ram_usage_percent||0))/100,1); color: theme.accent } }
                Text { Layout.alignment: Qt.AlignHCenter; text: fmtBytes(dashboard.metrics.ram_used_bytes||0)+" used / "+fmtBytes(dashboard.metrics.ram_total_bytes||0)+" total"; font.pixelSize: 18; color: theme.textSecondary }
    }}}

    // Ping expanded
    Component { id: pingExp
        Item { anchors.fill: parent
            ColumnLayout { anchors.centerIn: parent; spacing: 12; width: parent.width*0.85
                Text { Layout.alignment: Qt.AlignHCenter; text: "Network Latency"; font.pixelSize: 20; color: theme.textSecondary }
                Rectangle { Layout.preferredWidth: parent.width; Layout.preferredHeight: 220; radius: 10; color: theme.cardBackground; border.width: 1; border.color: theme.cardBorder
                    Canvas { anchors.fill: parent; anchors.margins: 10
                        onPaint: { var ctx=getContext('2d');ctx.clearRect(0,0,width,height);ctx.strokeStyle='#58A6FF';ctx.lineWidth=2;ctx.beginPath();var mid=height/2;for(var i=0;i<40;i++){var x=i*width/39;var y=mid+Math.sin(i*0.5+Date.now()*0.002)*30+Math.sin(i*1.3+Date.now()*0.003)*15;i===0?ctx.moveTo(x,y):ctx.lineTo(x,y)}ctx.stroke() }
                        Timer { interval: 200; running: true; repeat: true; onTriggered: parent.requestPaint() }
                    }
                }
                Text { Layout.alignment: Qt.AlignHCenter; text: "●  Online  •  ~8ms  •  0% loss"; font.pixelSize: 20; color: theme.success }
    }}}

    // Sensor expanded
    Component { id: sensorExp; Item { anchors.fill: parent
        ColumnLayout { anchors.centerIn: parent; spacing: 16; width: parent.width*0.8
            Text { Layout.alignment: Qt.AlignHCenter; text: "Sensor Overview"; font.pixelSize: 22; color: theme.textSecondary }
            Repeater { model: [{l:"CPU Usage",v:((dashboard.metrics.cpu_usage_percent||0)).toFixed(0)+"%",c:theme.accent},{l:"RAM Usage",v:((dashboard.metrics.ram_usage_percent||0)).toFixed(0)+"%",c:theme.warning},{l:"CPU Temp",v:(dashboard.metrics.cpu_temp_celsius||0)>0?(dashboard.metrics.cpu_temp_celsius||0).toFixed(0)+"°C":"N/A",c:theme.error}]
                ColumnLayout { Layout.fillWidth: true; spacing: 4
                    Text { text: modelData.l; font.pixelSize: 14; color: theme.textSecondary }
                    Rectangle { Layout.preferredWidth: parent.width; Layout.preferredHeight: 32; radius: 6; color: theme.cardBackground; border.width: 1; border.color: theme.cardBorder
                        Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; radius: 6; width: parent.width*Math.min(parseFloat(modelData.v)/100,1); color: modelData.c; opacity: 0.3 }
                        Text { anchors.centerIn: parent; text: modelData.v; font.pixelSize: 18; font.bold: true; color: theme.textPrimary }
                    }
                }
            }
    }}}

    // End of Day expanded
    Component { id: eodExp; Item { anchors.fill: parent
        ColumnLayout { anchors.centerIn: parent; spacing: 16
            Text { Layout.alignment: Qt.AlignHCenter; text: "Workday Countdown"; font.pixelSize: 20; color: theme.textSecondary }
            Text { Layout.alignment: Qt.AlignHCenter; font.pixelSize: 80; font.bold: true; font.family: "monospace"; color: theme.accent
                text: { var n=new Date();var e=new Date(n);e.setHours(17,0,0,0);var d=(e-n)/1000;return d>0?Math.floor(d/3600)+"h "+Math.floor((d%3600)/60)+"m "+Math.floor(d%60)+"s":"🎉 Done!" }
            }
            Text { Layout.alignment: Qt.AlignHCenter; text: "Until 5:00 PM"; font.pixelSize: 18; color: theme.textSecondary }
            Timer { interval: 1000; running: true; repeat: true; onTriggered: { parent.children[1].text=Qt.binding(function(){var n=new Date();var e=new Date(n);e.setHours(17,0,0,0);var d=(e-n)/1000;return d>0?Math.floor(d/3600)+"h "+Math.floor((d%3600)/60)+"m "+Math.floor(d%60)+"s":"🎉 Done!"}) } }
    }}}

    // Quote expanded
    Component { id: quoteExp; Item { anchors.fill: parent
        ColumnLayout { anchors.centerIn: parent; spacing: 12; width: parent.width*0.8
            Text { Layout.fillWidth: true; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 22; font.italic: true; color: theme.textPrimary
                text: { var q=["The only way to do great work is to love what you do. — Steve Jobs","Stay hungry, stay foolish. — Steve Jobs","Code is like humor. When you have to explain it, it's bad. — Cory House","Simplicity is the soul of efficiency. — Austin Freeman","First, solve the problem. Then, write the code. — John Johnson","Make it work, make it right, make it fast. — Kent Beck"]; return q[new Date().getDate()%q.length] }
            }
    }}}

    // Moon expanded
    Component { id: moonExp; Item { anchors.fill: parent
        ColumnLayout { anchors.centerIn: parent; spacing: 12
            Text { Layout.alignment: Qt.AlignHCenter; font.pixelSize: 96
                text: { var d=new Date();var p=d.getDate()/29.53;if(p<0.03)return"🌑";if(p<0.22)return"🌒";if(p<0.28)return"🌓";if(p<0.47)return"🌔";if(p<0.53)return"🌕";if(p<0.72)return"🌖";if(p<0.78)return"🌗";return"🌘" }
            }
            Text { Layout.alignment: Qt.AlignHCenter; font.pixelSize: 24; color: theme.textSecondary
                text: { var p=new Date().getDate()/29.53; return (Math.min(p*100,99.9)).toFixed(0)+"% illuminated" }
            }
    }}}

    // Pomodoro expanded
    Component { id: pomoExp
        Rectangle { anchors.fill: parent; color: theme.backgroundColor
            property int minutes: 25; property int seconds: 0; property bool running: false
            ColumnLayout { anchors.centerIn: parent; spacing: 24
                Text { Layout.alignment: Qt.AlignHCenter; text: "Focus Timer"; font.pixelSize: 24; color: theme.textSecondary }
                Text { Layout.alignment: Qt.AlignHCenter; text: String(minutes).padStart(2,'0')+":"+String(seconds).padStart(2,'0'); font.pixelSize: 100; font.bold: true; font.family: "monospace"; color: running?theme.accent:theme.textPrimary }
                RowLayout { Layout.alignment: Qt.AlignHCenter; spacing: 16
                    Rectangle { width: 90; height: 44; radius: 12; color: running?theme.error:theme.accent
                        Text { anchors.centerIn: parent; text: running?"Stop":(minutes===25?"Start":"Resume"); font.pixelSize: 16; color: "#fff" }
                        MouseArea { anchors.fill: parent; onClicked: { running=!running } }
                    }
                    Rectangle { width: 90; height: 44; radius: 12; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                        Text { anchors.centerIn: parent; text: "Reset"; font.pixelSize: 16; color: theme.textSecondary }
                        MouseArea { anchors.fill: parent; onClicked: { running=false;minutes=25;seconds=0 } }
                    }
                }
                Timer { interval: 1000; repeat: true; running: running; onTriggered: { if(seconds>0)seconds--;else if(minutes>0){minutes--;seconds=59}else running=false } }
            }
    }}

    // Checklist expanded
    Component { id: checkExp
        Rectangle { anchors.fill: parent; color: theme.backgroundColor
            property var items: ["Review PRs","Update docs","Standup notes","Team sync","Deploy build"]
            property var checked: [false,false,false,false,false]
            ColumnLayout { anchors.fill: parent; anchors.margins: 24; spacing: 10
                Text { Layout.alignment: Qt.AlignHCenter; text: "Checklist"; font.pixelSize: 24; color: theme.textSecondary }
                TextField { Layout.fillWidth: true; placeholderText: "Add new item..."; font.pixelSize: 16
                    background: Rectangle { radius: 8; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder }
                    onAccepted: { if(text){var i=items;i.push(text);items=i;text=""} }
                }
                ListView { Layout.fillWidth: true; Layout.fillHeight: true; model: items; spacing: 8; clip: true
                    delegate: Rectangle { width: ListView.view.width; height: 48; radius: 10; color: checked[index]?Qt.rgba(0.34,0.65,1,0.1):theme.cardBackground; border.width:1; border.color:checked[index]?theme.accent:theme.cardBorder
                        RowLayout { anchors.fill: parent; anchors.margins: 10; spacing: 12
                            Rectangle { width: 26; height: 26; radius: 7; color: checked[index]?theme.accent:theme.cardBorder
                                Text { anchors.centerIn: parent; visible: checked[index]; text: "✓"; font.pixelSize: 16; color: "#000" } }
                            Text { text: modelData; font.pixelSize: 18; color: checked[index]?theme.textSecondary:theme.textPrimary; Layout.fillWidth: true }
                        }
                        MouseArea { anchors.fill: parent; onClicked: {var c=checked;c[index]=!c[index];checked=c} }
                    }
                }
            }
    }}

    // Habit expanded
    Component { id: habitExp; Item { anchors.fill: parent
        ColumnLayout { anchors.centerIn: parent; spacing: 12
            Text { Layout.alignment: Qt.AlignHCenter; text: "Habit Tracker"; font.pixelSize: 22; color: theme.textSecondary }
            GridLayout { Layout.alignment: Qt.AlignHCenter; columns: 7; rowSpacing: 4; columnSpacing: 4
                Repeater { model: ["Mo","Tu","We","Th","Fr","Sa","Su"]; Text { Layout.alignment: Qt.AlignHCenter; text: modelData; font.pixelSize: 12; color: theme.textSecondary } }
                Repeater { model: 28
                    Rectangle { width: 30; height: 30; radius: 6
                        color: index<new Date().getDate()?Qt.rgba(0.34,0.65,1,0.2+Math.random()*0.5):"transparent"
                        border.width: 1; border.color: index<new Date().getDate()?theme.accent:theme.cardBorder }
                }
            }
    }}}

    // Countdown expanded
    Component { id: cntExp; Item { anchors.fill: parent
        ColumnLayout { anchors.centerIn: parent; spacing: 16
            Text { Layout.alignment: Qt.AlignHCenter; text: "Countdown to Christmas"; font.pixelSize: 22; color: theme.textSecondary }
            Text { Layout.alignment: Qt.AlignHCenter; font.pixelSize: 80; font.bold: true; font.family: "monospace"; color: theme.accent
                text: { var n=new Date();var t=new Date("2026-12-25");var d=Math.ceil((t-n)/86400000);return d>0?d+" days":"🎄 Today!" }
            }
    }}}

    // Dice expanded
    Component { id: diceExp
        Rectangle { anchors.fill: parent; color: theme.backgroundColor
            property int lastRoll: 0; property int sides: 6
            ColumnLayout { anchors.centerIn: parent; spacing: 24
                Text { Layout.alignment: Qt.AlignHCenter; text: "Roll d"+sides; font.pixelSize: 24; color: theme.textSecondary }
                Text { Layout.alignment: Qt.AlignHCenter; text: lastRoll>0?"🎲 "+lastRoll:"Tap to roll"; font.pixelSize: lastRoll>0?88:28; font.bold: lastRoll>0; color: theme.textPrimary }
                RowLayout { Layout.alignment: Qt.AlignHCenter; spacing: 8
                    Repeater { model: [4,6,8,10,12,20]
                        Rectangle { width: 44; height: 44; radius: 10; color: sides===modelData?theme.accent:theme.cardBackground; border.width:1; border.color: sides===modelData?theme.accent:theme.cardBorder
                            Text { anchors.centerIn: parent; text: "d"+modelData; font.pixelSize: 14; font.bold: true; color: sides===modelData?"#000":theme.textSecondary }
                            MouseArea { anchors.fill: parent; onClicked: { sides=modelData;lastRoll=0 } } }
                    }
                }
                Rectangle { width: 140; height: 56; radius: 14; color: theme.accent
                    Text { anchors.centerIn: parent; text: "Roll!"; font.pixelSize: 20; color: "#fff" }
                    MouseArea { anchors.fill: parent; onClicked: { lastRoll=Math.floor(Math.random()*sides)+1 } }
                }
            }
    }}

    // Lunch expanded
    Component { id: lunchExp
        Rectangle { anchors.fill: parent; color: theme.backgroundColor
            property var options: ["🍕 Pizza","🍣 Sushi","🌮 Tacos","🍜 Ramen","🥗 Salad","🍔 Burger","🥙 Kebab","🍝 Pasta"]
            property string selected: ""; property int idx: 0
            ColumnLayout { anchors.centerIn: parent; spacing: 24
                Text { Layout.alignment: Qt.AlignHCenter; text: "What's for lunch?"; font.pixelSize: 24; color: theme.textSecondary }
                Text { Layout.alignment: Qt.AlignHCenter; text: selected||"Spin the wheel!"; font.pixelSize: selected?56:28; font.bold: selected!==""; color: theme.accent }
                Rectangle { width: 200; height: 60; radius: 16; color: theme.accent
                    Text { anchors.centerIn: parent; text: "🎰  Spin!"; font.pixelSize: 22; color: "#fff" }
                    MouseArea { anchors.fill: parent; onClicked: { idx=0;spinTimer.start() } }
                }
                Timer { id: spinTimer; interval: 80; repeat: true
                    onTriggered: { selected=options[idx%options.length];idx++;if(idx>14+Math.floor(Math.random()*10))stop() }
                }
            }
    }}

    // Loss tracker expanded
    Component { id: lossExp
        Rectangle { anchors.fill: parent; color: theme.backgroundColor
            property int wins: 42; property int losses: 18
            ColumnLayout { anchors.centerIn: parent; spacing: 20
                Text { Layout.alignment: Qt.AlignHCenter; text: "Win/Loss Tracker"; font.pixelSize: 22; color: theme.textSecondary }
                Text { Layout.alignment: Qt.AlignHCenter; font.pixelSize: 80; font.bold: true; color: theme.accent; text: (wins/(wins+losses)*100).toFixed(0)+"%" }
                Text { Layout.alignment: Qt.AlignHCenter; font.pixelSize: 24; color: theme.textSecondary; text: wins+" Wins  •  "+losses+" Losses" }
                RowLayout { Layout.alignment: Qt.AlignHCenter; spacing: 20
                    Rectangle { width: 70; height: 50; radius: 12; color: theme.success
                        Text { anchors.centerIn: parent; text: "W +1"; font.pixelSize: 16; color: "#000" }
                        MouseArea { anchors.fill: parent; onClicked: wins=wins+1 } }
                    Rectangle { width: 70; height: 50; radius: 12; color: theme.error
                        Text { anchors.centerIn: parent; text: "L +1"; font.pixelSize: 16; color: "#fff" }
                        MouseArea { anchors.fill: parent; onClicked: losses=losses+1 } }
                    Rectangle { width: 70; height: 50; radius: 12; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                        Text { anchors.centerIn: parent; text: "Reset"; font.pixelSize: 14; color: theme.textSecondary }
                        MouseArea { anchors.fill: parent; onClicked: { wins=0;losses=0 } } }
                }
            }
    }}

    // Doodle expanded
    Component { id: doodleExp
        Rectangle { anchors.fill: parent; color: theme.backgroundColor
            Canvas { anchors.fill: parent; anchors.margins: 8
                property var points: []
                onPaint: { var ctx=getContext('2d');ctx.fillStyle=theme.backgroundColor;ctx.fillRect(0,0,width,height);if(points.length<2)return;ctx.strokeStyle=theme.accent;ctx.lineWidth=4;ctx.lineCap="round";ctx.beginPath();ctx.moveTo(points[0].x,points[0].y);for(var i=1;i<points.length;i++)ctx.lineTo(points[i].x,points[i].y);ctx.stroke() }
                MouseArea { anchors.fill: parent
                    onPressed: parent.points.push({x:mouseX,y:mouseY})
                    onPositionChanged: { parent.points.push({x:mouseX,y:mouseY});parent.requestPaint() } }
            }
            Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 8
                width: 40; height: 40; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                Text { anchors.centerIn: parent; text: "✕"; font.pixelSize: 16; color: theme.textSecondary }
                MouseArea { anchors.fill: parent; onClicked: { var c=parent.parent.children[0];c.points=[];c.requestPaint() } }
            }
    }}

    // Remaining expanded views (compact stubs)
    Component { id: smokeExp; Item { anchors.fill: parent; Canvas { anchors.fill: parent; anchors.margins: 20
        onPaint: { var ctx=getContext('2d');var cx=width/2,cy=height/2,r=Math.min(cx,cy)-4;ctx.clearRect(0,0,width,height);ctx.strokeStyle=theme.cardBorder;ctx.lineWidth=10;ctx.beginPath();ctx.arc(cx,cy,r,0,2*Math.PI);ctx.stroke();var n=new Date();var h=n.getHours()%12,m=n.getMinutes(),s=n.getSeconds();var ha=(h+m/60)*Math.PI/6-1.57,ma=(m+s/60)*Math.PI/30-1.57,sa=s*Math.PI/30-1.57;ctx.strokeStyle=theme.textPrimary;ctx.lineWidth=4;ctx.beginPath();ctx.moveTo(cx,cy);ctx.lineTo(cx+Math.cos(ha)*r*0.45,cy+Math.sin(ha)*r*0.45);ctx.stroke();ctx.lineWidth=2.5;ctx.beginPath();ctx.moveTo(cx,cy);ctx.lineTo(cx+Math.cos(ma)*r*0.7,cy+Math.sin(ma)*r*0.7);ctx.stroke();ctx.strokeStyle=theme.accent;ctx.lineWidth=1.5;ctx.beginPath();ctx.moveTo(cx,cy);ctx.lineTo(cx+Math.cos(sa)*r*0.8,cy+Math.sin(sa)*r*0.8);ctx.stroke() }
        Timer { interval: 1000; running: true; repeat: true; onTriggered: parent.requestPaint() }
    }}}
    Component { id: robexExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 8
        Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatTime(new Date(),"HH:mm:ss"); font.pixelSize: 64; font.bold: true; font.family: "monospace"; color: theme.accent }
        Text { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDate(new Date(),"MMMM d, yyyy"); font.pixelSize: 22; color: theme.textSecondary }
        Timer { interval: 500; running: true; repeat: true; onTriggered: { parent.children[0].text=Qt.formatTime(new Date(),"HH:mm:ss") } }
    }}}
    Component { id: rssExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 12; width: parent.width*0.85
        Text { Layout.alignment: Qt.AlignHCenter; text: "RSS Feed"; font.pixelSize: 22; color: theme.textSecondary }
        Repeater { model: [{t:"Linux 6.12 released",s:"Real-time kernel support lands in mainline, bringing PREEMPT_RT to all users."},{t:"Qt 6.8 announced",s:"New rendering backend and improved QML tooling highlight this release."},{t:"Rust 1.82 stabilizes",s:"New async traits and const generics features now available in stable Rust."}]
            Rectangle { Layout.preferredWidth: parent.width; Layout.preferredHeight: 60; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                ColumnLayout { anchors.fill: parent; anchors.margins: 10; spacing: 4
                    Text { text: modelData.t; font.pixelSize: 14; font.bold: true; color: theme.textPrimary; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    Text { text: modelData.s; font.pixelSize: 12; color: theme.textSecondary; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    Rectangle { Layout.preferredWidth: parent.width; Layout.preferredHeight: 1; color: theme.cardBorder }
    }}}}}}
    Component { id: cardExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 14
        Text { Layout.alignment: Qt.AlignHCenter; text: "Card Optimizer"; font.pixelSize: 22; color: theme.textSecondary }
        Repeater { model: [{n:"Amex Gold",p:"🏦 2% Cashback • ✈ 3x Travel • 🍽 5x Dining"},{n:"Chase Sapphire",p:"✈ 5x Flights • 🏨 3x Hotels • 🍽 2x Dining"},{n:"Citi Double",p:"🏦 2% Everything • 💰 No annual fee"}]
            Rectangle { Layout.preferredWidth: 300; Layout.preferredHeight: 56; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                ColumnLayout { anchors.centerIn: parent; spacing: 2
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.n; font.pixelSize: 16; font.bold: true; color: theme.textPrimary }
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.p; font.pixelSize: 12; color: theme.textSecondary }
    }}}}}}
    Component { id: bbExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 10
        Text { Layout.alignment: Qt.AlignHCenter; text: "MLB Scores"; font.pixelSize: 22; color: theme.textSecondary }
        Repeater { model: [{t:"LAD 5 - SF 3",s:"Final • Dodger Stadium"},{t:"NYY 7 - BOS 4",s:"Final • Yankee Stadium"},{t:"HOU 3 - TEX 2",s:"Final • Minute Maid Park"}]
            Rectangle { Layout.preferredWidth: 280; Layout.preferredHeight: 52; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                ColumnLayout { anchors.centerIn: parent; spacing: 2
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.t; font.pixelSize: 18; font.bold: true; font.family: "monospace"; color: theme.textPrimary }
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.s; font.pixelSize: 12; color: theme.textSecondary }
    }}}}}}
    Component { id: bballExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 10
        Text { Layout.alignment: Qt.AlignHCenter; text: "NBA Scores"; font.pixelSize: 22; color: theme.textSecondary }
        Repeater { model: [{t:"LAL 112 - GSW 108",s:"Final • Chase Center"},{t:"BOS 98 - MIA 95",s:"Final • TD Garden"},{t:"DEN 115 - PHX 110",s:"Final • Ball Arena"}]
            Rectangle { Layout.preferredWidth: 280; Layout.preferredHeight: 52; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                ColumnLayout { anchors.centerIn: parent; spacing: 2
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.t; font.pixelSize: 18; font.bold: true; font.family: "monospace"; color: theme.textPrimary }
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.s; font.pixelSize: 12; color: theme.textSecondary }
    }}}}}}
    Component { id: fbExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 10
        Text { Layout.alignment: Qt.AlignHCenter; text: "NFL Scores"; font.pixelSize: 22; color: theme.textSecondary }
        Repeater { model: [{t:"KC 31 - SF 28",s:"Final • Levi's Stadium"},{t:"DAL 24 - PHI 21",s:"Final • AT&T Stadium"},{t:"BUF 27 - MIA 17",s:"Final • Highmark Stadium"}]
            Rectangle { Layout.preferredWidth: 280; Layout.preferredHeight: 52; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                ColumnLayout { anchors.centerIn: parent; spacing: 2
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.t; font.pixelSize: 18; font.bold: true; font.family: "monospace"; color: theme.textPrimary }
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.s; font.pixelSize: 12; color: theme.textSecondary }
    }}}}}}
    Component { id: hockeyExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 10
        Text { Layout.alignment: Qt.AlignHCenter; text: "NHL Scores"; font.pixelSize: 22; color: theme.textSecondary }
        Repeater { model: [{t:"TOR 4 - MTL 2",s:"Final • Scotiabank Arena"},{t:"EDM 5 - CGY 3",s:"Final • Rogers Place"},{t:"BOS 3 - NYR 1",s:"Final • TD Garden"}]
            Rectangle { Layout.preferredWidth: 280; Layout.preferredHeight: 52; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                ColumnLayout { anchors.centerIn: parent; spacing: 2
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.t; font.pixelSize: 18; font.bold: true; font.family: "monospace"; color: theme.textPrimary }
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.s; font.pixelSize: 12; color: theme.textSecondary }
    }}}}}}
    Component { id: f1Exp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 12
        Text { Layout.alignment: Qt.AlignHCenter; text: "Formula 1"; font.pixelSize: 22; color: theme.textSecondary }
        Text { Layout.alignment: Qt.AlignHCenter; text: "🏁 Silverstone GP"; font.pixelSize: 32; font.bold: true; color: theme.accent }
        Text { Layout.alignment: Qt.AlignHCenter; text: "Next Race: July 14, 2026"; font.pixelSize: 18; color: theme.textSecondary }
    }}}
    Component { id: matchExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 10
        Text { Layout.alignment: Qt.AlignHCenter; text: "Matchday"; font.pixelSize: 22; color: theme.textSecondary }
        Repeater { model: [{t:"ARS 2 - CHE 1",s:"Premier League • Full Time"},{t:"MCI 3 - LIV 3",s:"Premier League • Full Time"},{t:"BAR 1 - RMA 0",s:"La Liga • Full Time"}]
            Rectangle { Layout.preferredWidth: 280; Layout.preferredHeight: 52; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                ColumnLayout { anchors.centerIn: parent; spacing: 2
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.t; font.pixelSize: 18; font.bold: true; font.family: "monospace"; color: theme.textPrimary }
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.s; font.pixelSize: 12; color: theme.textSecondary }
    }}}}}}
    Component { id: bartExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 10
        Text { Layout.alignment: Qt.AlignHCenter; text: "BART Transit"; font.pixelSize: 22; color: theme.textSecondary }
        Repeater { model: [{l:"SFO → Embarcadero",t:"4 min • 12 min"},{l:"SFO → Millbrae",t:"8 min • 22 min"},{l:"SFO → Daly City",t:"15 min • 30 min"}]
            Rectangle { Layout.preferredWidth: 280; Layout.preferredHeight: 52; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                ColumnLayout { anchors.centerIn: parent; spacing: 2
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.l; font.pixelSize: 16; font.bold: true; color: theme.textPrimary }
                    Text { Layout.alignment: Qt.AlignHCenter; text: modelData.t; font.pixelSize: 14; font.family: "monospace"; color: theme.accent }
    }}}}}}
    Component { id: tubeExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 10
        Text { Layout.alignment: Qt.AlignHCenter; text: "London Underground"; font.pixelSize: 22; color: theme.textSecondary }
        Repeater { model: [{l:"Central Line",c:"#DC241F",t:"Good Service"},{l:"Circle Line",c:"#FFD100",t:"Minor Delays"},{l:"Piccadilly",c:"#0019A8",t:"Good Service"},{l:"District",c:"#00782A",t:"Part Closure"}]
            Rectangle { Layout.preferredWidth: 280; Layout.preferredHeight: 44; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                RowLayout { anchors.fill: parent; anchors.margins: 10; spacing: 10
                    Rectangle { width: 8; height: 8; radius: 4; color: modelData.c }
                    Text { text: modelData.l; font.pixelSize: 16; color: theme.textPrimary; Layout.fillWidth: true }
                    Text { text: modelData.t; font.pixelSize: 13; color: modelData.t.indexOf("Good")>=0?theme.success:theme.warning }
    }}}}}}
    Component { id: commuteExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 16
        Text { Layout.alignment: Qt.AlignHCenter; text: "Live Commute"; font.pixelSize: 22; color: theme.textSecondary }
        Text { Layout.alignment: Qt.AlignHCenter; text: "🏠 Home → 🏢 Office"; font.pixelSize: 24; color: theme.textPrimary }
        Text { Layout.alignment: Qt.AlignHCenter; text: "~22 minutes"; font.pixelSize: 60; font.bold: true; color: theme.accent }
        Text { Layout.alignment: Qt.AlignHCenter; text: "Light traffic on US-101"; font.pixelSize: 16; color: theme.textSecondary }
    }}}
    Component { id: readitExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 10; width: parent.width*0.85
        Text { Layout.alignment: Qt.AlignHCenter; text: "Readit Feed"; font.pixelSize: 22; color: theme.textSecondary }
        Repeater { model: [{t:"Linux 6.12 brings real-time kernel support to mainline",s:"2.4k ↑ • 342 comments • r/linux"},{t:"Why Rust's async model is the future of systems programming",s:"1.8k ↑ • 215 comments • r/rust"},{t:"AI coding assistants: productivity boost or crutch?",s:"892 ↑ • 567 comments • r/programming"}]
            Rectangle { Layout.preferredWidth: parent.width; Layout.preferredHeight: 60; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                ColumnLayout { anchors.fill: parent; anchors.margins: 10; spacing: 4
                    Text { text: modelData.t; font.pixelSize: 14; font.bold: true; color: theme.textPrimary; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: modelData.s; font.pixelSize: 12; color: theme.textSecondary }
    }}}}}}
    Component { id: scrollitExp; Item { anchors.fill: parent; ColumnLayout { anchors.centerIn: parent; spacing: 12
        Text { Layout.alignment: Qt.AlignHCenter; text: "Media Gallery"; font.pixelSize: 22; color: theme.textSecondary }
        GridLayout { Layout.alignment: Qt.AlignHCenter; columns: 3; rowSpacing: 8; columnSpacing: 8
            Repeater { model: 6
                Rectangle { width: 80; height: 80; radius: 10; color: theme.cardBackground; border.width:1; border.color:theme.cardBorder
                    Text { anchors.centerIn: parent; text: "🖼"; font.pixelSize: 28; color: theme.textSecondary } } }
        }
    }}}
}
