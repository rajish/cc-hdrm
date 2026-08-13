import SwiftUI

/// Composed view for model-scoped limit gauges in the popover.
/// Renders one label + ring + countdown block per `AppState.scopedLimits` entry,
/// matching the 7-day section's label + ring + countdown layout (no hover, slope,
/// or tap behavior). Renders nothing when no scoped limit is reported.
struct ScopedLimitGaugeSection: View {
    let appState: AppState

    /// Generic label used when the API reports no display name for an entry.
    static let fallbackLabel = "Model"

    /// The entries the body renders, in API order.
    /// Internal (not private) to allow @testable import verification.
    var entries: [ScopedLimitState] {
        appState.scopedLimits
    }

    /// Display label for an entry: API display name, or the generic fallback
    /// when the name is nil or blank.
    /// Internal (not private) to allow @testable import verification.
    func label(for entry: ScopedLimitState) -> String {
        let trimmed = entry.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? Self.fallbackLabel : trimmed
    }

    /// Combined VoiceOver announcement per entry:
    /// "{label} headroom: [X] percent, resets in [relative], at [absolute]"
    /// Internal (not private) to allow @testable import verification.
    func combinedAccessibilityLabel(for entry: ScopedLimitState) -> String {
        let headroom = Int(max(0, 100.0 - entry.utilization))
        var label = "\(label(for: entry)) headroom: \(headroom) percent"
        if let resetsAt = entry.resetsAt {
            label += ", resets in \(resetsAt.countdownString()), \(resetsAt.absoluteTimeString())"
        }
        return label
    }

    @ViewBuilder
    var body: some View {
        if !appState.scopedLimits.isEmpty {
            VStack(spacing: 8) {
                ForEach(entries.indices, id: \.self) { index in
                    if index > 0 {
                        Divider()
                    }
                    entryView(entries[index])
                }
            }
        }
    }

    @ViewBuilder
    private func entryView(_ entry: ScopedLimitState) -> some View {
        VStack(spacing: 4) {
            Text(label(for: entry))
                .font(.caption)
                .foregroundStyle(.secondary)

            HeadroomRingGauge(
                headroomPercentage: 100.0 - entry.utilization,
                windowLabel: label(for: entry),
                ringSize: 56,
                strokeWidth: 4
            )

            CountdownLabel(
                resetTime: entry.resetsAt,
                headroomState: entry.headroomState,
                countdownTick: appState.countdownTick
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combinedAccessibilityLabel(for: entry))
    }
}
