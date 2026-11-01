import Foundation
import SQLite3
import Testing
@testable import cc_hdrm

private let week1 = "2026-11-08T00:00:00Z"
private let week2 = "2026-11-15T00:00:00Z"
private let week3 = "2026-11-22T00:00:00Z"
private let proTier = RateLimitTier.pro.rawValue

/// Drives real polls through `persistPoll` on a temporary database. Detection stamps polls with
/// the current time, so elapsed time is simulated by moving everything stored so far into the past.
private final class PollHistory {
    let manager: DatabaseManager
    let service: HistoricalDataService
    var tier: String? = proTier
    private let path: URL

    init() throws {
        path = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).db")
        manager = DatabaseManager(databasePath: path)
        try manager.ensureSchema()
        service = HistoricalDataService(databaseManager: manager, headroomAnalysisService: HeadroomAnalysisService())
    }

    deinit {
        manager.closeConnection()
        try? FileManager.default.removeItem(at: path)
    }

    func poll(
        fiveHour: Double? = nil,
        fiveHourResetsAt: String? = nil,
        sevenDay: Double?,
        sevenDayResetsAt: String?
    ) async throws {
        let window = (fiveHour != nil || fiveHourResetsAt != nil)
            ? WindowUsage(utilization: fiveHour, resetsAt: fiveHourResetsAt)
            : nil
        try await service.persistPoll(
            UsageResponse(
                fiveHour: window,
                sevenDay: WindowUsage(utilization: sevenDay, resetsAt: sevenDayResetsAt),
                limits: nil,
                extraUsage: nil
            ),
            tier: tier
        )
    }

    func advance(hours: Double) throws {
        let ms = Int64(hours * 3_600_000)
        let connection = try manager.getConnection()
        sqlite3_exec(connection, "UPDATE usage_polls SET timestamp = timestamp - \(ms)", nil, nil, nil)
        sqlite3_exec(connection, "UPDATE reset_events SET timestamp = timestamp - \(ms)", nil, nil, nil)
    }

    func events() async throws -> [ResetEvent] {
        try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
    }
}

private func event(
    id: Int64 = 1,
    daysAgo: Double = 0,
    from nowMs: Int64 = 1_800_000_000_000,
    fiveHourPeak: Double? = nil,
    sevenDayUtil: Double? = 70,
    tier: String? = proTier,
    credits: (used: Double, constrained: Double?, unused: Double)? = nil,
    weekly: Bool = false
) -> ResetEvent {
    ResetEvent(
        id: id,
        timestamp: nowMs - Int64(daysAgo * 86_400_000),
        fiveHourPeak: fiveHourPeak,
        sevenDayUtil: sevenDayUtil,
        tier: tier,
        usedCredits: credits?.used,
        constrainedCredits: credits?.constrained,
        unusedCredits: credits?.unused,
        isWeeklyCycle: weekly
    )
}

private func approximately(_ a: Double, _ b: Double, within tolerance: Double = 0.001) -> Bool {
    abs(a - b) <= tolerance
}

@Suite("Weekly cycle detection through real polls")
struct WeeklyCycleDetectionTests {

    @Test("A sleep gap over 5 hours with a number creates no weekly cycle and drops no real event")
    func sleepGapWithNumber() async throws {
        let history = try PollHistory()
        try await history.poll(fiveHour: 60, fiveHourResetsAt: "2026-11-01T05:00:00Z", sevenDay: 30, sevenDayResetsAt: week1)
        try history.advance(hours: 4.5)
        try await history.poll(fiveHour: 5, fiveHourResetsAt: "2026-11-01T10:00:00Z", sevenDay: 31, sevenDayResetsAt: week1)
        try history.advance(hours: 6)
        try await history.poll(fiveHour: 0, fiveHourResetsAt: "2026-11-01T16:00:00Z", sevenDay: 31, sevenDayResetsAt: week1)
        try history.advance(hours: 1)
        try await history.poll(fiveHour: 70, fiveHourResetsAt: "2026-11-01T16:00:00Z", sevenDay: 35, sevenDayResetsAt: week1)
        try history.advance(hours: 4)
        try await history.poll(fiveHour: 5, fiveHourResetsAt: "2026-11-01T21:00:00Z", sevenDay: 36, sevenDayResetsAt: week1)

        let events = try await history.events()

        #expect(events.map(\.fiveHourPeak) == [60, nil, 70])
        #expect(events[1].sevenDayUtil == 31)
        #expect(events.allSatisfy { !$0.isWeeklyCycle })
        #expect(events.excludingWeeklyOverlap() == events)

        let summary = HeadroomAnalysisService().aggregateBreakdown(events: events)
        #expect(summary.resetCount == 2)
        #expect(summary.weeklyCycleCount == 0)
        #expect(approximately(summary.usedCredits, 0.6 * 550_000 + 0.7 * 550_000))
    }

