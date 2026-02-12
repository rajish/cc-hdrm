import Foundation

/// Protocol for tier recommendation operations.
/// Compares actual usage against all available subscription tiers
/// using total cost (base price + extra usage) to determine the optimal tier.
protocol TierRecommendationServiceProtocol: Sendable {
    /// Compares the user's actual usage against all tiers and returns a recommendation.
    ///
    /// - Parameter range: Time range to analyze (.day, .week, .month, .all)
    /// - Returns: A recommendation (.downgrade, .upgrade, .goodFit), or nil if insufficient data
    ///   (fewer than 14 days of usage history or unresolvable current tier)
    /// - Throws: Database errors from historical data queries
    func recommendTier(for range: TimeRange) async throws -> TierRecommendation?
}
