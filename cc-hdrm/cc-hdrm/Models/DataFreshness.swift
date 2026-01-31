import Foundation

/// Represents the freshness of usage data based on elapsed time since last successful fetch.
enum DataFreshness: String, CaseIterable, Sendable {
    /// Less than 60 seconds since last update — normal, no indicators.
    case fresh
    /// 60s–5m since last update — popover timestamp turns amber (Story 4.4).
    case stale
    /// More than 5m since last update — StatusMessageView shows "Data may be outdated".
    case veryStale
    /// Never fetched or disconnected — full grey state.
    case unknown

    static let staleThreshold: TimeInterval = 60
    static let veryStaleThreshold: TimeInterval = 300

    /// Computes freshness from the elapsed time since `lastUpdated`.
    /// Returns `.unknown` when `lastUpdated` is nil (never fetched).
    init(lastUpdated: Date?) {
        guard let lastUpdated else {
            self = .unknown
            return
        }
        let elapsed = max(0, Date().timeIntervalSince(lastUpdated))
        switch elapsed {
        case ..<Self.staleThreshold:
            self = .fresh
        case ..<Self.veryStaleThreshold:
            self = .stale
        default:
            self = .veryStale
        }
    }
}
