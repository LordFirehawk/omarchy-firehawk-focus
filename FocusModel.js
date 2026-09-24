// Firehawk Focus state machine and statistics model.
// Kept dependency-free so the same code runs in QML and Node tests.

var PHASES = ["focus", "shortBreak", "longBreak"]
var STATUSES = ["ready", "running", "paused", "complete"]

var DEFAULT_CONFIG = {
  focusMinutes: 25,
  shortBreakMinutes: 5,
  longBreakMinutes: 15,
  cyclesPerLong: 4,
  autoDnd: true,
  notifications: true,
  soundEnabled: true,
  completionMode: "nonInvasive",
  trackApps: true,
  focusEndSound: "Glass",
  breakEndSound: "DigitalAlarm"
}

function numberInRange(value, fallback, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, Math.floor(n)))
}

function readConfig(raw) {
  var value = raw && typeof raw === "object" ? raw : {}
  return {
    focusMinutes: numberInRange(value.focusMinutes, DEFAULT_CONFIG.focusMinutes, 1, 240),
    shortBreakMinutes: numberInRange(value.shortBreakMinutes, DEFAULT_CONFIG.shortBreakMinutes, 1, 120),
    longBreakMinutes: numberInRange(value.longBreakMinutes, DEFAULT_CONFIG.longBreakMinutes, 1, 180),
    cyclesPerLong: numberInRange(value.cyclesPerLong, DEFAULT_CONFIG.cyclesPerLong, 1, 12),
    autoDnd: value.autoDnd === false ? false : true,
    notifications: value.notifications === false ? false : true,
    soundEnabled: value.soundEnabled === false ? false : true,
    completionMode: value.completionMode === "invasive" ? "invasive" : "nonInvasive",
    trackApps: value.trackApps === false ? false : true,
    focusEndSound: typeof value.focusEndSound === "string" && value.focusEndSound.trim() ? value.focusEndSound.trim() : DEFAULT_CONFIG.focusEndSound,
    breakEndSound: typeof value.breakEndSound === "string" && value.breakEndSound.trim() ? value.breakEndSound.trim() : DEFAULT_CONFIG.breakEndSound
  }
}

function phaseDurationMs(phase, config) {
  var c = readConfig(config)
  if (phase === "shortBreak") return c.shortBreakMinutes * 60000
  if (phase === "longBreak") return c.longBreakMinutes * 60000
  return c.focusMinutes * 60000
}

function dateKey(nowMs) {
  var date = new Date(Number(nowMs))
  function pad(n) { return n < 10 ? "0" + n : String(n) }
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function dateFromKey(key) {
  var parts = String(key || "").split("-")
  if (parts.length !== 3) return null
  var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12, 0, 0, 0)
  return isNaN(date.getTime()) ? null : date
}

function shiftedDateKey(key, amount) {
  var date = dateFromKey(key)
  if (!date) return ""
  date.setDate(date.getDate() + Number(amount || 0))
  return dateKey(date.getTime())
}

function cleanApps(value) {
  var apps = []
  if (!Array.isArray(value)) return apps
  for (var i = 0; i < value.length; i++) {
    var a = value[i]
    if (a && typeof a === "object" && a.bundleId) {
      apps.push({
        bundleId: String(a.bundleId),
        appName: String(a.appName || a.bundleId),
        durationMs: Math.max(0, Math.floor(Number(a.durationMs) || 0))
      })
    }
  }
  return apps
}

function cleanSession(value) {
  if (!value || typeof value !== "object") return null
  var endedAtMs = Number(value.endedAtMs)
  var durationMs = Number(value.durationMs)
  if (!isFinite(endedAtMs) || endedAtMs <= 0 || !isFinite(durationMs) || durationMs <= 0) return null
  return {
    phase: PHASES.indexOf(value.phase) >= 0 ? value.phase : "focus",
    date: typeof value.date === "string" && value.date !== "" ? value.date : dateKey(endedAtMs),
    startedAtMs: Math.max(0, Number(value.startedAtMs) || (endedAtMs - durationMs)),
    endedAtMs: endedAtMs,
    durationMs: Math.floor(durationMs),
    completed: value.completed === false ? false : true,
    apps: cleanApps(value.apps)
  }
}

