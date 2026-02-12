import SwiftUI

/// Popover card showing extra usage spend, limit, utilization bar, and billing cycle reset date.
/// Renders in three modes: full card (active spend), collapsed (enabled but no spend), or hidden (disabled).
struct ExtraUsageCardView: View {
    let appState: AppState
    let preferencesManager: PreferencesManagerProtocol

    var body: some View {
        if appState.extraUsageEnabled {
            if let used = appState.extraUsageUsedCredits, used > 0 {
                fullCard(usedCredits: used)
            } else {
                collapsedCard
            }
        }
    }

    // MARK: - Full Card

    @ViewBuilder
    private func fullCard(usedCredits: Double) -> some View {
        let limit = appState.extraUsageMonthlyLimit
        let hasLimit = limit != nil && limit! > 0
        let utilization = hasLimit ? min(1.0, usedCredits / limit!) : 0.0

        VStack(alignment: .leading, spacing: 6) {
            // Progress bar (only when limit is known)
            if hasLimit {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.extraUsageColor(for: utilization))
                            .frame(width: geometry.size.width * utilization, height: 6)
                    }
                }
                .frame(height: 6)
            }

            // Currency and utilization text
            HStack {
                Text(currencyText(usedCredits: usedCredits, limit: limit))
                    .font(.caption)
                    .fontWeight(.semibold)

                Spacer()

                if hasLimit {
                    Text(String(format: "%.0f%%", utilization * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Reset date context
            resetDateText
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fullCardAccessibilityLabel(usedCredits: usedCredits, limit: limit))
    }

    // MARK: - Collapsed Card

    private var collapsedCard: some View {
        Text("Extra usage: enabled, no spend this period")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Extra usage: enabled, no spend this period")
    }

    // MARK: - Currency Formatting

    private func currencyText(usedCredits: Double, limit: Double?) -> String {
        if let limit, limit > 0 {
            return String(format: "$%.2f / $%.2f", usedCredits, limit)
        }
        return String(format: "$%.2f spent", usedCredits)
    }

    // MARK: - Reset Date

    @ViewBuilder
    private var resetDateText: some View {
        if let day = preferencesManager.billingCycleDay {
            let resetDate = Self.nextResetDate(billingCycleDay: day)
            Text("Resets \(Self.formatResetDate(resetDate))")
        } else {
            Text("Set billing day in Settings for reset date")
        }
    }

    /// Computes the next occurrence of the billing cycle day from today.
    /// If today's day < billingCycleDay, reset is this month. Otherwise next month.
    static func nextResetDate(billingCycleDay: Int, relativeTo today: Date = Date()) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: today)
        let currentDay = components.day ?? 1

        var targetComponents = DateComponents()
        targetComponents.year = components.year
        targetComponents.day = billingCycleDay

        if currentDay < billingCycleDay {
            // Reset is this month
            targetComponents.month = components.month
        } else {
            // Reset is next month
            targetComponents.month = (components.month ?? 1) + 1
            // Handle December -> January year rollover
            if targetComponents.month! > 12 {
                targetComponents.month = 1
                targetComponents.year = (targetComponents.year ?? 2026) + 1
            }
        }

        // Calendar.date handles day overflow (e.g., day 30 in Feb -> last day of Feb)
        if let date = calendar.date(from: targetComponents) {
            return date
        }

        // Fallback: if the day is too large for the target month, use last day of month
        targetComponents.day = 1
        if let firstOfMonth = calendar.date(from: targetComponents),
           let range = calendar.range(of: .day, in: .month, for: firstOfMonth) {
            targetComponents.day = min(billingCycleDay, range.count)
            return calendar.date(from: targetComponents) ?? today
        }

        return today
    }

    /// Formats a date as "MMM d" (e.g., "Mar 1").
    static func formatResetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    // MARK: - Accessibility

    private func fullCardAccessibilityLabel(usedCredits: Double, limit: Double?) -> String {
        var parts: [String] = []

        if let limit, limit > 0 {
            let utilization = min(1.0, usedCredits / limit)
            parts.append(String(format: "Extra usage: $%.2f spent of $%.2f monthly limit, %.0f%% used", usedCredits, limit, utilization * 100))
        } else {
            parts.append(String(format: "Extra usage: $%.2f spent, no monthly limit set", usedCredits))
        }

        if let day = preferencesManager.billingCycleDay {
            let resetDate = Self.nextResetDate(billingCycleDay: day)
            parts.append("resets \(Self.formatResetDate(resetDate))")
        } else {
            parts.append("billing day not configured")
        }

        return parts.joined(separator: ", ")
    }
}
