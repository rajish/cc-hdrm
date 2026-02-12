import SwiftUI

/// Resolved billing cycle reset info shared between display and accessibility label.
private struct ResetInfo {
    let displayText: String
    let accessibilityText: String
}

/// Popover card showing extra usage spend, limit, utilization bar, and billing cycle reset date.
/// Renders in three modes: full card (active spend), collapsed (enabled but no spend), or hidden (disabled).
struct ExtraUsageCardView: View {
    let appState: AppState
    let preferencesManager: PreferencesManagerProtocol

    var body: some View {
        if appState.extraUsageEnabled {
            if let usedCents = appState.extraUsageUsedCreditsCents, usedCents > 0 {
                fullCard(usedCents: usedCents)
            } else {
                collapsedCard
            }
        }
    }

    // MARK: - Full Card

    @ViewBuilder
    private func fullCard(usedCents: Int) -> some View {
        let limitCents = appState.extraUsageMonthlyLimitCents
        let hasLimit = limitCents != nil && limitCents! > 0
        let utilization = hasLimit ? min(1.0, Double(usedCents) / Double(limitCents!)) : 0.0
        let resetInfo = resolvedResetInfo

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
                Text(Self.currencyText(usedCents: usedCents, limitCents: limitCents))
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
            Text(resetInfo.displayText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fullCardAccessibilityLabel(usedCents: usedCents, limitCents: limitCents, utilization: utilization, resetInfo: resetInfo))
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

    /// Formats cent amounts to display currency using integer math (no floating-point rounding).
    /// Example: `currencyText(usedCents: 1561, limitCents: 4250)` → `"$15.61 / $42.50"`.
    static func currencyText(usedCents: Int, limitCents: Int?) -> String {
        if let limitCents, limitCents > 0 {
            return "\(AppState.formatCents(usedCents)) / \(AppState.formatCents(limitCents))"
        }
        return "\(AppState.formatCents(usedCents)) spent"
    }

    // MARK: - Reset Date

    /// Resolved reset info, computed once and shared between display and accessibility label.
    private var resolvedResetInfo: ResetInfo {
        if let day = appState.billingCycleDay {
            let resetDate = Self.nextResetDate(billingCycleDay: day)
            let formatted = Self.formatResetDate(resetDate)
            return ResetInfo(displayText: "Resets \(formatted)", accessibilityText: "resets \(formatted)")
        }
        return ResetInfo(displayText: "Set billing day in Settings for reset date", accessibilityText: "billing day not configured")
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
            let nextMonth = (components.month ?? 1) + 1
            // Handle December -> January year rollover
            if nextMonth > 12 {
                targetComponents.month = 1
                targetComponents.year = (components.year ?? 2026) + 1
            } else {
                targetComponents.month = nextMonth
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
        resetDateFormatter.string(from: date)
    }

    private static let resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    // MARK: - Accessibility

    private func fullCardAccessibilityLabel(usedCents: Int, limitCents: Int?, utilization: Double, resetInfo: ResetInfo) -> String {
        var parts: [String] = []

        if let limitCents, limitCents > 0 {
            parts.append("Extra usage: \(AppState.formatCents(usedCents)) spent of \(AppState.formatCents(limitCents)) monthly limit, \(Int(utilization * 100))% used")
        } else {
            parts.append("Extra usage: \(AppState.formatCents(usedCents)) spent, no monthly limit set")
        }

        parts.append(resetInfo.accessibilityText)
        return parts.joined(separator: ", ")
    }
}