function sessionPhase(session) {
  return session && PHASES.indexOf(session.phase) >= 0 ? session.phase : "focus"
}

function freshState(nowMs, config) {
  var c = readConfig(config)
  var duration = phaseDurationMs("focus", c)
  return {
    version: 1,
    phase: "focus",
    status: "ready",
    endsAtMs: 0,
    remainingMs: duration,
    sessionDurationMs: duration,
    startedAtMs: 0,
    completedAtMs: 0,
    cycleCount: 0,
    dndWasOn: false,
    config: c,
    currentApps: [],
    sessions: []
  }
}

function normalizeState(raw, nowMs) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return freshState(nowMs, null)
  var config = readConfig(raw.config)
  var phase = PHASES.indexOf(raw.phase) >= 0 ? raw.phase : "focus"
  var status = STATUSES.indexOf(raw.status) >= 0 ? raw.status : "ready"
  var fallbackDuration = phaseDurationMs(phase, config)
  var remaining = Number(raw.remainingMs)
  var sessionDuration = Number(raw.sessionDurationMs)
  var endsAt = Number(raw.endsAtMs)
  var startedAt = Number(raw.startedAtMs)
  var completedAt = Number(raw.completedAtMs)

  if (!isFinite(remaining) || remaining <= 0) remaining = status === "complete" ? 0 : fallbackDuration
  if (!isFinite(sessionDuration) || sessionDuration <= 0) sessionDuration = Math.max(remaining, fallbackDuration)
  if (!isFinite(endsAt) || endsAt < 0) endsAt = 0
  if (!isFinite(startedAt) || startedAt < 0) startedAt = 0
  if (!isFinite(completedAt) || completedAt < 0) completedAt = 0
  if (status === "running" && endsAt <= 0) status = "paused"
  if (status !== "running") endsAt = 0
  if (status !== "complete") completedAt = 0

  var sessions = []
  if (Array.isArray(raw.sessions)) {
    for (var i = 0; i < raw.sessions.length; i++) {
      var session = cleanSession(raw.sessions[i])
      if (session) sessions.push(session)
    }
  }
  sessions.sort(function(a, b) { return a.endedAtMs - b.endedAtMs })
  if (sessions.length > 1000) sessions = sessions.slice(sessions.length - 1000)

  return {
    version: 1,
    phase: phase,
    status: status,
    endsAtMs: endsAt,
    remainingMs: Math.floor(remaining),
    sessionDurationMs: Math.floor(sessionDuration),
    startedAtMs: startedAt,
    completedAtMs: completedAt,
    cycleCount: Math.max(0, Math.floor(Number(raw.cycleCount) || 0)),
    dndWasOn: raw.dndWasOn === true,
    config: config,
    currentApps: cleanApps(raw.currentApps),
    sessions: sessions
  }
}

function cloneState(state) {
  return normalizeState(JSON.parse(JSON.stringify(state)), Date.now())
}

function remainingMs(state, nowMs) {
  if (state.status === "running") return Math.max(0, Number(state.endsAtMs) - Number(nowMs))
  return Math.max(0, Number(state.remainingMs) || 0)
}

function progress(state, nowMs) {
  var duration = Math.max(1, Number(state.sessionDurationMs) || phaseDurationMs(state.phase, state.config))
  return Math.max(0, Math.min(1, 1 - remainingMs(state, nowMs) / duration))
}

function start(state, nowMs) {
  var next = cloneState(state)
  if (next.status === "running" || next.status === "complete") return next
  var remaining = Math.max(1000, Number(next.remainingMs) || phaseDurationMs(next.phase, next.config))
  next.status = "running"
  next.remainingMs = remaining
  next.endsAtMs = Number(nowMs) + remaining
  if (next.startedAtMs <= 0 || state.status === "ready") next.startedAtMs = Number(nowMs)
  if (state.status === "ready") next.sessionDurationMs = remaining
  return next
}

function pause(state, nowMs) {
  var next = cloneState(state)
  if (next.status !== "running") return next
  next.remainingMs = Math.max(1000, remainingMs(next, nowMs))
  next.endsAtMs = 0
  next.status = "paused"
  return next
}

