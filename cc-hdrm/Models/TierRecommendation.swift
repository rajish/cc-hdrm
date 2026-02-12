import Foundation

/// Result of comparing the user's actual usage against all available subscription tiers.
/// Produced by `TierRecommendationService.recommendTier(for:)`.
enum TierRecommendation: Sendable, Equatable {
    /// User's usage fits a cheaper tier with safety margin.
    case downgrade(
        currentTier: RateLimitTier,
        currentMonthlyCost: Double,
        recommendedTier: RateLimitTier,
        recommendedMonthlyCost: Double,
        monthlySavings: Double,
        weeksOfData: Int
    )

    /// A higher tier would be cheaper than current base + extra usage,
    /// or would avoid rate-limiting.
    case upgrade(
        currentTier: RateLimitTier,
        currentMonthlyCost: Double,
        recommendedTier: RateLimitTier,
        recommendedMonthlyPrice: Double,
        rateLimitsAvoided: Int,
        costComparison: String?
    )

    /// User is on the optimal tier — no action needed.
    case goodFit(
        tier: RateLimitTier,
        headroomPercent: Double
    )

    /// Stable identifier for dismissal tracking.
    /// Changes when the recommendation type or involved tiers change,
    /// causing a dismissed card to re-appear.
    var recommendationFingerprint: String {
        switch self {
        case .downgrade(let currentTier, _, let recommendedTier, _, _, _):
            return "downgrade-\(currentTier.rawValue)-\(recommendedTier.rawValue)"
        case .upgrade(let currentTier, _, let recommendedTier, _, _, _):
            return "upgrade-\(currentTier.rawValue)-\(recommendedTier.rawValue)"
        case .goodFit(let tier, _):
            return "goodFit-\(tier.rawValue)"
        }
    }

    /// Whether this recommendation is actionable (should display a card).
    var isActionable: Bool {
        switch self {
        case .downgrade, .upgrade: return true
        case .goodFit: return false
        }
    }
}
