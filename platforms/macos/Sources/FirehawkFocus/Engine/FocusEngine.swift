import AppKit
import Combine
import Foundation
import JavaScriptCore
import UserNotifications

@MainActor
public final class FocusEngine: ObservableObject {
    public static let shared = FocusEngine()

    // MARK: - Published Properties for SwiftUI

    @Published public private(set) var phase: FocusPhase = .focus
    @Published public private(set) var status: FocusStatus = .ready
    @Published public private(set) var remainingMs: Double = 25 * 60 * 1000
    @Published public private(set) var sessionDurationMs: Double = 25 * 60 * 1000
    @Published public private(set) var cycleCount: Int = 0
    @Published public private(set) var progress: Double = 0.0
    @Published public private(set) var clockText: String = "25:00"
    @Published public private(set) var statusMessageText: String = "A clean focus block is waiting."
    @Published public private(set) var primaryButtonLabel: String = "Start Focus"
    @Published public private(set) var todayPhaseDurationText: String = "0m"

    @Published public private(set) var config: FocusConfig = .default
    @Published public private(set) var today: TodaySummary = TodaySummary(date: "", durationMs: 0, sessions: 0)
    @Published public private(set) var week: [DaySummary] = []
    @Published public private(set) var streak: Int = 0
    @Published public private(set) var recent: [FocusSession] = []
    @Published public private(set) var todayApps: [AppUsage] = []

    // Callback for invasive alert opening
    public var onRequestOpenPanel: (() -> Void)?

    // MARK: - Internal JS State

    private var jsContext: JSContext!
    private var jsModel: JSValue!
    private var currentStateJS: JSValue!
    private var tickTimer: Timer?
    private var previousStatus: FocusStatus = .ready

    // MARK: - App Tracking State

    private var activeBundleId: String?
    private var activeAppName: String?
    private var activeStartTime: Date?
    private var appUsageMap: [String: (name: String, durationMs: Double)] = [:]
    private var appNotificationObserver: Any?

    private var activePlayingSound: NSSound?

