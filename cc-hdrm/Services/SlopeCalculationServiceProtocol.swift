import Foundation

/// Protocol for slope calculation service, enabling testability via dependency injection.
/// Implementations track recent poll data and calculate utilization rate-of-change.
protocol SlopeCalculationServiceProtocol: Sendable {
    /// Add a poll data point to the ring buffer.
    /// Evicts entries older than 15 minutes.
    /// - Parameter poll: The usage poll to add
    func addPoll(_ poll: UsagePoll)

    /// Calculate current slope for specified window.
    /// Returns `.flat` if insufficient data (< 10 minutes).
    /// - Parameter window: The usage window to calculate slope for
    /// - Returns: The slope level indicating rate of change
    func calculateSlope(for window: UsageWindow) -> SlopeLevel

    /// Bootstrap buffer from historical data on app launch.
    /// - Parameter polls: Array of historical polls to populate buffer
    func bootstrapFromHistory(_ polls: [UsagePoll])
}
