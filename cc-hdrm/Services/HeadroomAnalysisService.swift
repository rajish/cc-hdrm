import Foundation
import os

/// Calculates headroom breakdown (used vs unused) per weekly cycle and aggregates reset events.
/// Legacy 5h events are aggregated from their stored credits; only legacy events stored without
/// credits are rebuilt, from the historical 5h limits in `LegacyFiveHourLimit`.
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
        let peak = sevenDayPeak.isFinite ? min(max(sevenDayPeak, 0), 100) : 0
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

        for event in events.excludingWeeklyOverlap() {
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
            guard let credits = legacyCredits(for: event, fiveHourPeak: peak) else {
                Self.logger.info("Skipping legacy event id=\(event.id) — no stored credits and tier '\(event.tier ?? "nil", privacy: .public)' has no historical 5h limit")
                continue
            }

            totalUsed += credits.used
            totalConstrained += credits.constrained
            totalUnused += credits.unused
            peakSum += peak
            legacyCount += 1
        }

        let validCount = weeklyCount + legacyCount
        let eventCount = events.count
        let totalCredits = totalUsed + totalConstrained + totalUnused
        let usedPercent = totalCredits > 0 ? (totalUsed / totalCredits) * 100.0 : 0
        let constrainedPercent = totalCredits > 0 ? (totalConstrained / totalCredits) * 100.0 : 0
        let unusedPercent = totalCredits > 0 ? (totalUnused / totalCredits) * 100.0 : 0
        let avgPeak = validCount > 0 ? peakSum / Double(validCount) : 0

        Self.logger.debug("Aggregated \(eventCount) events: weekly=\(weeklyCount) legacy=\(legacyCount) skipped=\(eventCount - validCount) used=\(totalUsed, format: .fixed(precision: 0))")

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

    /// Stored credits of a legacy 5h event. Events recorded without credits (before credit
    /// storage existed) are rebuilt from the peak using the historical 5h limit, so their
    /// breakdown survives the retirement of the 5-hour limit.
    private func legacyCredits(
        for event: ResetEvent,
        fiveHourPeak: Double
    ) -> (used: Double, constrained: Double, unused: Double)? {
        if let used = event.usedCredits, let unused = event.unusedCredits {
            return (used, event.constrainedCredits ?? 0, unused)
        }

        guard let sevenDayUtil = event.sevenDayUtil,
              let fiveHourLimit = LegacyFiveHourLimit.credits(forTier: event.tier),
              let limits = RateLimitTier.resolve(tierString: event.tier, preferencesManager: preferencesManager) else {
            return nil
        }

        let fiveHourRemaining = (1.0 - fiveHourPeak / 100.0) * fiveHourLimit
        let sevenDayRemaining = (1.0 - sevenDayUtil / 100.0) * Double(limits.sevenDayCredits)
        let used = (fiveHourPeak / 100.0) * fiveHourLimit

        if fiveHourRemaining <= sevenDayRemaining {
            return (used, 0, fiveHourRemaining)
        }
        return (used, fiveHourRemaining - sevenDayRemaining, sevenDayRemaining)
    }
}

/// 5-hour credit limits per tier while the 5-hour limit existed (retired 2026-10-31).
/// Kept separate from `RateLimitTier` so that it can drop `fiveHourCredits`.
private enum LegacyFiveHourLimit {
    static func credits(forTier tier: String?) -> Double? {
        switch tier {
        case RateLimitTier.pro.rawValue: return 550_000
        case RateLimitTier.max5x.rawValue: return 3_300_000
        case RateLimitTier.max20x.rawValue: return 11_000_000
        default: return nil
        }
    }
}
