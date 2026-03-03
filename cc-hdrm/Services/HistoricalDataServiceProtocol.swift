import Foundation

/// Protocol for historical usage data persistence and retrieval.
/// HistoricalDataService is the primary consumer of DatabaseManager for poll data.
protocol HistoricalDataServiceProtocol: Sendable {
    /// Persists a poll snapshot to the database.
    /// - Parameter response: The usage response from the API
    /// - Throws: Database errors (caller should handle gracefully)
    func persistPoll(_ response: UsageResponse) async throws

    /// Persists a poll snapshot and detects/records any reset events.
    /// - Parameters:
    ///   - response: The usage response from the API
    ///   - tier: The rate limit tier string from credentials (for reset event recording)
    /// - Throws: Database errors (caller should handle gracefully)
    func persistPoll(_ response: UsageResponse, tier: String?) async throws

    /// Retrieves recent poll data for sparkline and chart rendering.
    ///
    /// Returns raw polls suitable for fine-grained visualization:
    /// - `timestamp`: Unix ms for X-axis positioning
    /// - `fiveHourUtil`: Y-axis primary series (5-hour utilization %)
    /// - `sevenDayUtil`: Y-axis secondary series (7-day utilization %)
    /// - `fiveHourResetsAt`/`sevenDayResetsAt`: Reset boundary markers
    ///
    /// - Parameter hours: Number of hours to look back (typically 24 for sparklines)
    /// - Returns: Array of poll records ordered by timestamp ascending
    func getRecentPolls(hours: Int) async throws -> [UsagePoll]

    /// Retrieves the most recent poll from the database.
    /// - Returns: The last poll, or nil if no polls exist
    func getLastPoll() async throws -> UsagePoll?

    /// Retrieves reset events within an optional time range.
    /// - Parameters:
    ///   - fromTimestamp: Optional start timestamp (Unix ms), inclusive
    ///   - toTimestamp: Optional end timestamp (Unix ms), inclusive
    /// - Returns: Array of reset events ordered by timestamp ascending
    func getResetEvents(fromTimestamp: Int64?, toTimestamp: Int64?) async throws -> [ResetEvent]

    /// Retrieves reset events within a time range.
    /// Uses TimeRange enum for API consistency (same parameter pattern as getRolledUpData).
    /// - Parameter range: Time range to query (.day, .week, .month, .all)
    /// - Returns: Array of reset events ordered by timestamp ascending
    func getResetEvents(range: TimeRange) async throws -> [ResetEvent]

    /// Returns the current database file size in bytes.
    func getDatabaseSize() async throws -> Int64

    // MARK: - Story 10.4: Tiered Rollup Engine

    /// Ensures all rollup tiers are up-to-date.
    /// Call before querying historical data for analytics.
    /// Performs rollups on-demand, not on a background timer.
    /// - Throws: Database errors (caller should handle gracefully)
    func ensureRollupsUpToDate() async throws

    /// Retrieves historical data at appropriate resolution for the time range.
    /// Automatically stitches data from different resolution tiers.
    /// - Parameter range: Time range to query (.day, .week, .month, .all)
    /// - Returns: Array of rollup records ordered by period_start ascending
    func getRolledUpData(range: TimeRange) async throws -> [UsageRollup]

    /// Prunes data older than the retention period.
    /// Called automatically at the end of ensureRollupsUpToDate().
    /// - Parameter retentionDays: Maximum age of data to retain
    func pruneOldData(retentionDays: Int) async throws

    /// Deletes all historical data (usage_polls, usage_rollups, reset_events, rollup_metadata, api_outages)
    /// and reclaims disk space via VACUUM.
    /// - Throws: Database errors (caller should handle gracefully)
    func clearAllData() async throws

    /// Returns total extra usage spend per billing cycle.
    /// Uses MAX(extra_usage_used_credits) per cycle since usedCredits is cumulative.
    /// - Parameter billingCycleDay: User-configured billing day (1-28), nil for calendar month grouping
    /// - Returns: Dictionary mapping cycle keys (e.g., "2026-Jan") to total extra usage spend
    func getExtraUsagePerCycle(billingCycleDay: Int?) async throws -> [String: Double]

    // MARK: - Story 10.6: API Outage Period Tracking

    /// Evaluates the current API connectivity state and manages outage records.
    /// Called after every poll cycle (success or failure). Uses a 2-failure threshold
    /// to start an outage and closes it on the first success.
    /// Handles errors internally (log and continue) — never throws.
    /// - Parameters:
    ///   - apiReachable: Whether the API responded successfully
    ///   - failureReason: The failure reason string (nil on success)
    func evaluateOutageState(apiReachable: Bool, failureReason: String?) async

    /// Retrieves outage periods that overlap the requested time range.
    /// - Parameters:
    ///   - from: Optional start of range (inclusive), nil for no lower bound
    ///   - to: Optional end of range (inclusive), nil for no upper bound
    /// - Returns: Array of outage periods ordered by started_at ascending
    func getOutagePeriods(from: Date?, to: Date?) async throws -> [OutagePeriod]

    /// Closes all open outage records by setting ended_at.
    /// Not currently called in production — `evaluateOutageState(apiReachable: true)` handles
    /// recovery inline. Retained for Story 13.8 (outage background rendering) which may need
    /// explicit cleanup of stale outage records.
    /// - Parameter endedAt: The timestamp to set as the outage end time
    func closeOpenOutages(endedAt: Date) async throws

    /// Restores in-memory outage tracking state from the database on startup.
    /// If an open outage record exists, sets outageActive = true so the next
    /// evaluateOutageState call can properly close it on success or continue it on failure.
    func loadOutageState() async throws
}
