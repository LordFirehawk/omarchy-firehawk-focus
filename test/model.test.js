'use strict'

const assert = require('node:assert/strict')
const model = require('../FocusModel.js')

const minute = 60_000
const now = new Date(2026, 7, 25, 12, 0, 0, 0).getTime()

let state = model.freshState(now)
assert.equal(state.phase, 'focus')
assert.equal(state.status, 'ready')
assert.equal(state.remainingMs, 25 * minute)
assert.equal(model.primaryLabel(state), 'Start Focus')

state = model.start(state, now)
assert.equal(state.status, 'running')
assert.equal(model.remainingMs(state, now + 5 * minute), 20 * minute)

state = model.pause(state, now + 5 * minute)
assert.equal(state.status, 'paused')
assert.equal(state.remainingMs, 20 * minute)
state = model.start(state, now + 10 * minute)
assert.equal(model.remainingMs(state, now + 11 * minute), 19 * minute)

state = model.extend(state, now + 11 * minute, 5)
assert.equal(model.remainingMs(state, now + 11 * minute), 24 * minute)
assert.equal(state.sessionDurationMs, 30 * minute)

// A completed block prepares the break but deliberately does not start it.
state = model.complete(state, now + 35 * minute)
assert.equal(state.phase, 'shortBreak')
assert.equal(state.status, 'ready')
assert.equal(state.remainingMs, 5 * minute)
assert.equal(state.sessions.length, 1)
assert.equal(state.sessions[0].durationMs, 30 * minute)
assert.equal(model.remainingMs(state, now + 90 * minute), 5 * minute)

// Skipping after a completed focus skips the break and prepares the next focus.
let completedFocus = model.freshState(now)
completedFocus = model.start(completedFocus, now)
completedFocus = model.resolve(completedFocus, now + 25 * minute)
completedFocus = model.skip(completedFocus, now + 25 * minute)
assert.equal(completedFocus.phase, 'focus')
assert.equal(completedFocus.status, 'ready')
assert.equal(completedFocus.sessions.length, 1)
assert.equal(completedFocus.sessions[0].durationMs, 25 * minute)
assert.equal(completedFocus.sessions[0].completed, true)
assert.equal(completedFocus.cycleCount, 1)

// A click at exactly zero gets the same completed-session semantics even if
// the resolve timer has not persisted status: complete focus, then skip break.
let zeroRace = model.start(model.freshState(now), now)
zeroRace = model.skip(zeroRace, now + 25 * minute)
assert.equal(zeroRace.phase, 'focus')
assert.equal(zeroRace.status, 'ready')
assert.equal(zeroRace.sessions[0].durationMs, 25 * minute)
assert.equal(zeroRace.sessions[0].completed, true)

// Skipping a completed break skips the next focus and prepares the following break.
let completedBreak = model.start(model.readyPhase(model.freshState(now), 'shortBreak'), now)
completedBreak = model.resolve(completedBreak, now + 5 * minute)
completedBreak = model.skip(completedBreak, now + 5 * minute)
assert.equal(completedBreak.phase, 'shortBreak')
assert.equal(completedBreak.status, 'ready')
assert.equal(completedBreak.sessions.length, 0)

// Every completion mode waits for an explicit extend-or-next-phase decision.
let pending = model.freshState(now)
pending = model.start(pending, now)
pending = model.resolve(pending, now + 25 * minute)
assert.equal(pending.phase, 'focus')
assert.equal(pending.status, 'complete')
assert.equal(model.primaryLabel(pending), 'Take a break')
assert.equal(model.remainingMs(pending, now + 30 * minute), 0)
assert.equal(pending.sessions.length, 0)

// Extending resumes the same phase for exactly five more minutes.
let extended = model.extend(pending, now + 25 * minute, 5)
assert.equal(extended.phase, 'focus')
assert.equal(extended.status, 'running')
assert.equal(model.remainingMs(extended, now + 25 * minute), 5 * minute)
assert.equal(extended.sessionDurationMs, 30 * minute)
extended = model.resolve(extended, now + 30 * minute)
assert.equal(extended.phase, 'focus')
assert.equal(extended.status, 'complete')