function toggleRunning(state, nowMs) {
  return state.status === "running" ? pause(state, nowMs) : start(state, nowMs)
}

function extend(state, nowMs, minutes) {
  var next = cloneState(state)
  var extra = numberInRange(minutes, 5, 1, 60) * 60000
  if (next.status === "complete") {
    next.status = "running"
    next.completedAtMs = 0
    next.remainingMs = extra
    next.endsAtMs = Number(nowMs) + extra
  } else if (next.status === "running") next.endsAtMs += extra
  else next.remainingMs += extra
  next.sessionDurationMs += extra
  return next
}

function breakPhaseAfterFocus(cycleCount, config) {
  var c = readConfig(config)
  return cycleCount > 0 && cycleCount % c.cyclesPerLong === 0 ? "longBreak" : "shortBreak"
}

function readyPhase(state, phase) {
  var next = cloneState(state)
  var duration = phaseDurationMs(phase, next.config)
  next.phase = phase
  next.status = "ready"
  next.endsAtMs = 0
  next.remainingMs = duration
  next.sessionDurationMs = duration
  next.startedAtMs = 0
  next.completedAtMs = 0
  return next
}

function elapsedPhaseMs(state, nowMs) {
  var duration = Math.max(0, Number(state.sessionDurationMs) || 0)
  return Math.max(0, Math.min(duration, duration - remainingMs(state, nowMs)))
}

function phaseWasStarted(state) {
  return state.status !== "ready" && Number(state.startedAtMs) > 0
}

function focusWasStarted(state) {
  return state.phase === "focus" && phaseWasStarted(state)
}

function appendPhaseSession(state, nowMs, completed) {
  var next = cloneState(state)
  var duration = Math.floor(elapsedPhaseMs(next, nowMs))
  if (duration < 1000) {
    if (!phaseWasStarted(next)) return next
    duration = 1000
  }
  var apps = next.phase === "focus" ? cleanApps(next.currentApps) : []
  next.sessions.push({
    phase: next.phase,
    date: dateKey(nowMs),
    startedAtMs: next.startedAtMs > 0 ? next.startedAtMs : Number(nowMs) - duration,
    endedAtMs: Number(nowMs),
    durationMs: duration,
    completed: completed === true,
    apps: apps
  })
  next.currentApps = []
  if (next.sessions.length > 1000) next.sessions = next.sessions.slice(next.sessions.length - 1000)
  return next
}

function appendFocusSession(state, nowMs, completed) {
  if (state.phase !== "focus") return cloneState(state)
  return appendPhaseSession(state, nowMs, completed)
}

function appendInterruptedFocus(state, nowMs) {
  var started = focusWasStarted(state)
  var next = appendFocusSession(state, nowMs, false)
  if (started) next.cycleCount += 1
  return next
}

function complete(state, nowMs) {
  var next = cloneState(state)
  if (next.phase === "focus") {
    next = appendFocusSession(next, nowMs, true)
    next.cycleCount += 1
    return readyPhase(next, breakPhaseAfterFocus(next.cycleCount, next.config))
  }
  return readyPhase(appendPhaseSession(next, nowMs, true), "focus")
}

function markComplete(state, nowMs) {
  var next = cloneState(state)
  next.status = "complete"
  next.remainingMs = 0
  next.endsAtMs = 0
  next.completedAtMs = Number(nowMs)
  return next
}

function acceptCompletion(state, nowMs) {
  if (state.status !== "complete") return cloneState(state)
  return complete(state, state.completedAtMs > 0 ? state.completedAtMs : Number(nowMs))
}

function startNext(state, nowMs) {
  if (state.status !== "complete") return cloneState(state)
  return start(acceptCompletion(state, nowMs), nowMs)
}

function resolve(state, nowMs) {
  var next = cloneState(state)
  if (next.status === "running" && next.endsAtMs > 0 && next.endsAtMs <= Number(nowMs))
    return markComplete(next, next.endsAtMs)
  return next
}

