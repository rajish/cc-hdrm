import Foundation
import SQLite3
import Testing
@testable import cc_hdrm

@Suite("WeeklySparklineData Tests")
struct WeeklySparklineDataTests {

    private let hourMs: Int64 = 3_600_000
    private let cycle: ClosedRange<Int64> = 1_000_000_000...1_604_800_000

    private func raw(_ timestamp: Int64, weekly: Double? = 10, fiveHour: Double? = 80) -> UsagePoll {
        UsagePoll(id: 1, timestamp: timestamp, fiveHourUtil: fiveHour, fiveHourResetsAt: timestamp + 1, sevenDayUtil: weekly, sevenDayResetsAt: timestamp + 2)
    }

    private func rollup(_ start: Int64, peak: Double? = 10) -> UsageRollup {
        UsageRollup(id: 1, periodStart: start, periodEnd: start + 300_000, resolution: .fiveMin, fiveHourAvg: 80, fiveHourPeak: 80, fiveHourMin: 80, sevenDayAvg: 5, sevenDayPeak: peak, sevenDayMin: 1, resetCount: 0, unusedCredits: nil)
    }

    // MARK: - Cycle

    @Test("cycle runs from 7 days before the reset to the reset")
    func cycleFromResetTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetsAt = now.addingTimeInterval(4 * 86400)
        let result = WeeklySparklineData.cycle(resetsAt: resetsAt, now: now)
        let dayMs: Int64 = 86_400_000
        let nowMs: Int64 = 1_000_000_000
        #expect(result?.lowerBound == nowMs - 3 * dayMs)
        #expect(result?.upperBound == nowMs + 4 * dayMs)
    }

    @Test("no cycle when the reset is unknown, passed, or further away than a week")
    func noCycle() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(WeeklySparklineData.cycle(resetsAt: nil, now: now) == nil)
        #expect(WeeklySparklineData.cycle(resetsAt: now, now: now) == nil)
        #expect(WeeklySparklineData.cycle(resetsAt: now.addingTimeInterval(-1), now: now) == nil)
        #expect(WeeklySparklineData.cycle(resetsAt: now.addingTimeInterval(8 * 86400), now: now) == nil)
    }

    // MARK: - Merge

    @Test("rollups before the first raw poll come first, in order, using the weekly peak")
    func mergeRollupsThenRaw() {
        let start = cycle.lowerBound
        let points = WeeklySparklineData.merge(
            rawPolls: [raw(start + 2 * hourMs, weekly: 30)],
            rollups: [rollup(start + hourMs, peak: 20)],
            cycle: cycle
        )
        #expect(points.map(\.timestamp) == [start + hourMs, start + 2 * hourMs])
        #expect(points.map(\.sevenDayUtil) == [20, 30])
    }

    @Test("the copies of recent raw polls inside the rollup list are not added twice")
    func mergeDropsDuplicates() {
        let start = cycle.lowerBound
        let copy = start + 2 * hourMs
        let points = WeeklySparklineData.merge(
            rawPolls: [raw(copy), raw(start + 3 * hourMs)],
            rollups: [rollup(start + hourMs), rollup(copy), rollup(start + 3 * hourMs)],
            cycle: cycle
        )
        #expect(points.map(\.timestamp) == [start + hourMs, copy, start + 3 * hourMs])
    }

    @Test("raw polls older than 24 hours that were never rolled up are kept")
    func mergeKeepsOldRaw() {
        let start = cycle.lowerBound
        let points = WeeklySparklineData.merge(rawPolls: [raw(start + hourMs), raw(start + 72 * hourMs)], rollups: [], cycle: cycle)
        #expect(points.count == 2)
    }

    @Test("a raw poll from before the cycle does not hide rollups inside the cycle")
    func mergeIgnoresRawBeforeCycle() {
        let start = cycle.lowerBound
        let points = WeeklySparklineData.merge(
            rawPolls: [raw(start - hourMs), raw(start + 2 * hourMs)],
            rollups: [rollup(start + hourMs)],
            cycle: cycle
        )
        #expect(points.map(\.timestamp) == [start + hourMs, start + 2 * hourMs])
    }

    @Test("rows outside the cycle and rows with no weekly number are dropped")
    func mergeFilters() {
        let start = cycle.lowerBound
        let points = WeeklySparklineData.merge(
            rawPolls: [raw(start + 3 * hourMs, weekly: nil), raw(start + 4 * hourMs)],
            rollups: [rollup(start - hourMs), rollup(start + hourMs, peak: nil)],
            cycle: cycle
        )
        #expect(points.map(\.timestamp) == [start + 4 * hourMs])
    }

    @Test("points carry no 5-hour fields, so an account that changed state draws no 5-hour reset")
    func mergeStripsFiveHour() {
        let points = WeeklySparklineData.merge(rawPolls: [raw(cycle.lowerBound + hourMs)], rollups: [rollup(cycle.lowerBound)], cycle: cycle)
        #expect(points.allSatisfy { $0.fiveHourUtil == nil && $0.fiveHourResetsAt == nil })
    }

    @Test("a full week of 10-second polls thins to one point per 5 minutes")
    func mergeThins() {
        let start = cycle.lowerBound
        let polls = stride(from: start, to: cycle.upperBound, by: 10_000).map { raw($0) }
        let points = WeeklySparklineData.merge(rawPolls: polls, rollups: [], cycle: cycle)
        #expect(polls.count == 60_480)
        #expect(points.count <= 2017)
        #expect(points.last?.timestamp == polls.last?.timestamp)
    }

    // MARK: - Appending

    @Test("a reading in the same bucket replaces the last point; a later bucket adds one")
    func appendingBuckets() {
        let bucket = WeeklySparklineData.bucketMs
        let first = WeeklySparklineData.appending(timestamp: bucket, utilization: 10, to: [])
        let same = WeeklySparklineData.appending(timestamp: bucket + 1000, utilization: 11, to: first)
        #expect(same.count == 1)
        #expect(same.last?.sevenDayUtil == 11)

        let next = WeeklySparklineData.appending(timestamp: 2 * bucket, utilization: 12, to: same)
        #expect(next.map(\.sevenDayUtil) == [11, 12])
    }

    @Test("an out-of-range reading does not replace a good point in its bucket")
    func outOfRangeKeepsGoodPoint() {
        let bucket = WeeklySparklineData.bucketMs
        let first = WeeklySparklineData.appending(timestamp: bucket, utilization: 90, to: [])
        let result = WeeklySparklineData.appending(timestamp: bucket + 1000, utilization: 101, to: first)
        #expect(result == first)
    }

    @Test("a reading no newer than the last point is ignored")
    func appendingOlderIgnored() {
        let first = WeeklySparklineData.appending(timestamp: 1000, utilization: 10, to: [])
        let result = WeeklySparklineData.appending(timestamp: 1000, utilization: 99, to: first)
        #expect(result == first)
    }

    // MARK: - Real Database

    @Test("the chart covers the cycle before and after rollups run, with no duplicates")
    func realDatabaseBeforeAndAfterRollups() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).db")
        let manager = DatabaseManager(databasePath: path)
        defer {
            manager.closeConnection()
            try? FileManager.default.removeItem(at: path)
        }
        try manager.ensureSchema()
        let service = HistoricalDataService(databaseManager: manager)
        let connection = try manager.getConnection()

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let days3Ago = now - 72 * hourMs
        let hours30Ago = now - 30 * hourMs
        let hours2Ago = now - 2 * hourMs
        for (timestamp, weekly) in [(days3Ago, 10.0), (hours30Ago, 20.0), (hours2Ago, 30.0)] {
            sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, seven_day_util) VALUES (\(timestamp), \(weekly))", nil, nil, nil)
        }
        let cycle = (now - 96 * hourMs)...(now + 72 * hourMs)

        // The week query alone cannot see raw polls older than 24 hours
        let weekOnly = try await service.getRolledUpData(range: .week)
        #expect(weekOnly.count == 1)

        let beforeRaw = try await service.getRecentPolls(hours: 96)
        let beforeRollups = try await service.getRolledUpData(range: .week)
        let before = WeeklySparklineData.merge(rawPolls: beforeRaw, rollups: beforeRollups, cycle: cycle)
        #expect(before.map(\.sevenDayUtil) == [10, 20, 30])

        try await service.ensureRollupsUpToDate()

        let afterRaw = try await service.getRecentPolls(hours: 96)
        #expect(afterRaw.count == 1)
        let afterRollups = try await service.getRolledUpData(range: .week)
        let after = WeeklySparklineData.merge(rawPolls: afterRaw, rollups: afterRollups, cycle: cycle)
        #expect(after.map(\.sevenDayUtil) == [10, 20, 30])
    }
}
