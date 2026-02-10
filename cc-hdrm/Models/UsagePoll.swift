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
    /// Whether extra usage billing is enabled, nil if not reported
    var extraUsageEnabled: Bool? = nil
    /// Monthly extra usage credit limit, nil if not reported
    var extraUsageMonthlyLimit: Double? = nil
    /// Extra usage credits consumed this month, nil if not reported
    var extraUsageUsedCredits: Double? = nil
    /// Extra usage utilization fraction (0-1), nil if not reported
    var extraUsageUtilization: Double? = nil
}
