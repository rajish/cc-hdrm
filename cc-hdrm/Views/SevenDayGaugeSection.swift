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

    /// Combined VoiceOver announcement (AC #7) + Story 11.4 AC #4:
    /// "7-day headroom: [X] percent, [slope level], resets in [relative], at [absolute]"
    /// Internal (not private) to allow @testable import verification.
    var combinedAccessibilityLabel: String {
        guard let headroom else {
            return "7-day headroom: unavailable"
        }
        var label = "7-day headroom: \(Int(max(0, headroom))) percent, \(appState.sevenDaySlope.accessibilityLabel)"
        if let resetsAt = appState.sevenDay?.resetsAt {
            label += ", resets in \(resetsAt.countdownString()), \(resetsAt.absoluteTimeString())"
        }
        if let quotas = appState.quotasRemaining {
            label += ", \(Int(floor(quotas))) full 5-hour quotas left"
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

                // Ring gauge: 56px diameter, 4px stroke (AC #1-#2) + slope display (Story 11.4)
                HeadroomRingGauge(
                    headroomPercentage: headroom,
                    windowLabel: "7d",
                    ringSize: 56,
                    strokeWidth: 4,
                    slopeLevel: appState.sevenDaySlope
                )

                // Countdown: relative + absolute (AC #4, #5)
                CountdownLabel(
                    resetTime: appState.sevenDay?.resetsAt,
                    headroomState: sevenDayState,
                    countdownTick: appState.countdownTick
                )

                // Quotas remaining (Story 3.3 AC-7)
                if let quotas = appState.quotasRemaining {
                    let wholeQuotas = Int(floor(quotas))
                    Text("\(wholeQuotas) full 5h quotas left")
                        .font(.caption2)
                        .foregroundStyle(Color.headroomColor(for: sevenDayState))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(combinedAccessibilityLabel)
        }
    }
}
