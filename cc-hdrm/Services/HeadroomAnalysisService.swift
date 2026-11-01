import Foundation
import os

/// Calculates headroom breakdown (used, constrained, unused) at each reset event.
/// Pure computation — no database access, no side effects.
final class HeadroomAnalysisService: HeadroomAnalysisServiceProtocol, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "headroom"
    )

    /// Optional preferences for resolving custom credit limits on unknown tiers.
    private let preferencesManager: (any PreferencesManagerProtocol)?

    init(preferencesManager: (any PreferencesManagerProtocol)? = nil) {
        self.preferencesManager = preferencesManager
    }

    func analyzeResetEvent(
        fiveHourPeak: Double,
        sevenDayUtil: Double,
        creditLimits: CreditLimits
    ) -> HeadroomBreakdown {
        let fiveHourPeak = fiveHourPeak.clampedToPercent
        let sevenDayUtil = sevenDayUtil.clampedToPercent
        let fiveHourLimit = Double(creditLimits.fiveHourCredits)
        let sevenDayLimit = Double(creditLimits.sevenDayCredits)

        // Remaining credits in each window
        let fiveHourRemaining = (1.0 - fiveHourPeak / 100.0) * fiveHourLimit
        let sevenDayRemaining = (1.0 - sevenDayUtil / 100.0) * sevenDayLimit

        // Credits actually used
        let usedCredits = (fiveHourPeak / 100.0) * fiveHourLimit

        // Determine unused vs constrained
        let trueUnusedCredits: Double
        let constrainedCredits: Double

        if fiveHourRemaining <= sevenDayRemaining {
            // 5h was NOT the binding constraint — all unused 5h was genuinely available
            trueUnusedCredits = fiveHourRemaining
            constrainedCredits = 0
        } else {
            // 7d was the binding constraint — only 7d_remaining was truly unused
            trueUnusedCredits = sevenDayRemaining
            constrainedCredits = fiveHourRemaining - sevenDayRemaining
        }

        // All percentages relative to 5h limit
        let usedPercent = fiveHourLimit > 0 ? (usedCredits / fiveHourLimit) * 100.0 : 0
        let unusedPercent = fiveHourLimit > 0 ? (trueUnusedCredits / fiveHourLimit) * 100.0 : 0
        let constrainedPercent = fiveHourLimit > 0 ? (constrainedCredits / fiveHourLimit) * 100.0 : 0

        let breakdown = HeadroomBreakdown(
            usedPercent: usedPercent,
            constrainedPercent: constrainedPercent,
            unusedPercent: unusedPercent,
            usedCredits: usedCredits,
            constrainedCredits: constrainedCredits,
            unusedCredits: trueUnusedCredits
        )

        return breakdown
    }

    func aggregateBreakdown(
        events: [ResetEvent]
    ) -> PeriodSummary {
        var totalUsed: Double = 0
        var totalConstrained: Double = 0
        var totalUnused: Double = 0
        var peakSum: Double = 0
        var validCount = 0
        var weeklyCycleCount = 0

        for event in events.excludingWeeklyOverlap() {
            // Skip events with no value for the window they measure, or no sevenDayUtil
            guard let util7d = event.sevenDayUtil,
                  let peak = event.isWeeklyCycle ? util7d.clampedToPercent : event.fiveHourPeak else {
                Self.logger.info("Skipping event id=\(event.id) — missing peak or sevenDayUtil")
                continue
            }

            guard let credits = credits(for: event, peak: peak, sevenDayUtil: util7d) else {
                Self.logger.info("Skipping event id=\(event.id) — no stored credits and unresolvable tier '\(event.tier ?? "nil", privacy: .public)'")
                continue
            }

            totalUsed += credits.used
            totalConstrained += credits.constrained
            totalUnused += credits.unused
            peakSum += peak
            validCount += 1
            if event.isWeeklyCycle { weeklyCycleCount += 1 }
        }

        Self.logger.debug("Aggregated \(events.count) events: counted=\(validCount), weekly=\(weeklyCycleCount)")

        let totalCredits = totalUsed + totalConstrained + totalUnused
        let usedPercent = totalCredits > 0 ? (totalUsed / totalCredits) * 100.0 : 0
        let constrainedPercent = totalCredits > 0 ? (totalConstrained / totalCredits) * 100.0 : 0
        let unusedPercent = totalCredits > 0 ? (totalUnused / totalCredits) * 100.0 : 0
        let avgPeak = validCount > 0 ? peakSum / Double(validCount) : 0

        return PeriodSummary(
            usedCredits: totalUsed,
            constrainedCredits: totalConstrained,
            unusedCredits: totalUnused,
            resetCount: validCount,
            avgPeakUtilization: avgPeak,
            usedPercent: usedPercent,
            constrainedPercent: constrainedPercent,
            unusedPercent: unusedPercent,
            weeklyCycleCount: weeklyCycleCount
        )
    }

    /// A weekly cycle keeps the credits it was recorded with. A 5-hour event is worked out from each
    /// event's tier as in 1.6.0, which supports mixed-tier aggregation, and falls back to its stored
    /// credits only when the tier no longer resolves.
    private func credits(
        for event: ResetEvent,
        peak: Double,
        sevenDayUtil: Double
    ) -> (used: Double, constrained: Double, unused: Double)? {
        var stored: (used: Double, constrained: Double, unused: Double)?
        if let used = event.usedCredits,
           let unused = event.unusedCredits,
           event.isWeeklyCycle || event.constrainedCredits != nil {
            stored = (used, event.constrainedCredits ?? 0, unused)
        }
        if event.isWeeklyCycle, let stored { return stored }

        guard let limits = RateLimitTier.resolve(
            tierString: event.tier,
            preferencesManager: preferencesManager
        ) else {
            return stored
        }

        let breakdown = event.isWeeklyCycle
            ? HeadroomBreakdown.weeklyCycle(sevenDayPeak: peak, creditLimits: limits)
            : analyzeResetEvent(fiveHourPeak: peak, sevenDayUtil: sevenDayUtil, creditLimits: limits)
        return (breakdown.usedCredits, breakdown.constrainedCredits, breakdown.unusedCredits)
    }
}
