import SwiftUI

/// Composed view for the 5-hour headroom section in the popover.
/// Stacks: "5h" label, ring gauge, countdown label.
struct FiveHourGaugeSection: View {
    let appState: AppState

    /// Headroom percentage derived from 5h utilization. `nil` when disconnected.
    private var headroom: Double? {
        appState.fiveHour.map { 100.0 - $0.utilization }
    }

    /// HeadroomState for the 5-hour window.
    private var fiveHourState: HeadroomState {
        appState.fiveHour?.headroomState ?? .disconnected
    }

    /// Combined VoiceOver announcement per AC #14 + Story 11.4 AC #4:
    /// "5-hour headroom: [X] percent, [slope level], resets in [relative], at [absolute]"
    /// Internal (not private) to allow @testable import verification.
    var combinedAccessibilityLabel: String {
        guard let headroom else {
            return "5-hour headroom: unavailable"
        }
        var label = "5-hour headroom: \(Int(max(0, headroom))) percent, \(appState.fiveHourSlope.accessibilityLabel)"
        if let resetsAt = appState.fiveHour?.resetsAt {
            label += ", resets in \(resetsAt.countdownString()), \(resetsAt.absoluteTimeString())"
        }
        return label
    }

    var body: some View {
        VStack(spacing: 4) {
            // "5h" label above gauge (AC #6)
            Text("5h")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Ring gauge (AC #1-#5, #9, #11-#13) + slope display (Story 11.4)
            HeadroomRingGauge(
                headroomPercentage: headroom,
                windowLabel: "5h",
                ringSize: 96,
                strokeWidth: 7,
                slopeLevel: appState.fiveHourSlope
            )

            // Countdown: relative + absolute (AC #7, #8, #10)
            CountdownLabel(
                resetTime: appState.fiveHour?.resetsAt,
                headroomState: fiveHourState,
                countdownTick: appState.countdownTick
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combinedAccessibilityLabel)
    }
}
