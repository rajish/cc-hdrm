import SwiftUI

/// Displays relative countdown ("resets in 47m") and absolute reset time ("at 4:52 PM").
/// Reads `countdownTick` to register an observation dependency for 60-second re-renders.
struct CountdownLabel: View {
    /// The reset time. `nil` means no countdown to display.
    let resetTime: Date?
    /// Current headroom state — used for color emphasis when exhausted.
    let headroomState: HeadroomState
    /// Pass-through from AppState to trigger re-renders every 60 seconds.
    let countdownTick: UInt

    var body: some View {
        if let resetTime {
            // Read countdownTick to register observation dependency for 60-second refresh
            let _ = countdownTick

            VStack(spacing: 2) {
                // Line 1: relative countdown
                Text("resets in \(resetTime.countdownString())")
                    .font(.caption)
                    .foregroundStyle(
                        headroomState == .exhausted
                            ? headroomState.swiftUIColor
                            : .secondary
                    )

                // Line 2: absolute time
                Text(resetTime.absoluteTimeString())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Resets in \(resetTime.countdownString()), \(resetTime.absoluteTimeString())"
            )
        }
    }
}
