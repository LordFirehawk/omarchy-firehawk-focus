import SwiftUI

struct StatsView: View {
    @ObservedObject var engine: FocusEngine
    @State private var showingClearConfirmation = false

    private var weekPeakMinutes: Double {
        let maxDuration = engine.week.map { $0.totalMinutes }.max() ?? 0
        return max(25.0, maxDuration)
    }

    private var weekFocusMinutes: Double {
        engine.week.reduce(0) { $0 + $1.durationMinutes }
    }

    private var weekBreakMinutes: Double {
        engine.week.reduce(0) { $0 + $1.breakDurationMinutes }
    }

    private static func shortDuration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total >= 60 {
            let hours = total / 60
            let rest = total % 60
            return rest > 0 ? "\(hours)h \(rest)m" : "\(hours)h"
        }
        return "\(total)m"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Top Metrics Cards
                HStack(spacing: 10) {
                    // Today Focus
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Focus Today", systemImage: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(engine.today.formattedDuration)
                            .font(.title3.bold())
                            .foregroundColor(.primary)
                        Text("\(engine.today.sessions) session\(engine.today.sessions == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Break Today
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Break Today", systemImage: "cup.and.saucer.fill")
                            .font(.caption)
                            .foregroundStyle(Color.teal)
                        Text(engine.today.formattedBreakDuration)
                            .font(.title3.bold())
                            .foregroundColor(.primary)
                        Text("\(Self.shortDuration(minutes: weekBreakMinutes)) this week")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Streak
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Streak", systemImage: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("\(engine.streak) day\(engine.streak == 1 ? "" : "s")")
                            .font(.title3.bold())
                            .foregroundColor(.primary)
                        Text(engine.streak > 0 ? "Keep it going!" : "Start today!")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Apps Tracked Today (Kofe Flow style)
                if !engine.todayApps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Apps in Focus Today", systemImage: "app.badge.checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(engine.todayApps.count) app\(engine.todayApps.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 7) {
                            ForEach(engine.todayApps) { app in
                                HStack(spacing: 10) {
                                    Image(nsImage: app.icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 20, height: 20)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(app.appName)
                                                .font(.caption.bold())
                                                .lineLimit(1)
                                            Spacer()
                                            if let pct = app.percentage {
                                                Text("\(pct)%")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text(app.formattedDuration)
                                                .font(.caption2.monospacedDigit().bold())
                                                .foregroundStyle(.primary)
                                        }

                                        // Proportion progress bar
                                        if let pct = app.percentage {
                                            GeometryReader { barGeo in
                                                ZStack(alignment: .leading) {
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(Color.secondary.opacity(0.15))
                                                        .frame(height: 3)
                                                    RoundedRectangle(cornerRadius: 2)
                                                        .fill(Color.orange.opacity(0.85))
                                                        .frame(width: max(2, barGeo.size.width * CGFloat(pct) / 100.0), height: 3)
                                                }
                                            }
                                            .frame(height: 3)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.secondary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // 7-Day Activity Chart
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Last 7 Days")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 10) {
                            legendDot(color: .orange, label: Self.shortDuration(minutes: weekFocusMinutes) + " focus")
                            legendDot(color: .teal, label: Self.shortDuration(minutes: weekBreakMinutes) + " break")
                        }
                    }

                    HStack(alignment: .bottom, spacing: 8) {
                        // Y axis
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(Self.shortDuration(minutes: weekPeakMinutes))
                            Spacer()
                            Text(Self.shortDuration(minutes: weekPeakMinutes / 2))
                            Spacer()
                            Text("0")
                        }
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .frame(width: 26, height: 92)
                        .padding(.bottom, 18)

                        ZStack(alignment: .bottom) {
                            // Grid lines
                            VStack(spacing: 0) {
                                ForEach(0..<3, id: \.self) { index in
                                    Rectangle()
                                        .fill(Color.secondary.opacity(index == 2 ? 0.28 : 0.12))
                                        .frame(height: 1)
                                    if index < 2 { Spacer() }
                                }
                            }
                            .frame(height: 92)
                            .padding(.bottom, 18)

                            HStack(alignment: .bottom, spacing: 6) {
                                ForEach(engine.week) { day in
                                    dayColumn(day)
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Recent Sessions
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Sessions")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    if engine.recent.isEmpty {
                        Text("No sessions recorded yet. Start a focus block to begin!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(engine.recent) { session in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: session.completed ? "checkmark.circle.fill" : "stop.circle.fill")
                                            .foregroundStyle(session.completed ? .green : .orange)
                                            .font(.subheadline)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(session.formattedTime)
                                                .font(.caption.bold())
                                            Text(session.completed ? "Completed focus" : "Interrupted focus")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Text(session.formattedDuration)
                                            .font(.caption.monospacedDigit().bold())
                                    }

                                    // Inline App Tags if any were recorded for this session
                                    if !session.apps.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                ForEach(session.apps) { app in
                                                    HStack(spacing: 4) {
                                                        Image(nsImage: app.icon)
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fit)
                                                            .frame(width: 12, height: 12)
                                                        Text(app.appName)
                                                            .font(.system(size: 9.5, weight: .medium))
                                                            .lineLimit(1)
                                                        Text(app.formattedDuration)
                                                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2.5)
                                                    .background(Color.secondary.opacity(0.09))
                                                    .clipShape(Capsule())
                                                }
                                            }
                                        }
                                        .padding(.leading, 24)
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Color.secondary.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Clear History Button
                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear Focus History", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .confirmationDialog("Clear all focus history?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                    Button("Clear History", role: .destructive) {
                        engine.clearHistory()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will reset your recorded sessions, app tracking stats, and streaks.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dayColumn(_ day: DaySummary) -> some View {
        let isToday = day.date == engine.today.date
        let chartHeight: CGFloat = 92
        let focusHeight = CGFloat(day.durationMinutes / weekPeakMinutes) * chartHeight
        let breakHeight = CGFloat(day.breakDurationMinutes / weekPeakMinutes) * chartHeight

        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                // Empty track so quiet days still read as a column
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.07))
                    .frame(height: chartHeight)

                if day.totalMinutes > 0 {
                    VStack(spacing: 1.5) {
                        if day.breakDurationMinutes > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.teal.opacity(isToday ? 0.95 : 0.65))
                                .frame(height: max(3, breakHeight))
                        }
                        if day.durationMinutes > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(isToday ? 1.0 : 0.72))
                                .frame(height: max(3, focusHeight))
                        }
                    }
                }
            }
            .frame(height: chartHeight)
            .frame(maxWidth: 34)

            Text(day.day)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(isToday ? Color.orange : Color.secondary)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .help("\(Self.shortDuration(minutes: day.durationMinutes)) focus · \(Self.shortDuration(minutes: day.breakDurationMinutes)) break")
    }
}
