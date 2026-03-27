import Foundation

/// Health metrics for the passive TPP measurement engine.
struct PassiveTPPHealth: Sendable, Equatable {
    /// Number of poll-to-poll windows with >=1% utilization delta.
    let totalUtilizationChanges: Int
    /// Number of those windows that had matching Claude Code token data.
    let windowsWithTokenData: Int
    /// Percentage of utilization changes covered by token data (0-100).
    let coveragePercent: Double
    /// Whether coverage has degraded below the threshold.
    let isDegraded: Bool
    /// User-facing suggestion when coverage is degraded.
    let degradationSuggestion: String?

    /// Coverage threshold below which the engine is considered degraded.
    static let degradationThreshold: Double = 70.0
}