    @Test("A sleep across the weekly reset with a number is not a weekly cycle")
    func sleepAcrossWeeklyResetWithNumber() async throws {
        let history = try PollHistory()
        try await history.poll(fiveHour: 40, fiveHourResetsAt: "2026-11-01T05:00:00Z", sevenDay: 80, sevenDayResetsAt: week1)
        try history.advance(hours: 8)
        try await history.poll(fiveHour: 0, fiveHourResetsAt: nil, sevenDay: 0, sevenDayResetsAt: week2)

        let events = try await history.events()

        #expect(events.count == 1)
        #expect(events[0].fiveHourPeak == nil)
        #expect(!events[0].isWeeklyCycle)
        #expect(HeadroomAnalysisService().aggregateBreakdown(events: events).resetCount == 0)
    }

    @Test("An idle 5-hour window reporting 0 still counts as a number across a sleep")
    func idleNumberAcrossWeeklyReset() async throws {
        let history = try PollHistory()
        try await history.poll(fiveHour: 0, fiveHourResetsAt: nil, sevenDay: 80, sevenDayResetsAt: week1)
        try history.advance(hours: 8)
        try await history.poll(fiveHour: 0, fiveHourResetsAt: nil, sevenDay: 0, sevenDayResetsAt: week2)

        let events = try await history.events()

        #expect(events.count == 1)
        #expect(!events[0].isWeeklyCycle)
    }

    @Test("A weekly reset with no number around it is a weekly cycle with two stored bands")
    func weeklyCycleRecorded() async throws {
        let history = try PollHistory()
        try await history.poll(sevenDay: 30, sevenDayResetsAt: week1)
        try history.advance(hours: 72)
        try await history.poll(sevenDay: 70, sevenDayResetsAt: week1)
        try history.advance(hours: 96)
        try await history.poll(sevenDay: 0, sevenDayResetsAt: week2)

        let events = try await history.events()

        #expect(events.count == 1)
        #expect(events[0].isWeeklyCycle)
        #expect(events[0].fiveHourPeak == nil)
        #expect(events[0].sevenDayUtil == 70)
        #expect(approximately(events[0].usedCredits ?? 0, 3_500_000))
        #expect(events[0].constrainedCredits == nil)
        #expect(approximately(events[0].unusedCredits ?? 0, 1_500_000))
    }

    @Test("A weekly utilization drop with no reset time is still a weekly cycle")
    func weeklyCycleFromDrop() async throws {
        let history = try PollHistory()
        try await history.poll(sevenDay: 70, sevenDayResetsAt: week1)
        try history.advance(hours: 8)
        try await history.poll(sevenDay: 0, sevenDayResetsAt: nil)

        let events = try await history.events()

        #expect(events.count == 1)
        #expect(events[0].isWeeklyCycle)
    }

    @Test("No weekly reset means no event, even with no number")
    func noResetNoEvent() async throws {
        let history = try PollHistory()
        try await history.poll(sevenDay: 30, sevenDayResetsAt: week1)
        try history.advance(hours: 8)
        try await history.poll(sevenDay: 31, sevenDayResetsAt: week1)

        #expect(try await history.events().isEmpty)
    }

    @Test("A number in the last 5 hours stops a weekly cycle, even if the nearest polls have none")
    func recentNumberStopsWeeklyCycle() async throws {
        let history = try PollHistory()
        try await history.poll(fiveHour: 30, fiveHourResetsAt: "2026-11-01T05:00:00Z", sevenDay: 50, sevenDayResetsAt: week1)
        try history.advance(hours: 1)
        try await history.poll(sevenDay: 50, sevenDayResetsAt: week1)
        try history.advance(hours: 1)
        try await history.poll(sevenDay: 0, sevenDayResetsAt: week2)

        let events = try await history.events()

        #expect(events.count == 1)
        #expect(!events[0].isWeeklyCycle)
        #expect(events[0].fiveHourPeak == 30)
    }

    @Test("A number on the poll before the reset stops a weekly cycle")
    func numberBeforeReset() async throws {
        let history = try PollHistory()
        try await history.poll(fiveHour: 10, fiveHourResetsAt: "2026-11-01T05:00:00Z", sevenDay: 70, sevenDayResetsAt: week1)
        try history.advance(hours: 8)
        try await history.poll(sevenDay: 0, sevenDayResetsAt: week2)

        let events = try await history.events()

        #expect(events.count == 1)
        #expect(!events[0].isWeeklyCycle)
    }

    @Test("A number on the poll that saw the reset stops a weekly cycle")
    func numberAfterReset() async throws {
        let history = try PollHistory()
        try await history.poll(sevenDay: 70, sevenDayResetsAt: week1)
        try history.advance(hours: 8)
        try await history.poll(fiveHour: 0, fiveHourResetsAt: nil, sevenDay: 0, sevenDayResetsAt: week2)

        let events = try await history.events()

        #expect(events.count == 1)
        #expect(!events[0].isWeeklyCycle)
    }

