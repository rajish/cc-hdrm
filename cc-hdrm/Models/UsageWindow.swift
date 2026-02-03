import Foundation

/// Identifies the time window for usage tracking and slope calculation.
enum UsageWindow: String, Sendable, Equatable, CaseIterable {
    /// 5-hour rolling window
    case fiveHour
    /// 7-day rolling window
    case sevenDay
}
