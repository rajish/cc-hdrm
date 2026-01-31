import Foundation
import Testing
@testable import cc_hdrm

@Suite("Date+Formatting Tests")
struct DateFormattingTests {

    @Test("ISO 8601 with fractional seconds parses correctly")
    func fractionalSecondsParse() {
        let dateString = "2026-01-31T01:59:59.782798+00:00"
        let date = Date.fromISO8601(dateString)

        #expect(date != nil)

        // Verify the parsed date is roughly correct (Jan 31, 2026)
        if let date {
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
            #expect(components.year == 2026)
            #expect(components.month == 1)
            #expect(components.day == 31)
            #expect(components.hour == 1)
            #expect(components.minute == 59)
            #expect(components.second == 59)
        }
    }

    @Test("ISO 8601 with timezone offset parses correctly")
    func timezoneOffsetParse() {
        let dateString = "2026-02-06T08:59:59+00:00"
        let date = Date.fromISO8601(dateString)

        #expect(date != nil)

        if let date {
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
            #expect(components.year == 2026)
            #expect(components.month == 2)
            #expect(components.day == 6)
        }
    }

    @Test("ISO 8601 with Z suffix parses correctly")
    func zSuffixParse() {
        let dateString = "2026-01-31T12:00:00Z"
        let date = Date.fromISO8601(dateString)

        #expect(date != nil)
    }

    @Test("invalid string returns nil")
    func invalidStringReturnsNil() {
        #expect(Date.fromISO8601("not a date") == nil)
        #expect(Date.fromISO8601("") == nil)
        #expect(Date.fromISO8601("2026-13-45") == nil)
    }

    // MARK: - relativeTimeAgo Tests

    @Test("0 seconds ago returns 'just now'")
    func zeroSecondsAgoReturnsJustNow() {
        let date = Date()
        #expect(date.relativeTimeAgo() == "just now")
    }

    @Test("future date returns 'just now'")
    func futureDateReturnsJustNow() {
        let date = Date().addingTimeInterval(60)
        #expect(date.relativeTimeAgo() == "just now")
    }

    @Test("5 seconds ago returns seconds format")
    func fiveSecondsAgo() {
        let date = Date().addingTimeInterval(-5)
        #expect(date.relativeTimeAgo() == "5s ago")
    }

    @Test("45 seconds ago returns seconds format")
    func fortyFiveSecondsAgo() {
        let date = Date().addingTimeInterval(-45)
        #expect(date.relativeTimeAgo() == "45s ago")
    }

    @Test("90 seconds ago returns minutes format")
    func ninetySecondsAgo() {
        let date = Date().addingTimeInterval(-90)
        #expect(date.relativeTimeAgo() == "1m ago")
    }

    @Test("150 seconds ago returns minutes format")
    func oneHundredFiftySecondsAgo() {
        let date = Date().addingTimeInterval(-150)
        #expect(date.relativeTimeAgo() == "2m ago")
    }

    @Test("3720 seconds ago returns hours and minutes format")
    func threeThousandSevenHundredTwentySecondsAgo() {
        let date = Date().addingTimeInterval(-3720)
        #expect(date.relativeTimeAgo() == "1h 2m ago")
    }

    @Test("90000 seconds ago returns days and hours format")
    func ninetyThousandSecondsAgo() {
        let date = Date().addingTimeInterval(-90000)
        #expect(date.relativeTimeAgo() == "1d 1h ago")
    }
}