    @Test("A 5-hour reset time with no value still counts as a 5-hour window")
    func resetTimeWithoutValue() async throws {
        let history = try PollHistory()
        try await history.poll(fiveHourResetsAt: "2026-11-01T05:00:00Z", sevenDay: 70, sevenDayResetsAt: week1)
        try history.advance(hours: 8)
        try await history.poll(fiveHourResetsAt: "2026-11-01T05:00:00Z", sevenDay: 0, sevenDayResetsAt: week2)

        let events = try await history.events()

        #expect(events.count == 1)
        #expect(!events[0].isWeeklyCycle)
    }

    @Test("A previous poll with no weekly value makes no weekly cycle")
    func noWeeklyValueBeforeReset() async throws {
        let history = try PollHistory()
        try await history.poll(sevenDay: nil, sevenDayResetsAt: week1)
        try history.advance(hours: 8)
        try await history.poll(sevenDay: 0, sevenDayResetsAt: week2)

        let events = try await history.events()

        #expect(events.count == 1)
        #expect(!events[0].isWeeklyCycle)
    }

    @Test("A drifting weekly reset time with no drop in usage makes no weekly cycle")
    func driftingResetTime() async throws {
        let history = try PollHistory()
        try await history.poll(sevenDay: 30, sevenDayResetsAt: "2026-11-08T00:00:00Z")
        try history.advance(hours: 8)
        try await history.poll(sevenDay: 31, sevenDayResetsAt: "2026-11-08T01:00:00Z")

        let events = try await history.events()

        #expect(events.count == 1)
        #expect(!events[0].isWeeklyCycle)
    }

    @Test("An early weekly reset, seen as a drop in usage, is a weekly cycle")
    func earlyReset() async throws {
        let history = try PollHistory()
        try await history.poll(sevenDay: 60, sevenDayResetsAt: "2026-11-08T00:00:00Z")
        try history.advance(hours: 8)
        try await history.poll(sevenDay: 0, sevenDayResetsAt: "2026-11-11T00:00:00Z")

        #expect(try await history.events().map(\.isWeeklyCycle) == [true])
    }

    @Test("A zero-use cycle is a weekly cycle, reporting 0% used")
    func zeroUseCycle() async throws {
        let history = try PollHistory()
        try await history.poll(sevenDay: 0, sevenDayResetsAt: week1)
        try history.advance(hours: 8)
        try await history.poll(sevenDay: 0, sevenDayResetsAt: week2)

        let events = try await history.events()
        let summary = HeadroomAnalysisService().aggregateBreakdown(events: events)

        #expect(events.map(\.isWeeklyCycle) == [true])
        #expect(summary.usedPercent == 0)
        #expect(summary.unusedPercent == 100)
    }

    @Test("An unknown tier stores no credits, and the row counts once limits are known")
    func unknownTier() async throws {
        let history = try PollHistory()
        history.tier = "default_claude_unmapped"
        try await history.poll(sevenDay: 70, sevenDayResetsAt: week1)
        try history.advance(hours: 8)
        try await history.poll(sevenDay: 0, sevenDayResetsAt: week2)

        let events = try await history.events()
        #expect(events.map(\.isWeeklyCycle) == [true])
        #expect(events[0].usedCredits == nil)
        #expect(events[0].unusedCredits == nil)
        #expect(HeadroomAnalysisService().aggregateBreakdown(events: events).resetCount == 0)

        let preferences = MockPreferencesManager()
        preferences.customFiveHourCredits = 1_000_000
        preferences.customSevenDayCredits = 10_000_000
        let summary = HeadroomAnalysisService(preferencesManager: preferences).aggregateBreakdown(events: events)
        #expect(summary.weeklyCycleCount == 1)
        #expect(approximately(summary.usedCredits, 7_000_000))
    }

