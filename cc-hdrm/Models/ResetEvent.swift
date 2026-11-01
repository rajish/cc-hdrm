import Foundation

/// Represents a 5-hour window reset event for headroom analysis.
/// Captures the peak utilization reached before a window reset, enabling
/// future unused credit calculations (deferred to Epic 14).
struct ResetEvent: Sendable, Equatable {
    /// Database row ID
    let id: Int64
    /// Unix milliseconds when the reset was detected
    let timestamp: Int64
    /// Peak 5h utilization before reset (percentage 0-100), nil if unavailable
    let fiveHourPeak: Double?
    /// 7d utilization at reset time (percentage 0-100), nil if unavailable
    let sevenDayUtil: Double?
    /// Rate limit tier string from credentials (e.g., "default_claude_max_5x")
    let tier: String?
    /// Credits actually used (NULL until Epic 14)
    let usedCredits: Double?
    /// Credits blocked by 7d limit - NOT unused (NULL until Epic 14)
    let constrainedCredits: Double?
    /// True unused credits (NULL until Epic 14)
    let unusedCredits: Double?
}
