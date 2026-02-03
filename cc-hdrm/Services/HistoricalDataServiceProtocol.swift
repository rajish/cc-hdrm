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

    /// Retrieves recent poll data.
    /// - Parameter hours: Number of hours to look back
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

    /// Returns the current database file size in bytes.
    func getDatabaseSize() async throws -> Int64
}