    @Test("An account that changes state keeps old breakdowns and counts overlapping capacity once")
    func stateChangeMidHistory() async throws {
        let history = try PollHistory()
        // Event one, more than a cycle before the first weekly reset.
        try await history.poll(fiveHour: 60, fiveHourResetsAt: "2026-11-01T05:00:00Z", sevenDay: 20, sevenDayResetsAt: week1)
        try history.advance(hours: 4.5)
        try await history.poll(fiveHour: 5, fiveHourResetsAt: "2026-11-01T10:00:00Z", sevenDay: 21, sevenDayResetsAt: week1)
        // Event two, inside the first weekly cycle's 7 days.
        try history.advance(hours: 192)
        try await history.poll(fiveHour: 50, fiveHourResetsAt: "2026-11-09T05:00:00Z", sevenDay: 40, sevenDayResetsAt: week1)
        try history.advance(hours: 4.5)
        try await history.poll(fiveHour: 5, fiveHourResetsAt: "2026-11-09T10:00:00Z", sevenDay: 41, sevenDayResetsAt: week1)
        // The account verifies. Its first weekly reset comes 2 days later, and the next a week after that.
        try history.advance(hours: 24)
        try await history.poll(sevenDay: 45, sevenDayResetsAt: week1)
        try history.advance(hours: 24)
        try await history.poll(sevenDay: 60, sevenDayResetsAt: week1)
        try history.advance(hours: 1)
        try await history.poll(sevenDay: 0, sevenDayResetsAt: week2)
        try history.advance(hours: 167)
        try await history.poll(sevenDay: 50, sevenDayResetsAt: week2)
        try history.advance(hours: 1)
        try await history.poll(sevenDay: 0, sevenDayResetsAt: week3)

        let events = try await history.events()

        // The 8-day gap leaves an empty-peak event, as any long gap does with a number.
        #expect(events.map(\.isWeeklyCycle) == [false, false, false, true, true])
        #expect(events.map(\.fiveHourPeak) == [60, nil, 50, nil, nil])
        #expect(events.map(\.sevenDayUtil) == [20, 21, 40, 60, 50])

        // Old rows still carry their three bands.
        let service = HeadroomAnalysisService()
        let limits = RateLimitTier.pro.creditLimits
        for (old, peak, sevenDay) in [(events[0], 60.0, 20.0), (events[2], 50.0, 40.0)] {
            let expected = service.analyzeResetEvent(fiveHourPeak: peak, sevenDayUtil: sevenDay, creditLimits: limits)
            #expect(old.usedCredits == expected.usedCredits)
            #expect(old.constrainedCredits == expected.constrainedCredits)
            #expect(old.unusedCredits == expected.unusedCredits)
        }

        // The later 5-hour event is inside the first weekly cycle; the first event is not.
        #expect(events.excludingWeeklyOverlap().map(\.id) == [events[0].id, events[3].id, events[4].id])

        let summary = service.aggregateBreakdown(events: events)
        #expect(summary.resetCount == 3)
        #expect(summary.weeklyCycleCount == 2)
        #expect(approximately(summary.usedCredits, 330_000 + 3_000_000 + 2_500_000))
        #expect(approximately(summary.constrainedCredits, events[0].constrainedCredits ?? -1))
        #expect(SubscriptionValueCalculator.periodDays(for: .all, events: events) == 1 + 14)

        // Later reads see the same stored values: analysis writes nothing back.
        #expect(try await history.events() == events)
    }

    @Test("Weekly cycles can run on after an account regains a number")
    func numberReturns() async throws {
        let history = try PollHistory()
        try await history.poll(sevenDay: 70, sevenDayResetsAt: week1)
        try history.advance(hours: 8)
        try await history.poll(sevenDay: 0, sevenDayResetsAt: week2)
        try history.advance(hours: 8)
        try await history.poll(fiveHour: 80, fiveHourResetsAt: "2026-11-02T05:00:00Z", sevenDay: 10, sevenDayResetsAt: week2)
        try history.advance(hours: 4.5)
        try await history.poll(fiveHour: 5, fiveHourResetsAt: "2026-11-02T10:00:00Z", sevenDay: 11, sevenDayResetsAt: week2)

        let events = try await history.events()

        #expect(events.map(\.isWeeklyCycle) == [true, false])
        #expect(events.excludingWeeklyOverlap() == events)
        #expect(!events.isOnlyWeeklyCycles)
    }
}

@Suite("Weekly cycle value and headroom")
@MainActor
struct WeeklyCycleValueTests {
    private let service = HeadroomAnalysisService()
    private let pro = RateLimitTier.pro.creditLimits

