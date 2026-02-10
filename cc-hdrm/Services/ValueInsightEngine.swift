import Foundation

/// Result of computing a context-aware insight for the analytics summary.
struct ValueInsight: Sendable, Equatable {
    /// Display text for the insight
    let text: String
    /// true = muted styling, single quiet line (nothing notable)
    let isQuiet: Bool
}

/// Pure computation of context-aware value insights by time range.
/// No side effects, no database access.
enum ValueInsightEngine {

    /// Computes the most relevant insight for the selected time range.
    ///
    /// - Parameters:
    ///   - timeRange: Currently selected time range
    ///   - subscriptionValue: Pre-computed subscription value for the current range (nil if unknown tier)
    ///   - resetEvents: Reset events in the selected time range
    ///   - allTimeResetEvents: All reset events across all time (for 7d comparison)
    ///   - creditLimits: Credit limits (nil if unknown tier)
    ///   - headroomAnalysisService: Service for computing aggregate breakdowns
    /// - Returns: A `ValueInsight` with display text and quiet/notable flag
    static func computeInsight(
        timeRange: TimeRange,
        subscriptionValue: SubscriptionValue?,
        resetEvents: [ResetEvent],
        allTimeResetEvents: [ResetEvent],
        creditLimits: CreditLimits?,
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol
    ) -> ValueInsight {
        guard !resetEvents.isEmpty else {
            return ValueInsight(text: "No reset events in this period", isQuiet: true)
        }

        switch timeRange {
        case .day:
            return dayInsight(subscriptionValue: subscriptionValue, resetEvents: resetEvents, creditLimits: creditLimits, headroomAnalysisService: headroomAnalysisService)
        case .week:
            return weekInsight(subscriptionValue: subscriptionValue, resetEvents: resetEvents, allTimeResetEvents: allTimeResetEvents, creditLimits: creditLimits, headroomAnalysisService: headroomAnalysisService)
        case .month:
            return monthInsight(subscriptionValue: subscriptionValue, resetEvents: resetEvents, creditLimits: creditLimits, headroomAnalysisService: headroomAnalysisService)
        case .all:
            return allInsight(resetEvents: resetEvents, creditLimits: creditLimits, headroomAnalysisService: headroomAnalysisService)
        }
    }

    // MARK: - 24h Insight

    private static func dayInsight(
        subscriptionValue: SubscriptionValue?,
        resetEvents: [ResetEvent],
        creditLimits: CreditLimits?,
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol
    ) -> ValueInsight {
        if let value = subscriptionValue {
            let used = SubscriptionValueCalculator.formatDollars(value.usedDollars)
            let total = SubscriptionValueCalculator.formatDollars(value.periodPrice)
            let text = "Used \(used) of \(total) today"
            return ValueInsight(text: text, isQuiet: isQuietUtilization(value.utilizationPercent))
        }

        let util = computeUtilization(resetEvents: resetEvents, creditLimits: creditLimits, timeRange: .day, headroomAnalysisService: headroomAnalysisService)
        if let pct = util {
            return ValueInsight(text: "\(formatPercent(pct)) utilization today", isQuiet: isQuietUtilization(pct))
        }

        return ValueInsight(text: "Usage data available", isQuiet: true)
    }

    // MARK: - 7d Insight

    private static func weekInsight(
        subscriptionValue: SubscriptionValue?,
        resetEvents: [ResetEvent],
        allTimeResetEvents: [ResetEvent],
        creditLimits: CreditLimits?,
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol
    ) -> ValueInsight {
        // Check if we have sufficient history for comparison (>= 14 days of data)
        if let firstAll = allTimeResetEvents.first, let lastAll = allTimeResetEvents.last {
            let spanDays = Double(lastAll.timestamp - firstAll.timestamp) / (24.0 * 60.0 * 60.0 * 1000.0)

            if spanDays >= 14, let limits = creditLimits {
                let allTimeValue = SubscriptionValueCalculator.calculate(
                    resetEvents: allTimeResetEvents,
                    creditLimits: limits,
                    timeRange: .all,
                    headroomAnalysisService: headroomAnalysisService
                )

                if let allTimeUtil = allTimeValue?.utilizationPercent,
                   let currentUtil = subscriptionValue?.utilizationPercent ?? computeUtilization(resetEvents: resetEvents, creditLimits: creditLimits, timeRange: .week, headroomAnalysisService: headroomAnalysisService) {
                    let diff = currentUtil - allTimeUtil
                    if abs(diff) >= 5.0 {
                        let direction = diff > 0 ? "above" : "below"
                        return ValueInsight(text: "\(formatPercent(abs(diff))) \(direction) your typical week", isQuiet: false)
                    }
                    return ValueInsight(text: "Normal usage", isQuiet: true)
                }
            }
        }

        // Insufficient history — fall back to dollar/percentage summary
        if let value = subscriptionValue {
            let used = SubscriptionValueCalculator.formatDollars(value.usedDollars)
            let total = SubscriptionValueCalculator.formatDollars(value.periodPrice)
            return ValueInsight(text: "Used \(used) of \(total) this week", isQuiet: isQuietUtilization(value.utilizationPercent))
        }

        let util = computeUtilization(resetEvents: resetEvents, creditLimits: creditLimits, timeRange: .week, headroomAnalysisService: headroomAnalysisService)
        if let pct = util {
            return ValueInsight(text: "\(formatPercent(pct)) utilization this week", isQuiet: isQuietUtilization(pct))
        }

        return ValueInsight(text: "Usage data available", isQuiet: true)
    }

