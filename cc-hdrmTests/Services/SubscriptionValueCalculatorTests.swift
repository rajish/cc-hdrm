import Foundation
import Testing
@testable import cc_hdrm

@Suite("SubscriptionValueCalculator Tests")
struct SubscriptionValueCalculatorTests {

    // MARK: - Helpers

    private func makeMockService(
        usedCredits: Double = 2_860_000
    ) -> MockHeadroomAnalysisService {
        let mock = MockHeadroomAnalysisService()
        mock.mockPeriodSummary = PeriodSummary(
            usedCredits: usedCredits,
            constrainedCredits: 660_000,
            wasteCredits: 1_980_000,
            resetCount: 3,
            avgPeakUtilization: 52.0,
            usedPercent: 52,
            constrainedPercent: 12,
            wastePercent: 36
        )
        return mock
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
                wasteCredits: nil
            )
        }
    }

    // MARK: - 9.3: Pro tier, week range, 50% utilization -> correct dollars

    @Test("Pro tier week range: period price = $20 * 7/30.44")
    func proWeekPeriodPrice() {
        let mock = makeMockService()
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: RateLimitTier.pro.creditLimits,
            timeRange: .week,
            headroomAnalysisService: mock
        )
        #expect(value != nil)
        let expected = 20.0 * 7.0 / 30.44
        #expect(abs(value!.periodPrice - expected) < 0.01)
        #expect(value!.monthlyPrice == 20.0)
    }

    @Test("Pro tier week: usedDollars + wastedDollars = periodPrice")
    func proWeekDollarsSumToPeriodPrice() {
        let mock = makeMockService()
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: RateLimitTier.pro.creditLimits,
            timeRange: .week,
            headroomAnalysisService: mock
        )
        #expect(value != nil)
        let total = value!.usedDollars + value!.wastedDollars
        #expect(abs(total - value!.periodPrice) < 0.01, "Used + wasted must equal period price")
    }

    // MARK: - 9.4: Max 5x, month range, 75% utilization -> $75 of $100

    @Test("Max 5x month range: period price approximates monthly price")
    func max5xMonthPeriodPrice() {
        let mock = makeMockService()
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: RateLimitTier.max5x.creditLimits,
            timeRange: .month,
            headroomAnalysisService: mock
        )
        #expect(value != nil)
        let expected = 100.0 * 30.0 / 30.44
        #expect(abs(value!.periodPrice - expected) < 0.01)
        #expect(value!.monthlyPrice == 100.0)
    }

    // MARK: - 9.5: Day range proration

    @Test("Day range proration is 1/30.44 of monthly price")
    func dayRangeProration() {
        let mock = makeMockService()
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: RateLimitTier.pro.creditLimits,
            timeRange: .day,
            headroomAnalysisService: mock
        )
        #expect(value != nil)
        let expected = 20.0 * 1.0 / 30.44
        #expect(abs(value!.periodPrice - expected) < 0.01)
    }

    // MARK: - 9.6: .all range uses actual event span

    @Test(".all range uses actual event span, not fixed period")
    func allRangeUsesActualSpan() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let ninetyDaysMs: Int64 = 90 * 24 * 3_600_000
        let event1 = ResetEvent(
            id: 1, timestamp: nowMs - ninetyDaysMs,
            fiveHourPeak: 50, sevenDayUtil: 30, tier: "default_claude_pro",
            usedCredits: nil, constrainedCredits: nil, wasteCredits: nil
        )
        let event2 = ResetEvent(
            id: 2, timestamp: nowMs,
            fiveHourPeak: 60, sevenDayUtil: 40, tier: "default_claude_pro",
            usedCredits: nil, constrainedCredits: nil, wasteCredits: nil
        )
        let days = SubscriptionValueCalculator.periodDays(for: .all, events: [event1, event2])
        #expect(abs(days - 90.0) < 1.0, "Should be approximately 90 days")
    }

    @Test("Empty events returns 0 days for all ranges")
    func emptyEventsReturnsZero() {
        #expect(SubscriptionValueCalculator.periodDays(for: .all, events: []) == 0)
        #expect(SubscriptionValueCalculator.periodDays(for: .day, events: []) == 0)
        #expect(SubscriptionValueCalculator.periodDays(for: .week, events: []) == 0)
        #expect(SubscriptionValueCalculator.periodDays(for: .month, events: []) == 0)
    }

    // MARK: - 9.7: nil creditLimits returns nil

    @Test("nil monthlyPrice returns nil (custom limits without price)")
    func nilMonthlyPriceReturnsNil() {
        let customLimits = CreditLimits(fiveHourCredits: 1_000_000, sevenDayCredits: 10_000_000)
        let mock = makeMockService()
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: customLimits,
            timeRange: .week,
            headroomAnalysisService: mock
        )
        #expect(value == nil, "Should return nil when monthlyPrice is unknown")
    }

    // MARK: - 9.8: empty resetEvents edge case

    @Test("Empty resetEvents with .all range returns nil (0 period days)")
    func emptyEventsAllRange() {
        let mock = makeMockService()
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: [],
            creditLimits: RateLimitTier.pro.creditLimits,
            timeRange: .all,
            headroomAnalysisService: mock
        )
        #expect(value == nil, "Should return nil when .all has 0 period days")
    }

    // MARK: - 9.9: Custom limits with nil monthlyPrice

    @Test("Custom limits with nil monthlyPrice returns nil for percentage-only mode")
    func customLimitsNilPriceReturnsNil() {
        let customLimits = CreditLimits(fiveHourCredits: 800_000, sevenDayCredits: 8_000_000)
        #expect(customLimits.monthlyPrice == nil)
        let mock = makeMockService()
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: customLimits,
            timeRange: .week,
            headroomAnalysisService: mock
        )
        #expect(value == nil)
    }

    @Test("Custom limits WITH monthlyPrice returns valid SubscriptionValue")
    func customLimitsWithPriceReturnsValue() {
        let customLimits = CreditLimits(fiveHourCredits: 800_000, sevenDayCredits: 8_000_000, monthlyPrice: 50.0)
        let mock = makeMockService()
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: customLimits,
            timeRange: .week,
            headroomAnalysisService: mock
        )
        #expect(value != nil)
        #expect(value!.monthlyPrice == 50.0)
    }

    // MARK: - 9.11: Dollar formatting

    @Test("Dollar formatting: < $10 shows cents, >= $10 shows whole dollars")
    func dollarFormatting() {
        #expect(SubscriptionValueCalculator.formatDollars(4.60) == "$4.60")
        #expect(SubscriptionValueCalculator.formatDollars(0.66) == "$0.66")
        #expect(SubscriptionValueCalculator.formatDollars(9.99) == "$9.99")
        #expect(SubscriptionValueCalculator.formatDollars(10.0) == "$10")
        #expect(SubscriptionValueCalculator.formatDollars(75.0) == "$75")
        #expect(SubscriptionValueCalculator.formatDollars(200.0) == "$200")
    }

    // MARK: - 9.12: RateLimitTier.monthlyPrice values

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

    // MARK: - Edge cases

    @Test("100% utilization produces zero wasted dollars")
    func fullUtilizationZeroWaste() {
        let mock = makeMockService(usedCredits: 5_000_000)
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: sampleEvents(),
            creditLimits: RateLimitTier.pro.creditLimits,
            timeRange: .week,
            headroomAnalysisService: mock
        )
        #expect(value != nil)
        #expect(value!.utilizationPercent == 100.0)
        #expect(abs(value!.wastedDollars) < 0.01)
    }

    @Test("0% utilization means all money wasted")
    func zeroUtilizationAllWaste() {
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
        #expect(abs(value!.wastedDollars - value!.periodPrice) < 0.01)
    }

    @Test("averageDaysPerMonth constant is 30.44")
    func averageDaysPerMonthConstant() {
        #expect(SubscriptionValueCalculator.averageDaysPerMonth == 30.44)
    }

    @Test("periodDays returns correct values for fixed ranges when data span is sufficient")
    func periodDaysFixedRanges() {
        let events = sampleEvents(spanDays: 30)
        #expect(SubscriptionValueCalculator.periodDays(for: .day, events: events) == 1.0)
        #expect(SubscriptionValueCalculator.periodDays(for: .week, events: events) == 7.0)
        #expect(SubscriptionValueCalculator.periodDays(for: .month, events: events) == 30.0)
    }

    @Test("periodDays caps at actual data span when data is shorter than selected range")
    func periodDaysCapsAtActualSpan() {
        let events = sampleEvents(count: 3, spanDays: 5)
        // .day: min(1, 5) = 1
        #expect(SubscriptionValueCalculator.periodDays(for: .day, events: events) == 1.0)
        // .week: min(7, 5) = 5
        #expect(SubscriptionValueCalculator.periodDays(for: .week, events: events) == 5.0)
        // .month: min(30, 5) = 5
        #expect(SubscriptionValueCalculator.periodDays(for: .month, events: events) == 5.0)
        // .all: min(inf, 5) = 5
        #expect(SubscriptionValueCalculator.periodDays(for: .all, events: events) == 5.0)
    }

    @Test(".all with single event returns minimum 1 day")
    func allRangeSingleEventMinimumOneDay() {
        let event = ResetEvent(
            id: 1, timestamp: 1000,
            fiveHourPeak: 50, sevenDayUtil: 30, tier: "default_claude_pro",
            usedCredits: nil, constrainedCredits: nil, wasteCredits: nil
        )
        let days = SubscriptionValueCalculator.periodDays(for: .all, events: [event, event])
        #expect(days == 1.0, "Same-timestamp events should return minimum 1 day")
    }

    // MARK: - customMonthlyPrice wiring through resolve()

    @Test("resolve() passes customMonthlyPrice to CreditLimits for custom tiers")
    func resolvePassesCustomMonthlyPrice() {
        let prefs = MockPreferencesManager()
        prefs.customFiveHourCredits = 1_000_000
        prefs.customSevenDayCredits = 10_000_000
        prefs.customMonthlyPrice = 50.0

        let limits = RateLimitTier.resolve(tierString: "unknown_tier", preferencesManager: prefs)
        #expect(limits != nil)
        #expect(limits!.monthlyPrice == 50.0)
    }

    @Test("resolve() returns nil monthlyPrice when customMonthlyPrice is unset")
    func resolveNilCustomMonthlyPrice() {
        let prefs = MockPreferencesManager()
        prefs.customFiveHourCredits = 1_000_000
        prefs.customSevenDayCredits = 10_000_000
        // customMonthlyPrice not set — defaults to nil

        let limits = RateLimitTier.resolve(tierString: "unknown_tier", preferencesManager: prefs)
        #expect(limits != nil)
        #expect(limits!.monthlyPrice == nil)
    }
}