    @Test("A 70% weekly cycle reports 70% used, 30% unused and a non-zero value")
    func seventyPercentCycle() throws {
        let events = [event(weekly: true)]
        let summary = service.aggregateBreakdown(events: events)

        #expect(approximately(summary.usedPercent, 70))
        #expect(approximately(summary.unusedPercent, 30))
        #expect(summary.constrainedCredits == 0)
        #expect(summary.constrainedPercent == 0)
        #expect(summary.avgPeakUtilization == 70)
        #expect(summary.weeklyCycleCount == 1)

        for range in [TimeRange.day, .week, .month, .all] {
            let value = try #require(SubscriptionValueCalculator.calculate(
                resetEvents: events, creditLimits: pro, timeRange: range, headroomAnalysisService: service
            ))
            #expect(approximately(value.utilizationPercent, 70))
            #expect(approximately(value.periodPrice, 20 * 7 / SubscriptionValueCalculator.averageDaysPerMonth))
            #expect(approximately(value.usedDollars, value.periodPrice * 0.7))
            #expect(value.usedDollars > 0)
        }
    }

    @Test("Stored credits on a weekly cycle stay, even if the tier table no longer matches")
    func weeklyStoredCredits() {
        let stored = event(tier: "tier_from_before", credits: (used: 1_000, constrained: nil, unused: 3_000), weekly: true)
        let summary = service.aggregateBreakdown(events: [stored])

        #expect(summary.usedCredits == 1_000)
        #expect(summary.unusedCredits == 3_000)
        #expect(summary.weeklyCycleCount == 1)
    }

    @Test("A weekly cycle that cannot be analysed adds no capacity")
    func unresolvableWeeklyCycle() throws {
        let events = [
            event(id: 1, daysAgo: 7, tier: "unknown", weekly: true),
            event(id: 2, weekly: true)
        ]
        let value = try #require(SubscriptionValueCalculator.calculate(
            resetEvents: events, creditLimits: pro, timeRange: .all, headroomAnalysisService: service
        ))

        #expect(approximately(value.utilizationPercent, 70))
        #expect(approximately(value.totalAvailableCredits, 5_000_000))
    }

    @Test("Five cycles in a 30-day range are priced at 30 days and keep their utilization")
    func fiveCyclesInAMonth() throws {
        let events = (0..<5).map { event(id: Int64($0), daysAgo: Double(28 - $0 * 7), weekly: true) }
        let value = try #require(SubscriptionValueCalculator.calculate(
            resetEvents: events, creditLimits: pro, timeRange: .month, headroomAnalysisService: service
        ))

        #expect(approximately(value.utilizationPercent, 70))
        #expect(approximately(value.periodPrice, 20 * 30 / SubscriptionValueCalculator.averageDaysPerMonth))
    }

    @Test("Values over 100 or not finite stay inside the bands")
    func clamping() {
        let over = HeadroomBreakdown.weeklyCycle(sevenDayPeak: 104, creditLimits: pro)
        #expect(over.usedPercent == 100)
        #expect(over.unusedPercent == 0)
        #expect(over.unusedCredits == 0)

        let notFinite = HeadroomBreakdown.weeklyCycle(sevenDayPeak: .nan, creditLimits: pro)
        #expect(notFinite.usedPercent == 0)

        let fiveHour = service.analyzeResetEvent(fiveHourPeak: 50, sevenDayUtil: 104, creditLimits: pro)
        #expect(fiveHour.unusedCredits == 0)
        #expect(approximately(fiveHour.constrainedCredits, 275_000))

        let overPeak = service.analyzeResetEvent(fiveHourPeak: 104, sevenDayUtil: 10, creditLimits: pro)
        #expect(overPeak.usedPercent == 100)
        #expect(overPeak.unusedCredits == 0)
    }

    @Test("A 5-hour event with stored credits counts them when its tier is unknown")
    func storedCreditsUnknownTier() {
        let stored = event(fiveHourPeak: 60, tier: "unknown", credits: (used: 100, constrained: 20, unused: 30))
        let summary = service.aggregateBreakdown(events: [stored])

        #expect(summary.resetCount == 1)
        #expect(summary.usedCredits == 100)
        #expect(summary.constrainedCredits == 20)
        #expect(summary.unusedCredits == 30)
    }

    @Test("A 5-hour event with a known tier is recomputed from current limits, as in 1.6.0")
    func fiveHourRecomputedWhenTierKnown() {
        let stored = event(fiveHourPeak: 60, sevenDayUtil: 30, credits: (used: 100, constrained: 20, unused: 30))
        let expected = service.analyzeResetEvent(fiveHourPeak: 60, sevenDayUtil: 30, creditLimits: RateLimitTier.pro.creditLimits)
        #expect(service.aggregateBreakdown(events: [stored]).usedCredits == expected.usedCredits)

        let custom = event(fiveHourPeak: 60, sevenDayUtil: 30, tier: "unmapped_tier", credits: (used: 100, constrained: 20, unused: 30))
        let preferences = MockPreferencesManager()
        preferences.customFiveHourCredits = 1_000_000
        preferences.customSevenDayCredits = 10_000_000
        let edited = HeadroomAnalysisService(preferencesManager: preferences)
        #expect(edited.aggregateBreakdown(events: [custom]).usedCredits == 600_000)
    }

    @Test("The overlap is removed before grouping by month")
    func overlapBeforeMonthGrouping() {
        let calendar = Calendar.current
        func ms(_ month: Int, _ day: Int) -> Int64 {
            let date = calendar.date(from: DateComponents(year: 2025, month: month, day: day, hour: 12))!
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        let inJanuary = event(id: 1, from: ms(1, 5), fiveHourPeak: 40, sevenDayUtil: 10)
        let overlapping = event(id: 2, from: ms(1, 30), fiveHourPeak: 90, sevenDayUtil: 10)
        let weekly = (0..<3).map { event(id: Int64($0 + 3), from: ms($0 + 2, 2), weekly: true) }
        let events = [inJanuary, overlapping] + weekly

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: events, creditLimits: pro, billingCycleDay: nil, headroomAnalysisService: service
        )
        #expect(cycles.map(\.resetCount) == [1, 1, 1, 1])
        #expect(cycles.dropFirst().allSatisfy { approximately($0.utilizationPercent, 70) })

        let monthly = ValueInsightEngine.computeMonthlyUtilizations(
            events: events, creditLimits: pro, headroomAnalysisService: service
        )
        let withoutOverlapping = ValueInsightEngine.computeMonthlyUtilizations(
            events: [inJanuary] + weekly, creditLimits: pro, headroomAnalysisService: service
        )
        #expect(monthly == withoutOverlapping)
    }

    @Test("The overlap is removed before grouping by billing cycle")
    func overlapBeforeBillingGrouping() {
        func ms(_ month: Int, _ day: Int) -> Int64 {
            let date = Calendar.current.date(from: DateComponents(year: 2025, month: month, day: day, hour: 12))!
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        let overlapping = event(id: 1, from: ms(1, 14), fiveHourPeak: 90, sevenDayUtil: 10)
        let kept = event(id: 2, from: ms(1, 2), fiveHourPeak: 40, sevenDayUtil: 10)
        let weekly = (0..<3).map { event(id: Int64($0 + 3), from: ms($0 + 1, 16), weekly: true) }

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: [kept, overlapping] + weekly,
            creditLimits: pro,
            billingCycleDay: 15,
            headroomAnalysisService: service
        )
        #expect(cycles.map(\.resetCount) == [1, 1, 1, 1])
    }

    @Test("Capacity for a week between 5-hour events is counted once")
    func cycleBetweenFiveHourEvents() {
        let events = [
            event(id: 1, daysAgo: 30, fiveHourPeak: 40, sevenDayUtil: 10),
            event(id: 2, daysAgo: 15, weekly: true),
            event(id: 3, fiveHourPeak: 40, sevenDayUtil: 10)
        ]

        #expect(SubscriptionValueCalculator.periodDays(for: .all, events: events) == 30)
        #expect(SubscriptionValueCalculator.periodDays(for: .month, events: events) == 30)
        #expect(AnalyticsView.computeDataSpanHours(resetEvents: events) == 30 * 24)
    }

    @Test("Old empty-peak rows do not dilute a weekly cycle or change its wording")
    func oldEmptyPeakRows() throws {
        let events = [
            event(id: 1, daysAgo: 35, sevenDayUtil: 20),
            event(id: 2, daysAgo: 14, sevenDayUtil: 20),
            event(id: 3, weekly: true)
        ]
        let value = try #require(SubscriptionValueCalculator.calculate(
            resetEvents: events, creditLimits: pro, timeRange: .all, headroomAnalysisService: service
        ))

        #expect(approximately(value.utilizationPercent, 70))
        #expect(events.isOnlyWeeklyCycles)
    }

    @Test("Weekly copy names the last cycle in every band, with and without a price", arguments: [10.0, 50.0, 90.0])
    func weeklyCopyBands(peak: Double) throws {
        let events = [event(sevenDayUtil: peak, weekly: true)]
        let priced = try #require(SubscriptionValueCalculator.calculate(
            resetEvents: events, creditLimits: pro, timeRange: .day, headroomAnalysisService: service
        ))
        let unpriced = CreditLimits(fiveHourCredits: 550_000, sevenDayCredits: 5_000_000)

        for range in [TimeRange.day, .week] {
            for (value, limits) in [(Optional(priced), pro), (nil, unpriced)] {
                let insight = ValueInsightEngine.computeInsight(
                    timeRange: range,
                    subscriptionValue: value,
                    resetEvents: events,
                    allTimeResetEvents: events,
                    creditLimits: limits,
                    headroomAnalysisService: service
                )
                #expect(insight.text.contains("last cycle"), "\(insight.text)")
                #expect(!insight.text.contains("today") && !insight.text.contains("week"), "\(insight.text)")
            }
        }
    }

    @Test("Two weekly cycles in one range are not called the last cycle")
    func twoCyclesCopy() {
        let cycles = [
            event(id: 1, daysAgo: 8, sevenDayUtil: 50, weekly: true),
            event(id: 2, daysAgo: 1, sevenDayUtil: 50, weekly: true)
        ]
        let unpriced = CreditLimits(fiveHourCredits: 550_000, sevenDayCredits: 5_000_000)
        let insight = ValueInsightEngine.computeInsight(
            timeRange: .week,
            subscriptionValue: nil,
            resetEvents: cycles,
            allTimeResetEvents: cycles,
            creditLimits: unpriced,
            headroomAnalysisService: service
        )
        #expect(insight.text.contains("last 2 cycles"), "\(insight.text)")
    }

    @Test("A 5-hour peak over 100 cannot push the average peak past 100")
    func clampedAveragePeak() {
        let summary = service.aggregateBreakdown(events: [event(id: 1, fiveHourPeak: 120, sevenDayUtil: 20)])
        #expect(summary.avgPeakUtilization == 100)
    }

    @Test("A weekly-only range speaks of the last cycle and shows the bar")
    func weeklyCopy() throws {
        let events = [event(weekly: true)]
        let value = SubscriptionValueCalculator.calculate(
            resetEvents: events, creditLimits: pro, timeRange: .day, headroomAnalysisService: service
        )

        for range in [TimeRange.day, .week] {
            let insight = ValueInsightEngine.computeInsight(
                timeRange: range,
                subscriptionValue: value,
                resetEvents: events,
                allTimeResetEvents: events,
                creditLimits: pro,
                headroomAnalysisService: service
            )
            #expect(insight.text == "Used $3.22 of $4.60 last cycle")
            #expect(AnalyticsView.showsFullBar(usageInsight: insight, resetEvents: events))
        }
    }

    @Test("Two cycles count as enough history to compare with the average")
    func weeklyDeviation() throws {
        let allTime = [event(id: 1, daysAgo: 7, sevenDayUtil: 10, weekly: true), event(id: 2, sevenDayUtil: 90, weekly: true)]
        let current = [allTime[1]]
        let insight = ValueInsightEngine.computeInsight(
            timeRange: .week,
            subscriptionValue: nil,
            resetEvents: current,
            allTimeResetEvents: allTime,
            creditLimits: pro,
            headroomAnalysisService: service
        )

        #expect(insight.text.hasPrefix("Last cycle: "))
    }

    @Test("A range whose only counted events are weekly cycles reads as weekly")
    func overlapOnlyLeavesWeekly() {
        let events = [event(id: 1, daysAgo: 1, fiveHourPeak: 40, sevenDayUtil: 10), event(id: 2, weekly: true)]

        #expect(events.isOnlyWeeklyCycles)
        #expect(![event(fiveHourPeak: 40)].isOnlyWeeklyCycles)
        #expect(![ResetEvent]().isOnlyWeeklyCycles)
    }

    @Test("VoiceOver speaks two bands for weekly cycles")
    func voiceOverLabel() {
        let events = [event(weekly: true)]

        #expect(HeadroomBreakdownBar.usageAccessibilityLabel(events: events, utilizationPercent: 70)
            == "Headroom breakdown: 70% used, 30% unused capacity.")
        #expect(HeadroomBreakdownBar.usageAccessibilityLabel(events: events, utilizationPercent: 70, dollars: ("$3.22", "$4.60"))
            == "Headroom breakdown: 70% used, 30% unused capacity. $3.22 used of $4.60.")
    }

    @Test("Data span adds a week per weekly cycle")
    func dataSpan() {
        #expect(AnalyticsView.computeDataSpanHours(resetEvents: [event(weekly: true)]) == 168)
        let mixed = [
            event(id: 1, daysAgo: 20, fiveHourPeak: 40, sevenDayUtil: 10),
            event(id: 2, daysAgo: 19, fiveHourPeak: 40, sevenDayUtil: 10),
            event(id: 3, weekly: true)
        ]
        #expect(AnalyticsView.computeDataSpanHours(resetEvents: mixed) == 24 + 168)
    }
}

