import Foundation

/// Priority level for insight display ordering.
/// Higher-priority insights are shown first in the InsightStack.
enum InsightPriority: Int, Sendable, Comparable {
    /// Active pattern findings (forgotten subscription, chronic mismatch) — highest priority.
    case patternFinding = 3
    /// Tier recommendation (actionable downgrade/upgrade) — high priority.
    case tierRecommendation = 2
    /// Notable usage deviation from personal baseline — medium priority.
    case usageDeviation = 1
    /// Default subscription value summary — fallback.
    case summary = 0

    static func < (lhs: InsightPriority, rhs: InsightPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Result of computing a context-aware insight for the analytics summary.
struct ValueInsight: Sendable, Equatable {
    /// Display text for the insight
    let text: String
    /// true = muted styling, single quiet line (nothing notable)
    let isQuiet: Bool
    /// Priority for ordering in InsightStack. Defaults to `.summary`.
    let priority: InsightPriority
    /// Precise detail for hover tooltip and VoiceOver (e.g., "76.2% of $200 monthly limit").
    let preciseDetail: String?

    init(text: String, isQuiet: Bool, priority: InsightPriority = .summary, preciseDetail: String? = nil) {
        self.text = text
        self.isQuiet = isQuiet
        self.priority = priority
        self.preciseDetail = preciseDetail
    }
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
            let util = value.utilizationPercent
            let precise = "\(used) of \(total) (\(formatPercent(util)) utilization)"

            if util > 80 {
                return ValueInsight(text: "Close to today's limit — \(used) of \(total) used", isQuiet: false, preciseDetail: precise)
            } else if util < 20 {
                return ValueInsight(text: "Plenty of room — \(used) of \(total) used today", isQuiet: false, preciseDetail: precise)
            }
            return ValueInsight(text: "Used \(used) of \(total) today", isQuiet: isQuietUtilization(util), preciseDetail: precise)
        }

        let util = computeUtilization(resetEvents: resetEvents, creditLimits: creditLimits, timeRange: .day, headroomAnalysisService: headroomAnalysisService)
        if let pct = util {
            let precise = "\(formatPercent(pct)) utilization today"
            if pct > 80 {
                return ValueInsight(text: "Running close to today's limit", isQuiet: false, preciseDetail: precise)
            } else if pct < 20 {
                return ValueInsight(text: "Light usage today", isQuiet: false, preciseDetail: precise)
            }
            let nl = NaturalLanguageFormatter.formatPercentNatural(pct)
            return ValueInsight(text: "\(capitalizeFirst(nl)) of today's capacity", isQuiet: isQuietUtilization(pct), preciseDetail: precise)
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
                        let comparison = NaturalLanguageFormatter.formatComparisonNatural(current: currentUtil, baseline: allTimeUtil)
                        let direction = diff > 0 ? "above" : "below"
                        let precise = "\(formatPercent(abs(diff))) \(direction) average weekly utilization"
                        return ValueInsight(text: "This week: \(comparison)", isQuiet: false, priority: .usageDeviation, preciseDetail: precise)
                    }
                    return ValueInsight(text: "Normal usage", isQuiet: true, preciseDetail: "\(formatPercent(currentUtil)) utilization this week")
                }
            }
        }

        // Insufficient history — fall back to dollar/percentage summary
        if let value = subscriptionValue {
            let used = SubscriptionValueCalculator.formatDollars(value.usedDollars)
            let total = SubscriptionValueCalculator.formatDollars(value.periodPrice)
            let util = value.utilizationPercent
            let precise = "\(used) of \(total) (\(formatPercent(util)) utilization)"

            if util > 80 {
                return ValueInsight(text: "Close to this week's limit — \(used) of \(total) used", isQuiet: false, preciseDetail: precise)
            } else if util < 20 {
                return ValueInsight(text: "Plenty of room — \(used) of \(total) used this week", isQuiet: false, preciseDetail: precise)
            }
            return ValueInsight(text: "Used \(used) of \(total) this week", isQuiet: isQuietUtilization(util), preciseDetail: precise)
        }

        let util = computeUtilization(resetEvents: resetEvents, creditLimits: creditLimits, timeRange: .week, headroomAnalysisService: headroomAnalysisService)
        if let pct = util {
            let precise = "\(formatPercent(pct)) utilization this week"
            if pct > 80 {
                return ValueInsight(text: "Running close to this week's limit", isQuiet: false, preciseDetail: precise)
            } else if pct < 20 {
                return ValueInsight(text: "Light usage this week", isQuiet: false, preciseDetail: precise)
            }
            let nl = NaturalLanguageFormatter.formatPercentNatural(pct)
            return ValueInsight(text: "\(capitalizeFirst(nl)) of this week's capacity", isQuiet: isQuietUtilization(pct), preciseDetail: precise)
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
            let util = value.utilizationPercent
            let precise = "Used \(used) of \(total) this month (\(formatPercent(util)))"

            if util > 80 {
                return ValueInsight(text: "Close to this month's limit — \(used) of \(total) used", isQuiet: false, preciseDetail: precise)
            } else if util < 20 {
                return ValueInsight(text: "Plenty of room — \(used) of \(total) used this month", isQuiet: false, preciseDetail: precise)
            }
            let nl = NaturalLanguageFormatter.formatPercentNatural(util)
            let text = "Used \(used) of \(total) this month (\(nl))"
            return ValueInsight(text: text, isQuiet: isQuietUtilization(util), preciseDetail: precise)
        }

        let util = computeUtilization(resetEvents: resetEvents, creditLimits: creditLimits, timeRange: .month, headroomAnalysisService: headroomAnalysisService)
        if let pct = util {
            let precise = "\(formatPercent(pct)) utilization this month"
            if pct > 80 {
                return ValueInsight(text: "Running close to this month's limit", isQuiet: false, preciseDetail: precise)
            } else if pct < 20 {
                return ValueInsight(text: "Light usage this month", isQuiet: false, preciseDetail: precise)
            }
            let nl = NaturalLanguageFormatter.formatPercentNatural(pct)
            return ValueInsight(text: "\(capitalizeFirst(nl)) of this month's capacity", isQuiet: isQuietUtilization(pct), preciseDetail: precise)
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
            let precise = "Avg utilization: \(formatPercent(pct))"
            if pct > 80 {
                return ValueInsight(text: "High average utilization", isQuiet: false, preciseDetail: precise)
            } else if pct < 20 {
                return ValueInsight(text: "Light overall usage", isQuiet: false, preciseDetail: precise)
            }
            let nl = NaturalLanguageFormatter.formatPercentNatural(pct)
            return ValueInsight(text: "Avg utilization: \(nl)", isQuiet: isQuietUtilization(pct), preciseDetail: precise)
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
        let nl = NaturalLanguageFormatter.formatPercentNatural(avgUtil)
        var text: String
        if avgUtil > 80 {
            text = "High average monthly utilization"
        } else if avgUtil < 20 {
            text = "Light average monthly usage"
        } else {
            text = "Avg monthly utilization: \(nl)"
        }
        var isQuiet = isQuietUtilization(avgUtil)
        var preciseText = "Avg monthly utilization: \(formatPercent(avgUtil))"

        // Trend detection: compare last 3 completed months.
        // Exclude the current (potentially partial) month to avoid spurious trends.
        let completedMonthUtils: [Double]
        if let lastEvent = resetEvents.last {
            let lastDate = Date(timeIntervalSince1970: Double(lastEvent.timestamp) / 1000.0)
            let calendar = Calendar.current
            if calendar.dateComponents([.year, .month], from: lastDate)
                == calendar.dateComponents([.year, .month], from: Date()),
               monthlyUtilizations.count > 1 {
                completedMonthUtils = Array(monthlyUtilizations.dropLast())
            } else {
                completedMonthUtils = monthlyUtilizations
            }
        } else {
            completedMonthUtils = monthlyUtilizations
        }

        if completedMonthUtils.count >= 3 {
            let lastThree = Array(completedMonthUtils.suffix(3))
            let allRising = lastThree[1] - lastThree[0] > 5.0 && lastThree[2] - lastThree[1] > 5.0
            let allFalling = lastThree[0] - lastThree[1] > 5.0 && lastThree[1] - lastThree[2] > 5.0

            if allRising {
                text += ", trending up"
                preciseText += ", trending up"
                isQuiet = false
            } else if allFalling {
                text += ", trending down"
                preciseText += ", trending down"
                isQuiet = false
            }
        }

        return ValueInsight(text: text, isQuiet: isQuiet, preciseDetail: preciseText)
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

    /// Capitalizes the first character of a string.
    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    // MARK: - Multi-Insight API (Story 16.5)

    /// Computes all available insights for the current context, sorted by priority (highest first).
    /// Pattern findings and tier recommendations are converted to ValueInsight entries
    /// alongside the time-range-specific usage insight.
    static func computeInsights(
        timeRange: TimeRange,
        subscriptionValue: SubscriptionValue?,
        resetEvents: [ResetEvent],
        allTimeResetEvents: [ResetEvent],
        creditLimits: CreditLimits?,
        headroomAnalysisService: any HeadroomAnalysisServiceProtocol,
        patternFindings: [PatternFinding] = [],
        tierRecommendation: TierRecommendation? = nil
    ) -> [ValueInsight] {
        var insights: [ValueInsight] = []

        // Pattern findings → highest priority
        for finding in patternFindings {
            insights.append(insightFromPatternFinding(finding))
        }

        // Tier recommendation → high priority (only actionable ones)
        if let recommendation = tierRecommendation {
            if let insight = insightFromTierRecommendation(recommendation) {
                insights.append(insight)
            }
        }

        // Usage insight → summary priority
        let usageInsight = computeInsight(
            timeRange: timeRange,
            subscriptionValue: subscriptionValue,
            resetEvents: resetEvents,
            allTimeResetEvents: allTimeResetEvents,
            creditLimits: creditLimits,
            headroomAnalysisService: headroomAnalysisService
        )
        insights.append(usageInsight)

        // Sort by priority descending (highest first), stable order within same priority
        insights.sort { $0.priority > $1.priority }

        return insights
    }

    /// Converts a PatternFinding into a ValueInsight with `.patternFinding` priority.
    static func insightFromPatternFinding(_ finding: PatternFinding) -> ValueInsight {
        ValueInsight(
            text: finding.summary,
            isQuiet: false,
            priority: .patternFinding,
            preciseDetail: finding.title
        )
    }

    /// Converts a TierRecommendation into a ValueInsight with `.tierRecommendation` priority.
    /// Returns nil for `.goodFit` (not actionable, no insight needed).
    static func insightFromTierRecommendation(_ recommendation: TierRecommendation) -> ValueInsight? {
        guard recommendation.isActionable else { return nil }

        let text = TierRecommendationCard.buildSummary(for: recommendation)
        let context = TierRecommendationCard.buildContext(for: recommendation)
        let detail = context.map { "\(text). \($0)" } ?? text

        return ValueInsight(
            text: text,
            isQuiet: false,
            priority: .tierRecommendation,
            preciseDetail: detail
        )
    }
}