// Taking the break from a completed focus starts it in one action.
pending = model.startNext(extended, now + 30 * minute)
assert.equal(pending.phase, 'shortBreak')
assert.equal(pending.status, 'running')
assert.equal(pending.sessions.length, 1)
assert.equal(pending.sessions[0].durationMs, 30 * minute)

// A completed break similarly starts focus in one action, or can be extended.
pending = model.resolve(pending, now + 35 * minute)
assert.equal(pending.phase, 'shortBreak')
assert.equal(pending.status, 'complete')
assert.equal(model.primaryLabel(pending), 'Start Focus')
pending = model.startNext(pending, now + 35 * minute)
assert.equal(pending.phase, 'focus')
assert.equal(pending.status, 'running')

// Every fourth completed focus block earns a long break.
let fourth = model.freshState(now)
fourth.cycleCount = 3
fourth = model.start(fourth, now)
fourth = model.complete(fourth, now + 25 * minute)
assert.equal(fourth.cycleCount, 4)
assert.equal(fourth.phase, 'longBreak')
assert.equal(fourth.status, 'ready')
assert.equal(fourth.remainingMs, 15 * minute)

// Leaving a partial focus block preserves its elapsed analytics.
let skipped = model.freshState(now)
skipped = model.start(skipped, now)
skipped = model.skip(skipped, now + 12.5 * minute)
assert.equal(skipped.phase, 'shortBreak')
assert.equal(skipped.status, 'ready')
assert.equal(skipped.sessions.length, 1)
assert.equal(skipped.sessions[0].durationMs, 12.5 * minute)
assert.equal(skipped.sessions[0].completed, false)
assert.equal(skipped.cycleCount, 1)

let pausedPartial = model.start(model.freshState(now), now)
pausedPartial = model.pause(pausedPartial, now + 10 * minute)
pausedPartial = model.skip(pausedPartial, now + 30 * minute)
assert.equal(pausedPartial.sessions[0].durationMs, 10 * minute)
assert.equal(pausedPartial.cycleCount, 1)

let breakNow = model.start(model.freshState(now), now)
breakNow = model.takeBreak(breakNow, now + 8 * minute)
assert.equal(breakNow.phase, 'shortBreak')
assert.equal(breakNow.status, 'running')
assert.equal(breakNow.sessions[0].durationMs, 8 * minute)
assert.equal(breakNow.sessions[0].completed, false)
assert.equal(breakNow.cycleCount, 1)

// Even an immediate interruption counts once the timer has started.
let immediate = model.start(model.freshState(now), now)
immediate = model.skip(immediate, now)
assert.equal(immediate.sessions.length, 1)
assert.equal(immediate.sessions[0].durationMs, 1000)
assert.equal(immediate.cycleCount, 1)

// An unstarted ready timer still does not create a phantom session.
let unstarted = model.skip(model.freshState(now), now)
assert.equal(unstarted.sessions.length, 0)
assert.equal(unstarted.cycleCount, 0)
assert.equal(unstarted.phase, 'shortBreak')

// An interrupted fourth focus earns the configured long break.
let interruptedFourth = model.freshState(now)
interruptedFourth.cycleCount = 3
interruptedFourth = model.start(interruptedFourth, now)
interruptedFourth = model.skip(interruptedFourth, now + 6 * minute)
assert.equal(interruptedFourth.cycleCount, 4)
assert.equal(interruptedFourth.phase, 'longBreak')
assert.equal(interruptedFourth.status, 'ready')
assert.equal(interruptedFourth.remainingMs, 15 * minute)

let takeLongBreak = model.freshState(now)
takeLongBreak.cycleCount = 3
takeLongBreak = model.start(takeLongBreak, now)
takeLongBreak = model.takeBreak(takeLongBreak, now + 6 * minute)
assert.equal(takeLongBreak.cycleCount, 4)
assert.equal(takeLongBreak.phase, 'longBreak')
assert.equal(takeLongBreak.status, 'running')

