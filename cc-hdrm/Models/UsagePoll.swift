import Foundation

/// Represents a single poll snapshot stored in the database.
struct UsagePoll: Sendable, Equatable {
    /// Database row ID
    let id: Int64
    /// Unix milliseconds when the poll was recorded
    let timestamp: Int64
    /// 5-hour window utilization percentage (0-100), nil if unavailable
    let fiveHourUtil: Double?
    /// 5-hour window reset time as Unix milliseconds, nil if unavailable
    let fiveHourResetsAt: Int64?
    /// 7-day window utilization percentage (0-100), nil if unavailable
    let sevenDayUtil: Double?
    /// 7-day window reset time as Unix milliseconds, nil if unavailable
    let sevenDayResetsAt: Int64?
}