    private let stateFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FirehawkFocus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("firehawk-focus.json")
    }()

    private let fallbackLinuxStateFileURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".local/state/omarchy/firehawk-focus.json")
    }()

    public init() {
        setupJS()
        loadState()
        setupAppTracking()
        requestNotificationPermission()
        startTickTimer()
    }

    // MARK: - JavaScriptCore Setup

    private func setupJS() {
        jsContext = JSContext()
        jsContext.exceptionHandler = { _, exception in
            print("[FocusEngine JS Error]:", exception?.toString() ?? "unknown error")
        }

        let jsCode = loadModelJS()
        jsContext.evaluateScript("var module = { exports: {} };")
        jsContext.evaluateScript(jsCode)

        guard let exports = jsContext.objectForKeyedSubscript("module")?.objectForKeyedSubscript("exports"),
              !exports.isUndefined else {
            fatalError("Could not initialize FocusModel.js module exports")
        }
        self.jsModel = exports
    }

    private func loadModelJS() -> String {
        // 1. Try Bundle resources
        if let url = Bundle.main.url(forResource: "FocusModel", withExtension: "js"),
           let code = try? String(contentsOf: url, encoding: .utf8) {
            return code
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "FocusModel", withExtension: "js"),
           let code = try? String(contentsOf: url, encoding: .utf8) {
            return code
        }
        #endif

        // 2. Try file paths relative to current repo
        let candidatePaths: [String] = [
            Bundle.main.bundlePath + "/Contents/Resources/FocusModel.js",
            FileManager.default.currentDirectoryPath + "/FocusModel.js",
            FileManager.default.currentDirectoryPath + "/../../FocusModel.js",
            FileManager.default.currentDirectoryPath + "/platforms/macos/Resources/FocusModel.js",
            "/Users/janscodingapple/Projects/Personal/omarchy-firehawk-focus/FocusModel.js"
        ]

        for path in candidatePaths {
            if let code = try? String(contentsOfFile: path, encoding: .utf8) {
                return code
            }
        }

        fatalError("FocusModel.js could not be located in bundle or repository.")
    }

    // MARK: - App Tracking Setup

    private func setupAppTracking() {
        appNotificationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.handleAppActivated(app)
            }
        }
    }

    private func handleAppActivated(_ app: NSRunningApplication) {
        guard status == .running && phase == .focus && config.trackApps else { return }
        // Don't switch tracking if user simply clicked Firehawk Focus menu bar or tray
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        flushCurrentAppSlice()
        activeBundleId = app.bundleIdentifier ?? "unknown"
        activeAppName = app.localizedName ?? "Unknown"
        activeStartTime = Date()
    }

    private func flushCurrentAppSlice(now: Date = Date()) {
        guard let start = activeStartTime,
              let bundleId = activeBundleId,
              let name = activeAppName else { return }
        let elapsed = now.timeIntervalSince(start) * 1000.0
        if elapsed > 0 {
            let existing = appUsageMap[bundleId]?.durationMs ?? 0
            appUsageMap[bundleId] = (name: name, durationMs: existing + elapsed)
            activeStartTime = now
        }
    }

    private func syncActiveAppsToJS() {
        guard config.trackApps else { return }
        flushCurrentAppSlice()
        let appsList: [[String: Any]] = appUsageMap.map { bundleId, tuple in
            [
                "bundleId": bundleId,
                "appName": tuple.name,
                "durationMs": tuple.durationMs
            ]
        }
        if let updated = jsModel.invokeMethod("updateCurrentApps", withArguments: [currentStateJS!, appsList]) {
            currentStateJS = updated
        }
    }

    private func resetAppTracker() {
        appUsageMap.removeAll()
        activeStartTime = nil
        activeBundleId = nil
        activeAppName = nil
    }

    // MARK: - State Management

    private func loadState() {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        var loadedText: String?

        if FileManager.default.fileExists(atPath: stateFileURL.path) {
            loadedText = try? String(contentsOf: stateFileURL, encoding: .utf8)
        } else if FileManager.default.fileExists(atPath: fallbackLinuxStateFileURL.path) {
            loadedText = try? String(contentsOf: fallbackLinuxStateFileURL, encoding: .utf8)
        }

        if let text = loadedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            currentStateJS = jsModel.invokeMethod("parseState", withArguments: [text, nowMs])
        } else {
            currentStateJS = jsModel.invokeMethod("freshState", withArguments: [nowMs, NSNull()])
        }

        refreshProperties(nowMs: nowMs)
    }

    private func persistState() {
        guard let currentStateJS = currentStateJS else { return }
        if let jsonString = jsModel.invokeMethod("serializeState", withArguments: [currentStateJS])?.toString() {
            try? jsonString.write(to: stateFileURL, atomically: true, encoding: .utf8)
        }
    }

    private func refreshProperties(nowMs: Double) {
        guard let state = currentStateJS else { return }

        // Core fields
        let phaseStr = state.objectForKeyedSubscript("phase")?.toString() ?? "focus"
        self.phase = FocusPhase(rawValue: phaseStr) ?? .focus

        let statusStr = state.objectForKeyedSubscript("status")?.toString() ?? "ready"
        self.status = FocusStatus(rawValue: statusStr) ?? .ready

        self.cycleCount = Int(state.objectForKeyedSubscript("cycleCount")?.toInt32() ?? 0)
        self.sessionDurationMs = state.objectForKeyedSubscript("sessionDurationMs")?.toDouble() ?? (25 * 60 * 1000)

        // Remaining & Progress calculated via FocusModel.js
        if let remVal = jsModel.invokeMethod("remainingMs", withArguments: [state, nowMs]) {
            self.remainingMs = max(0, remVal.toDouble())
        }

        if let progVal = jsModel.invokeMethod("progress", withArguments: [state, nowMs]) {
            self.progress = max(0, min(1, progVal.toDouble()))
        }

        if let clockVal = jsModel.invokeMethod("formatClock", withArguments: [self.remainingMs]) {
            self.clockText = clockVal.toString() ?? "0:00"
        }

        if let msgVal = jsModel.invokeMethod("statusMessage", withArguments: [state]) {
            self.statusMessageText = msgVal.toString() ?? ""
        }

        if let primVal = jsModel.invokeMethod("primaryLabel", withArguments: [state]) {
            self.primaryButtonLabel = primVal.toString() ?? "Start"
        }

        var todayBreakMs: Double = 0
        if let phaseSummary = jsModel.invokeMethod("todayPhaseSummary", withArguments: [state, nowMs]) {
            let key = self.phase == .focus ? "focusMs" : "breakMs"
            let durationMs = phaseSummary.objectForKeyedSubscript(key)?.toDouble() ?? 0
            self.todayPhaseDurationText = jsModel.invokeMethod("formatDuration", withArguments: [durationMs])?.toString() ?? "0m"
            todayBreakMs = phaseSummary.objectForKeyedSubscript("breakMs")?.toDouble() ?? 0
        }

        // Parse config
        if let cfgVal = state.objectForKeyedSubscript("config") {
            self.config = FocusConfig(
                focusMinutes: Int(cfgVal.objectForKeyedSubscript("focusMinutes")?.toInt32() ?? 25),
                shortBreakMinutes: Int(cfgVal.objectForKeyedSubscript("shortBreakMinutes")?.toInt32() ?? 5),
                longBreakMinutes: Int(cfgVal.objectForKeyedSubscript("longBreakMinutes")?.toInt32() ?? 15),
                cyclesPerLong: Int(cfgVal.objectForKeyedSubscript("cyclesPerLong")?.toInt32() ?? 4),
                autoDnd: cfgVal.objectForKeyedSubscript("autoDnd")?.toBool() ?? true,
                notifications: cfgVal.objectForKeyedSubscript("notifications")?.toBool() ?? true,
                soundEnabled: cfgVal.objectForKeyedSubscript("soundEnabled")?.toBool() ?? true,
                completionMode: cfgVal.objectForKeyedSubscript("completionMode")?.toString() ?? "nonInvasive",
                trackApps: cfgVal.objectForKeyedSubscript("trackApps")?.toBool() ?? true,
                focusEndSound: cfgVal.objectForKeyedSubscript("focusEndSound")?.toString() ?? "Glass",
                breakEndSound: cfgVal.objectForKeyedSubscript("breakEndSound")?.toString() ?? "DigitalAlarm"
            )
        }

        // Today summary
        if let todayVal = jsModel.invokeMethod("todaySummary", withArguments: [state, nowMs]) {
            self.today = TodaySummary(
                date: todayVal.objectForKeyedSubscript("date")?.toString() ?? "",
                durationMs: todayVal.objectForKeyedSubscript("durationMs")?.toDouble() ?? 0,
                sessions: Int(todayVal.objectForKeyedSubscript("sessions")?.toInt32() ?? 0),
                breakDurationMs: todayBreakMs
            )
        }

        // Week summary
        if let weekVal = jsModel.invokeMethod("weekSummary", withArguments: [state, nowMs]), let weekArray = weekVal.toArray() as? [[String: Any]] {
            self.week = weekArray.compactMap { dict in
                guard let date = dict["date"] as? String,
                      let day = dict["day"] as? String,
                      let durationMs = dict["durationMs"] as? Double,
                      let sessions = dict["sessions"] as? Int else { return nil }
                return DaySummary(
                    date: date,
                    day: day,
                    durationMs: durationMs,
                    sessions: sessions,
                    breakDurationMs: dict["breakDurationMs"] as? Double ?? 0,
                    breakSessions: dict["breakSessions"] as? Int ?? 0
                )
            }
        }

        // Streak
        if let streakVal = jsModel.invokeMethod("streakDays", withArguments: [state, nowMs]) {
            self.streak = Int(streakVal.toInt32())
        }

        // Recent sessions
        if let recentVal = jsModel.invokeMethod("recentSessions", withArguments: [state, 10]), let recentArr = recentVal.toArray() as? [[String: Any]] {
            self.recent = recentArr.compactMap { dict in
                guard let date = dict["date"] as? String,
                      let startedAtMs = dict["startedAtMs"] as? Double,
                      let endedAtMs = dict["endedAtMs"] as? Double,
                      let durationMs = dict["durationMs"] as? Double,
                      let completed = dict["completed"] as? Bool else { return nil }
                let appsArr = dict["apps"] as? [[String: Any]] ?? []
                let apps: [AppUsage] = appsArr.compactMap { a in
                    guard let bId = a["bundleId"] as? String,
                          let name = a["appName"] as? String,
                          let dMs = a["durationMs"] as? Double else { return nil }
                    return AppUsage(bundleId: bId, appName: name, durationMs: dMs)
                }
                return FocusSession(
                    date: date,
                    startedAtMs: startedAtMs,
                    endedAtMs: endedAtMs,
                    durationMs: durationMs,
                    completed: completed,
                    apps: apps
                )
            }
        }

        // Today app summary
        if let appsVal = jsModel.invokeMethod("todayAppSummary", withArguments: [state, nowMs]),
           let arr = appsVal.toArray() as? [[String: Any]] {
            self.todayApps = arr.compactMap { d in
                guard let bId = d["bundleId"] as? String,
                      let name = d["appName"] as? String,
                      let ms = d["durationMs"] as? Double else { return nil }
                let pct = d["percentage"] as? Int
                return AppUsage(bundleId: bId, appName: name, durationMs: ms, percentage: pct)
            }
        }
    }

    // MARK: - Timer Tick Loop

    private func startTickTimer() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func handleTick() {
        let nowMs = Date().timeIntervalSince1970 * 1000.0

        if status == .running && phase == .focus && config.trackApps {
            if activeStartTime == nil {
                let front = NSWorkspace.shared.frontmostApplication
                if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
                    activeBundleId = front?.bundleIdentifier ?? "unknown"
                    activeAppName = front?.localizedName ?? "Unknown"
                }
                activeStartTime = Date()
            }
            syncActiveAppsToJS()
        }

        if status == .running {
            // Check if timer expired
            if let resolved = jsModel.invokeMethod("resolve", withArguments: [currentStateJS!, nowMs]) {
                let resolvedStatus = resolved.objectForKeyedSubscript("status")?.toString() ?? ""
                if resolvedStatus == "complete" && self.status == .running {
                    let prevPhase = self.phase
                    currentStateJS = resolved
                    persistState()
                    refreshProperties(nowMs: nowMs)
                    handleCompletion(previousPhase: prevPhase)
                    resetAppTracker()
                    return
                }
            }
        }

        refreshProperties(nowMs: nowMs)
    }

    // MARK: - Notifications and Sound Completion

    public func playSound(named name: String) {
        activePlayingSound?.stop()

        // 1. Try bundle resources (e.g. DigitalAlarm.wav, AlarmBell.wav)
        for ext in ["wav", "aiff", "mp3", "m4a"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let sound = NSSound(contentsOf: url, byReference: true) {
                activePlayingSound = sound
                sound.play()
                return
            }
            #if SWIFT_PACKAGE
            if let url = Bundle.module.url(forResource: name, withExtension: ext),
               let sound = NSSound(contentsOf: url, byReference: true) {
                activePlayingSound = sound
                sound.play()
                return
            }
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Sounds"),
               let sound = NSSound(contentsOf: url, byReference: true) {
                activePlayingSound = sound
                sound.play()
                return
            }
            #endif
        }

        // 2. Try NSSound named lookup (system sounds like Glass, Hero, Ping, etc.)
        if let sound = NSSound(named: name) {
            activePlayingSound = sound
            sound.play()
            return
        }

        // 3. Try System Library Sounds
        let sysUrl = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        if let sound = NSSound(contentsOf: sysUrl, byReference: true) {
            activePlayingSound = sound
            sound.play()
            return
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[FocusEngine] Notification auth error:", error)
            }
        }
    }

    private func handleCompletion(previousPhase: FocusPhase) {
        if config.soundEnabled {
            let soundName = (previousPhase == .focus) ? config.focusEndSound : config.breakEndSound
            playSound(named: soundName)
        }

        if config.notifications {
            sendCompletionNotification(previousPhase: previousPhase)
        }

        if config.completionMode == "invasive" {
            onRequestOpenPanel?()
        }
    }

    private func sendCompletionNotification(previousPhase: FocusPhase) {
        let content = UNMutableNotificationContent()
        if previousPhase == .focus {
            content.title = "Focus block complete!"
            content.body = "Time for a well-deserved break."
        } else {
            content.title = "Break finished!"
            content.body = "Open Firehawk Focus to start focus or add 5 minutes."
        }
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Public Actions

    public func primaryAction() {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        if status == .complete {
            resetAppTracker()
            let accepted = jsModel.invokeMethod("acceptCompletion", withArguments: [currentStateJS!, nowMs])!
            currentStateJS = jsModel.invokeMethod("start", withArguments: [accepted, nowMs])!
        } else {
            if status == .running {
                syncActiveAppsToJS()
                flushCurrentAppSlice()
                activeStartTime = nil
            }
            currentStateJS = jsModel.invokeMethod("toggleRunning", withArguments: [currentStateJS!, nowMs])!
        }
        persistState()
        refreshProperties(nowMs: nowMs)
    }

    public func takeBreak() {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        syncActiveAppsToJS()
        resetAppTracker()
        currentStateJS = jsModel.invokeMethod("takeBreak", withArguments: [currentStateJS!, nowMs])!
        persistState()
        refreshProperties(nowMs: nowMs)
    }

    public func startFocusNow() {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        resetAppTracker()
        currentStateJS = jsModel.invokeMethod("startFocus", withArguments: [currentStateJS!, nowMs])!
        persistState()
        refreshProperties(nowMs: nowMs)
    }

    public func startNextFocusSession() {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        resetAppTracker()
        if status == .complete {
            let accepted = jsModel.invokeMethod("acceptCompletion", withArguments: [currentStateJS!, nowMs])!
            let ready = jsModel.invokeMethod("readyPhase", withArguments: [accepted, "focus"])!
            currentStateJS = jsModel.invokeMethod("start", withArguments: [ready, nowMs])!
        } else {
            startFocusNow()
            return
        }
        persistState()
        refreshProperties(nowMs: nowMs)
    }

    public func takeAnotherBreak() {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        resetAppTracker()
        if status == .complete {
            let accepted = jsModel.invokeMethod("acceptCompletion", withArguments: [currentStateJS!, nowMs])!
            let ready = jsModel.invokeMethod("readyPhase", withArguments: [accepted, "shortBreak"])!
            currentStateJS = jsModel.invokeMethod("start", withArguments: [ready, nowMs])!
        } else {
            takeBreak()
            return
        }
        persistState()
        refreshProperties(nowMs: nowMs)
    }

    public func skipPhase() {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        syncActiveAppsToJS()
        resetAppTracker()
        currentStateJS = jsModel.invokeMethod("skip", withArguments: [currentStateJS!, nowMs])!
        persistState()
        refreshProperties(nowMs: nowMs)
    }

    public func extendTimer(minutes: Int = 5) {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        currentStateJS = jsModel.invokeMethod("extend", withArguments: [currentStateJS!, nowMs, minutes])!
        persistState()
        refreshProperties(nowMs: nowMs)
    }

    public func resetTimer() {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        resetAppTracker()
        currentStateJS = jsModel.invokeMethod("reset", withArguments: [currentStateJS!, nowMs])!
        persistState()
        refreshProperties(nowMs: nowMs)
    }

    public func clearHistory() {
        resetAppTracker()
        currentStateJS = jsModel.invokeMethod("clearHistory", withArguments: [currentStateJS!])!
        persistState()
        refreshProperties(nowMs: Date().timeIntervalSince1970 * 1000.0)
    }

    public func updateConfigValue(key: String, value: Any) {
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        currentStateJS = jsModel.invokeMethod("updateConfig", withArguments: [currentStateJS!, key, value, nowMs])!
        persistState()
        refreshProperties(nowMs: nowMs)
    }
}
