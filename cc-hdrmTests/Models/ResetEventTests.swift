import Foundation
import Testing
@testable import cc_hdrm

@Suite("ResetEvent Tests")
struct ResetEventTests {

    @Test("ResetEvent stores all values correctly")
    func storesAllValues() {
        let event = ResetEvent(
            id: 1,
            timestamp: 1706976000000,
            fiveHourPeak: 85.5,
            sevenDayUtil: 42.3,
            tier: "default_claude_max_5x",
            usedCredits: 1000.0,
            constrainedCredits: 200.0,
            unusedCredits: 50.0
        )

        #expect(event.id == 1)
        #expect(event.timestamp == 1706976000000)
        #expect(event.fiveHourPeak == 85.5)
        #expect(event.sevenDayUtil == 42.3)
        #expect(event.tier == "default_claude_max_5x")
        #expect(event.usedCredits == 1000.0)
        #expect(event.constrainedCredits == 200.0)
        #expect(event.unusedCredits == 50.0)
    }

    @Test("ResetEvent handles nil values correctly")
    func handlesNilValues() {
        let event = ResetEvent(
            id: 2,
            timestamp: 1706976000000,
            fiveHourPeak: nil,
            sevenDayUtil: nil,
            tier: nil,
            usedCredits: nil,
            constrainedCredits: nil,
            unusedCredits: nil
        )

        #expect(event.id == 2)
        #expect(event.timestamp == 1706976000000)
        #expect(event.fiveHourPeak == nil)
        #expect(event.sevenDayUtil == nil)
        #expect(event.tier == nil)
        #expect(event.usedCredits == nil)
        #expect(event.constrainedCredits == nil)
        #expect(event.unusedCredits == nil)
    }

    @Test("ResetEvent equality works correctly")
    func equalityWorks() {
        let event1 = ResetEvent(
            id: 1,
            timestamp: 1706976000000,
            fiveHourPeak: 85.5,
            sevenDayUtil: 42.3,
            tier: "default",
            usedCredits: nil,
            constrainedCredits: nil,
            unusedCredits: nil
        )

        let event2 = ResetEvent(
            id: 1,
            timestamp: 1706976000000,
            fiveHourPeak: 85.5,
            sevenDayUtil: 42.3,
            tier: "default",
            usedCredits: nil,
            constrainedCredits: nil,
            unusedCredits: nil
        )

        let event3 = ResetEvent(
            id: 2,
            timestamp: 1706976000000,
            fiveHourPeak: 85.5,
            sevenDayUtil: 42.3,
            tier: "default",
            usedCredits: nil,
            constrainedCredits: nil,
            unusedCredits: nil
        )

        #expect(event1 == event2)
        #expect(event1 != event3)
    }

    @Test("ResetEvent conforms to Sendable")
    func conformsToSendable() {
        let event = ResetEvent(
            id: 1,
            timestamp: 1706976000000,
            fiveHourPeak: 85.5,
            sevenDayUtil: nil,
            tier: nil,
            usedCredits: nil,
            constrainedCredits: nil,
            unusedCredits: nil
        )

        // If this compiles, ResetEvent is Sendable
        Task {
            _ = event
        }
    }

    // MARK: - isWeeklyCycle

    private func makeEvent(timestamp: Int64, fiveHourPeak: Double?, sevenDayUtil: Double?) -> ResetEvent {
        ResetEvent(
            id: 1, timestamp: timestamp, fiveHourPeak: fiveHourPeak, sevenDayUtil: sevenDayUtil,
            tier: "default_claude_pro", usedCredits: nil, constrainedCredits: nil, unusedCredits: nil
        )
    }

    @Test("Cutover constant is 2026-10-31 08:03 UTC")
    func cutoverTimestamp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 8, minute: 3))!
        #expect(ResetEvent.fiveHourLimitRetiredAtMs == Int64(date.timeIntervalSince1970 * 1000))
    }

    @Test("Post-cutover event without 5h peak and with 7d util is a weekly cycle")
    func weeklyCyclePostCutover() {
        let cutover = ResetEvent.fiveHourLimitRetiredAtMs
        #expect(makeEvent(timestamp: cutover, fiveHourPeak: nil, sevenDayUtil: 70).isWeeklyCycle)
        #expect(makeEvent(timestamp: cutover + 86_400_000, fiveHourPeak: nil, sevenDayUtil: 0).isWeeklyCycle)
    }

    @Test("Pre-cutover peak-nil event is not a weekly cycle")
    func preCutoverPeakNilIsNotWeekly() {
        let event = makeEvent(timestamp: ResetEvent.fiveHourLimitRetiredAtMs - 1, fiveHourPeak: nil, sevenDayUtil: 70)
        #expect(!event.isWeeklyCycle)
    }

    @Test("Event with a 5h peak or without 7d util is not a weekly cycle")
    func peakOrMissingWeeklyIsNotWeekly() {
        let after = ResetEvent.fiveHourLimitRetiredAtMs + 1
        #expect(!makeEvent(timestamp: after, fiveHourPeak: 72, sevenDayUtil: 70).isWeeklyCycle)
        #expect(!makeEvent(timestamp: after, fiveHourPeak: nil, sevenDayUtil: nil).isWeeklyCycle)
    }
}
