import Testing
import SwiftUI
@testable import cc_hdrm

@Suite("HeadroomBreakdownBar Tests")
@MainActor
struct HeadroomBreakdownBarTests {

    // MARK: - Helpers

    private func makeMockService(
        usedPercent: Double = 52,
        constrainedPercent: Double = 12,
        unusedPercent: Double = 36,
        avgPeakUtilization: Double = 52.0,
        usedCredits: Double = 2_860_000
    ) -> MockHeadroomAnalysisService {
        let mock = MockHeadroomAnalysisService()
        mock.mockPeriodSummary = PeriodSummary(
            usedCredits: usedCredits,
            constrainedCredits: 660_000,
            unusedCredits: 1_980_000,
            resetCount: 3,
            avgPeakUtilization: avgPeakUtilization,
            usedPercent: usedPercent,
            constrainedPercent: constrainedPercent,
            unusedPercent: unusedPercent
        )
        return mock
    }

    private func makeBar(
        resetEvents: [ResetEvent] = [],
        creditLimits: CreditLimits? = RateLimitTier.pro.creditLimits,
        headroomAnalysisService: (any HeadroomAnalysisServiceProtocol)? = nil,
        selectedTimeRange: TimeRange = .week,
        dataQualifier: String? = nil
    ) -> HeadroomBreakdownBar {
        let service = headroomAnalysisService ?? makeMockService()
        return HeadroomBreakdownBar(
            resetEvents: resetEvents,
            creditLimits: creditLimits,
            headroomAnalysisService: service,
            selectedTimeRange: selectedTimeRange,
            dataQualifier: dataQualifier
        )
    }

