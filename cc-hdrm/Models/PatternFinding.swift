import Foundation

/// Represents a slow-burn subscription pattern detected by SubscriptionPatternDetector.
/// Each case captures the data needed for notification and analytics display (Story 16.2).
enum PatternFinding: Sendable, Equatable {
    /// Utilization below 5% for 2+ consecutive weeks.
    case forgottenSubscription(weeks: Int, avgUtilization: Double, monthlyCost: Double)

    /// Total cost (base + extra usage) fits within a cheaper tier for 3+ consecutive months.
    case chronicOverpaying(currentTier: String, recommendedTier: String, monthlySavings: Double)

    /// Rate-limited frequently for 2+ consecutive billing cycles, or extra usage cost exceeds higher tier.
    case chronicUnderpowering(rateLimitCount: Int, currentTier: String, suggestedTier: String)

    /// Monthly utilization has declined for 3+ consecutive months.
    case usageDecay(currentUtil: Double, threeMonthAgoUtil: Double)

    /// Extra usage overflow (used_credits > 0) for 2+ consecutive billing periods.
    case extraUsageOverflow(avgExtraSpend: Double, recommendedTier: String, estimatedSavings: Double)

    /// Extra usage spending exceeds 50% of base subscription for 2+ consecutive months.
    case persistentExtraUsage(avgMonthlyExtra: Double, basePrice: Double, recommendedTier: String)

    /// Notification title for this finding.
    var title: String {
        switch self {
        case .forgottenSubscription:
            return "Subscription check-in"
        case .chronicOverpaying:
            return "Tier recommendation"
        case .chronicUnderpowering:
            return "Tier recommendation"
        case .usageDecay:
            return "Usage trend"
        case .extraUsageOverflow:
            return "Extra usage alert"
        case .persistentExtraUsage:
            return "Extra usage alert"
        }
    }

    /// Natural language summary for display in notifications and analytics cards.
    var summary: String {
        switch self {
        case .forgottenSubscription(let weeks, let avgUtil, let cost):
            return "You've used less than 5% of your Claude capacity for \(weeks) weeks. That's $\(Int(cost))/mo for ~\(String(format: "%.0f", avgUtil))% utilization. Worth reviewing?"

        case .chronicOverpaying(_, let recommended, let savings):
            return "Your usage fits \(recommended) — you could save $\(Int(savings))/mo"

        case .chronicUnderpowering(let count, _, let suggested):
            return "You've been rate-limited \(count) times recently. \(suggested) would cover your usage."

        case .usageDecay(let current, let threeMonthAgo):
            let drop = threeMonthAgo - current
            return "Your usage has declined from \(String(format: "%.0f", threeMonthAgo))% to \(String(format: "%.0f", current))% over 3 months (down \(String(format: "%.0f", drop)) points)"

        case .extraUsageOverflow(let avgExtra, let recommended, let savings):
            return "You're averaging $\(String(format: "%.0f", avgExtra))/mo in extra usage. \(recommended) would save ~$\(Int(savings))/mo"

        case .persistentExtraUsage(let avgExtra, let base, let recommended):
            let pct = base > 0 ? Int((avgExtra / base) * 100) : 0
            return "Extra usage is \(pct)% of your base subscription ($\(String(format: "%.0f", avgExtra))/$\(Int(base))/mo). Consider \(recommended)."
        }
    }

    /// Deterministic key for cooldown tracking and dismiss persistence.
    /// Based on finding type only, not associated values.
    var cooldownKey: String {
        switch self {
        case .forgottenSubscription: return "forgottenSubscription"
        case .chronicOverpaying: return "chronicOverpaying"
        case .chronicUnderpowering: return "chronicUnderpowering"
        case .usageDecay: return "usageDecay"
        case .extraUsageOverflow: return "extraUsageOverflow"
        case .persistentExtraUsage: return "persistentExtraUsage"
        }
    }
}