function skip(state, nowMs) {
  var when = isFinite(Number(nowMs)) ? Number(nowMs) : Date.now()
  var current = cloneState(state)

  // A timer can be visually at zero before the resolve timer has persisted the
  // complete state. Normalize that race so a zero timer gets completion
  // semantics rather than being recorded as an interrupted session.
  if (current.status === "running" && remainingMs(current, when) <= 0)
    current = markComplete(current, current.endsAtMs > 0 ? current.endsAtMs : when)

  // The current phase is already complete, so skip the phase that follows it.
  // For example: completed focus -> skip break -> next focus.
  if (current.status === "complete") {
    var afterCompletion = acceptCompletion(current, when)
    return skip(afterCompletion, when)
  }

  if (current.phase === "focus") {
    var started = focusWasStarted(current)
    var partial = appendInterruptedFocus(current, when)
    var nextBreak = started ? breakPhaseAfterFocus(partial.cycleCount, partial.config) : "shortBreak"
    return readyPhase(partial, nextBreak)
  }
  return readyPhase(appendPhaseSession(current, when, false), "focus")
}

function takeBreak(state, nowMs) {
  var when = Number(nowMs)
  if (state.status === "complete") return startNext(state, when)
  if (state.phase !== "focus") return start(state, when)
  var started = focusWasStarted(state)
  var partial = appendInterruptedFocus(state, when)
  var nextBreak = started ? breakPhaseAfterFocus(partial.cycleCount, partial.config) : "shortBreak"
  return start(readyPhase(partial, nextBreak), when)
}

function startFocus(state, nowMs) {
  var when = Number(nowMs)
  if (state.status === "complete") return startNext(state, when)
  var recorded = state.phase !== "focus" ? appendPhaseSession(state, when, false) : cloneState(state)
  var ready = recorded.phase === "focus" ? recorded : readyPhase(recorded, "focus")
  return start(ready, when)
}

function reset(state, nowMs) {
  var next = freshState(nowMs, state.config)
  next.sessions = cloneState(state).sessions
  next.cycleCount = Math.max(0, Number(state.cycleCount) || 0)
  next.dndWasOn = state.dndWasOn === true
  return next
}

function clearHistory(state) {
  var next = cloneState(state)
  next.sessions = []
  next.cycleCount = 0
  next.currentApps = []
  return next
}

function withDndWasOn(state, value) {
  var next = cloneState(state)
  next.dndWasOn = value === true
  return next
}

function updateConfig(state, key, value, nowMs) {
  var next = cloneState(state)
  var raw = readConfig(next.config)
  raw[key] = value
  next.config = readConfig(raw)
  if (next.status === "ready") {
    var duration = phaseDurationMs(next.phase, next.config)
    next.remainingMs = duration
    next.sessionDurationMs = duration
  } else if (next.status === "paused" && keyForPhase(next.phase) === key) {
    var oldDuration = next.sessionDurationMs
    var newDuration = phaseDurationMs(next.phase, next.config)
    var elapsed = Math.max(0, oldDuration - next.remainingMs)
    next.sessionDurationMs = newDuration
    next.remainingMs = Math.max(1000, newDuration - elapsed)
  } else if (next.status === "running" && keyForPhase(next.phase) === key) {
    var currentRemaining = remainingMs(next, nowMs)
    var oldTotal = next.sessionDurationMs
    var changedTotal = phaseDurationMs(next.phase, next.config)
    var adjustment = changedTotal - oldTotal
    next.sessionDurationMs = changedTotal
    next.endsAtMs = Number(nowMs) + Math.max(1000, currentRemaining + adjustment)
  }
  return next
}

function keyForPhase(phase) {
  if (phase === "shortBreak") return "shortBreakMinutes"
  if (phase === "longBreak") return "longBreakMinutes"
  return "focusMinutes"
}

function updateCurrentApps(state, apps) {
  var next = cloneState(state)
  next.currentApps = cleanApps(apps)
  return next
}

