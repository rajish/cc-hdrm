import Foundation
import os

/// Compares actual usage against all available tiers using total cost (base + extra usage)
/// to determine whether the user is on the optimal subscription plan.
///
/// Data sources:
/// - ResetEvent history for peak usage and rate-limit frequency
/// - Extra usage poll data for overflow cost estimation
/// - RateLimitTier for credit limits and monthly pricing
final class TierRecommendationService: TierRecommendationServiceProtocol, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "recommendation"
    )

    private let historicalDataService: any HistoricalDataServiceProtocol
    private let preferencesManager: any PreferencesManagerProtocol

    /// Minimum days of data required to produce a recommendation.
    private let minimumDataDays: Int = 14

    /// Safety margin above actual peak usage. The recommended tier must have
    /// at least this much headroom above the user's peak usage.
    /// 0.20 = 20% headroom required.
    private let safetyMarginFraction: Double = 0.20

    /// Threshold for counting a reset event as a rate-limit event.
    /// A 5h peak at or above this percentage is considered rate-limited.
    private let rateLimitThreshold: Double = 95.0

    init(
        historicalDataService: any HistoricalDataServiceProtocol,
        preferencesManager: any PreferencesManagerProtocol
    ) {
        self.historicalDataService = historicalDataService
        self.preferencesManager = preferencesManager
    }

    // MARK: - TierRecommendationServiceProtocol

    func recommendTier(for range: TimeRange) async throws -> TierRecommendation? {
        // Gather reset events for the analysis range
        let resetEvents = try await historicalDataService.getResetEvents(range: range)

        // Check minimum data requirement
        guard hasMinimumData(events: resetEvents) else {
            Self.logger.info("Insufficient data for tier recommendation — fewer than \(self.minimumDataDays) days")
            return nil
        }

        // Resolve current tier from the most recent event
        guard let currentTierString = resetEvents.last?.tier,
              let currentTier = RateLimitTier(rawValue: currentTierString) else {
            Self.logger.info("Cannot resolve current tier — returning nil")
            return nil
        }

        let currentLimits = currentTier.creditLimits

        // Calculate peak usage in absolute credits
        let peakFiveHourCredits = calculatePeakCredits(
            events: resetEvents,
            creditLimit: currentLimits.fiveHourCredits,
            keyPath: \.fiveHourPeak
        )

        let peakSevenDayCredits = calculatePeakCredits(
            events: resetEvents,
            creditLimit: currentLimits.sevenDayCredits,
            keyPath: \.sevenDayUtil
        )

        // Count rate-limit events
        let rateLimitCount = countRateLimitEvents(events: resetEvents)

        // Estimate average monthly extra usage spend
        let monthlyExtraUsage = try await estimateMonthlyExtraUsage(range: range)

        // Current total monthly cost
        let currentMonthlyCost = currentTier.monthlyPrice + monthlyExtraUsage

        // Evaluate each tier
        var bestTier: RateLimitTier = currentTier
        var bestTotalCost: Double = currentMonthlyCost
        var bestFits = tierFitsUsage(
            tier: currentTier,
            peakFiveHourCredits: peakFiveHourCredits,
            peakSevenDayCredits: peakSevenDayCredits
        )

        for candidateTier in RateLimitTier.allCases {
            let fits = tierFitsUsage(
                tier: candidateTier,
                peakFiveHourCredits: peakFiveHourCredits,
                peakSevenDayCredits: peakSevenDayCredits
            )

            let candidateTotalCost: Double
            if fits {
                // Usage fits within tier — no extra usage needed
                candidateTotalCost = candidateTier.monthlyPrice
            } else if monthlyExtraUsage > 0 {
                // Usage exceeds tier — estimate extra usage cost
                // For simplicity, if usage doesn't fit, keep same extra usage cost
                // (in reality it would differ per tier, but we use the same actual spend)
                candidateTotalCost = candidateTier.monthlyPrice + monthlyExtraUsage
            } else {
                // Usage exceeds tier limits and no extra usage enabled — user would be rate-limited
                // This tier is not viable unless it's cheaper and the user accepts rate limiting
                candidateTotalCost = candidateTier.monthlyPrice
            }

            // Pick the cheapest tier that either fits or is cheaper in total cost
            if fits && candidateTotalCost < bestTotalCost {
                bestTier = candidateTier
                bestTotalCost = candidateTotalCost
                bestFits = true
            } else if !bestFits && fits {
                // Current best doesn't fit but this candidate does — prefer it
                bestTier = candidateTier
                bestTotalCost = candidateTotalCost
                bestFits = true
            }
        }

        let weeksOfData = calculateWeeksOfData(events: resetEvents)

        // Generate recommendation
        if bestTier == currentTier {
            // User is already on the best tier
            let avgHeadroom = calculateAverageHeadroom(events: resetEvents)
            Self.logger.info("Tier recommendation: goodFit on \(currentTier.rawValue, privacy: .public) with \(String(format: "%.1f", avgHeadroom))% headroom")
            return .goodFit(tier: currentTier, headroomPercent: avgHeadroom)
        } else if bestTier.monthlyPrice < currentTier.monthlyPrice {
            // Downgrade recommendation
            let savings = currentMonthlyCost - bestTotalCost
            Self.logger.info("Tier recommendation: downgrade from \(currentTier.rawValue, privacy: .public) to \(bestTier.rawValue, privacy: .public), saving $\(String(format: "%.0f", savings))/mo")
            return .downgrade(
                currentTier: currentTier,
                currentMonthlyCost: currentMonthlyCost,
                recommendedTier: bestTier,
                recommendedMonthlyCost: bestTotalCost,
                monthlySavings: savings,
                weeksOfData: weeksOfData
            )
        } else {
            // Upgrade recommendation — higher tier is cheaper in total cost
            let costComparison = buildCostComparison(
                currentTier: currentTier,
                currentMonthlyCost: currentMonthlyCost,
                recommendedTier: bestTier,
                monthlyExtraUsage: monthlyExtraUsage
            )
            Self.logger.info("Tier recommendation: upgrade from \(currentTier.rawValue, privacy: .public) to \(bestTier.rawValue, privacy: .public)")
            return .upgrade(
                currentTier: currentTier,
                currentMonthlyCost: currentMonthlyCost,
                recommendedTier: bestTier,
                recommendedMonthlyPrice: bestTier.monthlyPrice,
                rateLimitsAvoided: rateLimitCount,
                costComparison: costComparison
            )
        }
    }

    // MARK: - Private Helpers

    /// Checks whether the data spans at least `minimumDataDays` days.
    private func hasMinimumData(events: [ResetEvent]) -> Bool {
        guard let first = events.first, let last = events.last else { return false }
        let spanMs = last.timestamp - first.timestamp
        let spanDays = Double(spanMs) / (24.0 * 60.0 * 60.0 * 1000.0)
        return spanDays >= Double(minimumDataDays)
    }

    /// Calculates peak usage in absolute credits from reset events.
    private func calculatePeakCredits(
        events: [ResetEvent],
        creditLimit: Int,
        keyPath: KeyPath<ResetEvent, Double?>
    ) -> Double {
        let peakPercent = events.compactMap { $0[keyPath: keyPath] }.max() ?? 0
        return (peakPercent / 100.0) * Double(creditLimit)
    }

    /// Counts reset events where 5h utilization reached the rate-limit threshold.
    private func countRateLimitEvents(events: [ResetEvent]) -> Int {
        events.filter { ($0.fiveHourPeak ?? 0) >= rateLimitThreshold }.count
    }

    /// Estimates the average monthly extra usage spend from poll data.
    /// Returns 0 if extra usage is not enabled or no data available.
    private func estimateMonthlyExtraUsage(range: TimeRange) async throws -> Double {
        let hours: Int
        switch range {
        case .day: hours = 24
        case .week: hours = 168
        case .month: hours = 720
        case .all: hours = 8760
        }

        let polls = try await historicalDataService.getRecentPolls(hours: hours)

        // Filter to polls where extra usage is enabled with actual spend
        let extraUsagePolls = polls.filter { $0.extraUsageEnabled == true && $0.extraUsageUsedCredits != nil }
        guard !extraUsagePolls.isEmpty else { return 0 }

        // Get the most recent extra usage value — this represents cumulative spend for the current billing period
        // We need to find the maximum usedCredits value per billing period and average them
        let billingCycleDay = preferencesManager.billingCycleDay

        if let cycleDay = billingCycleDay {
            return estimateMonthlyExtraUsageWithBillingCycle(polls: extraUsagePolls, cycleDay: cycleDay)
        } else {
            return estimateMonthlyExtraUsageCalendarMonth(polls: extraUsagePolls)
        }
    }

    /// Estimates monthly extra usage by aggregating peak values per billing cycle.
    private func estimateMonthlyExtraUsageWithBillingCycle(polls: [UsagePoll], cycleDay: Int) -> Double {
        // Group polls by billing period
        var periodPeaks: [String: Double] = [:]

        for poll in polls {
            let date = Date(timeIntervalSince1970: Double(poll.timestamp) / 1000.0)
            let periodKey = billingPeriodKey(for: date, cycleDay: cycleDay)
            let credits = poll.extraUsageUsedCredits ?? 0
            periodPeaks[periodKey] = max(periodPeaks[periodKey] ?? 0, credits)
        }

        // Average the peak values across complete periods (exclude current partial period)
        let completePeriods = periodPeaks.filter { !isCurrentPeriod(key: $0.key, cycleDay: cycleDay) }
        guard !completePeriods.isEmpty else {
            // Only current period data — use it as provisional estimate
            let total = periodPeaks.values.reduce(0, +)
            return total / Double(max(periodPeaks.count, 1))
        }

        let total = completePeriods.values.reduce(0, +)
        return total / Double(completePeriods.count)
    }

    /// Estimates monthly extra usage using calendar months when billing cycle is not configured.
    private func estimateMonthlyExtraUsageCalendarMonth(polls: [UsagePoll]) -> Double {
        let calendar = Calendar.current
        var monthPeaks: [String: Double] = [:]

        for poll in polls {
            let date = Date(timeIntervalSince1970: Double(poll.timestamp) / 1000.0)
            let components = calendar.dateComponents([.year, .month], from: date)
            let key = "\(components.year ?? 0)-\(components.month ?? 0)"
            let credits = poll.extraUsageUsedCredits ?? 0
            monthPeaks[key] = max(monthPeaks[key] ?? 0, credits)
        }

        guard !monthPeaks.isEmpty else { return 0 }

        // Exclude current month as partial
        let now = Date()
        let currentComponents = calendar.dateComponents([.year, .month], from: now)
        let currentKey = "\(currentComponents.year ?? 0)-\(currentComponents.month ?? 0)"

        let completeMonths = monthPeaks.filter { $0.key != currentKey }
        if !completeMonths.isEmpty {
            let total = completeMonths.values.reduce(0, +)
            return total / Double(completeMonths.count)
        }

        // Only current month data — use as provisional
        let total = monthPeaks.values.reduce(0, +)
        return total / Double(monthPeaks.count)
    }

    /// Returns a billing period key string for grouping polls.
    private func billingPeriodKey(for date: Date, cycleDay: Int) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = components.day ?? 1
        let month = components.month ?? 1
        let year = components.year ?? 2026

        // If before cycle day in current month, the period started last month
        if day < cycleDay {
            if month == 1 {
                return "\(year - 1)-12"
            } else {
                return "\(year)-\(month - 1)"
            }
        } else {
            return "\(year)-\(month)"
        }
    }

    /// Checks if a billing period key represents the current (partial) period.
    private func isCurrentPeriod(key: String, cycleDay: Int) -> Bool {
        let currentKey = billingPeriodKey(for: Date(), cycleDay: cycleDay)
        return key == currentKey
    }

    /// Checks whether a candidate tier's limits would cover the user's peak usage
    /// with the configured safety margin.
    private func tierFitsUsage(
        tier: RateLimitTier,
        peakFiveHourCredits: Double,
        peakSevenDayCredits: Double
    ) -> Bool {
        let required5h = peakFiveHourCredits * (1.0 + safetyMarginFraction)
        let required7d = peakSevenDayCredits * (1.0 + safetyMarginFraction)
        return required5h <= Double(tier.fiveHourCredits) && required7d <= Double(tier.sevenDayCredits)
    }

    /// Calculates the average headroom percentage across recent reset events.
    private func calculateAverageHeadroom(events: [ResetEvent]) -> Double {
        let peaks = events.compactMap { $0.fiveHourPeak }
        guard !peaks.isEmpty else { return 100 }
        let avgPeak = peaks.reduce(0, +) / Double(peaks.count)
        return max(100.0 - avgPeak, 0)
    }

    /// Calculates the number of weeks of data from reset events.
    private func calculateWeeksOfData(events: [ResetEvent]) -> Int {
        guard let first = events.first, let last = events.last else { return 0 }
        let spanMs = last.timestamp - first.timestamp
        let spanWeeks = Double(spanMs) / (7.0 * 24.0 * 60.0 * 60.0 * 1000.0)
        return max(Int(spanWeeks.rounded()), 1)
    }

    /// Builds a natural language cost comparison string for upgrade recommendations.
    private func buildCostComparison(
        currentTier: RateLimitTier,
        currentMonthlyCost: Double,
        recommendedTier: RateLimitTier,
        monthlyExtraUsage: Double
    ) -> String? {
        guard monthlyExtraUsage > 0 else { return nil }
        let currentBase = currentTier.monthlyPrice
        let savings = currentMonthlyCost - recommendedTier.monthlyPrice
        if savings > 0 {
            return "On \(currentTier.displayName) ($\(Int(currentBase))/mo) you paid ~$\(Int(monthlyExtraUsage)) in extra usage ($\(Int(currentMonthlyCost)) total) — \(recommendedTier.displayName) ($\(Int(recommendedTier.monthlyPrice))/mo) would have covered you and saved $\(Int(savings))"
        } else {
            return "On \(currentTier.displayName) ($\(Int(currentBase))/mo) you paid ~$\(Int(monthlyExtraUsage)) in extra usage — \(recommendedTier.displayName) ($\(Int(recommendedTier.monthlyPrice))/mo) would eliminate rate limits"
        }
    }
}

