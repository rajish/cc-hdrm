import Foundation
import Testing
@testable import cc_hdrm

@Suite("DataFreshness Tests")
struct DataFreshnessTests {

    @Test("nil lastUpdated returns .unknown")
    func nilLastUpdatedReturnsUnknown() {
        #expect(DataFreshness(lastUpdated: nil) == .unknown)
    }

    @Test("0 seconds ago returns .fresh")
    func zeroSecondsAgoReturnsFresh() {
        #expect(DataFreshness(lastUpdated: Date()) == .fresh)
    }

    @Test("30 seconds ago returns .fresh")
    func thirtySecondsAgoReturnsFresh() {
        let date = Date().addingTimeInterval(-30)
        #expect(DataFreshness(lastUpdated: date) == .fresh)
    }

    @Test("59 seconds ago returns .fresh")
    func fiftyNineSecondsAgoReturnsFresh() {
        let date = Date().addingTimeInterval(-59)
        #expect(DataFreshness(lastUpdated: date) == .fresh)
    }

    @Test("60 seconds ago returns .stale")
    func sixtySecondsAgoReturnsStale() {
        let date = Date().addingTimeInterval(-60)
        #expect(DataFreshness(lastUpdated: date) == .stale)
    }

    @Test("180 seconds ago returns .stale")
    func oneEightySecondsAgoReturnsStale() {
        let date = Date().addingTimeInterval(-180)
        #expect(DataFreshness(lastUpdated: date) == .stale)
    }

    @Test("299 seconds ago returns .stale")
    func twoNinetyNineSecondsAgoReturnsStale() {
        let date = Date().addingTimeInterval(-299)
        #expect(DataFreshness(lastUpdated: date) == .stale)
    }

    @Test("300 seconds ago returns .veryStale")
    func threeHundredSecondsAgoReturnsVeryStale() {
        let date = Date().addingTimeInterval(-300)
        #expect(DataFreshness(lastUpdated: date) == .veryStale)
    }

    @Test("600 seconds ago returns .veryStale")
    func sixHundredSecondsAgoReturnsVeryStale() {
        let date = Date().addingTimeInterval(-600)
        #expect(DataFreshness(lastUpdated: date) == .veryStale)
    }

    @Test("future date (negative elapsed) returns .fresh")
    func futureDateReturnsFresh() {
        let date = Date().addingTimeInterval(120)
        #expect(DataFreshness(lastUpdated: date) == .fresh)
    }
}