/// Expected values are worked by hand from the 1.6.0 formulas, so these fail if the path changes.
@Suite("Accounts with a number match 1.6.0")
@MainActor
struct NumberAccountUnchangedTests {
    private let service = HeadroomAnalysisService()
    private let pro = RateLimitTier.pro.creditLimits

    private var events: [ResetEvent] {
        [
            event(id: 1, daysAgo: 14, fiveHourPeak: 60, sevenDayUtil: 30),
            event(id: 2, daysAgo: 7, fiveHourPeak: nil, sevenDayUtil: 31),
            event(id: 3, fiveHourPeak: 10, sevenDayUtil: 95)
        ]
    }

    @Test("Aggregate, with an empty-peak event among real ones")
    func aggregate() {
        let summary = service.aggregateBreakdown(events: events)

        #expect(summary.resetCount == 2)
        #expect(summary.weeklyCycleCount == 0)
        #expect(approximately(summary.usedCredits, 385_000))
        #expect(approximately(summary.constrainedCredits, 245_000))
        #expect(approximately(summary.unusedCredits, 470_000))
        #expect(approximately(summary.usedPercent, 35))
        #expect(summary.avgPeakUtilization == 35)
    }

    @Test("Value and capacity follow the span of events, including the empty-peak one")
    func value() throws {
        let value = try #require(SubscriptionValueCalculator.calculate(
            resetEvents: events, creditLimits: pro, timeRange: .all, headroomAnalysisService: service
        ))

        #expect(SubscriptionValueCalculator.periodDays(for: .all, events: events) == 14)
        #expect(SubscriptionValueCalculator.periodDays(for: .week, events: events) == 7)
        #expect(SubscriptionValueCalculator.periodDays(for: .day, events: events) == 1)
        #expect(value.totalAvailableCredits == 10_000_000)
        #expect(approximately(value.utilizationPercent, 3.85))
        #expect(approximately(value.periodPrice, 20 * 14 / SubscriptionValueCalculator.averageDaysPerMonth))
    }

    @Test("Copy, labels and bar visibility keep their wording")
    func wording() throws {
        let value = SubscriptionValue(
            usedCredits: 0, totalAvailableCredits: 1, utilizationPercent: 50,
            periodPrice: 2, usedDollars: 1, unusedDollars: 1, monthlyPrice: 20
        )
        let day = ValueInsightEngine.computeInsight(
            timeRange: .day, subscriptionValue: value, resetEvents: events, allTimeResetEvents: events,
            creditLimits: pro, headroomAnalysisService: service
        )
        #expect(day.text == "Used $1.00 of $2.00 today")
        #expect(day.isQuiet)
        #expect(!AnalyticsView.showsFullBar(usageInsight: day, resetEvents: events))

        let recent = Array(events.suffix(1))
        let week = ValueInsightEngine.computeInsight(
            timeRange: .week, subscriptionValue: value, resetEvents: recent, allTimeResetEvents: recent,
            creditLimits: pro, headroomAnalysisService: service
        )
        #expect(week.text == "Used $1.00 of $2.00 this week")

        #expect(HeadroomBreakdownBar.usageAccessibilityLabel(events: events, utilizationPercent: 50)
            == "Subscription usage: 50% utilization")
        #expect(HeadroomBreakdownBar.usageAccessibilityLabel(events: events, utilizationPercent: 50, dollars: ("$1.00", "$2.00"))
            == "Subscription usage: $1.00 used of $2.00, 50% utilization")
        #expect(AnalyticsView.computeDataSpanHours(resetEvents: events) == 14 * 24)
    }

    @Test("Month and all-time figures keep their results")
    func monthAndAll() throws {
        func ms(_ month: Int, _ day: Int) -> Int64 {
            let date = Calendar.current.date(from: DateComponents(year: 2025, month: month, day: day, hour: 12))!
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        // Each month runs 27 days from first to last event, and the empty-peak row adds no usage.
        var events: [ResetEvent] = []
        for month in 1...3 {
            let base = Int64(month * 10)
            events.append(event(id: base, from: ms(month, 1), fiveHourPeak: 60, sevenDayUtil: 30))
            events.append(event(id: base + 1, from: ms(month, 15), fiveHourPeak: nil, sevenDayUtil: 30))
            events.append(event(id: base + 2, from: ms(month, 28), fiveHourPeak: 40, sevenDayUtil: 30))
        }
        let days = 27.0
        let expected = 550_000.0 / (5_000_000.0 * days / 7.0) * 100.0

        let cycles = CycleUtilizationCalculator.computeCycles(
            resetEvents: events, creditLimits: pro, billingCycleDay: nil, headroomAnalysisService: service
        )
        #expect(cycles.map(\.resetCount) == [3, 3, 3])
        #expect(cycles.allSatisfy { approximately($0.utilizationPercent, expected) })

        let monthly = ValueInsightEngine.computeMonthlyUtilizations(events: events, creditLimits: pro, headroomAnalysisService: service)
        #expect(monthly.count == 3)
        #expect(monthly.allSatisfy { approximately($0, expected) })

        let all = ValueInsightEngine.computeInsight(
            timeRange: .all, subscriptionValue: nil, resetEvents: events, allTimeResetEvents: events,
            creditLimits: pro, headroomAnalysisService: service
        )
        #expect(all.text == "Light average monthly usage")

        let month = ValueInsightEngine.computeInsight(
            timeRange: .month, subscriptionValue: nil, resetEvents: Array(events.prefix(3)), allTimeResetEvents: events,
            creditLimits: pro, headroomAnalysisService: service
        )
        #expect(month.text == "Light usage this month")
    }

    @Test("Stored credits from recording equal what 1.6.0 computed for them")
    func storedMatchesComputed() {
        let computed = service.analyzeResetEvent(fiveHourPeak: 10, sevenDayUtil: 95, creditLimits: pro)
        let stored = event(fiveHourPeak: 10, sevenDayUtil: 95, credits: (computed.usedCredits, computed.constrainedCredits, computed.unusedCredits))

        #expect(service.aggregateBreakdown(events: [stored]) == service.aggregateBreakdown(events: [event(fiveHourPeak: 10, sevenDayUtil: 95)]))
    }
}
