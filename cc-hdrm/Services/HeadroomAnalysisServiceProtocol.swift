import Foundation

/// Protocol for headroom analysis operations on reset events.
protocol HeadroomAnalysisServiceProtocol: Sendable {
    /// Analyzes a single reset event to produce a headroom breakdown.
    /// - Parameters:
    ///   - fiveHourPeak: Peak 5h utilization before reset (percentage 0-100)
    ///   - sevenDayUtil: 7d utilization at reset time (percentage 0-100)
    ///   - creditLimits: Credit limits for the user's tier
    /// - Returns: Breakdown of used, constrained, and wasted credits
    func analyzeResetEvent(
        fiveHourPeak: Double,
        sevenDayUtil: Double,
        creditLimits: CreditLimits
    ) -> HeadroomBreakdown

    /// Aggregates headroom breakdown across multiple reset events.
    /// Each event's tier is resolved individually, supporting mixed-tier aggregation.
    /// Events with nil fiveHourPeak, sevenDayUtil, or unresolvable tier are skipped.
    /// - Parameter events: Array of reset events to aggregate
    /// - Returns: Aggregated period summary
    func aggregateBreakdown(
        events: [ResetEvent]
    ) -> PeriodSummary
}
