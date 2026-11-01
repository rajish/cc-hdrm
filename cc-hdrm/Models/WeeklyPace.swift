import Foundation

/// Weekly pace derived only from the weekly window's utilization and reset time.
/// Recomputed from current inputs on every read — no history, buffer, or tier credits.
struct WeeklyPace: Sendable, Equatable {
    static let weekDuration: TimeInterval = 7 * 24 * 60 * 60

    /// Early in the week the observed rate rests on too little data to project a run-out.
    static let minimumElapsedForRunOut: TimeInterval = 4 * 60 * 60

    /// Utilization minus the even-pace share of the elapsed week, in percentage points.
    /// Positive means spending faster than an even pace.
    let paceDelta: Double

    /// Projected time the weekly allowance runs out at the current average rate.
    /// Set only when that time falls before the weekly reset.
    let runOut: Date?

    /// Returns nil when the reset time is unknown or already passed, since the utilization
    /// then belongs to a finished week, or when the allowance is exhausted.
    init?(utilization: Double, resetsAt: Date?, now: Date) {
        guard let resetsAt, now < resetsAt, utilization < 100 else { return nil }

        let weekStart = resetsAt.addingTimeInterval(-Self.weekDuration)
        let sinceWeekStart = now.timeIntervalSince(weekStart)
        let elapsed = max(sinceWeekStart / Self.weekDuration, 0)
        paceDelta = utilization - elapsed * 100

        guard utilization > 0, sinceWeekStart >= Self.minimumElapsedForRunOut else {
            runOut = nil
            return
        }
        let rate = utilization / sinceWeekStart
        let projected = now.addingTimeInterval((100 - utilization) / rate)
        runOut = projected < resetsAt ? projected : nil
    }

    /// Popover pace line. Never relies on colour to convey pace.
    var paceLineText: String {
        guard let runOut else { return "On pace" }
        return "Ahead of pace \u{2014} runs out ~\(runOut.dayTimeString())"
    }

    /// Spoken counterpart of `paceLineText` for VoiceOver.
    var accessibilityText: String {
        guard let runOut else { return "on pace" }
        return "ahead of pace, runs out around \(runOut.dayTimeString())"
    }
}
