import Foundation

/// Protocol for headroom analysis operations on reset events.
protocol HeadroomAnalysisServiceProtocol: Sendable {
    /// Analyzes a single reset event to produce a headroom breakdown.
    /// - Parameters:
    ///   - fiveHourPeak: Peak 5h utilization before reset (percentage 0-100)
    ///   - sevenDayUtil: 7d utilization at reset time (percentage 0-100)
    ///   - creditLimits: Credit limits for the user's tier
    /// - Returns: Breakdown of used, constrained, and unused credits
    func analyzeResetEvent(
        fiveHourPeak: Double,
        sevenDayUtil: Double,
        creditLimits: CreditLimits
    ) -> HeadroomBreakdown

    /// Aggregates headroom breakdown across multiple reset events.
    /// Each event's tier is resolved individually, supporting mixed-tier aggregation.
    /// Weekly cycles keep their stored credits. A 5-hour event uses its stored credits only when its tier does not resolve.
    /// Skipped: events with nil sevenDayUtil, events with nil fiveHourPeak that are not weekly
    /// cycles, and events with neither stored credits nor a resolvable tier.
    /// 5-hour events inside a weekly cycle's 7 days are left out.
    /// - Parameter events: Array of reset events to aggregate
    /// - Returns: Aggregated period summary
    func aggregateBreakdown(
        events: [ResetEvent]
    ) -> PeriodSummary
}
