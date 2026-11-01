import Foundation

/// Breakdown of a single reset into used, constrained, and unused credits.
/// A 5-hour event has three bands relative to the 5-hour limit. A weekly cycle has two,
/// used and unused, relative to the weekly limit. Either way the percentages total 100%.
struct HeadroomBreakdown: Sendable, Equatable {
    /// Percentage of the window's credits actually consumed
    let usedPercent: Double
    /// Percentage of 5h credits blocked by the 7d limit (NOT unused). Always 0 for a weekly cycle.
    let constrainedPercent: Double
    /// Percentage of the window's credits that went unused
    let unusedPercent: Double
    /// Absolute credits consumed
    let usedCredits: Double
    /// Absolute credits blocked by 7d constraint
    let constrainedCredits: Double
    /// Absolute credits unused
    let unusedCredits: Double

    /// Two bands for a weekly cycle: its peak split into used and unused weekly credits.
    static func weeklyCycle(sevenDayPeak: Double, creditLimits: CreditLimits) -> HeadroomBreakdown {
        let peak = sevenDayPeak.clampedToPercent
        let weeklyLimit = Double(creditLimits.sevenDayCredits)
        let usedCredits = (peak / 100.0) * weeklyLimit
        return HeadroomBreakdown(
            usedPercent: peak,
            constrainedPercent: 0,
            unusedPercent: 100.0 - peak,
            usedCredits: usedCredits,
            constrainedCredits: 0,
            unusedCredits: weeklyLimit - usedCredits
        )
    }
}

extension Double {
    /// This value limited to 0-100. A value that is not finite counts as 0.
    var clampedToPercent: Double {
        isFinite ? Swift.min(Swift.max(self, 0), 100) : 0
    }
}

/// Aggregated headroom breakdown across multiple reset events in a time range.
struct PeriodSummary: Sendable, Equatable {
    /// Total credits consumed across all events
    let usedCredits: Double
    /// Total credits blocked by 7d constraint across all events
    let constrainedCredits: Double
    /// Total credits unused across all events
    let unusedCredits: Double
    /// Number of reset events in the period
    let resetCount: Int
    /// Average peak across events (percentage 0-100): 5-hour peak, or weekly peak for weekly cycles
    let avgPeakUtilization: Double
    /// Aggregate used percentage (relative to total capacity across all counted events)
    let usedPercent: Double
    /// Aggregate constrained percentage
    let constrainedPercent: Double
    /// Aggregate unused percentage
    let unusedPercent: Double
    /// How many of the counted events were weekly cycles. Each one stands for 7 days of capacity.
    var weeklyCycleCount: Int = 0
}
