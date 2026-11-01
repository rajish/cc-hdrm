import Foundation

/// Represents a window reset event for headroom analysis.
/// Captures the peak utilization reached before a window reset, enabling
/// future unused credit calculations (deferred to Epic 14).
struct ResetEvent: Sendable, Equatable {
    /// Length of the cycle a weekly reset event stands for, in milliseconds.
    static let weeklyCycleMs: Int64 = 7 * 24 * 60 * 60 * 1000

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
    /// True only if recorded as a weekly reset with no 5-hour number on the polls around it.
    /// Never derive this from an empty `fiveHourPeak`: a Mac asleep for over 5 hours leaves one too.
    var isWeeklyCycle: Bool = false
}

extension Array where Element == ResetEvent {
    /// Leaves out events inside the 7 days before a weekly cycle, because the weekly value
    /// already contains their usage, and empty-peak rows, which add days but no usage.
    /// Only an account that changed state has both kinds.
    func excludingWeeklyOverlap() -> [ResetEvent] {
        let cycleEnds = filter(\.isWeeklyCycle).map(\.timestamp)
        guard !cycleEnds.isEmpty else { return self }
        return filter { event in
            if event.isWeeklyCycle { return true }
            return event.fiveHourPeak != nil && !cycleEnds.contains { end in
                event.timestamp >= end - ResetEvent.weeklyCycleMs && event.timestamp < end
            }
        }
    }

    /// Time between the first and last counted 5-hour events, without the weeks that
    /// weekly cycles already stand for. Nil when no 5-hour event counts.
    var fiveHourSpanMs: Int64? {
        let counted = excludingWeeklyOverlap()
        let fiveHourEvents = counted.filter { !$0.isWeeklyCycle }
        guard let first = fiveHourEvents.first, let last = fiveHourEvents.last else { return nil }
        let coveredMs = counted.filter(\.isWeeklyCycle).reduce(Int64(0)) { sum, cycle in
            let start = Swift.max(cycle.timestamp - ResetEvent.weeklyCycleMs, first.timestamp)
            let end = Swift.min(cycle.timestamp, last.timestamp)
            return sum + Swift.max(0, end - start)
        }
        return Swift.max(0, last.timestamp - first.timestamp - coveredMs)
    }

    /// Whether the latest event that counts is a weekly cycle, so the account last reported no 5-hour number.
    var endsInWeeklyCycle: Bool {
        excludingWeeklyOverlap().last?.isWeeklyCycle == true
    }

    /// Whether the events that count are all weekly cycles, so the range has no 5-hour bands to show.
    var isOnlyWeeklyCycles: Bool {
        let counted = excludingWeeklyOverlap()
        return !counted.isEmpty && counted.allSatisfy(\.isWeeklyCycle)
    }
}
