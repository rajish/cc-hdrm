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

    @Test("24h insight with dollar value: 'Used $X of $Y today'")
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

        #expect(insight.text.hasPrefix("Used $"))
        #expect(insight.text.contains(" of $"))
        #expect(insight.text.hasSuffix(" today"))
    }

    // MARK: - 9.3: 24h insight percentage-only

    @Test("24h insight percentage-only: 'Z% utilization today'")
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

        #expect(insight.text.contains("% utilization today"))
    }

    // MARK: - 9.4: 7d insight above average

    @Test("7d insight above average: 'X% above your typical week'")
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

        // Week util (~90%) >> all-time util (~0.8%) → large positive diff
        #expect(insight.text.contains("above your typical week"))
        #expect(insight.isQuiet == false)
    }

    // MARK: - 9.5: 7d insight below average

    @Test("7d insight below average: 'X% below your typical week'")
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

        // Week util (~20%) << all-time util (~77.8%) → large negative diff
        #expect(insight.text.contains("below your typical week"))
        #expect(insight.isQuiet == false)
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

    @Test("30d insight with dollar value and utilization percentage")
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

        #expect(insight.text.hasPrefix("Used $"))
        #expect(insight.text.contains("this month"))
        #expect(insight.text.contains("%"))
    }

    // MARK: - 9.9: 30d insight percentage-only

    @Test("30d insight percentage-only (nil monthlyPrice)")
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

        // Falls back to aggregateBreakdown's usedPercent
        #expect(insight.text.contains("% utilization this month"))
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
