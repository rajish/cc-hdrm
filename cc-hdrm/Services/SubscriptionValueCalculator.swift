import Foundation

/// Result of computing subscription value for a time period.
struct SubscriptionValue: Sendable, Equatable {
    /// Total credits consumed in the period
    let usedCredits: Double
    /// Total credits available in the period (7d limit prorated)
    let totalAvailableCredits: Double
    /// Utilization as a percentage (0-100)
    let utilizationPercent: Double
    /// Subscription cost prorated to the displayed period
    let periodPrice: Double
    /// Dollar value of credits consumed
    let usedDollars: Double
    /// Dollar value of credits wasted (not consumed)
    let wastedDollars: Double
    /// Full monthly subscription price
    let monthlyPrice: Double
}

/// Pure computation of subscription value metrics.
/// No side effects, no database access.
enum SubscriptionValueCalculator {
    /// Average days per month (365.25 / 12).
    static let averageDaysPerMonth: Double = 30.44

    /// Computes subscription value metrics for a set of reset events over a time range.
    ///
    /// - Parameters:
    ///   - resetEvents: Reset events in the period (from HistoricalDataService)
    ///   - creditLimits: Credit limits for the user's tier (must include monthlyPrice)
    ///   - timeRange: The selected time range (determines proration)
    ///   - headroomAnalysisService: Service to compute aggregate usage from events
    /// - Returns: `SubscriptionValue` with dollar amounts, or nil if monthlyPrice is unknown
    static func calculate(
        resetEvents: [ResetEvent],
        creditLimits: CreditLimits,
        timeRange: TimeRange,
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol
    ) -> SubscriptionValue? {
        guard let monthlyPrice = creditLimits.monthlyPrice else {
            return nil
        }

        let periodDays = Self.periodDays(for: timeRange, events: resetEvents)
        guard periodDays > 0 else { return nil }

        let totalAvailableCredits = Double(creditLimits.sevenDayCredits) * (periodDays / 7.0)
        guard totalAvailableCredits > 0 else { return nil }

        let summary = headroomAnalysisService.aggregateBreakdown(events: resetEvents)
        let usedCredits = summary.usedCredits

        let utilizationPercent = min(100.0, (usedCredits / totalAvailableCredits) * 100.0)
        let periodPrice = monthlyPrice * (periodDays / averageDaysPerMonth)
        let usedDollars = (utilizationPercent / 100.0) * periodPrice
        let wastedDollars = periodPrice - usedDollars

        return SubscriptionValue(
            usedCredits: usedCredits,
            totalAvailableCredits: totalAvailableCredits,
            utilizationPercent: utilizationPercent,
            periodPrice: periodPrice,
            usedDollars: usedDollars,
            wastedDollars: wastedDollars,
            monthlyPrice: monthlyPrice
        )
    }

    /// Returns the number of days for a time range.
    /// For `.all`, uses the actual span from the first to last event.
    static func periodDays(for timeRange: TimeRange, events: [ResetEvent]) -> Double {
        switch timeRange {
        case .day: return 1.0
        case .week: return 7.0
        case .month: return 30.0
        case .all:
            guard let first = events.first, let last = events.last else { return 0 }
            let spanMs = last.timestamp - first.timestamp
            let days = Double(spanMs) / (24.0 * 60.0 * 60.0 * 1000.0)
            // Minimum 1 day to avoid near-zero denominators
            return max(1.0, days)
        }
    }

    /// Formats a dollar amount for display.
    /// - Amounts that round to < $10: two decimal places (e.g., "$4.60")
    /// - Amounts that round to >= $10: no decimal places (e.g., "$75")
    /// Uses rounded value to avoid displaying "$10.00" for amounts like $9.995.
    static func formatDollars(_ amount: Double) -> String {
        let rounded = (amount * 100).rounded() / 100
        if rounded < 10.0 {
            return String(format: "$%.2f", amount)
        } else {
            return String(format: "$%.0f", amount)
        }
    }
}
