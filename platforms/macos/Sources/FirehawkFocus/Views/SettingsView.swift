import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: FocusEngine
    @ObservedObject private var launchHelper = LaunchAtLoginHelper.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Section: Intervals
                VStack(alignment: .leading, spacing: 12) {
                    Text("Durations (Minutes)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Stepper(value: Binding(
                        get: { engine.config.focusMinutes },
                        set: { engine.updateConfigValue(key: "focusMinutes", value: $0) }
                    ), in: 1...120) {
                        HStack {
                            Text("Focus Block")
                            Spacer()
                            Text("\(engine.config.focusMinutes) min").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }

                    Stepper(value: Binding(
                        get: { engine.config.shortBreakMinutes },
                        set: { engine.updateConfigValue(key: "shortBreakMinutes", value: $0) }
                    ), in: 1...60) {
                        HStack {
                            Text("Short Break")
                            Spacer()
                            Text("\(engine.config.shortBreakMinutes) min").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }

                    Stepper(value: Binding(
                        get: { engine.config.longBreakMinutes },
                        set: { engine.updateConfigValue(key: "longBreakMinutes", value: $0) }
                    ), in: 1...90) {
                        HStack {
                            Text("Long Break")
                            Spacer()
                            Text("\(engine.config.longBreakMinutes) min").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }

                    Stepper(value: Binding(
                        get: { engine.config.cyclesPerLong },
                        set: { engine.updateConfigValue(key: "cyclesPerLong", value: $0) }
                    ), in: 1...12) {
                        HStack {
                            Text("Rounds per Long Break")
                            Spacer()
                            Text("\(engine.config.cyclesPerLong) rounds").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .padding(14)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Section: Sound & Alerts
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sounds & Alerts")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Toggle("Enable Sound Chimes / Alarms", isOn: Binding(
                        get: { engine.config.soundEnabled },
                        set: { engine.updateConfigValue(key: "soundEnabled", value: $0) }
                    ))

                    if engine.config.soundEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            // Focus Complete Sound
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Focus Complete Sound")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 8) {
                                    Picker("", selection: Binding(
                                        get: { engine.config.focusEndSound },
                                        set: { engine.updateConfigValue(key: "focusEndSound", value: $0) }
                                    )) {
                                        ForEach(SoundOption.allSounds) { sound in
                                            Text(sound.title).tag(sound.name)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)

                                    Button {
                                        engine.playSound(named: engine.config.focusEndSound)
                                    } label: {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.orange)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Preview sound")
                                }
                            }

                            Divider().padding(.vertical, 2)

                            // Break Complete Sound
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Break Complete Sound")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 8) {
                                    Picker("", selection: Binding(
                                        get: { engine.config.breakEndSound },
                                        set: { engine.updateConfigValue(key: "breakEndSound", value: $0) }
                                    )) {
                                        ForEach(SoundOption.allSounds) { sound in
                                            Text(sound.title).tag(sound.name)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)

                                    Button {
                                        engine.playSound(named: engine.config.breakEndSound)
                                    } label: {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.orange)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Preview sound")
                                }

                                Text("Tip: Digital Alarm or Mechanical Bell helps you hear the break ending across the room.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Picker("Completion Notification", selection: Binding(
                        get: { engine.config.completionMode },
                        set: { engine.updateConfigValue(key: "completionMode", value: $0) }
                    )) {
                        Text("Non-invasive (Notification banner)").tag("nonInvasive")
                        Text("Invasive (Popup on zero)").tag("invasive")
                    }
                    .pickerStyle(.menu)

                    Toggle("Desktop Notifications", isOn: Binding(
                        get: { engine.config.notifications },
                        set: { engine.updateConfigValue(key: "notifications", value: $0) }
                    ))

                    Toggle("Auto Do Not Disturb", isOn: Binding(
                        get: { engine.config.autoDnd },
                        set: { engine.updateConfigValue(key: "autoDnd", value: $0) }
                    ))
                }
                .padding(14)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Section: App Tracking & Productivity
                VStack(alignment: .leading, spacing: 10) {
                    Text("Activity & Privacy")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Toggle("Track Active Apps in Focus", isOn: Binding(
                        get: { engine.config.trackApps },
                        set: { engine.updateConfigValue(key: "trackApps", value: $0) }
                    ))

                    Text("Logs which frontmost application you work in during focus blocks. No screen recording or accessibility permissions required. Kept 100% locally on your Mac.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Section: Startup & Reopening
                VStack(alignment: .leading, spacing: 10) {
                    Text("Startup & Reopening")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Toggle("Launch at Login (Start on Boot)", isOn: Binding(
                        get: { launchHelper.isEnabled },
                        set: { launchHelper.setEnabled($0) }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("How to re-open Firehawk Focus if closed:")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Text("•").foregroundStyle(.secondary)
                            Text("Spotlight:").font(.caption2.bold())
                            Text("Press ⌘ Space, type 'Firehawk Focus'").font(.caption2).foregroundStyle(.secondary)
                        }

                        HStack(spacing: 4) {
                            Text("•").foregroundStyle(.secondary)
                            Text("Terminal:").font(.caption2.bold())
                            Text("Run 'firehawk-focus'").font(.caption2).foregroundStyle(.secondary)
                        }

                        HStack(spacing: 4) {
                            Text("•").foregroundStyle(.secondary)
                            Text("Finder:").font(.caption2.bold())
                            Text("Open Applications → Firehawk Focus").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(14)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Section: About & Quit
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Firehawk Focus")
                                .font(.caption.bold())
                            Text("Shared engine with Omarchy Linux")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("v0.4.0 (macOS)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button(role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("Quit Firehawk Focus")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}