function todayAppSummary(state, nowMs) {
  var key = dateKey(nowMs)
  var map = {}
  var totalMs = 0

  if (Array.isArray(state.sessions)) {
    for (var i = 0; i < state.sessions.length; i++) {
      var s = state.sessions[i]
      if (s.date === key && sessionPhase(s) === "focus" && Array.isArray(s.apps)) {
        for (var j = 0; j < s.apps.length; j++) {
          var a = s.apps[j]
          if (!map[a.bundleId]) {
            map[a.bundleId] = { bundleId: a.bundleId, appName: a.appName, durationMs: 0 }
          }
          map[a.bundleId].durationMs += a.durationMs
          totalMs += a.durationMs
        }
      }
    }
  }

  if (state.phase === "focus" && Array.isArray(state.currentApps)) {
    for (var k = 0; k < state.currentApps.length; k++) {
      var ca = state.currentApps[k]
      if (!map[ca.bundleId]) {
        map[ca.bundleId] = { bundleId: ca.bundleId, appName: ca.appName, durationMs: 0 }
      }
      map[ca.bundleId].durationMs += ca.durationMs
      totalMs += ca.durationMs
    }
  }

  var list = []
  for (var bId in map) {
    var item = map[bId]
    var pct = totalMs > 0 ? Math.round((item.durationMs / totalMs) * 100) : 0
    list.push({
      bundleId: item.bundleId,
      appName: item.appName,
      durationMs: item.durationMs,
      percentage: pct
    })
  }
  list.sort(function(a, b) { return b.durationMs - a.durationMs })
  return list
}

function todaySummary(state, nowMs) {
  var key = dateKey(nowMs)
  var duration = 0
  var count = 0
  for (var i = 0; i < state.sessions.length; i++) {
    if (state.sessions[i].date !== key || sessionPhase(state.sessions[i]) !== "focus") continue
    duration += Number(state.sessions[i].durationMs) || 0
    count += 1
  }
  return { date: key, durationMs: duration, sessions: count }
}

function todayPhaseSummary(state, nowMs) {
  var key = dateKey(nowMs)
  var focusMs = 0
  var breakMs = 0
  for (var i = 0; i < state.sessions.length; i++) {
    var session = state.sessions[i]
    if (session.date !== key) continue
    if (sessionPhase(session) === "focus") focusMs += Number(session.durationMs) || 0
    else breakMs += Number(session.durationMs) || 0
  }
  if (phaseWasStarted(state) && dateKey(state.startedAtMs) === key) {
    var liveMs = elapsedPhaseMs(state, nowMs)
    if (state.phase === "focus") focusMs += liveMs
    else breakMs += liveMs
  }
  return { date: key, focusMs: focusMs, breakMs: breakMs }
}

function weekSummary(state, nowMs) {
  var today = dateKey(nowMs)
  var rows = []
  for (var offset = -6; offset <= 0; offset++) {
    var key = shiftedDateKey(today, offset)
    var duration = 0
    var count = 0
    var breakDuration = 0
    var breakCount = 0
    for (var i = 0; i < state.sessions.length; i++) {
      if (state.sessions[i].date !== key) continue
      if (sessionPhase(state.sessions[i]) === "focus") {
        duration += Number(state.sessions[i].durationMs) || 0
        count += 1
      } else {
        breakDuration += Number(state.sessions[i].durationMs) || 0
        breakCount += 1
      }
    }
    var date = dateFromKey(key)
    var names = ["S", "M", "T", "W", "T", "F", "S"]
    rows.push({
      date: key,
      day: date ? names[date.getDay()] : "?",
      durationMs: duration,
      sessions: count,
      breakDurationMs: breakDuration,
      breakSessions: breakCount
    })
  }
  return rows
}

function streakDays(state, nowMs) {
  var active = {}
  for (var i = 0; i < state.sessions.length; i++) {
    if (sessionPhase(state.sessions[i]) === "focus") active[state.sessions[i].date] = true
  }
  var cursor = dateKey(nowMs)
  if (!active[cursor]) cursor = shiftedDateKey(cursor, -1)
  var count = 0
  while (active[cursor] && count < 1000) {
    count += 1
    cursor = shiftedDateKey(cursor, -1)
  }
  return count
}

function recentSessions(state, limit) {
  var max = Math.max(1, Number(limit) || 5)
  var focusSessions = state.sessions.filter(function(session) { return sessionPhase(session) === "focus" })
  return focusSessions.slice(Math.max(0, focusSessions.length - max)).reverse()
}

