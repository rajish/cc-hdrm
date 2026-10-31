import Foundation
import os

/// Calculates headroom breakdown (used vs unused) per weekly cycle and aggregates reset events.
/// Legacy 5h events are aggregated from their stored credits, never recomputed.
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
        sevenDayPeak: Double,
        creditLimits: CreditLimits
    ) -> HeadroomBreakdown {
        let peak = min(max(sevenDayPeak, 0), 100)
        let weeklyLimit = Double(creditLimits.sevenDayCredits)
        let usedCredits = (peak / 100.0) * weeklyLimit

        return HeadroomBreakdown(
            usedPercent: peak,
            unusedPercent: 100.0 - peak,
            usedCredits: usedCredits,
            unusedCredits: weeklyLimit - usedCredits
        )
    }

    func aggregateBreakdown(
        events: [ResetEvent]
    ) -> PeriodSummary {
        var totalUsed: Double = 0
        var totalConstrained: Double = 0
        var totalUnused: Double = 0
        var peakSum: Double = 0
        var weeklyCount = 0
        var legacyCount = 0

        for event in events {
            if event.isWeeklyCycle, let sevenDayPeak = event.sevenDayUtil {
                guard let limits = RateLimitTier.resolve(
                    tierString: event.tier,
                    preferencesManager: preferencesManager
                ) else {
                    Self.logger.info("Skipping weekly cycle id=\(event.id) — unresolvable tier '\(event.tier ?? "nil", privacy: .public)'")
                    continue
                }

                let breakdown = analyzeResetEvent(sevenDayPeak: sevenDayPeak, creditLimits: limits)
                totalUsed += breakdown.usedCredits
                totalUnused += breakdown.unusedCredits
                peakSum += breakdown.usedPercent
                weeklyCount += 1
                continue
            }

            guard let peak = event.fiveHourPeak else {
                Self.logger.info("Skipping event id=\(event.id) — no 5h peak and not a weekly cycle (ts=\(event.timestamp))")
                continue
            }
            guard let used = event.usedCredits, let unused = event.unusedCredits else {
                Self.logger.info("Skipping legacy event id=\(event.id) — no stored credits")
                continue
            }

            totalUsed += used
            totalConstrained += event.constrainedCredits ?? 0
            totalUnused += unused
            peakSum += peak
            legacyCount += 1
        }

        let validCount = weeklyCount + legacyCount
        let totalCredits = totalUsed + totalConstrained + totalUnused
        let usedPercent = totalCredits > 0 ? (totalUsed / totalCredits) * 100.0 : 0
        let constrainedPercent = totalCredits > 0 ? (totalConstrained / totalCredits) * 100.0 : 0
        let unusedPercent = totalCredits > 0 ? (totalUnused / totalCredits) * 100.0 : 0
        let avgPeak = validCount > 0 ? peakSum / Double(validCount) : 0

        Self.logger.debug("Aggregated \(events.count) events: weekly=\(weeklyCount) legacy=\(legacyCount) skipped=\(events.count - validCount) used=\(totalUsed, format: .fixed(precision: 0))")

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
