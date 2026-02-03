import Foundation

/// Represents the rate of change in utilization over time.
/// Only three levels exist — utilization is monotonically increasing within a window,
/// so there is no "cooling" level. A negative slope is impossible during normal operation.
enum SlopeLevel: String, Sendable, Equatable, CaseIterable {
    /// No meaningful change — idle or very light use (rate < 0.3%/min)
    case flat
    /// Moderate consumption (rate 0.3-1.5%/min)
    case rising
    /// Heavy consumption, burning fast (rate > 1.5%/min)
    case steep

    /// Arrow symbol for display in UI
    var arrow: String {
        switch self {
        case .flat: return "\u{2192}"   // →
        case .rising: return "\u{2197}" // ↗
        case .steep: return "\u{2B06}"  // ⬆
        }
    }

    /// Accessibility label describing the slope level
    var accessibilityLabel: String {
        rawValue
    }
}
