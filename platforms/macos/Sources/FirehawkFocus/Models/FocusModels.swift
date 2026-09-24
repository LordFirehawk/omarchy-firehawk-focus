import AppKit
import Foundation
import UniformTypeIdentifiers

public enum FocusPhase: String, Codable, CaseIterable {
    case focus = "focus"
    case shortBreak = "shortBreak"
    case longBreak = "longBreak"

    public var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .focus: return "flame.fill"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "sparkles"
        }
    }
}

public enum FocusStatus: String, Codable, CaseIterable {
    case ready = "ready"
    case running = "running"
    case paused = "paused"
    case complete = "complete"

    public var title: String {
        switch self {
        case .ready: return "Ready"
        case .running: return "Running"
        case .paused: return "Paused"
        case .complete: return "Complete"
        }
    }
}

public struct SoundOption: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let title: String
    public let category: String

    public static let allSounds: [SoundOption] = [
        SoundOption(name: "DigitalAlarm", title: "Digital Alarm (Loud Beeps)", category: "Alarms"),
        SoundOption(name: "AlarmBell", title: "Mechanical Bell (Ringing)", category: "Alarms"),
        SoundOption(name: "Glass", title: "Glass (Gentle Chime)", category: "Chimes"),
        SoundOption(name: "Hero", title: "Hero (Trumpet Chime)", category: "Chimes"),
        SoundOption(name: "Ping", title: "Ping (Crisp Sonar)", category: "Alerts"),
        SoundOption(name: "Sosumi", title: "Sosumi (Classic Mac)", category: "Alerts"),
        SoundOption(name: "Blow", title: "Blow (Airy Whistle)", category: "Alerts"),
        SoundOption(name: "Bottle", title: "Bottle (Pop)", category: "Alerts"),
        SoundOption(name: "Frog", title: "Frog (Croak)", category: "Alerts"),
        SoundOption(name: "Funk", title: "Funk (Retro Synth)", category: "Alerts"),
        SoundOption(name: "Submarine", title: "Submarine (Deep Pulse)", category: "Alerts"),
        SoundOption(name: "Tink", title: "Tink (Subtle Click)", category: "Alerts"),
        SoundOption(name: "Basso", title: "Basso (Deep Alert)", category: "Alerts")
    ]
}

public struct FocusConfig: Codable, Equatable {
    public var focusMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    public var cyclesPerLong: Int
    public var autoDnd: Bool
    public var notifications: Bool
    public var soundEnabled: Bool
    public var completionMode: String // "nonInvasive" or "invasive"
    public var trackApps: Bool
    public var focusEndSound: String
    public var breakEndSound: String

    public static let `default` = FocusConfig(
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
    )
}

public struct AppUsage: Codable, Identifiable, Equatable {
    public var id: String { bundleId }
    public var bundleId: String
    public var appName: String
    public var durationMs: Double
    public var percentage: Int?

    public init(bundleId: String, appName: String, durationMs: Double, percentage: Int? = nil) {
        self.bundleId = bundleId
        self.appName = appName
        self.durationMs = durationMs
        self.percentage = percentage
    }

    public var formattedDuration: String {
        let totalSeconds = Int(round(max(0, durationMs) / 1000.0))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    public var durationMinutes: Double {
        durationMs / 60000.0
    }

    public var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}

public struct FocusSession: Codable, Identifiable, Equatable {
    public var id: String { "\(startedAtMs)-\(endedAtMs)" }
    public var date: String
    public var startedAtMs: Double
    public var endedAtMs: Double
    public var durationMs: Double
    public var completed: Bool
    public var apps: [AppUsage]

    public var formattedDuration: String {
        let minutes = Int(round(max(0, durationMs) / 60000.0))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 {
            return "\(hours)h \(rest > 0 ? "\(rest)m" : "")"
        }
        return "\(minutes)m"
    }

    public var formattedTime: String {
        let date = Date(timeIntervalSince1970: endedAtMs / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }
}

public struct DaySummary: Codable, Identifiable, Equatable {
    public var id: String { date }
    public var date: String
    public var day: String
    public var durationMs: Double
    public var sessions: Int
    public var breakDurationMs: Double = 0
    public var breakSessions: Int = 0

    public var durationMinutes: Double {
        durationMs / 60000.0
    }

    public var breakDurationMinutes: Double {
        breakDurationMs / 60000.0
    }

    public var totalMinutes: Double {
        durationMinutes + breakDurationMinutes
    }
}

public struct TodaySummary: Codable, Equatable {
    public var date: String
    public var durationMs: Double
    public var sessions: Int
    public var breakDurationMs: Double = 0

    public var formattedDuration: String {
        TodaySummary.format(durationMs)
    }

    public var formattedBreakDuration: String {
        TodaySummary.format(breakDurationMs)
    }

    static func format(_ ms: Double) -> String {
        let minutes = Int(round(max(0, ms) / 60000.0))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 {
            return "\(hours)h \(rest > 0 ? "\(rest)m" : "")"
        }
        return "\(minutes)m"
    }
}
