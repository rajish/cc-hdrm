import Foundation

/// Represents the current headroom status derived from API utilization data.
/// Headroom = 100 - utilization. Always derived, never stored separately.
enum HeadroomState: String, CaseIterable, Sendable {
    case normal
    case caution
    case warning
    case critical
    case exhausted
    case disconnected

    /// Derives headroom state from a utilization percentage (0–100).
    /// - Parameter utilization: The utilization percentage from the API, or `nil` if unavailable.
    /// - Returns: The corresponding `HeadroomState`.
    init(from utilization: Double?) {
        guard let utilization else {
            self = .disconnected
            return
        }

        let headroom = 100.0 - utilization

        switch headroom {
        case ...0:
            self = .exhausted
        case 0..<5:
            self = .critical
        case 5..<20:
            self = .warning
        case 20...40:
            self = .caution
        default:
            self = .normal
        }
    }

    /// The name of the color token in the asset catalog for this state.
    var colorTokenName: String {
        switch self {
        case .normal: "HeadroomNormal"
        case .caution: "HeadroomCaution"
        case .warning: "HeadroomWarning"
        case .critical: "HeadroomCritical"
        case .exhausted: "HeadroomExhausted"
        case .disconnected: "Disconnected"
        }
    }

    /// The recommended font weight for displaying this state.
    var fontWeight: String {
        switch self {
        case .normal: "regular"
        case .caution: "medium"
        case .warning: "semibold"
        case .critical: "bold"
        case .exhausted: "bold"
        case .disconnected: "regular"
        }
    }
}
