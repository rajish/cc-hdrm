import Foundation

/// A detected usage-window reset, used for headroom and value analysis.
/// Before the 5-hour limit was retired these were 5-hour resets; since then they are weekly resets.
struct ResetEvent: Sendable, Equatable {
    /// Unix milliseconds when the 5-hour limit was retired (2026-10-31 08:03 UTC).
    /// Pre-cutover 5h resets after a long sleep also have a nil `fiveHourPeak`, so the
    /// timestamp is needed to tell them apart from weekly cycles.
    static let fiveHourLimitRetiredAtMs: Int64 = 1_793_433_780_000

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
    /// Credits actually used, as stored at record time
    let usedCredits: Double?
    /// Credits blocked by 7d limit - NOT unused (legacy 5h events only)
    let constrainedCredits: Double?
    /// True unused credits, as stored at record time
    let unusedCredits: Double?

    /// Whether this event closes a weekly cycle (post-cutover, no 5h peak, has a weekly value).
    var isWeeklyCycle: Bool {
        timestamp >= Self.fiveHourLimitRetiredAtMs && fiveHourPeak == nil && sevenDayUtil != nil
    }
}