function formatClock(ms) {
  var seconds = Math.ceil(Math.max(0, Number(ms) || 0) / 1000)
  var minutes = Math.floor(seconds / 60)
  var rest = seconds % 60
  return minutes + ":" + (rest < 10 ? "0" + rest : String(rest))
}

function formatDuration(ms) {
  var minutes = Math.round(Math.max(0, Number(ms) || 0) / 60000)
  var hours = Math.floor(minutes / 60)
  var rest = minutes % 60
  if (hours > 0) return hours + "h " + (rest > 0 ? rest + "m" : "")
  return minutes + "m"
}

function phaseLabel(phase) {
  if (phase === "shortBreak") return "Short break"
  if (phase === "longBreak") return "Long break"
  return "Focus"
}

function phaseGlyph(phase) {
  if (phase === "shortBreak" || phase === "longBreak") return "󰅶"
  return "󰔟"
}

function statusMessage(state) {
  if (state.status === "complete") return "Time is up. Add five minutes or move to the next phase."
  if (state.status === "paused") return "Paused — your place is saved."
  if (state.status === "running" && state.phase === "focus") return "Stay with the work in front of you."
  if (state.status === "running") return "Step away. The next block can wait."
  if (state.phase === "focus") return "A clean focus block is waiting."
  if (state.phase === "longBreak") return "A longer reset is ready when you are."
  return "Your break is ready when you are."
}

function primaryLabel(state) {
  if (state.status === "complete") return state.phase === "focus" ? "Take a break" : "Start Focus"
  if (state.status === "running") return "Pause"
  if (state.status === "paused") return "Resume " + phaseLabel(state.phase)
  return "Start " + phaseLabel(state.phase)
}

function serializeState(state) {
  return JSON.stringify(normalizeState(state, Date.now()), null, 2) + "\n"
}

function parseState(text, nowMs) {
  if (typeof text !== "string" || text.trim() === "") return freshState(nowMs, null)
  try { return normalizeState(JSON.parse(text), nowMs) }
  catch (error) { return freshState(nowMs, null) }
}

if (typeof module !== "undefined") {
  module.exports = {
    PHASES: PHASES,
    STATUSES: STATUSES,
    DEFAULT_CONFIG: DEFAULT_CONFIG,
    readConfig: readConfig,
    phaseDurationMs: phaseDurationMs,
    dateKey: dateKey,
    shiftedDateKey: shiftedDateKey,
    freshState: freshState,
    normalizeState: normalizeState,
    remainingMs: remainingMs,
    progress: progress,
    start: start,
    pause: pause,
    toggleRunning: toggleRunning,
    extend: extend,
    breakPhaseAfterFocus: breakPhaseAfterFocus,
    readyPhase: readyPhase,
    elapsedPhaseMs: elapsedPhaseMs,
    phaseWasStarted: phaseWasStarted,
    focusWasStarted: focusWasStarted,
    appendFocusSession: appendFocusSession,
    appendInterruptedFocus: appendInterruptedFocus,
    complete: complete,
    markComplete: markComplete,
    acceptCompletion: acceptCompletion,
    startNext: startNext,
    resolve: resolve,
    skip: skip,
    takeBreak: takeBreak,
    startFocus: startFocus,
    reset: reset,
    clearHistory: clearHistory,
    withDndWasOn: withDndWasOn,
    updateConfig: updateConfig,
    updateCurrentApps: updateCurrentApps,
    todayAppSummary: todayAppSummary,
    cleanApps: cleanApps,
    cleanSession: cleanSession,
    todaySummary: todaySummary,
    todayPhaseSummary: todayPhaseSummary,
    weekSummary: weekSummary,
    streakDays: streakDays,
    recentSessions: recentSessions,
    formatClock: formatClock,
    formatDuration: formatDuration,
    phaseLabel: phaseLabel,
    phaseGlyph: phaseGlyph,
    statusMessage: statusMessage,
    primaryLabel: primaryLabel,
    serializeState: serializeState,
    parseState: parseState
  }
}
