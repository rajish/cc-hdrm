import Foundation

/// Protocol for slope calculation service, enabling testability via dependency injection.
/// Implementations track recent poll data and calculate utilization rate-of-change.
protocol SlopeCalculationServiceProtocol: Sendable {
    /// Add a poll data point to the ring buffer.
    /// Evicts entries older than 15 minutes.
    /// - Parameter poll: The usage poll to add
    func addPoll(_ poll: UsagePoll)

    /// Calculate current slope for specified window with optional credit normalization.
    /// Returns `.flat` if insufficient data (< 10 minutes).
    /// - Parameters:
    ///   - window: The usage window to calculate slope for
    ///   - normalizationFactor: For 7d window, multiplies raw rate by this factor (7d_limit / 5h_limit).
    ///     Nil means no normalization (raw percentage rate). Ignored for 5h window.
    /// - Returns: The slope level indicating rate of change
    func calculateSlope(for window: UsageWindow, normalizationFactor: Double?) -> SlopeLevel

    /// Bootstrap buffer from historical data on app launch.
    /// - Parameter polls: Array of historical polls to populate buffer
    func bootstrapFromHistory(_ polls: [UsagePoll])
}

// MARK: - Default convenience overload

extension SlopeCalculationServiceProtocol {
    /// Convenience overload without normalization factor (backward compatible).
    func calculateSlope(for window: UsageWindow) -> SlopeLevel {
        calculateSlope(for: window, normalizationFactor: nil)
    }
}
