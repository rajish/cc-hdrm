import Foundation
import Testing
@testable import cc_hdrm

@Suite("UsagePoll Tests")
struct UsagePollTests {

    @Test("UsagePoll stores all values correctly")
    func storesAllValues() {
        let poll = UsagePoll(
            id: 1,
            timestamp: 1706976000000,
            fiveHourUtil: 45.5,
            fiveHourResetsAt: 1706979600000,
            sevenDayUtil: 23.1,
            sevenDayResetsAt: 1707580800000
        )

        #expect(poll.id == 1)
        #expect(poll.timestamp == 1706976000000)
        #expect(poll.fiveHourUtil == 45.5)
        #expect(poll.fiveHourResetsAt == 1706979600000)
        #expect(poll.sevenDayUtil == 23.1)
        #expect(poll.sevenDayResetsAt == 1707580800000)
    }

    @Test("UsagePoll handles nil values correctly")
    func handlesNilValues() {
        let poll = UsagePoll(
            id: 2,
            timestamp: 1706976000000,
            fiveHourUtil: nil,
            fiveHourResetsAt: nil,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )

        #expect(poll.id == 2)
        #expect(poll.timestamp == 1706976000000)
        #expect(poll.fiveHourUtil == nil)
        #expect(poll.fiveHourResetsAt == nil)
        #expect(poll.sevenDayUtil == nil)
        #expect(poll.sevenDayResetsAt == nil)
    }

    @Test("UsagePoll equality works correctly")
    func equalityWorks() {
        let poll1 = UsagePoll(
            id: 1,
            timestamp: 1706976000000,
            fiveHourUtil: 45.5,
            fiveHourResetsAt: 1706979600000,
            sevenDayUtil: 23.1,
            sevenDayResetsAt: 1707580800000
        )

        let poll2 = UsagePoll(
            id: 1,
            timestamp: 1706976000000,
            fiveHourUtil: 45.5,
            fiveHourResetsAt: 1706979600000,
            sevenDayUtil: 23.1,
            sevenDayResetsAt: 1707580800000
        )

        let poll3 = UsagePoll(
            id: 2,
            timestamp: 1706976000000,
            fiveHourUtil: 45.5,
            fiveHourResetsAt: 1706979600000,
            sevenDayUtil: 23.1,
            sevenDayResetsAt: 1707580800000
        )

        #expect(poll1 == poll2)
        #expect(poll1 != poll3)
    }

    @Test("UsagePoll conforms to Sendable")
    func conformsToSendable() {
        let poll = UsagePoll(
            id: 1,
            timestamp: 1706976000000,
            fiveHourUtil: 45.5,
            fiveHourResetsAt: nil,
            sevenDayUtil: nil,
            sevenDayResetsAt: nil
        )

        // If this compiles, UsagePoll is Sendable
        Task {
            _ = poll
        }
    }
}
