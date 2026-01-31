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
}
