import Foundation
import Testing
@testable import cc_hdrm

@Suite("ValueInsightEngine Tests")
struct ValueInsightEngineTests {

    // MARK: - Helpers

    private let proLimits = RateLimitTier.pro.creditLimits

    private func makeMockService(
        usedCredits: Double = 2_860_000,
        utilizationUsedPercent: Double = 52
    ) -> MockHeadroomAnalysisService {
        let mock = MockHeadroomAnalysisService()
        mock.mockPeriodSummary = PeriodSummary(
            usedCredits: usedCredits,
            constrainedCredits: 660_000,
            unusedCredits: 1_980_000,
            resetCount: 3,
            avgPeakUtilization: utilizationUsedPercent,
            usedPercent: utilizationUsedPercent,
            constrainedPercent: 12,
            unusedPercent: 36
        )
        return mock
    }

    private func makeEvents(count: Int = 3, spanDays: Int = 30) -> [ResetEvent] {
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        let totalSpanMs: Int64 = Int64(spanDays) * 24 * 3_600_000
        let stepMs: Int64 = count > 1 ? totalSpanMs / Int64(count - 1) : 0
        var events: [ResetEvent] = []
        for i in 0..<count {
            let ts: Int64 = nowMs - totalSpanMs + Int64(i) * stepMs
            events.append(ResetEvent(
                id: Int64(i + 1),
                timestamp: ts,
                fiveHourPeak: 50.0 + Double(i),
                sevenDayUtil: 40.0 + Double(i),
                tier: "default_claude_pro",
                usedCredits: nil,
                constrainedCredits: nil,
                unusedCredits: nil
            ))
        }
        return events
    }

    // MARK: - 9.2: 24h insight with dollar value

    @Test("24h insight with dollar value and high utilization: cautious tone")
    func dayInsightWithDollars() {
        let mock = makeMockService()
        let events = makeEvents(count: 2, spanDays: 1)

        let value = SubscriptionValueCalculator.calculate(
            resetEvents: events,
            creditLimits: proLimits,
            timeRange: .day,
            headroomAnalysisService: mock
        )
        #expect(value != nil)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .day,
            subscriptionValue: value,
            resetEvents: events,
            allTimeResetEvents: makeEvents(count: 30, spanDays: 90),
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        // High utilization (100% — usedCredits exceed daily prorated limit) → cautious tone
        #expect(insight.text.contains("Close to today's limit"))
        #expect(insight.text.contains("$"))
        #expect(insight.isQuiet == false)
        #expect(insight.preciseDetail != nil)
        #expect(insight.preciseDetail?.contains("utilization") == true)
    }

    // MARK: - 9.3: 24h insight percentage-only

    @Test("24h insight percentage-only: natural language description")
    func dayInsightPercentageOnly() {
        let mock = makeMockService()
        let events = makeEvents(count: 2, spanDays: 1)
        let customLimits = CreditLimits(fiveHourCredits: 550_000, sevenDayCredits: 5_000_000)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .day,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: makeEvents(count: 30, spanDays: 90),
            creditLimits: customLimits,
            headroomAnalysisService: mock
        )

