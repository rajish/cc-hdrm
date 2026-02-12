import SwiftUI

/// Compact card displaying a tier recommendation in the analytics value section.
/// Appears between the HeadroomBreakdownBar and ContextAwareValueSummary.
/// Dismissible — writes fingerprint to PreferencesManager so it stays hidden
/// until the recommendation changes (different tiers or direction).
struct TierRecommendationCard: View {
    let recommendation: TierRecommendation
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.buildTitle(for: recommendation))
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(Self.buildSummary(for: recommendation))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let context = Self.buildContext(for: recommendation) {
                    Text(context)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityLabel("Dismiss recommendation")
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.buildAccessibilityLabel(for: recommendation))
    }

    // MARK: - Text Builders

    /// Title line for the recommendation card.
    static func buildTitle(for recommendation: TierRecommendation) -> String {
        switch recommendation {
        case .downgrade(_, _, let recommendedTier, _, _, _):
            return "Consider \(recommendedTier.displayName)"
        case .upgrade(_, _, let recommendedTier, _, _, _):
            return "Consider \(recommendedTier.displayName)"
        case .goodFit(let tier, _):
            return "\(tier.displayName) is a good fit"
        }
    }

    /// Natural language summary describing the recommendation.
    static func buildSummary(for recommendation: TierRecommendation) -> String {
        switch recommendation {
        case .downgrade(_, _, let recommendedTier, _, let monthlySavings, _):
            return "\(recommendedTier.displayName) would cover your usage and save ~$\(Int(monthlySavings))/mo"
        case .upgrade(_, _, _, _, let rateLimitsAvoided, let costComparison):
            if let costComparison {
                return costComparison
            } else if rateLimitsAvoided > 0 {
                return "Would have avoided \(rateLimitsAvoided) rate limit\(rateLimitsAvoided == 1 ? "" : "s") in this period"
            } else {
                return "A higher tier would provide more headroom"
            }
        case .goodFit(_, let headroomPercent):
            return "You're averaging \(Int(headroomPercent))% headroom"
        }
    }

    /// Optional context line (weeks of data or rate limits avoided).
    static func buildContext(for recommendation: TierRecommendation) -> String? {
        switch recommendation {
        case .downgrade(_, _, _, _, _, let weeksOfData):
            return "Based on \(weeksOfData) week\(weeksOfData == 1 ? "" : "s") of usage data"
        case .upgrade(_, _, _, _, let rateLimitsAvoided, _) where rateLimitsAvoided > 0:
            return "\(rateLimitsAvoided) rate limit\(rateLimitsAvoided == 1 ? "" : "s") detected in this period"
        default:
            return nil
        }
    }

    /// Combined accessibility label for VoiceOver.
    static func buildAccessibilityLabel(for recommendation: TierRecommendation) -> String {
        var parts = [buildTitle(for: recommendation), buildSummary(for: recommendation)]
        if let context = buildContext(for: recommendation) {
            parts.append(context)
        }
        return parts.joined(separator: ". ")
    }
}
