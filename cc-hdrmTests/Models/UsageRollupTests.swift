import Foundation
import Testing
@testable import cc_hdrm

@Suite("UsageRollup Tests")
struct UsageRollupTests {

    // MARK: - Model Tests

    @Test("UsageRollup conforms to Sendable")
    func conformsToSendable() {
        let rollup = UsageRollup(
            id: 1,
            periodStart: 1000,
            periodEnd: 2000,
            resolution: .fiveMin,
            fiveHourAvg: 50.0,
            fiveHourPeak: 60.0,
            fiveHourMin: 40.0,
            sevenDayAvg: 30.0,
            sevenDayPeak: 35.0,
            sevenDayMin: 25.0,
            resetCount: 2,
            unusedCredits: nil
        )
        let _: any Sendable = rollup
    }

    @Test("UsageRollup conforms to Equatable")
    func conformsToEquatable() {
        let rollup1 = UsageRollup(
            id: 1,
            periodStart: 1000,
            periodEnd: 2000,
            resolution: .fiveMin,
            fiveHourAvg: 50.0,
            fiveHourPeak: 60.0,
            fiveHourMin: 40.0,
            sevenDayAvg: 30.0,
            sevenDayPeak: 35.0,
            sevenDayMin: 25.0,
            resetCount: 2,
            unusedCredits: nil
        )
        let rollup2 = UsageRollup(
            id: 1,
            periodStart: 1000,
            periodEnd: 2000,
            resolution: .fiveMin,
            fiveHourAvg: 50.0,
            fiveHourPeak: 60.0,
            fiveHourMin: 40.0,
            sevenDayAvg: 30.0,
            sevenDayPeak: 35.0,
            sevenDayMin: 25.0,
            resetCount: 2,
            unusedCredits: nil
        )
        #expect(rollup1 == rollup2)
    }

    @Test("UsageRollup stores all fields correctly")
    func storesAllFieldsCorrectly() {
        let rollup = UsageRollup(
            id: 42,
            periodStart: 1706745600000,
            periodEnd: 1706745900000,
            resolution: .hourly,
            fiveHourAvg: 55.5,
            fiveHourPeak: 78.3,
            fiveHourMin: 32.1,
            sevenDayAvg: 42.0,
            sevenDayPeak: 65.0,
            sevenDayMin: 20.0,
            resetCount: 5,
            unusedCredits: 123.45
        )

        #expect(rollup.id == 42)
        #expect(rollup.periodStart == 1706745600000)
        #expect(rollup.periodEnd == 1706745900000)
        #expect(rollup.resolution == .hourly)
        #expect(rollup.fiveHourAvg == 55.5)
        #expect(rollup.fiveHourPeak == 78.3)
        #expect(rollup.fiveHourMin == 32.1)
        #expect(rollup.sevenDayAvg == 42.0)
        #expect(rollup.sevenDayPeak == 65.0)
        #expect(rollup.sevenDayMin == 20.0)
        #expect(rollup.resetCount == 5)
        #expect(rollup.unusedCredits == 123.45)
    }

    @Test("UsageRollup handles nil optional fields")
    func handlesNilOptionalFields() {
        let rollup = UsageRollup(
            id: 1,
            periodStart: 1000,
            periodEnd: 2000,
            resolution: .daily,
            fiveHourAvg: nil,
            fiveHourPeak: nil,
            fiveHourMin: nil,
            sevenDayAvg: nil,
            sevenDayPeak: nil,
            sevenDayMin: nil,
            resetCount: 0,
            unusedCredits: nil
        )

        #expect(rollup.fiveHourAvg == nil)
        #expect(rollup.fiveHourPeak == nil)
        #expect(rollup.fiveHourMin == nil)
        #expect(rollup.sevenDayAvg == nil)
        #expect(rollup.sevenDayPeak == nil)
        #expect(rollup.sevenDayMin == nil)
        #expect(rollup.unusedCredits == nil)
    }

    // MARK: - Resolution Enum Tests

    @Test("Resolution enum has correct raw values")
    func resolutionHasCorrectRawValues() {
        #expect(UsageRollup.Resolution.fiveMin.rawValue == "5min")
        #expect(UsageRollup.Resolution.hourly.rawValue == "hourly")
        #expect(UsageRollup.Resolution.daily.rawValue == "daily")
    }

    @Test("Resolution enum is CaseIterable")
    func resolutionIsCaseIterable() {
        let allCases = UsageRollup.Resolution.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.fiveMin))
        #expect(allCases.contains(.hourly))
        #expect(allCases.contains(.daily))
    }

    @Test("Resolution enum is Codable")
    func resolutionIsCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for resolution in UsageRollup.Resolution.allCases {
            let encoded = try encoder.encode(resolution)
            let decoded = try decoder.decode(UsageRollup.Resolution.self, from: encoded)
            #expect(resolution == decoded)
        }
    }

    @Test("Resolution enum is Sendable")
    func resolutionIsSendable() {
        let resolution: UsageRollup.Resolution = .fiveMin
        let _: any Sendable = resolution
    }
}

@Suite("TimeRange Tests")
struct TimeRangeTests {

    @Test("TimeRange is CaseIterable")
    func isCaseIterable() {
        let allCases = TimeRange.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.day))
        #expect(allCases.contains(.week))
        #expect(allCases.contains(.month))
        #expect(allCases.contains(.all))
    }

    @Test("TimeRange is Sendable")
    func isSendable() {
        let range: TimeRange = .week
        let _: any Sendable = range
    }

    @Test("TimeRange.day returns 24 hours ago timestamp")
    func dayReturns24HoursAgo() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let expectedMs = nowMs - (24 * 60 * 60 * 1000)
        let rangeStart = TimeRange.day.startTimestamp

        // Allow 1 second tolerance for test execution time
        #expect(abs(rangeStart - expectedMs) < 1000)
    }

    @Test("TimeRange.week returns 7 days ago timestamp")
    func weekReturns7DaysAgo() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let expectedMs = nowMs - (7 * 24 * 60 * 60 * 1000)
        let rangeStart = TimeRange.week.startTimestamp

        #expect(abs(rangeStart - expectedMs) < 1000)
    }

    @Test("TimeRange.month returns 30 days ago timestamp")
    func monthReturns30DaysAgo() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let expectedMs = nowMs - (30 * 24 * 60 * 60 * 1000)
        let rangeStart = TimeRange.month.startTimestamp

        #expect(abs(rangeStart - expectedMs) < 1000)
    }

    @Test("TimeRange.all returns 0")
    func allReturnsZero() {
        #expect(TimeRange.all.startTimestamp == 0)
    }
}
