import SwiftUI

/// Displays a slope level arrow with appropriate styling.
/// Used in popover gauges to show burn rate.
///
/// Uses `.accessibilityHidden(true)` because the parent gauge section provides
/// a combined accessibility label that includes slope information. This prevents
/// VoiceOver from reading the slope twice.
struct SlopeIndicator: View {
    /// The slope level to display (flat, rising, or steep).
    let slopeLevel: SlopeLevel
    /// The current headroom state, used to determine arrow color for rising/steep.
    let headroomState: HeadroomState

    var body: some View {
        Text(slopeLevel.arrow)
            .font(.caption)
            .foregroundStyle(slopeLevel.color(for: headroomState))
            .accessibilityHidden(true) // Parent gauge provides combined label
    }
}

// MARK: - Previews

#Preview("All Slopes by Headroom State") {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(HeadroomState.allCases, id: \.self) { state in
            HStack(spacing: 16) {
                Text(String(describing: state).capitalized)
                    .frame(width: 80, alignment: .leading)
                    .font(.caption)
                ForEach(SlopeLevel.allCases, id: \.self) { slope in
                    VStack(spacing: 2) {
                        SlopeIndicator(slopeLevel: slope, headroomState: state)
                        Text(slope.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    .padding()
}

#Preview("In Context - Normal") {
    HStack(spacing: 20) {
        ForEach(SlopeLevel.allCases, id: \.self) { slope in
            SlopeIndicator(slopeLevel: slope, headroomState: .normal)
        }
    }
    .padding()
}

#Preview("In Context - Critical") {
    HStack(spacing: 20) {
        ForEach(SlopeLevel.allCases, id: \.self) { slope in
            SlopeIndicator(slopeLevel: slope, headroomState: .critical)
        }
    }
    .padding()
}
