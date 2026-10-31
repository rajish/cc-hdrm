import Foundation

/// Breakdown of a single weekly cycle into used and unused weekly credits.
/// Percentages are relative to the weekly credit limit (used + unused = 100%).
struct HeadroomBreakdown: Sendable, Equatable {
    /// Percentage of weekly credits consumed
    let usedPercent: Double
    /// Percentage of weekly credits that went unused
    let unusedPercent: Double
    /// Absolute credits consumed
    let usedCredits: Double
    /// Absolute credits unused
    let unusedCredits: Double
}

/// Aggregated headroom breakdown across multiple reset events in a time range.
/// Constrained credits only come from stored legacy 5h events; weekly cycles contribute none.
struct PeriodSummary: Sendable, Equatable {
    /// Total credits consumed across all events
    let usedCredits: Double
    /// Total credits blocked by 7d constraint across legacy events
    let constrainedCredits: Double
    /// Total credits unused across all events
    let unusedCredits: Double
    /// Number of reset events in the period
    let resetCount: Int
    /// Average peak utilization across events (percentage 0-100): 5h peak for legacy events, weekly peak for weekly cycles
    let avgPeakUtilization: Double
    /// Aggregate used percentage (relative to total capacity across all counted events)
    let usedPercent: Double
    /// Aggregate constrained percentage
    let constrainedPercent: Double
    /// Aggregate unused percentage
    let unusedPercent: Double
}
