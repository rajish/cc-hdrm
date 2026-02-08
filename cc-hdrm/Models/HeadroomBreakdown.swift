import Foundation

/// Breakdown of a single 5-hour reset window into used, constrained, and wasted credits.
/// All percentages are relative to the 5-hour credit limit (used + constrained + waste = 100%).
struct HeadroomBreakdown: Sendable, Equatable {
    /// Percentage of 5h credits actually consumed
    let usedPercent: Double
    /// Percentage of 5h credits blocked by the 7d limit (NOT waste)
    let constrainedPercent: Double
    /// Percentage of 5h credits genuinely wasted (unused and available)
    let wastePercent: Double
    /// Absolute credits consumed
    let usedCredits: Double
    /// Absolute credits blocked by 7d constraint
    let constrainedCredits: Double
    /// Absolute credits wasted
    let wasteCredits: Double
}

/// Aggregated headroom breakdown across multiple reset events in a time range.
struct PeriodSummary: Sendable, Equatable {
    /// Total credits consumed across all events
    let usedCredits: Double
    /// Total credits blocked by 7d constraint across all events
    let constrainedCredits: Double
    /// Total credits wasted across all events
    let wasteCredits: Double
    /// Number of reset events in the period
    let resetCount: Int
    /// Average peak 5h utilization across events (percentage 0-100)
    let avgPeakUtilization: Double
    /// Aggregate used percentage (relative to total 5h capacity across all events)
    let usedPercent: Double
    /// Aggregate constrained percentage
    let constrainedPercent: Double
    /// Aggregate waste percentage
    let wastePercent: Double
}
