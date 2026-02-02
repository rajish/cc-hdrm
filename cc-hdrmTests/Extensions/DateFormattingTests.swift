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

    // MARK: - countdownString Tests (Story 3.2, Task 7)

    @Test("resetsAt 30 minutes from now → 30m")
    func countdown30Minutes() {
        let date = Date().addingTimeInterval(30 * 60 + 10) // +10s buffer for test execution
        #expect(date.countdownString() == "30m")
    }

    @Test("resetsAt 47 minutes from now → 47m")
    func countdown47Minutes() {
        let date = Date().addingTimeInterval(47 * 60 + 10)
        #expect(date.countdownString() == "47m")
    }

    @Test("resetsAt 59 minutes from now → 59m")
    func countdown59Minutes() {
        let date = Date().addingTimeInterval(59 * 60 + 10)
        #expect(date.countdownString() == "59m")
    }

    @Test("resetsAt 1 hour from now → 1h 0m")
    func countdown1Hour() {
        let date = Date().addingTimeInterval(60 * 60 + 10)
        #expect(date.countdownString() == "1h 0m")
    }

    @Test("resetsAt 2h 13m from now → 2h 13m")
    func countdown2h13m() {
        let date = Date().addingTimeInterval(2 * 3600 + 13 * 60 + 10)
        #expect(date.countdownString() == "2h 13m")
    }

    @Test("resetsAt 23h 59m from now → 23h 59m")
    func countdown23h59m() {
        let date = Date().addingTimeInterval(23 * 3600 + 59 * 60 + 10)
        #expect(date.countdownString() == "23h 59m")
    }

    @Test("resetsAt 25h from now → 1d 1h")
    func countdown25h() {
        let date = Date().addingTimeInterval(25 * 3600 + 10)
        #expect(date.countdownString() == "1d 1h")
    }

    @Test("resetsAt 49h from now → 2d 1h")
    func countdown49h() {
        let date = Date().addingTimeInterval(49 * 3600 + 10)
        #expect(date.countdownString() == "2d 1h")
    }

    @Test("resetsAt in the past → 0m")
    func countdownPast() {
        let date = Date().addingTimeInterval(-60)
        #expect(date.countdownString() == "0m")
    }

    @Test("resetsAt exactly now → 0m")
    func countdownNow() {
        let date = Date()
        #expect(date.countdownString() == "0m")
    }

    // MARK: - absoluteTimeString Tests (Story 4.2, Task 3)

    @Test("absoluteTimeString for same-day date produces 'at H:mm a' format")
    func absoluteTimeSameDay() {
        // Create a date today at 4:52 PM local time
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 16
        components.minute = 52
        let date = Calendar.current.date(from: components)!

        let result = date.absoluteTimeString()
        #expect(result.hasPrefix("at "))
        // Should NOT contain a weekday abbreviation for same-day
        let withoutAt = String(result.dropFirst(3))
        // Same-day format: "4:52 PM" — no weekday
        #expect(withoutAt.contains(":"))
        #expect(withoutAt.lowercased().contains("m")) // AM/PM or am/pm
    }

    @Test("absoluteTimeString for different-day date produces 'at EEE H:mm a' format")
    func absoluteTimeDifferentDay() {
        // Create a date 2 days from now
        let date = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let result = date.absoluteTimeString()
        #expect(result.hasPrefix("at "))
        // Different-day format should include weekday abbreviation (3 chars like Mon, Tue)
        let withoutAt = String(result.dropFirst(3))
        #expect(withoutAt.contains(":"))
        #expect(withoutAt.lowercased().contains("m")) // AM/PM or am/pm
        // Should have a weekday prefix (e.g. "Mon ", "Tue ")
        let parts = withoutAt.split(separator: " ")
        #expect(parts.count >= 3, "Expected weekday + time + AM/PM, got: \(withoutAt)")
    }
}
