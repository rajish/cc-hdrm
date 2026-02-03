import Foundation

/// Time range options for querying historical usage data.
/// Determines which resolution tiers are used for data retrieval.
enum TimeRange: CaseIterable, Sendable {
    /// Last 24 hours - raw polls only
    case day
    /// Last 7 days - raw + 5min rollups
    case week
    /// Last 30 days - raw + 5min + hourly rollups
    case month
    /// Full retention period - includes daily rollups
    case all

    /// Returns the start timestamp (Unix ms) for this time range.
    var startTimestamp: Int64 {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        switch self {
        case .day:
            return nowMs - (24 * 60 * 60 * 1000)
        case .week:
            return nowMs - (7 * 24 * 60 * 60 * 1000)
        case .month:
            return nowMs - (30 * 24 * 60 * 60 * 1000)
        case .all:
            return 0 // All available data
        }
    }
}
