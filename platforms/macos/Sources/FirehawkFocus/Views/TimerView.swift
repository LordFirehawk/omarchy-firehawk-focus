import SwiftUI

struct TimerView: View {
    @ObservedObject var engine: FocusEngine

    private var phaseColor: Color {
        switch engine.phase {
        case .focus: return .orange
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }

    private var primaryIconName: String {
        switch engine.status {
        case .ready:
            return engine.phase == .focus ? "flame.fill" : "play.fill"
        case .running:
            return "pause.fill"
        case .paused:
            return "play.fill"
        case .complete:
            return "arrow.right.circle.fill"
        }
    }

    private var bottomActionLabel: String {
        if engine.status == .complete {
            return engine.phase == .focus ? "Start Next Focus Session" : "Take Another Break"
        } else {
            return engine.phase == .focus ? "Take a Break" : "Start Focus"
        }
    }

    private var bottomActionIcon: String {
        if engine.status == .complete {
            return engine.phase == .focus ? "flame.fill" : "cup.and.saucer.fill"
        } else {
            return engine.phase == .focus ? "cup.and.saucer.fill" : "flame.fill"
        }
    }

    private var bottomActionColor: Color {
        if engine.status == .complete {
            return engine.phase == .focus ? .orange : .green
        } else {
            return engine.phase == .focus ? .green : .orange
        }
    }

    private var bottomActionHelp: String {
        if engine.status == .complete {
            return engine.phase == .focus ? "Start next focus session without a break" : "Start another break"
        } else {
            return engine.phase == .focus ? "Immediately stop clock and start break" : "Immediately stop break and start focus"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            // Main Circular Gauge Card
            ZStack {
                // Background Track Ring
                Circle()
                    .stroke(
                        Color.secondary.opacity(0.15),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )

                // Foreground Progress Arc
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.001, min(1.0, engine.progress))))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [phaseColor.opacity(0.7), phaseColor]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: engine.progress)

                // Center Information Stack
                VStack(spacing: 6) {
                    Text("TODAY  \(engine.todayPhaseDurationText)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()

                    // Phase Capsule Badge
                    HStack(spacing: 5) {
                        Image(systemName: engine.phase.sfSymbol)
                            .font(.caption.bold())
                        Text(engine.phase.title.uppercased())
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(phaseColor.opacity(0.18))
                    .foregroundColor(phaseColor)
                    .clipShape(Capsule())

                    // Digital Clock Display
                    Text(engine.clockText)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)

                    // Pomodoro Cycle Progress Dots
                    let total = max(1, engine.config.cyclesPerLong)
                    let currentInCycle = engine.cycleCount % total

                    HStack(spacing: 6) {
                        ForEach(0..<total, id: \.self) { idx in
                            Circle()
                                .fill(idx < currentInCycle ? phaseColor : Color.secondary.opacity(0.25))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(width: 220, height: 220)
            .padding(.top, 6)

            // Status message
            Text(engine.statusMessageText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 38)
                .padding(.horizontal, 16)

            // Primary & Secondary Action Controls
            VStack(spacing: 10) {
                // Primary Action Button
                Button {
                    engine.primaryAction()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: primaryIconName)
                            .font(.headline)
                        Text(engine.primaryButtonLabel)
                            .font(.headline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(phaseColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: phaseColor.opacity(0.35), radius: 6, y: 3)
                }
                .buttonStyle(.plain)

                // Secondary Controls Row
                HStack(spacing: 8) {
                    // +5 Min Extend
                    Button {
                        engine.extendTimer(minutes: 5)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.caption.bold())
                            Text("5m")
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .help("Add 5 minutes to current timer")

                    // Phase Switch Action:
                    // During active timer: "Take a Break" / "Start Focus"
                    // When completed: "Start Next Focus Session" / "Take Another Break"
                    Button {
                        if engine.status == .complete {
                            if engine.phase == .focus {
                                engine.startNextFocusSession()
                            } else {
                                engine.takeAnotherBreak()
                            }
                        } else {
                            if engine.phase == .focus {
                                engine.takeBreak()
                            } else {
                                engine.startFocusNow()
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: bottomActionIcon)
                                .font(.caption.bold())
                                .foregroundColor(bottomActionColor)
                            Text(bottomActionLabel)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .help(bottomActionHelp)

                    // Reset
                    Button {
                        engine.resetTimer()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .help("Reset current phase")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}
