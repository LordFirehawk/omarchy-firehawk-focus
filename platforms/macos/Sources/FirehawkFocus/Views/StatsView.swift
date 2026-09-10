import SwiftUI

struct StatsView: View {
    @ObservedObject var engine: FocusEngine
    @State private var showingClearConfirmation = false

    private var weekPeakMinutes: Double {
        let maxDuration = engine.week.map { $0.durationMinutes }.max() ?? 0
        return max(25.0, maxDuration)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Top Metrics Cards
                HStack(spacing: 10) {
                    // Today Focus
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Today", systemImage: "clock.fill")
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
                VStack(alignment: .leading, spacing: 10) {
                    Text("Last 7 Days")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(engine.week) { day in
                            VStack(spacing: 6) {
                                // Bar
                                GeometryReader { geo in
                                    let barHeight = max(4.0, (day.durationMinutes / weekPeakMinutes) * geo.size.height)
                                    VStack {
                                        Spacer()
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(day.durationMinutes > 0 ? Color.orange : Color.secondary.opacity(0.2))
                                            .frame(height: barHeight)
                                    }
                                }
                                .frame(height: 70)

                                // Day Label
                                Text(day.day)
                                    .font(.caption2.bold())
                                    .foregroundStyle(day.date == engine.today.date ? Color.orange : Color.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
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
}