// A running break can be ended and focus started in one action.
let focusNow = model.start(model.readyPhase(model.freshState(now), 'shortBreak'), now)
focusNow = model.startFocus(focusNow, now + 2 * minute)
assert.equal(focusNow.phase, 'focus')
assert.equal(focusNow.status, 'running')
assert.equal(focusNow.remainingMs, 25 * minute)

// Ready durations track setting changes.
let configured = model.updateConfig(model.freshState(now), 'focusMinutes', 50, now)
assert.equal(configured.config.focusMinutes, 50)
assert.equal(configured.remainingMs, 50 * minute)
configured = model.updateConfig(configured, 'autoDnd', false, now)
assert.equal(configured.config.autoDnd, false)
configured = model.updateConfig(configured, 'soundEnabled', false, now)
assert.equal(configured.config.soundEnabled, false)
configured = model.updateConfig(configured, 'completionMode', 'invasive', now)
assert.equal(configured.config.completionMode, 'invasive')
configured = model.updateConfig(configured, 'trackApps', false, now)
assert.equal(configured.config.trackApps, false)
configured = model.updateConfig(configured, 'focusEndSound', 'Hero', now)
assert.equal(configured.config.focusEndSound, 'Hero')
configured = model.updateConfig(configured, 'breakEndSound', 'AlarmBell', now)
assert.equal(configured.config.breakEndSound, 'AlarmBell')

// History powers today's cards, the seven-day chart, and streaks.
let history = model.freshState(now)
const today = model.dateKey(now)
const yesterday = model.shiftedDateKey(today, -1)
const twoDaysAgo = model.shiftedDateKey(today, -2)
history.sessions = [
  { date: twoDaysAgo, startedAtMs: now - 2 * 86400000, endedAtMs: now - 2 * 86400000 + minute, durationMs: 20 * minute },
  { date: yesterday, startedAtMs: now - 86400000, endedAtMs: now - 86400000 + minute, durationMs: 25 * minute },
  { date: today, startedAtMs: now - minute, endedAtMs: now, durationMs: 25 * minute },
  { date: today, startedAtMs: now - minute, endedAtMs: now, durationMs: 30 * minute }
]
assert.deepEqual(model.todaySummary(history, now), { date: today, durationMs: 55 * minute, sessions: 2 })
assert.equal(model.streakDays(history, now), 3)
const week = model.weekSummary(history, now)
assert.equal(week.length, 7)
assert.equal(week[6].durationMs, 55 * minute)
assert.equal(model.recentSessions(history, 2).length, 2)

// App activity tracking aggregates per-session and today's breakdown
let appSessionState = model.freshState(now)
appSessionState = model.start(appSessionState, now)
appSessionState = model.updateCurrentApps(appSessionState, [
  { bundleId: 'com.apple.dt.Xcode', appName: 'Xcode', durationMs: 20 * minute },
  { bundleId: 'com.apple.Safari', appName: 'Safari', durationMs: 5 * minute }
])
appSessionState = model.complete(appSessionState, now + 25 * minute)
assert.equal(appSessionState.sessions.length, 1)
assert.equal(appSessionState.sessions[0].apps.length, 2)
assert.equal(appSessionState.sessions[0].apps[0].appName, 'Xcode')
assert.equal(appSessionState.currentApps.length, 0)

const todayApps = model.todayAppSummary(appSessionState, now + 25 * minute)
assert.equal(todayApps.length, 2)
assert.equal(todayApps[0].bundleId, 'com.apple.dt.Xcode')
assert.equal(todayApps[0].percentage, 80)
assert.equal(todayApps[1].percentage, 20)

// State remains valid across disk round trips and malformed files recover.
const restored = model.parseState(model.serializeState(history), now)
assert.equal(restored.sessions.length, 4)
assert.equal(restored.config.focusMinutes, 25)
assert.equal(model.parseState('{broken', now).status, 'ready')
assert.equal(model.formatClock(25 * minute), '25:00')
assert.equal(model.formatDuration(90 * minute), '1h 30m')

console.log('ok - Firehawk Focus model')
