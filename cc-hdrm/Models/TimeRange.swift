import Foundation

/// Time range options for querying historical usage data.
///
/// Used with `getRolledUpData(range:)` and `getResetEvents(range:)` to query
/// data at appropriate resolutions. Each range automatically stitches data
/// from the optimal resolution tiers:
///
/// ```
/// .day:   Raw polls (last 24h) - finest granularity
/// .week:  Raw + 5min rollups (1-7d) - balanced detail
/// .month: Raw + 5min + hourly rollups (7-30d) - good overview
/// .all:   Raw + 5min + hourly + daily rollups - full history
/// ```
///
/// - Note: Results are always sorted by timestamp/period_start ascending.
enum TimeRange: CaseIterable, Sendable {
    /// Last 24 hours - raw polls only (finest granularity for detailed views)
    case day
    /// Last 7 days - raw polls (<24h) + 5-minute rollups (1-7d)
    case week
    /// Last 30 days - raw + 5-minute + hourly rollups
    case month
    /// All available data - no time limit (actual retention controlled by pruneOldData, typically ~90 days)
    case all

    /// Short label displayed in UI controls (e.g., "24h", "7d").
    var displayLabel: String {
        switch self {
        case .day: return "24h"
        case .week: return "7d"
        case .month: return "30d"
        case .all: return "All"
        }
    }

    /// Accessibility description for VoiceOver (e.g., "Last 24 hours").
    var accessibilityDescription: String {
        switch self {
        case .day: return "Last 24 hours"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .all: return "All time"
        }
    }

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
