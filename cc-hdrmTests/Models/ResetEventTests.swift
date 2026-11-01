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
}
