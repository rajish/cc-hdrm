import Foundation

/// Protocol for historical usage data persistence and retrieval.
/// HistoricalDataService is the primary consumer of DatabaseManager for poll data.
protocol HistoricalDataServiceProtocol: Sendable {
    /// Persists a poll snapshot to the database.
    /// - Parameter response: The usage response from the API
    /// - Throws: Database errors (caller should handle gracefully)
    func persistPoll(_ response: UsageResponse) async throws

    /// Retrieves recent poll data.
    /// - Parameter hours: Number of hours to look back
    /// - Returns: Array of poll records ordered by timestamp ascending
    func getRecentPolls(hours: Int) async throws -> [UsagePoll]

    /// Returns the current database file size in bytes.
    func getDatabaseSize() async throws -> Int64
}
