import Foundation
import os

/// Analyzes historical usage data for slow-burn subscription patterns.
/// Pure analysis service: queries data from HistoricalDataService, returns PatternFinding results.
/// Does NOT send notifications or update UI (that is Story 16.2).
final class SubscriptionPatternDetector: SubscriptionPatternDetectorProtocol, @unchecked Sendable {
    private let historicalDataService: any HistoricalDataServiceProtocol
    private let preferencesManager: any PreferencesManagerProtocol

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "patterns"
    )

    /// Minimum weeks of low utilization to trigger forgotten subscription pattern.
    static let forgottenSubscriptionMinWeeks = 2
    /// Utilization threshold (%) below which usage is considered "forgotten".
    static let forgottenSubscriptionThreshold = 5.0
    /// Minimum consecutive months for chronic overpaying detection.
    static let chronicOverpayingMinMonths = 3
    /// Minimum consecutive months for chronic underpowering detection.
    static let chronicUnderpoweringMinMonths = 2
    /// Minimum rate-limit events per billing cycle to trigger underpowering.
    static let rateLimitThreshold = 3
    /// Minimum consecutive months for usage decay detection.
    static let usageDecayMinMonths = 3
    /// Minimum consecutive billing periods for extra usage overflow detection.
    static let extraUsageOverflowMinPeriods = 2
    /// Minimum consecutive months for persistent extra usage detection.
    static let persistentExtraUsageMinMonths = 2
    /// Threshold: extra usage must exceed this fraction of base price to be "persistent".
    static let persistentExtraUsageThreshold = 0.5

    init(
        historicalDataService: any HistoricalDataServiceProtocol,
        preferencesManager: any PreferencesManagerProtocol
    ) {
        self.historicalDataService = historicalDataService
        self.preferencesManager = preferencesManager
    }

    func analyzePatterns() async throws -> [PatternFinding] {
        var findings: [PatternFinding] = []

        if let finding = try await detectForgottenSubscription() {
            findings.append(finding)
        }
        if let finding = try await detectChronicOverpaying() {
            findings.append(finding)
        }
        if let finding = try await detectChronicUnderpowering() {
            findings.append(finding)
        }
        if let finding = try await detectUsageDecay() {
            findings.append(finding)
        }
        if let finding = try await detectExtraUsageOverflow() {
            findings.append(finding)
        }
        if let finding = try await detectPersistentExtraUsage() {
            findings.append(finding)
        }

        Self.logger.info("Pattern analysis complete: \(findings.count, privacy: .public) findings")
        return findings
    }

    // MARK: - Forgotten Subscription (AC: 2)

    /// Detects if utilization has been below 5% for 2+ consecutive weeks.
    private func detectForgottenSubscription() async throws -> PatternFinding? {
        // Need at least 14 days of data
        let polls = try await historicalDataService.getRecentPolls(hours: 24 * 30) // 30 days
        guard !polls.isEmpty else {
            Self.logger.debug("Forgotten subscription: insufficient data (no polls)")
            return nil
        }

        let firstTimestamp = polls.first!.timestamp
        let lastTimestamp = polls.last!.timestamp
        let daysCovered = Double(lastTimestamp - firstTimestamp) / (1000.0 * 60 * 60 * 24)
        guard daysCovered >= 14 else {
            Self.logger.debug("Forgotten subscription: insufficient data (\(String(format: "%.1f", daysCovered)) days < 14)")
            return nil
        }

        // Group polls by calendar week
        let calendar = Calendar.current
        var weeklyUtilization: [(weekStart: Date, avgUtil: Double)] = []
        var weekGroups: [Int: [Double]] = [:] // weekOfYear -> utilization values

        for poll in polls {
            guard let util = poll.fiveHourUtil else { continue }
            let date = Date(timeIntervalSince1970: Double(poll.timestamp) / 1000.0)
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            let key = year * 100 + weekOfYear
            weekGroups[key, default: []].append(util)
        }

        // Calculate average utilization per week, sorted chronologically
        let sortedKeys = weekGroups.keys.sorted()
        for key in sortedKeys {
            let values = weekGroups[key]!
            let avg = values.reduce(0, +) / Double(values.count)
            let year = key / 100
            let week = key % 100
            var components = DateComponents()
            components.yearForWeekOfYear = year
            components.weekOfYear = week
            components.weekday = 2 // Monday
            let weekStart = calendar.date(from: components) ?? Date()
            weeklyUtilization.append((weekStart, avg))
        }

        // Find consecutive low-utilization weeks
        var consecutiveLowWeeks = 0
        var totalLowUtil = 0.0

        for weekData in weeklyUtilization.reversed() {
            if weekData.avgUtil < Self.forgottenSubscriptionThreshold {
                consecutiveLowWeeks += 1
                totalLowUtil += weekData.avgUtil
            } else {
                break
            }
        }

        guard consecutiveLowWeeks >= Self.forgottenSubscriptionMinWeeks else {
            return nil
        }

        let avgUtil = totalLowUtil / Double(consecutiveLowWeeks)

        // Get monthly cost from current tier
        let resetEvents = try await historicalDataService.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        let tierString = resetEvents.last?.tier
        let monthlyCost: Double
        if let tier = RateLimitTier(rawValue: tierString ?? "") {
            monthlyCost = tier.monthlyPrice
        } else if let customPrice = preferencesManager.customMonthlyPrice {
            monthlyCost = customPrice
        } else {
            monthlyCost = 0
        }

        Self.logger.info("Forgotten subscription detected: \(consecutiveLowWeeks) weeks at \(String(format: "%.1f", avgUtil))% avg")
        return .forgottenSubscription(weeks: consecutiveLowWeeks, avgUtilization: avgUtil, monthlyCost: monthlyCost)
    }

    // MARK: - Chronic Overpaying (AC: 3)

    /// Detects if total cost fits within a cheaper tier for 3+ consecutive months.
    private func detectChronicOverpaying() async throws -> PatternFinding? {
        let resetEvents = try await historicalDataService.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        guard !resetEvents.isEmpty else { return nil }

        let tierString = resetEvents.last?.tier
        guard let currentTier = RateLimitTier(rawValue: tierString ?? ""),
              currentTier != .pro else {
            // Already on cheapest tier or unknown tier
            return nil
        }

        // Group reset events by calendar month
        let monthlyData = groupByCalendarMonth(resetEvents)
        guard monthlyData.count >= Self.chronicOverpayingMinMonths else {
            Self.logger.debug("Chronic overpaying: insufficient data (\(monthlyData.count) months < \(Self.chronicOverpayingMinMonths))")
            return nil
        }

        // Get extra usage data for cost calculation
        let polls = try await historicalDataService.getRecentPolls(hours: 24 * 90)
        let monthlyExtraUsage = calculateMonthlyExtraUsage(polls)

        // Check cheaper tiers
        let cheaperTiers = RateLimitTier.allCases
            .filter { $0.monthlyPrice < currentTier.monthlyPrice }
            .sorted { $0.monthlyPrice > $1.monthlyPrice } // most expensive first among cheaper

        for cheaperTier in cheaperTiers {
            var consecutiveMonths = 0

            // Check most recent months
            let recentMonths = Array(monthlyData.suffix(Self.chronicOverpayingMinMonths))

            for monthData in recentMonths {
                let peakUtil5h = monthData.events.compactMap(\.fiveHourPeak).max() ?? 0
                let peakUtil7d = monthData.events.compactMap(\.sevenDayUtil).max() ?? 0

                // Would this cheaper tier have covered usage?
                let fiveHourCapacity = Double(cheaperTier.fiveHourCredits) / Double(currentTier.fiveHourCredits) * 100.0
                let sevenDayCapacity = Double(cheaperTier.sevenDayCredits) / Double(currentTier.sevenDayCredits) * 100.0

                if peakUtil5h <= fiveHourCapacity && peakUtil7d <= sevenDayCapacity {
                    consecutiveMonths += 1
                } else {
                    break
                }
            }

            if consecutiveMonths >= Self.chronicOverpayingMinMonths {
                let currentTotalCost = currentTier.monthlyPrice + (monthlyExtraUsage.last ?? 0)
                let savings = currentTotalCost - cheaperTier.monthlyPrice

                if savings > 0 {
                    Self.logger.info("Chronic overpaying detected: \(currentTier.displayName) -> \(cheaperTier.displayName), savings $\(String(format: "%.0f", savings))/mo")
                    return .chronicOverpaying(
                        currentTier: currentTier.displayName,
                        recommendedTier: cheaperTier.displayName,
                        monthlySavings: savings
                    )
                }
            }
        }

        return nil
    }

    // MARK: - Chronic Underpowering (AC: 4)

    /// Detects frequent rate-limiting for 2+ billing cycles, or excessive extra usage cost.
    private func detectChronicUnderpowering() async throws -> PatternFinding? {
        let resetEvents = try await historicalDataService.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        guard !resetEvents.isEmpty else { return nil }

        let tierString = resetEvents.last?.tier
        guard let currentTier = RateLimitTier(rawValue: tierString ?? ""),
              currentTier != .max20x else {
            // Already on highest tier or unknown tier
            return nil
        }

        // Get polls to check for rate-limit events (utilization >= 100%)
        let polls = try await historicalDataService.getRecentPolls(hours: 24 * 60) // 60 days
        let monthlyRateLimits = countMonthlyRateLimits(polls)

        guard monthlyRateLimits.count >= Self.chronicUnderpoweringMinMonths else {
            Self.logger.debug("Chronic underpowering: insufficient data (\(monthlyRateLimits.count) months < \(Self.chronicUnderpoweringMinMonths))")
            return nil
        }

        // Check extra usage cost path first
        let monthlyExtraUsage = calculateMonthlyExtraUsage(polls)
        let hasExtraUsageEnabled = polls.contains { $0.extraUsageEnabled == true }

        if hasExtraUsageEnabled {
            // Cost-based: check if base + extra exceeds a higher tier
            let higherTiers = RateLimitTier.allCases
                .filter { $0.monthlyPrice > currentTier.monthlyPrice }
                .sorted { $0.monthlyPrice < $1.monthlyPrice } // cheapest higher tier first

            if let suggestedTier = higherTiers.first {
                let recentExtra = monthlyExtraUsage.suffix(Self.chronicUnderpoweringMinMonths)
                let avgExtraUsage = recentExtra.isEmpty ? 0.0 : recentExtra.reduce(0, +) / Double(recentExtra.count)
                let totalCost = currentTier.monthlyPrice + avgExtraUsage

                if totalCost > suggestedTier.monthlyPrice {
                    let totalRateLimits = monthlyRateLimits.suffix(Self.chronicUnderpoweringMinMonths).reduce(0, +)
                    Self.logger.info("Chronic underpowering (cost-based): total $\(String(format: "%.0f", totalCost)) > \(suggestedTier.displayName) $\(suggestedTier.monthlyPrice)")
                    return .chronicUnderpowering(
                        rateLimitCount: totalRateLimits,
                        currentTier: currentTier.displayName,
                        suggestedTier: suggestedTier.displayName
                    )
                }
            }
        }

        // Frequency-based: count rate-limit events per cycle
        let recentMonths = monthlyRateLimits.suffix(Self.chronicUnderpoweringMinMonths)
        let allAboveThreshold = recentMonths.allSatisfy { $0 >= Self.rateLimitThreshold }

        if allAboveThreshold {
            let totalRateLimits = recentMonths.reduce(0, +)
            let higherTiers = RateLimitTier.allCases
                .filter { $0.monthlyPrice > currentTier.monthlyPrice }
                .sorted { $0.monthlyPrice < $1.monthlyPrice }

            if let suggestedTier = higherTiers.first {
                Self.logger.info("Chronic underpowering (frequency): \(totalRateLimits) rate-limits in \(Self.chronicUnderpoweringMinMonths) months")
                return .chronicUnderpowering(
                    rateLimitCount: totalRateLimits,
                    currentTier: currentTier.displayName,
                    suggestedTier: suggestedTier.displayName
                )
            }
        }

        return nil
    }

    // MARK: - Usage Decay (AC: 5)

    /// Detects if monthly utilization has declined for 3+ consecutive months.
    private func detectUsageDecay() async throws -> PatternFinding? {
        let rollups = try await historicalDataService.getRolledUpData(range: .all)
        guard !rollups.isEmpty else { return nil }

        // Group rollups by calendar month, compute average 5h utilization
        let calendar = Calendar.current
        var monthlyAvg: [(yearMonth: Int, avg: Double)] = []
        var monthGroups: [Int: [Double]] = [:]

        for rollup in rollups {
            guard let avg = rollup.fiveHourAvg else { continue }
            let date = Date(timeIntervalSince1970: Double(rollup.periodStart) / 1000.0)
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let key = year * 100 + month
            monthGroups[key, default: []].append(avg)
        }

        let sortedKeys = monthGroups.keys.sorted()
        for key in sortedKeys {
            let values = monthGroups[key]!
            let avg = values.reduce(0, +) / Double(values.count)
            monthlyAvg.append((key, avg))
        }

        guard monthlyAvg.count >= Self.usageDecayMinMonths else {
            Self.logger.debug("Usage decay: insufficient data (\(monthlyAvg.count) months < \(Self.usageDecayMinMonths))")
            return nil
        }

        // Check for consecutive decline in most recent months
        let recent = Array(monthlyAvg.suffix(Self.usageDecayMinMonths + 1))
        guard recent.count > Self.usageDecayMinMonths else { return nil }

        var isDecaying = true
        for i in 1..<recent.count {
            if recent[i].avg >= recent[i - 1].avg {
                isDecaying = false
                break
            }
        }

        guard isDecaying else { return nil }

        let currentUtil = recent.last!.avg
        let threeMonthAgoUtil = recent.first!.avg

        Self.logger.info("Usage decay detected: \(String(format: "%.0f", threeMonthAgoUtil))% -> \(String(format: "%.0f", currentUtil))%")
        return .usageDecay(currentUtil: currentUtil, threeMonthAgoUtil: threeMonthAgoUtil)
    }

    // MARK: - Extra Usage Overflow (AC: 6)

    /// Detects extra usage overflow for 2+ consecutive billing periods.
    private func detectExtraUsageOverflow() async throws -> PatternFinding? {
        let polls = try await historicalDataService.getRecentPolls(hours: 24 * 90) // 90 days
        guard !polls.isEmpty else { return nil }

        // Check if extra usage is enabled
        guard polls.contains(where: { $0.extraUsageEnabled == true }) else {
            Self.logger.debug("Extra usage overflow: extra usage not enabled")
            return nil
        }

        // Group by calendar month and track extra usage per period
        let monthlyExtra = calculateMonthlyExtraUsageDetails(polls)
        guard monthlyExtra.count >= Self.extraUsageOverflowMinPeriods else {
            Self.logger.debug("Extra usage overflow: insufficient periods (\(monthlyExtra.count))")
            return nil
        }

        // Check most recent periods for consecutive overflow
        let recentPeriods = Array(monthlyExtra.suffix(Self.extraUsageOverflowMinPeriods))
        let allOverflowing = recentPeriods.allSatisfy { $0.usedCredits > 0 }

        guard allOverflowing else { return nil }

        let avgExtraSpend = recentPeriods.map(\.estimatedCost).reduce(0, +) / Double(recentPeriods.count)

        // Find a tier that would cover usage without overflow
        let resetEvents = try await historicalDataService.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        let tierString = resetEvents.last?.tier
        guard let currentTier = RateLimitTier(rawValue: tierString ?? "") else { return nil }

        let higherTiers = RateLimitTier.allCases
            .filter { $0.monthlyPrice > currentTier.monthlyPrice }
            .sorted { $0.monthlyPrice < $1.monthlyPrice }

        guard let recommendedTier = higherTiers.first else { return nil }

        let currentTotalCost = currentTier.monthlyPrice + avgExtraSpend
        let estimatedSavings = currentTotalCost - recommendedTier.monthlyPrice

        guard estimatedSavings > 0 else { return nil }

        Self.logger.info("Extra usage overflow detected: avg $\(String(format: "%.0f", avgExtraSpend))/mo extra, savings $\(String(format: "%.0f", estimatedSavings))/mo")
        return .extraUsageOverflow(
            avgExtraSpend: avgExtraSpend,
            recommendedTier: recommendedTier.displayName,
            estimatedSavings: estimatedSavings
        )
    }

    // MARK: - Persistent Extra Usage (AC: 7)

    /// Detects if extra usage spending exceeds 50% of base subscription for 2+ months.
    private func detectPersistentExtraUsage() async throws -> PatternFinding? {
        let polls = try await historicalDataService.getRecentPolls(hours: 24 * 90)
        guard !polls.isEmpty else { return nil }

        guard polls.contains(where: { $0.extraUsageEnabled == true }) else {
            Self.logger.debug("Persistent extra usage: extra usage not enabled")
            return nil
        }

        let resetEvents = try await historicalDataService.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        let tierString = resetEvents.last?.tier
        guard let currentTier = RateLimitTier(rawValue: tierString ?? "") else { return nil }

        let basePrice = currentTier.monthlyPrice
        guard basePrice > 0 else { return nil }

        let monthlyExtra = calculateMonthlyExtraUsageDetails(polls)
        guard monthlyExtra.count >= Self.persistentExtraUsageMinMonths else {
            Self.logger.debug("Persistent extra usage: insufficient data (\(monthlyExtra.count) months)")
            return nil
        }

        let threshold = basePrice * Self.persistentExtraUsageThreshold
        let recentMonths = Array(monthlyExtra.suffix(Self.persistentExtraUsageMinMonths))
        let allAboveThreshold = recentMonths.allSatisfy { $0.estimatedCost > threshold }

        guard allAboveThreshold else { return nil }

        let avgMonthlyExtra = recentMonths.map(\.estimatedCost).reduce(0, +) / Double(recentMonths.count)

        // Find recommended tier
        let higherTiers = RateLimitTier.allCases
            .filter { $0.monthlyPrice > currentTier.monthlyPrice }
            .sorted { $0.monthlyPrice < $1.monthlyPrice }

        guard let recommendedTier = higherTiers.first else {
            // Already on highest tier, no upgrade to recommend
            return nil
        }

        Self.logger.info("Persistent extra usage detected: avg $\(String(format: "%.0f", avgMonthlyExtra))/mo vs $\(basePrice) base")
        return .persistentExtraUsage(
            avgMonthlyExtra: avgMonthlyExtra,
            basePrice: basePrice,
            recommendedTier: recommendedTier.displayName
        )
    }

    // MARK: - Helpers

    /// Groups reset events by calendar month.
    private struct MonthData {
        let yearMonth: Int
        let events: [ResetEvent]
    }

    private func groupByCalendarMonth(_ events: [ResetEvent]) -> [MonthData] {
        let calendar = Calendar.current
        var groups: [Int: [ResetEvent]] = [:]

        for event in events {
            let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000.0)
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let key = year * 100 + month
            groups[key, default: []].append(event)
        }

        return groups.keys.sorted().map { key in
            MonthData(yearMonth: key, events: groups[key]!)
        }
    }

    /// Calculates monthly extra usage spend from polls (estimated from used_credits).
    /// Returns an array of monthly extra usage dollar amounts, sorted chronologically.
    private func calculateMonthlyExtraUsage(_ polls: [UsagePoll]) -> [Double] {
        let details = calculateMonthlyExtraUsageDetails(polls)
        return details.map(\.estimatedCost)
    }

    /// Extra usage data aggregated per billing period.
    private struct MonthlyExtraUsageData {
        let yearMonth: Int
        let usedCredits: Double
        let estimatedCost: Double
    }

    /// Calculates detailed monthly extra usage from polls.
    /// Uses the maximum `extraUsageUsedCredits` value per month as the cumulative spend for that period.
    private func calculateMonthlyExtraUsageDetails(_ polls: [UsagePoll]) -> [MonthlyExtraUsageData] {
        let calendar = Calendar.current
        var monthlyMaxCredits: [Int: Double] = [:]

        for poll in polls {
            guard poll.extraUsageEnabled == true,
                  let usedCredits = poll.extraUsageUsedCredits,
                  usedCredits > 0 else { continue }

            let date = Date(timeIntervalSince1970: Double(poll.timestamp) / 1000.0)
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let key = year * 100 + month
            monthlyMaxCredits[key] = max(monthlyMaxCredits[key] ?? 0, usedCredits)
        }

        return monthlyMaxCredits.keys.sorted().map { key in
            let credits = monthlyMaxCredits[key]!
            // Extra usage cost is the used_credits value (already in dollar-equivalent units
            // based on API response format). If the API returns raw credits, this may need
            // conversion. For now, use the value directly as it represents dollar spend.
            return MonthlyExtraUsageData(yearMonth: key, usedCredits: credits, estimatedCost: credits)
        }
    }

    /// Counts rate-limit events (utilization >= 100%) per calendar month.
    /// Returns an array of counts sorted chronologically.
    private func countMonthlyRateLimits(_ polls: [UsagePoll]) -> [Int] {
        let calendar = Calendar.current
        var monthlyCounts: [Int: Int] = [:]

        for poll in polls {
            let isRateLimited = (poll.fiveHourUtil ?? 0) >= 100.0 || (poll.sevenDayUtil ?? 0) >= 100.0
            guard isRateLimited else { continue }

            let date = Date(timeIntervalSince1970: Double(poll.timestamp) / 1000.0)
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let key = year * 100 + month
            monthlyCounts[key, default: 0] += 1
        }

        // Include months with zero rate-limits if they have polls
        let allMonths = Set(polls.map { poll -> Int in
            let date = Date(timeIntervalSince1970: Double(poll.timestamp) / 1000.0)
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            return year * 100 + month
        })

        return allMonths.sorted().map { monthlyCounts[$0] ?? 0 }
    }
}
