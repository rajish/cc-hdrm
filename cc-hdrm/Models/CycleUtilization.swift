import Foundation

/// Per-cycle utilization data for the cycle-over-cycle visualization.
/// Each instance represents one billing cycle (or calendar month) with
/// its utilization percentage, optional dollar value, and partial-cycle flag.
struct CycleUtilization: Identifiable, Sendable, Equatable {
    /// Short month label (e.g., "Jan", "Feb")
    let label: String
    /// Calendar year of the cycle
    let year: Int
    /// Utilization percentage (0-100)
    let utilizationPercent: Double
    /// Dollar value of usage in this cycle (nil if monthly price unknown)
    let dollarValue: Double?
    /// True if this is the current incomplete cycle
    let isPartial: Bool
    /// Number of reset events in this cycle
    let resetCount: Int
    /// Extra usage spend in cents for this cycle (nil if no extra usage data)
    var extraUsageSpend: Double? = nil

    var id: String { "\(year)-\(label)" }
}
