import SwiftUI

/// Composed view for the 7-day headroom section in the popover.
/// Stacks: "7d" label, ring gauge, countdown label.
/// Returns `EmptyView` when `appState.sevenDay` is nil (AC #6).
struct SevenDayGaugeSection: View {
    let appState: AppState

    /// Headroom percentage derived from 7-day utilization. `nil` when no data.
    private var headroom: Double? {
        appState.sevenDay.map { 100.0 - $0.utilization }
    }

    /// HeadroomState for the 7-day window.
    private var sevenDayState: HeadroomState {
        appState.sevenDay?.headroomState ?? .disconnected
    }

    /// Combined VoiceOver announcement (AC #7):
    /// "7-day headroom: [X] percent, resets in [relative], at [absolute]"
    private var combinedAccessibilityLabel: String {
        guard let headroom else {
            return "7-day headroom: unavailable"
        }
        var label = "7-day headroom: \(Int(max(0, headroom))) percent"
        if let resetsAt = appState.sevenDay?.resetsAt {
            label += ", resets in \(resetsAt.countdownString()), \(resetsAt.absoluteTimeString())"
        }
        return label
    }

    @ViewBuilder
    var body: some View {
        if appState.sevenDay != nil {
            VStack(spacing: 4) {
                // "7d" label above gauge (AC #3)
                Text("7d")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Ring gauge: 56px diameter, 4px stroke (AC #1-#2)
                HeadroomRingGauge(
                    headroomPercentage: headroom,
                    windowLabel: "7d",
                    ringSize: 56,
                    strokeWidth: 4
                )

                // Countdown: relative + absolute (AC #4, #5)
                CountdownLabel(
                    resetTime: appState.sevenDay?.resetsAt,
                    headroomState: sevenDayState,
                    countdownTick: appState.countdownTick
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(combinedAccessibilityLabel)
        }
    }
}
