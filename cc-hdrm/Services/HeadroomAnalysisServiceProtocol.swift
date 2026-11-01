import Foundation

/// Protocol for headroom analysis operations on reset events.
protocol HeadroomAnalysisServiceProtocol: Sendable {
    /// Analyzes a single weekly cycle to produce a two-band headroom breakdown.
    /// - Parameters:
    ///   - sevenDayPeak: Weekly utilization reached before the reset (percentage, clamped to 0-100)
    ///   - creditLimits: Credit limits for the user's tier
    /// - Returns: Breakdown of used and unused weekly credits
    func analyzeResetEvent(
        sevenDayPeak: Double,
        creditLimits: CreditLimits
    ) -> HeadroomBreakdown

    /// Aggregates headroom breakdown across multiple reset events.
    /// Weekly cycles are computed from `sevenDayUtil` × weekly credits of each event's tier;
    /// legacy 5h events contribute their stored credits unchanged.
    /// Skipped: weekly cycles with unresolvable tier, non-weekly events without a 5h peak,
    /// and legacy events without stored credits.
    /// - Parameter events: Array of reset events to aggregate
    /// - Returns: Aggregated period summary
    func aggregateBreakdown(
        events: [ResetEvent]
    ) -> PeriodSummary
}
