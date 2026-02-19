import Foundation

/// Represents aggregated usage data at a specific resolution tier.
/// Used for tiered rollup storage: 5-minute, hourly, and daily aggregations.
struct UsageRollup: Sendable, Equatable {
    /// Database row ID
    let id: Int64
    /// Start of the aggregation period (Unix ms, inclusive)
    let periodStart: Int64
    /// End of the aggregation period (Unix ms, exclusive)
    let periodEnd: Int64
    /// Aggregation resolution level
    let resolution: Resolution
    /// Average 5h utilization for the period (0-100)
    let fiveHourAvg: Double?
    /// Peak (max) 5h utilization for the period
    let fiveHourPeak: Double?
    /// Minimum 5h utilization for the period
    let fiveHourMin: Double?
    /// Average 7d utilization for the period
    let sevenDayAvg: Double?
    /// Peak 7d utilization for the period
    let sevenDayPeak: Double?
    /// Minimum 7d utilization for the period
    let sevenDayMin: Double?
    /// Number of 5h reset events in the period
    let resetCount: Int
    /// Calculated true unused credits (daily resolution only, NULL otherwise)
    let unusedCredits: Double?
    /// Extra usage credits consumed (persisted in rollup DB schema since v4).
    /// MAX aggregation across source polls/rollups in each period.
    var extraUsageUsedCredits: Double? = nil
    /// Extra usage utilization percentage 0-100 (persisted in rollup DB schema since v4).
    /// MAX aggregation across source polls/rollups in each period.
    var extraUsageUtilization: Double? = nil
    /// Extra usage delta: SUM of credits consumed across polls/rollups in this period.
    /// Persisted in rollup DB schema since v5.
    var extraUsageDelta: Double? = nil

    /// Resolution tier for aggregated usage data.
    enum Resolution: String, Codable, CaseIterable, Sendable {
        /// 5-minute aggregation (raw polls 24h-7d ago)
        case fiveMin = "5min"
        /// Hourly aggregation (5min rollups 7d-30d ago)
        case hourly = "hourly"
        /// Daily aggregation (hourly rollups 30d+ ago)
        case daily = "daily"
    }
}
