import Foundation

/// Protocol for the historical TPP backfill service, enabling testability via dependency injection.
/// Computes approximate TPP values from existing raw poll history and log data.
protocol HistoricalTPPBackfillServiceProtocol: Sendable {
    /// Runs backfill if it hasn't been run before.
    /// Checks preferences fast path, then DB slow path for idempotency.
    func runBackfillIfNeeded() async

    /// Runs backfill with optional force flag to re-process existing data.
    /// - Parameter force: When true, deletes existing backfill records before re-running
    /// - Returns: Number of measurements generated
    @discardableResult
    func runBackfill(force: Bool) async -> Int
}
