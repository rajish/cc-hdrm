import Foundation
import os

/// Calculates headroom breakdown (used, constrained, unused) at each 5-hour reset event.
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

        for event in events {
            // Skip events with nil fiveHourPeak or sevenDayUtil
            guard let peak = event.fiveHourPeak,
                  let util7d = event.sevenDayUtil else {
                Self.logger.info("Skipping event id=\(event.id) — missing fiveHourPeak or sevenDayUtil")
                continue
            }

            // Resolve credit limits per-event from each event's tier
            guard let limits = RateLimitTier.resolve(
                tierString: event.tier,
                preferencesManager: preferencesManager
            ) else {
                Self.logger.info("Skipping event id=\(event.id) — unresolvable tier '\(event.tier ?? "nil", privacy: .public)'")
                continue
            }

            let breakdown = analyzeResetEvent(
                fiveHourPeak: peak,
                sevenDayUtil: util7d,
                creditLimits: limits
            )

            totalUsed += breakdown.usedCredits
            totalConstrained += breakdown.constrainedCredits
            totalUnused += breakdown.unusedCredits
            peakSum += peak
            validCount += 1
        }

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
            unusedPercent: unusedPercent
        )
    }
}
