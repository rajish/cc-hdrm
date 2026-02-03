import AppKit
import SwiftUI

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

    // MARK: - Color Methods (Story 11.2)

    /// Returns the display color for this slope level.
    ///
    /// For `.flat`, returns `.secondary` (muted, non-actionable).
    /// For `.rising` and `.steep`, returns the headroom state's color via
    /// `Color.headroomColor(for:)` to maintain visual coherence with headroom display.
    ///
    /// - Parameter headroomState: The current headroom state for color inheritance.
    /// - Returns: `.secondary` for flat; headroom color for rising/steep.
    func color(for headroomState: HeadroomState) -> Color {
        switch self {
        case .flat:
            return .secondary
        case .rising, .steep:
            return Color.headroomColor(for: headroomState)
        }
    }

    /// Returns NSColor for AppKit compatibility (menu bar rendering).
    /// - Parameter headroomState: The current headroom state for color inheritance.
    /// - Returns: `.secondaryLabelColor` for flat; headroom NSColor for rising/steep.
    func nsColor(for headroomState: HeadroomState) -> NSColor {
        switch self {
        case .flat:
            return .secondaryLabelColor
        case .rising, .steep:
            return NSColor.headroomColor(for: headroomState)
        }
    }

    // MARK: - Actionability (Story 11.2)

    /// Whether this slope level should trigger menu bar display.
    /// Per UX spec: only rising and steep are shown in menu bar.
    var isActionable: Bool {
        switch self {
        case .flat:
            return false
        case .rising, .steep:
            return true
        }
    }
}