    /// Creates sample events spanning the given number of days (default 30).
    /// Events are evenly spaced from `spanDays` ago to now.
    private func sampleEvents(count: Int = 3, spanDays: Int = 30) -> [ResetEvent] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let totalSpanMs = Int64(spanDays) * 24 * 3_600_000
        let stepMs = count > 1 ? totalSpanMs / Int64(count - 1) : 0
        return (0..<count).map { i in
            ResetEvent(
                id: Int64(i + 1),
                timestamp: nowMs - totalSpanMs + Int64(i) * stepMs,
                fiveHourPeak: 85.0 + Double(i),
                sevenDayUtil: 40.0 + Double(i),
                tier: "default_claude_pro",
                usedCredits: nil,
                constrainedCredits: nil,
                unusedCredits: nil
            )
        }
    }

    // MARK: - Two-band bar renders (AC 1)

    @Test("Bar renders two segments (used + unused) without crashing")
    func rendersTwoSegments() {
        let mock = makeMockService()
        let bar = makeBar(resetEvents: sampleEvents(), headroomAnalysisService: mock)
        let _ = bar.body
        #expect(mock.aggregateBreakdownCallCount == 1, "aggregateBreakdown should be called once")
    }

    @Test("Bar passes correct events to aggregateBreakdown")
    func passesCorrectEvents() {
        let events = sampleEvents(count: 5)
        let mock = makeMockService()
        let bar = makeBar(resetEvents: events, headroomAnalysisService: mock)
        let _ = bar.body
        #expect(mock.lastEvents?.count == 5, "Should pass all 5 events to service")
    }

    // MARK: - Dollar amounts (AC 2)

    @Test("Pro tier week range produces correct dollar proration")
    func proWeekDollarProration() {
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: RateLimitTier.pro.creditLimits,
            timeRange: .week,
            headroomAnalysisService: makeMockService()
        )
        #expect(value != nil)
        // Period price = $20 * 7/30.44 ≈ $4.60
        #expect(abs(value!.periodPrice - (20.0 * 7.0 / 30.44)) < 0.01)
        #expect(value!.monthlyPrice == 20.0)
    }

    @Test("Max 5x month range produces correct dollar proration")
    func max5xMonthDollarProration() {
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: RateLimitTier.max5x.creditLimits,
            timeRange: .month,
            headroomAnalysisService: makeMockService()
        )
        #expect(value != nil)
        // Period price = $100 * 30/30.44 ≈ $98.55
        #expect(abs(value!.periodPrice - (100.0 * 30.0 / 30.44)) < 0.01)
        #expect(value!.monthlyPrice == 100.0)
    }

    @Test("usedDollars + unusedDollars = periodPrice")
    func dollarsSumToPeriodPrice() {
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: RateLimitTier.pro.creditLimits,
            timeRange: .week,
            headroomAnalysisService: makeMockService()
        )
        #expect(value != nil)
        let total = value!.usedDollars + value!.unusedDollars
        #expect(abs(total - value!.periodPrice) < 0.01, "Used + unused must equal period price")
    }

    // MARK: - Nil creditLimits (AC 4)

    @Test("Nil creditLimits shows unavailable message -- does not call service")
    func nilCreditLimitsShowsUnavailable() {
        let mock = makeMockService()
        let bar = makeBar(resetEvents: sampleEvents(), creditLimits: nil, headroomAnalysisService: mock)
        let _ = bar.body
        #expect(mock.aggregateBreakdownCallCount == 0, "Service should NOT be called when creditLimits is nil")
    }

    // MARK: - Empty resetEvents (AC 5)

    @Test("Empty resetEvents shows no-events message -- does not call service")
    func emptyEventsShowsNoEventsMessage() {
        let mock = makeMockService()
        let bar = makeBar(resetEvents: [], headroomAnalysisService: mock)
        let _ = bar.body
        #expect(mock.aggregateBreakdownCallCount == 0, "Service should NOT be called when events are empty")
    }

    // MARK: - Custom limits without price (percentage-only mode)

    @Test("Custom limits with nil monthlyPrice shows percentage-only mode")
    func customLimitsPercentageOnly() {
        let customLimits = CreditLimits(fiveHourCredits: 1_000_000, sevenDayCredits: 10_000_000)
        let mock = makeMockService()
        let bar = makeBar(resetEvents: sampleEvents(), creditLimits: customLimits, headroomAnalysisService: mock)
        let _ = bar.body
        // SubscriptionValueCalculator returns nil -> percentage-only path calls aggregateBreakdown
        #expect(mock.aggregateBreakdownCallCount == 1, "Service should be called for percentage-only mode")
    }

    // MARK: - VoiceOver (AC 3)

    @Test("Dollar formatting: < $10 shows cents, >= $10 shows whole dollars")
    func dollarFormatting() {
        #expect(SubscriptionValueCalculator.formatDollars(4.60) == "$4.60")
        #expect(SubscriptionValueCalculator.formatDollars(0.66) == "$0.66")
        #expect(SubscriptionValueCalculator.formatDollars(9.99) == "$9.99")
        #expect(SubscriptionValueCalculator.formatDollars(10.0) == "$10")
        #expect(SubscriptionValueCalculator.formatDollars(75.0) == "$75")
        #expect(SubscriptionValueCalculator.formatDollars(200.0) == "$200")
    }

    // MARK: - Time range variations

    @Test("Day range proration is correct (1/30.44 of monthly)")
    func dayRangeProration() {
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: RateLimitTier.pro.creditLimits,
            timeRange: .day,
            headroomAnalysisService: makeMockService()
        )
        #expect(value != nil)
        #expect(abs(value!.periodPrice - (20.0 * 1.0 / 30.44)) < 0.01)
    }

    @Test(".all range uses actual event span")
    func allRangeUsesEventSpan() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let events = [
            ResetEvent(id: 1, timestamp: nowMs - 90 * 24 * 3_600_000, fiveHourPeak: 50, sevenDayUtil: 30, tier: "default_claude_pro", usedCredits: nil, constrainedCredits: nil, unusedCredits: nil),
            ResetEvent(id: 2, timestamp: nowMs, fiveHourPeak: 60, sevenDayUtil: 40, tier: "default_claude_pro", usedCredits: nil, constrainedCredits: nil, unusedCredits: nil)
        ]
        let days = SubscriptionValueCalculator.periodDays(for: .all, events: events)
        #expect(abs(days - 90.0) < 1.0, "Should be approximately 90 days")
    }

    @Test(".all range with empty events returns 0 days")
    func allRangeEmptyEvents() {
        let days = SubscriptionValueCalculator.periodDays(for: .all, events: [])
        #expect(days == 0)
    }

    // MARK: - Utilization color

    @Test("Low utilization produces .normal state (green)")
    func lowUtilizationProducesNormal() {
        let state = HeadroomState(from: 30.0)
        #expect(state == .normal, "30% utilization = 70% headroom -> .normal")
    }

    @Test("High utilization produces .critical state (red)")
    func highUtilizationProducesCritical() {
        let state = HeadroomState(from: 97.0)
        #expect(state == .critical, "97% utilization = 3% headroom -> .critical")
    }

    // MARK: - Edge cases

    @Test("Bar renders with different time ranges")
    func differentTimeRanges() {
        let mock = makeMockService()
        for range in TimeRange.allCases {
            let bar = makeBar(resetEvents: sampleEvents(), headroomAnalysisService: mock, selectedTimeRange: range)
            let _ = bar.body
        }
        // Called once per time range (4 times)
        #expect(mock.aggregateBreakdownCallCount == 4)
    }

    @Test("Bar renders with single reset event")
    func singleResetEvent() {
        let mock = makeMockService()
        let bar = makeBar(resetEvents: sampleEvents(count: 1), headroomAnalysisService: mock)
        let _ = bar.body
        #expect(mock.lastEvents?.count == 1)
    }

    @Test("100% utilization produces zero unused dollars")
    func fullUtilizationZeroUnused() {
        // usedCredits = sevenDayCredits * (7/7) = 5_000_000 (100% of weekly capacity)
        let mock = makeMockService(usedCredits: 5_000_000)
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: RateLimitTier.pro.creditLimits,
            timeRange: .week,
            headroomAnalysisService: mock
        )
        #expect(value != nil)
        #expect(value!.utilizationPercent == 100.0)
        #expect(abs(value!.unusedDollars) < 0.01)
    }

    @Test("0% utilization means all money unused")
    func zeroUtilizationAllUnused() {
        let mock = makeMockService(usedCredits: 0)
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: RateLimitTier.pro.creditLimits,
            timeRange: .week,
            headroomAnalysisService: mock
        )
        #expect(value != nil)
        #expect(value!.utilizationPercent == 0.0)
        #expect(value!.usedDollars == 0.0)
        #expect(abs(value!.unusedDollars - value!.periodPrice) < 0.01)
    }

    // MARK: - RateLimitTier monthlyPrice

    @Test("RateLimitTier.monthlyPrice values are correct")
    func tierMonthlyPrices() {
        #expect(RateLimitTier.pro.monthlyPrice == 20.0)
        #expect(RateLimitTier.max5x.monthlyPrice == 100.0)
        #expect(RateLimitTier.max20x.monthlyPrice == 200.0)
    }

    @Test("RateLimitTier.creditLimits includes monthlyPrice")
    func tierCreditLimitsIncludePrice() {
        #expect(RateLimitTier.pro.creditLimits.monthlyPrice == 20.0)
        #expect(RateLimitTier.max5x.creditLimits.monthlyPrice == 100.0)
        #expect(RateLimitTier.max20x.creditLimits.monthlyPrice == 200.0)
    }

    @Test("CreditLimits defaults monthlyPrice to nil")
    func creditLimitsDefaultNilPrice() {
        let limits = CreditLimits(fiveHourCredits: 100, sevenDayCredits: 909)
        #expect(limits.monthlyPrice == nil)
    }

    // MARK: - Qualifier mode (Story 14.5 AC 3)

    @Test("dataQualifier nil renders normal dollar breakdown (no regression)")
    func dataQualifierNilRendersNormalBreakdown() {
        let mock = makeMockService()
        let bar = makeBar(resetEvents: sampleEvents(), headroomAnalysisService: mock, dataQualifier: nil)
        let _ = bar.body
        // With nil dataQualifier, the bar takes the normal breakdownContent path.
        // Pro tier has monthlyPrice -> SubscriptionValueCalculator.calculate() calls aggregateBreakdown once.
        #expect(mock.aggregateBreakdownCallCount == 1, "Dollar breakdown calls aggregateBreakdown via SubscriptionValueCalculator")
    }

    @Test("dataQualifier set renders percentage-only mode (suppresses dollars)")
    func dataQualifierSetRendersPercentageOnly() {
        let mock = makeMockService()
        let bar = makeBar(resetEvents: sampleEvents(), headroomAnalysisService: mock, dataQualifier: "3 hours of data in this view")
        let _ = bar.body
        // With dataQualifier set, the bar should go to qualifierContent which shows percentage-only.
        // This confirms it renders without crashing.
        #expect(mock.aggregateBreakdownCallCount == 1, "Qualifier mode should call aggregateBreakdown for percentage computation")
    }

    @Test("dataQualifier set calls aggregateBreakdown (percentage-only path)")
    func dataQualifierCallsAggregateBreakdown() {
        let events = sampleEvents(count: 5)
        let mock = makeMockService()
        let bar = makeBar(resetEvents: events, headroomAnalysisService: mock, dataQualifier: "5 hours of data in this view")
        let _ = bar.body
        #expect(mock.aggregateBreakdownCallCount == 1)
        #expect(mock.lastEvents?.count == 5, "Should pass all events to aggregateBreakdown")
    }

    @Test("dataQualifier with nil creditLimits still shows unavailable message (creditLimits nil takes priority)")
    func dataQualifierWithNilCreditLimits() {
        let mock = makeMockService()
        let bar = makeBar(resetEvents: sampleEvents(), creditLimits: nil, headroomAnalysisService: mock, dataQualifier: "3 hours of data in this view")
        let _ = bar.body
        // creditLimits == nil check happens before dataQualifier check
        #expect(mock.aggregateBreakdownCallCount == 0, "Service should NOT be called when creditLimits is nil, even with dataQualifier set")
    }

    @Test("dataQualifier with empty events still shows no-events message (empty events takes priority)")
    func dataQualifierWithEmptyEvents() {
        let mock = makeMockService()
        let bar = makeBar(resetEvents: [], headroomAnalysisService: mock, dataQualifier: "1 hour of data in this view")
        let _ = bar.body
        // resetEvents.isEmpty check happens before dataQualifier check
        #expect(mock.aggregateBreakdownCallCount == 0, "Service should NOT be called when events are empty, even with dataQualifier set")
    }
}
