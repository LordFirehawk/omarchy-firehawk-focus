import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "FocusModel.js" as FocusModel

Panel {
  id: root
  moduleName: "lordfirehawk.focus"
  ipcTarget: "lordfirehawk.focus"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.48)
  readonly property color faint: Qt.darker(foreground, 1.9)
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/omarchy/firehawk-focus.json"

  property var session: FocusModel.freshState(Date.now(), null)
  property double nowMs: Date.now()
  property int activeTab: 0
  property bool loaded: false
  property bool cursorActive: false
  property string pendingNotificationTitle: ""
  property string pendingNotificationBody: ""

  readonly property bool leader: {
    var screens = Quickshell.screens || []
    return screens.length === 0 || String(Screen.name) === String(screens[0].name)
  }
  readonly property real remaining: FocusModel.remainingMs(session, nowMs)
  readonly property real timerProgress: FocusModel.progress(session, nowMs)
  readonly property var today: FocusModel.todaySummary(session, nowMs)
  readonly property var todayPhases: FocusModel.todayPhaseSummary(session, nowMs)
  readonly property var week: FocusModel.weekSummary(session, nowMs)
  readonly property int streak: FocusModel.streakDays(session, nowMs)
  readonly property var recent: FocusModel.recentSessions(session, 6)
  readonly property real weekPeak: calculateWeekPeak()
  readonly property bool focusRunning: session.phase === "focus" && session.status === "running"

  function calculateWeekPeak() {
    var peak = 0
    for (var i = 0; i < week.length; i++) peak = Math.max(peak, Number(week[i].durationMs || 0))
    return Math.max(25 * 60000, peak)
  }

  function persist(next) {
    session = next
    stateWriter.setText(FocusModel.serializeState(next))
  }

  function dndService() {
    var host = bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell : null
    return host ? host.serviceFor("omarchy.notifications") : null
  }

  function dndActive() {
    var service = dndService()
    return service ? service.doNotDisturb === true : false
  }

  function applyDnd(state, forceRestore) {
    var service = dndService()
    if (!service || typeof service.setDoNotDisturb !== "function") return
    if (forceRestore === true) service.setDoNotDisturb(state.dndWasOn === true)
    else if (!state.config.autoDnd) return
    else if (state.phase === "focus" && state.status === "running") service.setDoNotDisturb(true)
    else service.setDoNotDisturb(state.dndWasOn === true)
  }

  function announceCompletion(before, next) {
    if (!leader) return

    if (next.config.soundEnabled) {
      soundProcess.running = false
      soundProcess.running = true
    }

    if (next.status === "complete" && next.config.completionMode === "invasive") {
      activeTab = 0
      root.open()
      Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
      return
    }

    if (!next.config.notifications) return
    pendingNotificationTitle = before.phase === "focus" ? "Focus complete" : "Break complete"
    pendingNotificationBody = before.phase === "focus"
      ? "Open Firehawk Focus to take a break or add five minutes."
      : "Open Firehawk Focus to start focus or add five minutes."
    // Give DND a moment to restore before sending a normal, temporary toast.
    notificationDelay.restart()
  }

  function resolveExpired() {
    if (!leader || session.status !== "running" || remaining > 0) return
    var before = session
    var next = FocusModel.resolve(before, Date.now())
    applyDnd(next, false)
    persist(next)
    announceCompletion(before, next)
  }

  function primaryAction() {
    if (session.status === "complete") {
      var now = Date.now()
      var accepted = FocusModel.acceptCompletion(session, now)
      if (accepted.phase === "focus")
        accepted = FocusModel.withDndWasOn(accepted, dndActive())
      var started = FocusModel.start(accepted, now)
      applyDnd(started, false)
      persist(started)
      return
    }
    var base = session
    if (base.phase === "focus" && base.status === "ready")
      base = FocusModel.withDndWasOn(base, dndActive())
    var next = FocusModel.toggleRunning(base, Date.now())
    applyDnd(next, false)
    persist(next)
  }

  function takeBreak() {
    var next = FocusModel.takeBreak(session, Date.now())
    applyDnd(next, false)
    persist(next)
  }

  function startFocusNow() {
    var now = Date.now()
    var base = FocusModel.withDndWasOn(session, dndActive())
    var next = FocusModel.startFocus(base, now)
    applyDnd(next, false)
    persist(next)
  }

  function skipPhase() {
    var next = FocusModel.skip(session, Date.now())
    applyDnd(next, false)
    persist(next)
  }

  function resetTimer() {
    var next = FocusModel.reset(session, Date.now())
    applyDnd(next, false)
    persist(next)
  }

  function extendTimer() {
    var next = FocusModel.extend(session, Date.now(), 5)
    applyDnd(next, false)
    persist(next)
  }

  function setConfig(key, value) {
    if (key === "autoDnd" && session.config.autoDnd && value === false)
      applyDnd(session, true)
    var next = FocusModel.updateConfig(session, key, value, Date.now())
    persist(next)
    if (key === "autoDnd" && value === true) applyDnd(next, false)
  }

  function clearHistory() {
    persist(FocusModel.clearHistory(session))
  }

  function switchTab(delta) {
    activeTab = ((activeTab + delta) % 3 + 3) % 3
    if (panelFlick) panelFlick.contentY = 0
  }

  function tabName(index) {
    if (index === 1) return "Stats"
    if (index === 2) return "Settings"
    return "Timer"
  }

  function tabIcon(index) {
    if (index === 1) return "󰄧"
    if (index === 2) return "󰒓"
    return "󱎫"
  }

  function phaseColor() {
    return session.phase === "focus" ? accent : foreground
  }

  function barLabel() {
    var glyph = FocusModel.phaseGlyph(session.phase)
    if (session.status === "ready") return glyph
    if (session.status === "complete") return glyph + " Done"
    var pauseMark = session.status === "paused" ? " 󰏤" : ""
    return glyph + " " + FocusModel.formatClock(remaining) + pauseMark
  }

  function recentTime(sessionRow) {
    var date = new Date(Number(sessionRow.endedAtMs))
    return Qt.formatDateTime(date, "ddd HH:mm")
  }

  visible: true
  // Countdown labels need breathing room beyond their own text padding so the
  // center row never visually runs into the clock/date beside it.
  implicitWidth: barButton.implicitWidth + (session.status === "ready" ? 0 : Style.space(12))
  implicitHeight: barButton.implicitHeight

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    cursorActive = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: stateDirProcess
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/omarchy"]
    running: true
    onExited: stateReader.reload()
  }

  FileView {
    id: stateReader
    path: root.stateFile
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var parsed = FocusModel.parseState(text(), Date.now())
      root.session = parsed
      root.loaded = true
      root.nowMs = Date.now()
      if (root.leader && parsed.status === "running" && FocusModel.remainingMs(parsed, root.nowMs) <= 0)
        Qt.callLater(root.resolveExpired)
    }
    onLoadFailed: {
      root.session = FocusModel.freshState(Date.now(), null)
      root.loaded = true
      if (root.leader) Qt.callLater(function() { root.persist(root.session) })
    }
  }

  FileView {
    id: stateWriter
    path: root.stateFile
    printErrors: false
    atomicWrites: true
    onSaved: stateReader.reload()
  }

  Timer {
    interval: 1000
    running: root.session.status === "running"
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.nowMs = Date.now()
      if (root.remaining <= 0) root.resolveExpired()
    }
  }

  Timer {
    interval: 30000
    running: root.opened && root.session.status !== "running"
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    id: notificationDelay
    interval: 250
    onTriggered: {
      notifyProcess.command = ["notify-send", "-a", "Firehawk Focus", "-u", "normal", "-t", "10000",
        root.pendingNotificationTitle, root.pendingNotificationBody]
      notifyProcess.running = true
    }
  }

  Process {
    id: notifyProcess
    command: ["notify-send", "-a", "Firehawk Focus", "Firehawk Focus", ""]
  }

  Process {
    id: soundProcess
    command: ["canberra-gtk-play", "-i", "alarm-clock-elapsed", "-d", "Firehawk Focus complete"]
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function begin(): string { root.primaryAction(); return root.session.status }
    function pause(): string {
      if (root.session.status === "running") root.primaryAction()
      return root.session.status
    }
    function breakNow(): string { root.takeBreak(); return root.session.phase }
    function focusNow(): string { root.startFocusNow(); return root.session.phase }
    function skip(): string { root.skipPhase(); return root.session.phase }
    function reset(): string { root.resetTimer(); return root.session.status }
    function extend(): string { root.extendTimer(); return "ok" }
    function status(): string {
      return JSON.stringify({
        phase: root.session.phase,
        status: root.session.status,
        remainingMs: Math.round(root.remaining),
        todayMinutes: Math.round(root.today.durationMs / 60000),
        todaySessions: root.today.sessions,
        streak: root.streak
      })
    }
  }

  WidgetButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel()
    fontSize: Style.font.bodySmall
    horizontalMargin: root.session.status === "ready" ? 7 : 12
    active: root.focusRunning || root.session.status === "complete"
    tooltipText: "Firehawk Focus — " + FocusModel.phaseLabel(root.session.phase)
      + " " + root.session.status + " · left opens · right starts/pauses"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.primaryAction()
      else if (buttonCode === Qt.MiddleButton) root.resetTimer()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(690))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: focusMinutes.field.activeFocus || shortMinutes.field.activeFocus
        || longMinutes.field.activeFocus || cycleCount.field.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.switchTab(dx)
        else if (dy !== 0)
          panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentY + dy * Style.space(56),
            Math.max(0, panelFlick.contentHeight - panelFlick.height)))
      }
      onActivateRequested: if (root.activeTab === 0) root.primaryAction()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "1") root.activeTab = 0
        else if (text === "2") root.activeTab = 1
        else if (text === "3") root.activeTab = 2
        else if (text === " " && root.activeTab === 0) root.primaryAction()
        else if ((text === "e" || text === "E") && root.activeTab === 0) root.extendTimer()
        else if ((text === "s" || text === "S") && root.activeTab === 0) root.skipPhase()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: panelFlick.width
          spacing: Style.space(14)

          Row {
            width: parent.width
            spacing: Style.space(10)

            Text {
              text: "󰈸"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              width: parent.width - Style.space(44)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                text: "Firehawk Focus"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                text: "Deliberate work. Deliberate rest."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Row {
            id: tabRow
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: 3
              Button {
                required property int index
                width: (tabRow.width - tabRow.spacing * 2) / 3
                text: root.tabName(index)
                iconText: root.tabIcon(index)
                foreground: root.foreground
                selected: root.activeTab === index
                bordered: true
                onClicked: {
                  root.activeTab = index
                  panelFlick.contentY = 0
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // ------------------------------------------------------------ Timer
          Column {
            id: timerTab
            visible: root.activeTab === 0
            width: parent.width
            spacing: Style.space(12)

            BorderSurface {
              id: timerHero
              width: parent.width
              height: Style.space(266)
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Row {
                anchors.fill: parent
                anchors.margins: Style.space(20)
                spacing: Style.space(16)

                Column {
                  width: parent.width - progressVisual.width - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(7)

                  Text {
                    text: "TODAY  " + FocusModel.formatDuration(root.session.phase === "focus"
                      ? root.todayPhases.focusMs : root.todayPhases.breakMs)
                    color: root.faint
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 0.8
                  }

                  Text {
                    text: FocusModel.phaseLabel(root.session.phase).toUpperCase()
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.5
                  }

                  Text {
                    text: FocusModel.formatClock(root.remaining)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 52
                    font.bold: true
                  }

                  Text {
                    width: parent.width
                    text: FocusModel.statusMessage(root.session)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                  }

                  Button {
                    width: parent.width
                    text: FocusModel.primaryLabel(root.session)
                    iconText: root.session.status === "running" ? "󰏤"
                      : (root.session.status === "complete" ? "󰒭" : "󰐊")
                    foreground: root.foreground
                    background: Style.selectedFillFor(root.foreground, root.accent)
                    bordered: true
                    verticalPadding: Style.space(10)
                    onClicked: root.primaryAction()
                  }

                  Button {
                    visible: root.session.status !== "complete"
                    text: root.session.phase === "focus" ? "Take a break" : "Start Focus"
                    iconText: root.session.phase === "focus" ? "󰅶" : "󰐊"
                    foreground: root.foreground
                    onClicked: {
                      if (root.session.phase === "focus") root.takeBreak()
                      else root.startFocusNow()
                    }
                  }
                }

                Item {
                  id: progressVisual
                  width: Style.space(142)
                  height: width
                  anchors.verticalCenter: parent.verticalCenter

                  Canvas {
                    id: progressRing
                    anchors.fill: parent
                    property real value: root.timerProgress
                    onValueChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                      var ctx = getContext("2d")
                      ctx.reset()
                      var center = width / 2
                      var radius = Math.max(1, center - 9)
                      ctx.lineWidth = 9
                      ctx.lineCap = "round"
                      ctx.strokeStyle = String(root.faint)
                      ctx.beginPath()
                      ctx.arc(center, center, radius, 0, Math.PI * 2)
                      ctx.stroke()
                      ctx.strokeStyle = String(root.phaseColor())
                      ctx.beginPath()
                      ctx.arc(center, center, radius, -Math.PI / 2,
                        -Math.PI / 2 + Math.PI * 2 * Math.max(0.012, value))
                      ctx.stroke()
                    }
                  }

                  Column {
                    anchors.centerIn: parent
                    spacing: Style.space(2)

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: FocusModel.phaseGlyph(root.session.phase)
                      color: root.phaseColor()
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.displayLarge
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: root.session.status
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(7)

              Button {
                width: (parent.width - parent.spacing * 2) / 3
                text: "+5 min"
                iconText: "󰐕"
                foreground: root.foreground
                bordered: true
                onClicked: root.extendTimer()
              }
              Button {
                width: (parent.width - parent.spacing * 2) / 3
                text: "Skip"
                iconText: "󰒭"
                foreground: root.foreground
                bordered: true
                onClicked: root.skipPhase()
              }
              Button {
                width: (parent.width - parent.spacing * 2) / 3
                text: "Reset"
                iconText: "󰑐"
                foreground: root.foreground
                bordered: true
                onClicked: root.resetTimer()
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              MetricCard {
                width: (parent.width - parent.spacing * 2) / 3
                label: "TODAY"
                value: FocusModel.formatDuration(root.today.durationMs)
                detail: root.today.sessions + " session" + (root.today.sessions === 1 ? "" : "s")
              }
              MetricCard {
                width: (parent.width - parent.spacing * 2) / 3
                label: "STREAK"
                value: root.streak + " day" + (root.streak === 1 ? "" : "s")
                detail: root.streak > 0 ? "Keep the rhythm" : "Begin today"
              }
              MetricCard {
                width: (parent.width - parent.spacing * 2) / 3
                label: "ROUND"
                value: String((root.session.cycleCount % root.session.config.cyclesPerLong) + 1)
                  + " / " + root.session.config.cyclesPerLong
                detail: "Until long break"
              }
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Space starts or pauses · E adds five minutes · S skips"
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ------------------------------------------------------------ Stats
          Column {
            id: statsTab
            visible: root.activeTab === 1
            width: parent.width
            spacing: Style.space(13)

            Row {
              width: parent.width
              spacing: Style.space(8)
              MetricCard {
                width: (parent.width - parent.spacing * 2) / 3
                label: "TODAY"
                value: FocusModel.formatDuration(root.today.durationMs)
                detail: root.today.sessions + " completed"
              }
              MetricCard {
                width: (parent.width - parent.spacing * 2) / 3
                label: "STREAK"
                value: root.streak + " days"
                detail: "Local history"
              }
              MetricCard {
                width: (parent.width - parent.spacing * 2) / 3
                label: "TOTAL"
                value: String(root.session.sessions.length)
                detail: "Focus blocks"
              }
            }

            PanelSectionHeader {
              width: parent.width
              text: "Last seven days"
              foreground: root.foreground
            }

            BorderSurface {
              width: parent.width
              height: Style.space(184)
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Row {
                id: weekBars
                anchors.fill: parent
                anchors.margins: Style.space(15)
                spacing: Style.space(8)

                Repeater {
                  model: root.week
                  Item {
                    required property var modelData
                    width: (weekBars.width - weekBars.spacing * 6) / 7
                    height: weekBars.height

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      text: modelData.day
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    BorderSurface {
                      id: dayTrack
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: Style.space(24)
                      width: Math.max(Style.space(12), parent.width * 0.58)
                      height: parent.height - Style.space(30)
                      radius: Math.min(width / 2, Style.cornerRadius)
                      color: Style.normalFillFor(root.foreground, root.accent)
                      borderSpec: Border.none()

                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Math.max(modelData.durationMs > 0 ? Style.space(5) : 0,
                          parent.height * Number(modelData.durationMs || 0) / root.weekPeak)
                        radius: parent.radius
                        color: modelData.date === root.today.date ? root.accent : root.dim

                        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                      }
                    }
                  }
                }
              }
            }

            PanelSectionHeader {
              width: parent.width
              text: "Recent focus blocks"
              foreground: root.foreground
            }

            Text {
              visible: root.recent.length === 0
              width: parent.width
              text: "Complete a focus block and its history will appear here."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Column {
              width: parent.width
              spacing: Style.space(5)

              Repeater {
                model: root.recent
                BorderSurface {
                  required property var modelData
                  width: parent.width
                  height: Style.space(44)
                  radius: Style.cornerRadius
                  color: Style.normalFillFor(root.foreground, root.accent)
                  borderSpec: Border.none()

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)

                    Text {
                      width: parent.width * 0.55
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.recentTime(modelData)
                        + (modelData.completed === false ? " · Partial" : "")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      width: parent.width * 0.45
                      anchors.verticalCenter: parent.verticalCenter
                      horizontalAlignment: Text.AlignRight
                      text: FocusModel.formatDuration(modelData.durationMs)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                  }
                }
              }
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: "Everything stays in ~/.local/state/omarchy on this PC."
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // --------------------------------------------------------- Settings
          Column {
            id: settingsTab
            visible: root.activeTab === 2
            width: parent.width
            spacing: Style.space(13)

            PanelSectionHeader {
              width: parent.width
              text: "Session lengths"
              foreground: root.foreground
            }

            Grid {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(24)
              rowSpacing: Style.space(12)

              NumberField {
                id: focusMinutes
                label: "Focus minutes"
                value: root.session.config.focusMinutes
                from: 1
                to: 240
                foreground: root.foreground
                onModified: function(value) { root.setConfig("focusMinutes", value) }
              }
              NumberField {
                id: shortMinutes
                label: "Short break"
                value: root.session.config.shortBreakMinutes
                from: 1
                to: 120
                foreground: root.foreground
                onModified: function(value) { root.setConfig("shortBreakMinutes", value) }
              }
              NumberField {
                id: longMinutes
                label: "Long break"
                value: root.session.config.longBreakMinutes
                from: 1
                to: 180
                foreground: root.foreground
                onModified: function(value) { root.setConfig("longBreakMinutes", value) }
              }
              NumberField {
                id: cycleCount
                label: "Rounds per long break"
                value: root.session.config.cyclesPerLong
                from: 1
                to: 12
                foreground: root.foreground
                onModified: function(value) { root.setConfig("cyclesPerLong", value) }
              }
            }

            PanelSeparator { width: parent.width; foreground: root.foreground }

            PanelSectionHeader {
              width: parent.width
              text: "Completion behavior"
              foreground: root.foreground
            }

            Row {
              id: completionModeRow
              width: parent.width
              spacing: Style.space(8)

              Button {
                width: (completionModeRow.width - completionModeRow.spacing) / 2
                text: "Non-invasive"
                iconText: "󰂚"
                foreground: root.foreground
                selected: root.session.config.completionMode === "nonInvasive"
                bordered: true
                onClicked: root.setConfig("completionMode", "nonInvasive")
              }
              Button {
                width: (completionModeRow.width - completionModeRow.spacing) / 2
                text: "Invasive"
                iconText: "󰍹"
                foreground: root.foreground
                selected: root.session.config.completionMode === "invasive"
                bordered: true
                onClicked: root.setConfig("completionMode", "invasive")
              }
            }

            Text {
              width: parent.width
              text: root.session.config.completionMode === "invasive"
                ? "Sound the alarm and open this panel at zero. It stays open until you dismiss it, so you can add five minutes or move on."
                : "Sound the alarm and show a temporary desktop notification. The finished phase waits for you to extend it or start the next one."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Toggle {
              width: parent.width
              label: "Completion sound"
              description: "Play the system alarm sound whenever a focus block or break reaches zero."
              checked: root.session.config.soundEnabled
              foreground: root.foreground
              onClicked: root.setConfig("soundEnabled", !root.session.config.soundEnabled)
            }

            PanelSeparator { width: parent.width; foreground: root.foreground }

            Toggle {
              width: parent.width
              label: "Focus Do Not Disturb"
              description: "Silence notifications only while a focus block is actively running."
              checked: root.session.config.autoDnd
              foreground: root.foreground
              onClicked: root.setConfig("autoDnd", !root.session.config.autoDnd)
            }

            Toggle {
              width: parent.width
              label: "Completion notifications"
              description: "Tell you when a block ends, then wait for you to start the next phase."
              checked: root.session.config.notifications
              foreground: root.foreground
              onClicked: root.setConfig("notifications", !root.session.config.notifications)
            }

            PanelSeparator { width: parent.width; foreground: root.foreground }

            BorderSurface {
              width: parent.width
              height: resetColumn.implicitHeight + Style.space(24)
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Column {
                id: resetColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(7)

                Text {
                  width: parent.width
                  text: "Local data"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }
                Text {
                  width: parent.width
                  text: "Timer state, settings, and completed focus blocks are stored locally. No account or cloud service is used."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
                Button {
                  text: "Clear focus history"
                  iconText: "󰆴"
                  foreground: root.urgent
                  bordered: true
                  onClicked: root.clearHistory()
                }
              }
            }
          }
        }
      }
    }
  }

  component MetricCard: BorderSurface {
    property string label: ""
    property string value: ""
    property string detail: ""

    height: Style.space(86)
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(11)
      anchors.rightMargin: Style.space(11)
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.0
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: detail
        color: root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