        // Falls back to aggregateBreakdown (52% usedPercent) → neutral NL text
        #expect(insight.text.contains("of today's capacity"))
        #expect(insight.preciseDetail?.contains("utilization today") == true)
    }

    // MARK: - 9.4: 7d insight above average

    @Test("7d insight above average: natural language comparison")
    func weekInsightAboveAverage() {
        // Mock returns high usedCredits for small batches (week) and low for large batches (all-time)
        let mock = MockHeadroomAnalysisService()
        mock.aggregateBreakdownHandler = { events in
            let usedCredits: Double = events.count <= 10 ? 4_500_000 : 500_000
            return PeriodSummary(
                usedCredits: usedCredits, constrainedCredits: 0,
                unusedCredits: max(0, 5_000_000 - usedCredits),
                resetCount: events.count, avgPeakUtilization: 90.0,
                usedPercent: 90, constrainedPercent: 0, unusedPercent: 10
            )
        }

        let weekEvents = makeEvents(count: 5, spanDays: 7)
        let allTimeEvents = makeEvents(count: 30, spanDays: 90)

        let weekValue = SubscriptionValueCalculator.calculate(
            resetEvents: weekEvents,
            creditLimits: proLimits,
            timeRange: .week,
            headroomAnalysisService: mock
        )

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .week,
            subscriptionValue: weekValue,
            resetEvents: weekEvents,
            allTimeResetEvents: allTimeEvents,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        // Week util (~90%) >> all-time util (~0.8%) → NL comparison
        #expect(insight.text.hasPrefix("This week:"))
        #expect(insight.isQuiet == false)
        #expect(insight.preciseDetail?.contains("above") == true)
    }

    // MARK: - 9.5: 7d insight below average

    @Test("7d insight below average: natural language comparison")
    func weekInsightBelowAverage() {
        // Mock returns low usedCredits for small batches (week) and high for large batches (all-time)
        let mock = MockHeadroomAnalysisService()
        mock.aggregateBreakdownHandler = { events in
            let usedCredits: Double = events.count <= 10 ? 1_000_000 : 50_000_000
            return PeriodSummary(
                usedCredits: usedCredits, constrainedCredits: 0,
                unusedCredits: max(0, 55_000_000 - usedCredits),
                resetCount: events.count, avgPeakUtilization: 20.0,
                usedPercent: 20, constrainedPercent: 0, unusedPercent: 80
            )
        }

        let weekEvents = makeEvents(count: 5, spanDays: 7)
        let allTimeEvents = makeEvents(count: 30, spanDays: 90)

        let weekValue = SubscriptionValueCalculator.calculate(
            resetEvents: weekEvents,
            creditLimits: proLimits,
            timeRange: .week,
            headroomAnalysisService: mock
        )

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .week,
            subscriptionValue: weekValue,
            resetEvents: weekEvents,
            allTimeResetEvents: allTimeEvents,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        // Week util (~20%) << all-time util (~77.8%) → NL comparison
        #expect(insight.text.hasPrefix("This week:"))
        #expect(insight.isQuiet == false)
        #expect(insight.preciseDetail?.contains("below") == true)
    }

    // MARK: - 9.6: 7d insight near average

    @Test("7d insight near average (< 5% diff): quiet 'Normal usage'")
    func weekInsightNearAverage() {
        // Use very high usedCredits so utilization caps at 100% for both week and all-time,
        // ensuring diff = 0 → "Normal usage"
        let mock = makeMockService(usedCredits: 100_000_000)
        let weekEvents = makeEvents(count: 5, spanDays: 7)
        let allTimeEvents = makeEvents(count: 30, spanDays: 90)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .week,
            subscriptionValue: SubscriptionValueCalculator.calculate(
                resetEvents: weekEvents,
                creditLimits: proLimits,
                timeRange: .week,
                headroomAnalysisService: mock
            ),
            resetEvents: weekEvents,
            allTimeResetEvents: allTimeEvents,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        // Both cap at 100% → diff = 0 → quiet "Normal usage"
        #expect(insight.text == "Normal usage")
        #expect(insight.isQuiet == true)
    }

    // MARK: - 9.7: 7d insight insufficient history

    @Test("7d insight insufficient history (< 14 days): falls back to dollar/percentage summary")
    func weekInsightInsufficientHistory() {
        let mock = makeMockService()
        let weekEvents = makeEvents(count: 3, spanDays: 7)
        // All-time events only span 10 days (< 14 day threshold)
        let allTimeEvents = makeEvents(count: 5, spanDays: 10)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .week,
            subscriptionValue: SubscriptionValueCalculator.calculate(
                resetEvents: weekEvents,
                creditLimits: proLimits,
                timeRange: .week,
                headroomAnalysisService: mock
            ),
            resetEvents: weekEvents,
            allTimeResetEvents: allTimeEvents,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        // Should fall back to dollar summary since < 14 days of history
        #expect(insight.text.contains("this week"))
    }

    // MARK: - 9.8: 30d insight with dollar value

    @Test("30d insight with dollar value: tone-appropriate display")
    func monthInsightWithDollars() {
        let mock = makeMockService()
        let events = makeEvents(count: 10, spanDays: 30)

        let value = SubscriptionValueCalculator.calculate(
            resetEvents: events,
            creditLimits: proLimits,
            timeRange: .month,
            headroomAnalysisService: mock
        )

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .month,
            subscriptionValue: value,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        // Dollar values present in text, tone depends on utilization
        #expect(insight.text.contains("$"))
        #expect(insight.preciseDetail != nil)
        #expect(insight.preciseDetail?.contains("this month") == true)
    }

    // MARK: - 9.9: 30d insight percentage-only

    @Test("30d insight percentage-only (nil monthlyPrice): natural language")
    func monthInsightPercentageOnly() {
        let mock = makeMockService(utilizationUsedPercent: 45)
        let events = makeEvents(count: 10, spanDays: 30)
        // Custom limits with no monthlyPrice → percentage-only mode
        let customLimits = CreditLimits(fiveHourCredits: 550_000, sevenDayCredits: 5_000_000)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .month,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: customLimits,
            headroomAnalysisService: mock
        )

        // Falls back to aggregateBreakdown's usedPercent (45%) → "roughly half" NL
        #expect(insight.text.contains("of this month's capacity"))
        #expect(insight.preciseDetail?.contains("utilization this month") == true)
    }

    // MARK: - 9.10: All insight with trending up

    @Test("All insight with trending up")
    func allInsightTrendingUp() {
        // Create events spanning 4 months with increasing peaks
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        let monthMs: Int64 = 30 * 24 * 3_600_000

        var events: [ResetEvent] = []
        let peaks: [Double] = [30, 45, 65, 85]
        for (monthIdx, peak) in peaks.enumerated() {
            for j in 0..<3 {
                let ts: Int64 = nowMs - Int64(4 - monthIdx) * monthMs + Int64(j) * 86_400_000
                events.append(ResetEvent(
                    id: Int64(monthIdx * 3 + j + 1),
                    timestamp: ts,
                    fiveHourPeak: peak,
                    sevenDayUtil: peak * 0.6,
                    tier: "default_claude_pro",
                    usedCredits: nil,
                    constrainedCredits: nil,
                    unusedCredits: nil
                ))
            }
        }

        // Handler maps event peaks to proportional usedCredits so each month gets distinct utilization
        let mock = MockHeadroomAnalysisService()
        mock.aggregateBreakdownHandler = { events in
            let avgPeak = events.compactMap(\.fiveHourPeak).reduce(0, +)
                / max(1.0, Double(events.compactMap(\.fiveHourPeak).count))
            let usedCredits = (avgPeak / 100.0) * 1_500_000
            return PeriodSummary(
                usedCredits: usedCredits, constrainedCredits: 0,
                unusedCredits: max(0, 1_500_000 - usedCredits),
                resetCount: events.count, avgPeakUtilization: avgPeak,
                usedPercent: avgPeak, constrainedPercent: 0, unusedPercent: max(0, 100 - avgPeak)
            )
        }

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .all,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        #expect(insight.text.contains("Avg monthly utilization:"))
        #expect(insight.text.contains("trending up"))
        #expect(insight.isQuiet == false)
    }

    // MARK: - 9.11: All insight with trending down

    @Test("All insight with trending down")
    func allInsightTrendingDown() {
        // Create events spanning 4 months with decreasing peaks
        let nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        let monthMs: Int64 = 30 * 24 * 3_600_000

        var events: [ResetEvent] = []
        let peaks: [Double] = [85, 65, 45, 30]
        for (monthIdx, peak) in peaks.enumerated() {
            for j in 0..<3 {
                let ts: Int64 = nowMs - Int64(4 - monthIdx) * monthMs + Int64(j) * 86_400_000
                events.append(ResetEvent(
                    id: Int64(monthIdx * 3 + j + 1),
                    timestamp: ts,
                    fiveHourPeak: peak,
                    sevenDayUtil: peak * 0.6,
                    tier: "default_claude_pro",
                    usedCredits: nil,
                    constrainedCredits: nil,
                    unusedCredits: nil
                ))
            }
        }

        let mock = MockHeadroomAnalysisService()
        mock.aggregateBreakdownHandler = { events in
            let avgPeak = events.compactMap(\.fiveHourPeak).reduce(0, +)
                / max(1.0, Double(events.compactMap(\.fiveHourPeak).count))
            let usedCredits = (avgPeak / 100.0) * 1_500_000
            return PeriodSummary(
                usedCredits: usedCredits, constrainedCredits: 0,
                unusedCredits: max(0, 1_500_000 - usedCredits),
                resetCount: events.count, avgPeakUtilization: avgPeak,
                usedPercent: avgPeak, constrainedPercent: 0, unusedPercent: max(0, 100 - avgPeak)
            )
        }

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .all,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        #expect(insight.text.contains("Avg monthly utilization:"))
        #expect(insight.text.contains("trending down"))
        #expect(insight.isQuiet == false)
    }

    // MARK: - 9.12: All insight stable

    @Test("All insight stable (no significant trend): quiet mode when 20-80%")
    func allInsightStable() {
        let mock = makeMockService()
        let events = makeEvents(count: 30, spanDays: 120)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .all,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        // Mock returns 52% utilization → within 20-80% → quiet
        #expect(insight.text.contains("Avg monthly utilization:"))
        #expect(insight.isQuiet == true)
    }

    // MARK: - 9.13: All insight insufficient history

    @Test("All insight insufficient history (< 2 months): average only, no trend")
    func allInsightInsufficientHistory() {
        let mock = makeMockService()
        let events = makeEvents(count: 5, spanDays: 20)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .all,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        #expect(insight.text.contains("Avg monthly utilization:"))
        // With < 2 months, no trend should be appended
        #expect(!insight.text.contains("trending"))
    }

    // MARK: - 9.14: Zero events

    @Test("Zero events: 'No reset events in this period'")
    func zeroEvents() {
        let mock = makeMockService()

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .week,
            subscriptionValue: nil,
            resetEvents: [],
            allTimeResetEvents: [],
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        #expect(insight.text == "No reset events in this period")
        #expect(insight.isQuiet == true)
    }

    // MARK: - 9.15: Nil creditLimits

    @Test("Nil creditLimits: percentages only, no dollar values")
    func nilCreditLimitsPercentagesOnly() {
        let mock = makeMockService()
        let events = makeEvents(count: 5, spanDays: 30)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .month,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: nil,
            headroomAnalysisService: mock
        )

        // Should not contain dollar values
        #expect(!insight.text.contains("$"))
    }

    // MARK: - 9.16: "Nothing notable" quiet mode

    @Test("Nothing notable quiet mode (20-80% utilization)")
    func nothingNotableQuietMode() {
        let mock = makeMockService() // 52% utilization - within 20-80%
        let events = makeEvents(count: 5, spanDays: 30)

        let value = SubscriptionValueCalculator.calculate(
            resetEvents: events,
            creditLimits: proLimits,
            timeRange: .month,
            headroomAnalysisService: mock
        )

        // Pro tier month: usedCredits=2,860,000, totalAvailable=5,000,000*(30/7)≈21,428,571
        // utilization ≈ 13.3% — outside 20-80% range. Use aggregateBreakdown path instead.
        // Pass nil subscriptionValue to trigger percentage fallback from aggregateBreakdown (52%)
        let insight = ValueInsightEngine.computeInsight(
            timeRange: .month,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: CreditLimits(fiveHourCredits: 550_000, sevenDayCredits: 5_000_000),
            headroomAnalysisService: mock
        )

        // aggregateBreakdown returns 52% → within 20-80% → quiet
        #expect(insight.isQuiet == true)
    }

    // MARK: - ValueInsight struct

    @Test("ValueInsight is Equatable")
    func valueInsightEquatable() {
        let a = ValueInsight(text: "hello", isQuiet: true)
        let b = ValueInsight(text: "hello", isQuiet: true)
        let c = ValueInsight(text: "world", isQuiet: false)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("ValueInsight is Sendable")
    func valueInsightSendable() {
        let insight = ValueInsight(text: "test", isQuiet: false)
        let _: any Sendable = insight
    }

    @Test("ValueInsight default priority is .summary")
    func valueInsightDefaultPriority() {
        let insight = ValueInsight(text: "test", isQuiet: true)
        #expect(insight.priority == .summary)
        #expect(insight.preciseDetail == nil)
    }

    // MARK: - computeInsights (Story 16.5)

    @Test("computeInsights returns usage insight when no findings or recommendation")
    func computeInsightsUsageOnly() {
        let mock = makeMockService()
        let events = makeEvents(count: 5, spanDays: 30)

        let insights = ValueInsightEngine.computeInsights(
            timeRange: .month,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        #expect(insights.count == 1)
        #expect(insights.first?.priority == .summary)
    }

    @Test("computeInsights includes pattern findings at highest priority")
    func computeInsightsWithPatternFindings() {
        let mock = makeMockService()
        let events = makeEvents(count: 5, spanDays: 30)
        let findings: [PatternFinding] = [
            .forgottenSubscription(weeks: 3, avgUtilization: 2.5, monthlyCost: 200)
        ]

        let insights = ValueInsightEngine.computeInsights(
            timeRange: .month,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock,
            patternFindings: findings
        )

        #expect(insights.count == 2)
        #expect(insights.first?.priority == .patternFinding)
        #expect(insights.first?.text.contains("5%") == true)
    }

    @Test("computeInsights includes tier recommendation between findings and summary")
    func computeInsightsWithTierRecommendation() {
        let mock = makeMockService()
        let events = makeEvents(count: 5, spanDays: 30)
        let recommendation = TierRecommendation.downgrade(
            currentTier: .max5x,
            currentMonthlyCost: 200,
            recommendedTier: .pro,
            recommendedMonthlyCost: 20,
            monthlySavings: 180,
            weeksOfData: 8
        )

        let insights = ValueInsightEngine.computeInsights(
            timeRange: .month,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock,
            tierRecommendation: recommendation
        )

        #expect(insights.count == 2)
        #expect(insights.first?.priority == .tierRecommendation)
    }

    @Test("computeInsights sorts by priority descending")
    func computeInsightsSortOrder() {
        let mock = makeMockService()
        let events = makeEvents(count: 5, spanDays: 30)
        let findings: [PatternFinding] = [
            .usageDecay(currentUtil: 30, threeMonthAgoUtil: 70)
        ]
        let recommendation = TierRecommendation.downgrade(
            currentTier: .max5x,
            currentMonthlyCost: 200,
            recommendedTier: .pro,
            recommendedMonthlyCost: 20,
            monthlySavings: 180,
            weeksOfData: 8
        )

        let insights = ValueInsightEngine.computeInsights(
            timeRange: .month,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock,
            patternFindings: findings,
            tierRecommendation: recommendation
        )

        #expect(insights.count == 3)
        #expect(insights[0].priority == .patternFinding)
        #expect(insights[1].priority == .tierRecommendation)
        #expect(insights[2].priority == .summary)
    }

    @Test("computeInsights skips .goodFit recommendation")
    func computeInsightsSkipsGoodFit() {
        let mock = makeMockService()
        let events = makeEvents(count: 5, spanDays: 30)
        let recommendation = TierRecommendation.goodFit(tier: .pro, headroomPercent: 45)

        let insights = ValueInsightEngine.computeInsights(
            timeRange: .month,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock,
            tierRecommendation: recommendation
        )

        // Should only have the summary, not the goodFit
        #expect(insights.count == 1)
        #expect(insights.first?.priority == .summary)
    }

    // MARK: - insightFromPatternFinding

    @Test("insightFromPatternFinding produces .patternFinding priority")
    func patternFindingConversion() {
        let finding = PatternFinding.chronicOverpaying(
            currentTier: "Max 5x", recommendedTier: "Pro", monthlySavings: 180
        )
        let insight = ValueInsightEngine.insightFromPatternFinding(finding)

        #expect(insight.priority == .patternFinding)
        #expect(insight.isQuiet == false)
        #expect(insight.text == finding.summary)
        #expect(insight.preciseDetail == finding.title)
    }

    // MARK: - insightFromTierRecommendation

    @Test("insightFromTierRecommendation produces .tierRecommendation priority for downgrade")
    func tierRecommendationDowngradeConversion() {
        let recommendation = TierRecommendation.downgrade(
            currentTier: .max5x,
            currentMonthlyCost: 200,
            recommendedTier: .pro,
            recommendedMonthlyCost: 20,
            monthlySavings: 180,
            weeksOfData: 8
        )
        let insight = ValueInsightEngine.insightFromTierRecommendation(recommendation)

        #expect(insight != nil)
        #expect(insight?.priority == .tierRecommendation)
        #expect(insight?.isQuiet == false)
    }

    @Test("insightFromTierRecommendation returns nil for .goodFit")
    func tierRecommendationGoodFitReturnsNil() {
        let recommendation = TierRecommendation.goodFit(tier: .pro, headroomPercent: 45)
        let insight = ValueInsightEngine.insightFromTierRecommendation(recommendation)

        #expect(insight == nil)
    }

    // MARK: - preciseDetail population (Story 16.5)

    @Test("preciseDetail is populated for day dollar insight")
    func preciseDetailDayDollar() {
        let mock = makeMockService()
        let events = makeEvents(count: 2, spanDays: 1)

        let value = SubscriptionValueCalculator.calculate(
            resetEvents: events,
            creditLimits: proLimits,
            timeRange: .day,
            headroomAnalysisService: mock
        )

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .day,
            subscriptionValue: value,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        #expect(insight.preciseDetail != nil)
        #expect(insight.preciseDetail?.contains("$") == true)
        #expect(insight.preciseDetail?.contains("utilization") == true)
    }

    @Test("preciseDetail is populated for week comparison insight")
    func preciseDetailWeekComparison() {
        let mock = MockHeadroomAnalysisService()
        mock.aggregateBreakdownHandler = { events in
            let usedCredits: Double = events.count <= 10 ? 4_500_000 : 500_000
            return PeriodSummary(
                usedCredits: usedCredits, constrainedCredits: 0,
                unusedCredits: max(0, 5_000_000 - usedCredits),
                resetCount: events.count, avgPeakUtilization: 90.0,
                usedPercent: 90, constrainedPercent: 0, unusedPercent: 10
            )
        }

        let weekEvents = makeEvents(count: 5, spanDays: 7)
        let allTimeEvents = makeEvents(count: 30, spanDays: 90)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .week,
            subscriptionValue: SubscriptionValueCalculator.calculate(
                resetEvents: weekEvents,
                creditLimits: proLimits,
                timeRange: .week,
                headroomAnalysisService: mock
            ),
            resetEvents: weekEvents,
            allTimeResetEvents: allTimeEvents,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        #expect(insight.preciseDetail != nil)
        #expect(insight.preciseDetail?.contains("average weekly utilization") == true)
    }

    @Test("preciseDetail is populated for all-time insight")
    func preciseDetailAllTime() {
        let mock = makeMockService()
        let events = makeEvents(count: 30, spanDays: 120)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .all,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        #expect(insight.preciseDetail != nil)
        #expect(insight.preciseDetail?.contains("Avg monthly utilization:") == true)
        #expect(insight.preciseDetail?.contains("%") == true)
    }

    @Test("preciseDetail for pattern finding is the finding title")
    func preciseDetailPatternFinding() {
        let finding = PatternFinding.forgottenSubscription(weeks: 3, avgUtilization: 2.5, monthlyCost: 200)
        let insight = ValueInsightEngine.insightFromPatternFinding(finding)

        #expect(insight.preciseDetail == finding.title)
    }

    @Test("preciseDetail for tier recommendation includes summary and context")
    func preciseDetailTierRecommendation() {
        let recommendation = TierRecommendation.downgrade(
            currentTier: .max5x,
            currentMonthlyCost: 200,
            recommendedTier: .pro,
            recommendedMonthlyCost: 20,
            monthlySavings: 180,
            weeksOfData: 8
        )
        let insight = ValueInsightEngine.insightFromTierRecommendation(recommendation)

        #expect(insight?.preciseDetail != nil)
        #expect(insight?.preciseDetail?.contains("Based on") == true)
    }

    // MARK: - Tone matching (Story 16.5)

    @Test("High utilization (>80%) produces cautious tone text")
    func toneMatchingHighUtilization() {
        // Mock with very high usage → >80% utilization for day range
        let mock = makeMockService(usedCredits: 4_000_000)
        let events = makeEvents(count: 2, spanDays: 1)

        let value = SubscriptionValueCalculator.calculate(
            resetEvents: events,
            creditLimits: proLimits,
            timeRange: .day,
            headroomAnalysisService: mock
        )

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .day,
            subscriptionValue: value,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        // Cautious tone: "Close to..." or "Running close to..."
        #expect(insight.text.contains("Close to") || insight.text.contains("Running close to"))
        #expect(insight.isQuiet == false)
    }

    @Test("Low utilization (<20%) with dollars produces reassuring tone text")
    func toneMatchingLowUtilizationDollar() {
        // Mock with very low usage → <20% utilization
        let mock = makeMockService(usedCredits: 50_000)
        let events = makeEvents(count: 2, spanDays: 30)

        let value = SubscriptionValueCalculator.calculate(
            resetEvents: events,
            creditLimits: proLimits,
            timeRange: .month,
            headroomAnalysisService: mock
        )

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .month,
            subscriptionValue: value,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        // Reassuring tone: "Plenty of room"
        #expect(insight.text.contains("Plenty of room") || insight.text.contains("Light usage"))
        #expect(insight.isQuiet == false)
    }

    @Test("Low utilization (<20%) percentage-only produces reassuring tone text")
    func toneMatchingLowUtilizationPercentage() {
        let mock = makeMockService(utilizationUsedPercent: 10)
        let events = makeEvents(count: 2, spanDays: 1)
        let customLimits = CreditLimits(fiveHourCredits: 550_000, sevenDayCredits: 5_000_000)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .day,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: customLimits,
            headroomAnalysisService: mock
        )

        // Reassuring tone for percentage path
        #expect(insight.text.contains("Light usage"))
        #expect(insight.isQuiet == false)
        #expect(insight.preciseDetail?.contains("10%") == true)
    }

    @Test("Neutral utilization (20-80%) produces natural language text, not raw percentage")
    func toneMatchingNeutralUtilization() {
        let mock = makeMockService(utilizationUsedPercent: 52)
        let events = makeEvents(count: 2, spanDays: 1)
        let customLimits = CreditLimits(fiveHourCredits: 550_000, sevenDayCredits: 5_000_000)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .day,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: customLimits,
            headroomAnalysisService: mock
        )

        // Neutral tone: NL text, no raw percentage in main text
        #expect(insight.text.contains("of today's capacity"))
        #expect(!insight.text.contains("52%"))
        #expect(insight.isQuiet == true)
        #expect(insight.preciseDetail?.contains("52%") == true)
    }

    @Test("Pattern findings use matter-of-fact tone (existing summary text)")
    func toneMatchingPatternFinding() {
        let finding = PatternFinding.usageDecay(currentUtil: 30, threeMonthAgoUtil: 70)
        let insight = ValueInsightEngine.insightFromPatternFinding(finding)

        // Pattern findings use direct, factual summary text
        #expect(insight.text.contains("declined"))
        #expect(insight.isQuiet == false)
    }

    @Test("Week deviation insight gets .usageDeviation priority")
    func weekDeviationPriority() {
        let mock = MockHeadroomAnalysisService()
        mock.aggregateBreakdownHandler = { events in
            let usedCredits: Double = events.count <= 10 ? 4_500_000 : 500_000
            return PeriodSummary(
                usedCredits: usedCredits, constrainedCredits: 0,
                unusedCredits: max(0, 5_000_000 - usedCredits),
                resetCount: events.count, avgPeakUtilization: 90.0,
                usedPercent: 90, constrainedPercent: 0, unusedPercent: 10
            )
        }

        let weekEvents = makeEvents(count: 5, spanDays: 7)
        let allTimeEvents = makeEvents(count: 30, spanDays: 90)

        let insight = ValueInsightEngine.computeInsight(
            timeRange: .week,
            subscriptionValue: SubscriptionValueCalculator.calculate(
                resetEvents: weekEvents,
                creditLimits: proLimits,
                timeRange: .week,
                headroomAnalysisService: mock
            ),
            resetEvents: weekEvents,
            allTimeResetEvents: allTimeEvents,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        // Notable deviation from baseline gets .usageDeviation priority
        #expect(insight.priority == .usageDeviation)
        #expect(insight.text.hasPrefix("This week:"))
    }

    @Test("Removing a finding promotes the next insight to primary position")
    func dismissPromotesNextInsight() {
        let mock = makeMockService()
        let events = makeEvents(count: 5, spanDays: 30)
        let findings: [PatternFinding] = [
            .forgottenSubscription(weeks: 3, avgUtilization: 2.5, monthlyCost: 200),
            .usageDecay(currentUtil: 30, threeMonthAgoUtil: 70)
        ]

        // With both findings: first finding is primary
        let insightsBefore = ValueInsightEngine.computeInsights(
            timeRange: .month,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock,
            patternFindings: findings
        )
        let primaryBefore = insightsBefore.first!

        // Dismiss first finding: second finding promotes to primary
        let insightsAfter = ValueInsightEngine.computeInsights(
            timeRange: .month,
            subscriptionValue: nil,
            resetEvents: events,
            allTimeResetEvents: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock,
            patternFindings: [findings[1]]
        )
        let primaryAfter = insightsAfter.first!

        #expect(primaryBefore.text != primaryAfter.text)
        #expect(primaryAfter.text == findings[1].summary)
        #expect(primaryAfter.priority == .patternFinding)
    }

    // MARK: - InsightPriority ordering

    @Test("InsightPriority ordering: patternFinding > tierRecommendation > usageDeviation > summary")
    func priorityOrdering() {
        #expect(InsightPriority.patternFinding > InsightPriority.tierRecommendation)
        #expect(InsightPriority.tierRecommendation > InsightPriority.usageDeviation)
        #expect(InsightPriority.usageDeviation > InsightPriority.summary)
    }

    // MARK: - computeMonthlyUtilizations

    @Test("computeMonthlyUtilizations groups events by calendar month")
    func monthlyUtilizationsGrouping() {
        let mock = makeMockService()
        let events = makeEvents(count: 10, spanDays: 90)

        let utilizations = ValueInsightEngine.computeMonthlyUtilizations(
            events: events,
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        // Should have at least 2 months of data
        #expect(utilizations.count >= 2)
    }

    // MARK: - Extra Usage Insights (Story 17.3)

    @Test("computeExtraUsageInsights returns empty when no cycles have extra usage")
    func extraUsageInsightsEmpty() {
        let cycles = [
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 50, dollarValue: 10, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 60, dollarValue: 12, isPartial: false, resetCount: 4),
            CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 70, dollarValue: 14, isPartial: false, resetCount: 5),
        ]
        let insights = ValueInsightEngine.computeExtraUsageInsights(cycles: cycles)
        #expect(insights.isEmpty)
    }

    @Test("computeExtraUsageInsights returns insight with correct total, count, and average")
    func extraUsageInsightsWithData() {
        let cycles = [
            CycleUtilization(label: "Sep", year: 2025, utilizationPercent: 50, dollarValue: 10, isPartial: false, resetCount: 3),
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 80, dollarValue: 16, isPartial: false, resetCount: 5, extraUsageSpend: 12.50),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 90, dollarValue: 18, isPartial: false, resetCount: 6, extraUsageSpend: 25.00),
            CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 60, dollarValue: 12, isPartial: false, resetCount: 4),
            CycleUtilization(label: "Jan", year: 2026, utilizationPercent: 85, dollarValue: 17, isPartial: true, resetCount: 3, extraUsageSpend: 8.75),
        ]
        let insights = ValueInsightEngine.computeExtraUsageInsights(cycles: cycles)
        #expect(insights.count == 1)

        let insight = insights[0]
        // Total: 12.50 + 25.00 + 8.75 = 46.25
        #expect(insight.text.contains("$46.25"))
        // Count: 3 months
        #expect(insight.text.contains("3 months"))
        // Average: 46.25 / 3 = 15.42
        #expect(insight.text.contains("$15.42"))
    }

    @Test("computeExtraUsageInsights returns insight at .usageDeviation priority")
    func extraUsageInsightPriority() {
        let cycles = [
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 80, dollarValue: 16, isPartial: false, resetCount: 5, extraUsageSpend: 10.0),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 90, dollarValue: 18, isPartial: false, resetCount: 6, extraUsageSpend: 20.0),
            CycleUtilization(label: "Dec", year: 2025, utilizationPercent: 70, dollarValue: 14, isPartial: false, resetCount: 4),
        ]
        let insights = ValueInsightEngine.computeExtraUsageInsights(cycles: cycles)
        #expect(insights.count == 1)
        #expect(insights[0].priority == .usageDeviation)
        #expect(insights[0].isQuiet == false)
    }

    @Test("computeExtraUsageInsights text format includes dollar amounts and cycle count")
    func extraUsageInsightTextFormat() {
        let cycles = [
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 80, dollarValue: 16, isPartial: false, resetCount: 5, extraUsageSpend: 5.0),
        ]
        let insights = ValueInsightEngine.computeExtraUsageInsights(cycles: cycles)
        #expect(insights.count == 1)
        let text = insights[0].text
        #expect(text.hasPrefix("Extra usage:"))
        #expect(text.contains("$5.00"))
        #expect(text.contains("1 month"))
    }

    @Test("computeExtraUsageInsights includes preciseDetail")
    func extraUsageInsightPreciseDetail() {
        let cycles = [
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 80, dollarValue: 16, isPartial: false, resetCount: 5, extraUsageSpend: 15.0),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 90, dollarValue: 18, isPartial: false, resetCount: 6, extraUsageSpend: 25.0),
        ]
        let insights = ValueInsightEngine.computeExtraUsageInsights(cycles: cycles)
        #expect(insights[0].preciseDetail != nil)
        #expect(insights[0].preciseDetail?.contains("Total extra spend") == true)
    }

    @Test("computeExtraUsageInsights ignores cycles with zero extra usage spend")
    func extraUsageInsightsIgnoresZero() {
        let cycles = [
            CycleUtilization(label: "Oct", year: 2025, utilizationPercent: 80, dollarValue: 16, isPartial: false, resetCount: 5, extraUsageSpend: 0.0),
            CycleUtilization(label: "Nov", year: 2025, utilizationPercent: 90, dollarValue: 18, isPartial: false, resetCount: 6, extraUsageSpend: 0.0),
        ]
        let insights = ValueInsightEngine.computeExtraUsageInsights(cycles: cycles)
        #expect(insights.isEmpty)
    }

    @Test("computeMonthlyUtilizations returns empty for empty events")
    func monthlyUtilizationsEmpty() {
        let mock = makeMockService()

        let utilizations = ValueInsightEngine.computeMonthlyUtilizations(
            events: [],
            creditLimits: proLimits,
            headroomAnalysisService: mock
        )

        #expect(utilizations.isEmpty)
    }
}