    // MARK: - 30d Insight

    private static func monthInsight(
        subscriptionValue: SubscriptionValue?,
        resetEvents: [ResetEvent],
        creditLimits: CreditLimits?,
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol
    ) -> ValueInsight {
        if let value = subscriptionValue {
            let used = SubscriptionValueCalculator.formatDollars(value.usedDollars)
            let total = SubscriptionValueCalculator.formatDollars(value.periodPrice)
            let pct = formatPercent(value.utilizationPercent)
            let text = "Used \(used) of \(total) this month (\(pct))"
            return ValueInsight(text: text, isQuiet: isQuietUtilization(value.utilizationPercent))
        }

        let util = computeUtilization(resetEvents: resetEvents, creditLimits: creditLimits, timeRange: .month, headroomAnalysisService: headroomAnalysisService)
        if let pct = util {
            return ValueInsight(text: "\(formatPercent(pct)) utilization this month", isQuiet: isQuietUtilization(pct))
        }

        return ValueInsight(text: "Usage data available", isQuiet: true)
    }

    // MARK: - All Insight

    private static func allInsight(
        resetEvents: [ResetEvent],
        creditLimits: CreditLimits?,
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol
    ) -> ValueInsight {
        guard let limits = creditLimits else {
            // Percentage-only mode: compute average utilization from aggregate
            let summary = headroomAnalysisService.aggregateBreakdown(events: resetEvents)
            let pct = summary.usedPercent
            return ValueInsight(text: "Avg utilization: \(formatPercent(pct))", isQuiet: isQuietUtilization(pct))
        }

        let monthlyUtilizations = computeMonthlyUtilizations(
            events: resetEvents,
            creditLimits: limits,
            headroomAnalysisService: headroomAnalysisService
        )

        guard !monthlyUtilizations.isEmpty else {
            return ValueInsight(text: "Usage data available", isQuiet: true)
        }

        let avgUtil = monthlyUtilizations.reduce(0, +) / Double(monthlyUtilizations.count)
        var text = "Avg monthly utilization: \(formatPercent(avgUtil))"
        var isQuiet = isQuietUtilization(avgUtil)

        // Trend detection: compare last 3 completed months
        if monthlyUtilizations.count >= 3 {
            let lastThree = Array(monthlyUtilizations.suffix(3))
            let allRising = lastThree[1] - lastThree[0] > 5.0 && lastThree[2] - lastThree[1] > 5.0
            let allFalling = lastThree[0] - lastThree[1] > 5.0 && lastThree[1] - lastThree[2] > 5.0

            if allRising {
                text += ", trending up"
                isQuiet = false
            } else if allFalling {
                text += ", trending down"
                isQuiet = false
            }
        }

        return ValueInsight(text: text, isQuiet: isQuiet)
    }

    // MARK: - Helpers

    /// Groups events by calendar month and computes per-month utilization.
    /// Returns utilizations in chronological order.
    /// Internal visibility for testing (peer helpers are private).
    static func computeMonthlyUtilizations(
        events: [ResetEvent],
        creditLimits: CreditLimits,
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol
    ) -> [Double] {
        let calendar = Calendar.current

        // Group events by (year, month)
        var groups: [DateComponents: [ResetEvent]] = [:]
        for event in events {
            let date = Date(timeIntervalSince1970: Double(event.timestamp) / 1000.0)
            let key = calendar.dateComponents([.year, .month], from: date)
            groups[key, default: []].append(event)
        }

        // Sort keys chronologically
        let sortedKeys = groups.keys.sorted { a, b in
            if a.year! != b.year! { return a.year! < b.year! }
            return a.month! < b.month!
        }

        var utilizations: [Double] = []
        for key in sortedKeys {
            guard let monthEvents = groups[key], !monthEvents.isEmpty else { continue }
            if let value = SubscriptionValueCalculator.calculate(
                resetEvents: monthEvents,
                creditLimits: creditLimits,
                timeRange: .month,
                headroomAnalysisService: headroomAnalysisService
            ) {
                utilizations.append(value.utilizationPercent)
            }
        }

        return utilizations
    }

    /// Computes utilization percentage from reset events when no SubscriptionValue is available.
    /// Falls back to aggregateBreakdown's usedPercent when SubscriptionValueCalculator
    /// can't compute (e.g., no monthlyPrice).
    private static func computeUtilization(
        resetEvents: [ResetEvent],
        creditLimits: CreditLimits?,
        timeRange: TimeRange,
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol
    ) -> Double? {
        if let limits = creditLimits {
            if let value = SubscriptionValueCalculator.calculate(
                resetEvents: resetEvents,
                creditLimits: limits,
                timeRange: timeRange,
                headroomAnalysisService: headroomAnalysisService
            ) {
                return value.utilizationPercent
            }
        }
        // Fall back to aggregate breakdown's usedPercent (relative to total 5h capacity,
        // not 7d-prorated — different denominator than SubscriptionValueCalculator)
        guard !resetEvents.isEmpty else { return nil }
        let summary = headroomAnalysisService.aggregateBreakdown(events: resetEvents)
        return summary.usedPercent
    }

    /// Whether the utilization is in the "quiet" range (20-80%).
    private static func isQuietUtilization(_ percent: Double) -> Bool {
        percent >= 20.0 && percent <= 80.0
    }

    /// Formats a percentage for display (e.g., "52%").
    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}
