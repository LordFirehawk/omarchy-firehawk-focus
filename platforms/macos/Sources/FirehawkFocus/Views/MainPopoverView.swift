import SwiftUI

struct MainPopoverView: View {
    @ObservedObject var engine: FocusEngine
    var onClose: (() -> Void)? = nil
    @State private var activeTab: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 8) {
                // Title Brand
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.orange)
                        .font(.system(size: 15, weight: .semibold))
                    Text("Firehawk Focus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .fixedSize()
                }

                Spacer(minLength: 4)

                // Refined Segmented Pill Tab Switcher
                HStack(spacing: 2) {
                    NavTabButton(icon: "timer", label: "Timer", isSelected: activeTab == 0) {
                        withAnimation(.snappy(duration: 0.2)) { activeTab = 0 }
                    }
                    NavTabButton(icon: "chart.bar.xaxis", label: "Stats", isSelected: activeTab == 1) {
                        withAnimation(.snappy(duration: 0.2)) { activeTab = 1 }
                    }
                    NavTabButton(icon: "gearshape", label: "Settings", isSelected: activeTab == 2) {
                        withAnimation(.snappy(duration: 0.2)) { activeTab = 2 }
                    }
                }
                .padding(2.5)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())

                // Close Button
                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            // Main Content Area
            Group {
                switch activeTab {
                case 0:
                    TimerView(engine: engine)
                        .padding(.top, 8)
                case 1:
                    StatsView(engine: engine)
                case 2:
                    SettingsView(engine: engine)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 360, height: 490)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onExitCommand {
            onClose?()
        }
    }
}

private struct NavTabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                if isSelected {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, isSelected ? 8 : 6)
            .padding(.vertical, 4.5)
            .background(isSelected ? Color.white.opacity(0.18) : Color.clear)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .clipShape(Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
