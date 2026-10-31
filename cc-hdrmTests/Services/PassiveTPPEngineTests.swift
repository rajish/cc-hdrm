import Foundation
import Testing
@testable import cc_hdrm

// MARK: - Test Mocks

private final class MockLogParser: ClaudeCodeLogParserProtocol, @unchecked Sendable {
    var scanCallCount = 0
    var tokensToReturn: [TokenAggregate] = []

    func scan() async {
        scanCallCount += 1
    }

    func getTokens(from start: Int64, to end: Int64, model: String?) -> [TokenAggregate] {
        if let model {
            return tokensToReturn.filter { $0.model == model }
        }
        return tokensToReturn
    }

    func getHealth() -> LogParserHealth {
        LogParserHealth(
            totalLinesProcessed: 0,
            successfulExtractions: 0,
            failedLines: 0,
            successRate: 100.0,
            lastScanTimestamp: Date(),
            filesScanned: 0
        )
    }
}

private final class MockPassiveTPPStorage: TPPStorageServiceProtocol, @unchecked Sendable {
    var storedMeasurements: [TPPMeasurement] = []
    var latestBenchmarkResult: TPPMeasurement?
    var lastTimestamp: Int64?

    func storeBenchmarkResult(_ measurement: TPPMeasurement) async throws {
        storedMeasurements.append(measurement)
    }

    func latestBenchmark(model: String, variant: String?) async throws -> TPPMeasurement? {
        return latestBenchmarkResult
    }

    func lastBenchmarkTimestamp() async throws -> Int64? {
        return lastTimestamp
    }

    func storePassiveResult(_ measurement: TPPMeasurement) async throws {
        storedMeasurements.append(measurement)
    }

    func getMeasurements(from: Int64, to: Int64, source: MeasurementSource?, model: String?, confidence: MeasurementConfidence?) async throws -> [TPPMeasurement] {
        return storedMeasurements.filter { $0.timestamp >= from && $0.timestamp <= to }
    }

    func getAverageTPP(from: Int64, to: Int64, model: String?, source: MeasurementSource?) async throws -> (fiveHour: Double?, sevenDay: Double?) {
        return (nil, nil)
    }

    func deleteBackfillRecords() async throws {
        storedMeasurements.removeAll { ($0.source == .passiveBackfill || $0.source == .rollupBackfill) && $0.fiveHourDelta == nil }
    }
}

// MARK: - Test Helpers

private func makePoll(
    timestamp: Int64,
    sevenDayUtil: Double?,
    fiveHourUtil: Double? = nil
) -> UsagePoll {
    UsagePoll(
        id: 0,
        timestamp: timestamp,
        fiveHourUtil: fiveHourUtil,
        fiveHourResetsAt: nil,
        sevenDayUtil: sevenDayUtil,
        sevenDayResetsAt: nil
    )
}

private func makeTokens(model: String, input: Int = 500, output: Int = 500, cacheCreate: Int = 0, cacheRead: Int = 0, messages: Int = 1) -> TokenAggregate {
    TokenAggregate(
        model: model,
        inputTokens: input,
        outputTokens: output,
        cacheCreateTokens: cacheCreate,
        cacheReadTokens: cacheRead,
        messageCount: messages
    )
}

private let oneHourMs: Int64 = 60 * 60 * 1000

// MARK: - Tests

@Suite("PassiveTPPEngine Tests")
struct PassiveTPPEngineTests {

    @Test("Weekly-only step: 1 percent weekly rise with 5h nil stores weekly TPP and leaves 5h fields nil")
    func weeklyOnlyStep() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 600, output: 400, cacheCreate: 400, cacheRead: 5000)]

        let prev = makePoll(timestamp: 1000, sevenDayUtil: 28.0)
        let curr = makePoll(timestamp: 2000, sevenDayUtil: 29.0)

        await engine.processPoll(current: curr, previous: prev)

        #expect(storage.storedMeasurements.count == 1)
        let m = storage.storedMeasurements[0]
        #expect(m.model == "claude-sonnet-4-6")
        #expect(m.source == .passive)
        #expect(m.sevenDayBefore == 28.0)
        #expect(m.sevenDayAfter == 29.0)
        #expect(m.sevenDayDelta == 1.0)
        #expect(m.tppSevenDay == 1500.0)  // (600 + 400 + 400 * 1.25) / 1%
        #expect(m.fiveHourBefore == nil)
        #expect(m.fiveHourAfter == nil)
        #expect(m.fiveHourDelta == nil)
        #expect(m.tppFiveHour == nil)
        #expect(m.windowStart == 1000)
        #expect(m.confidence == .low)
    }

    @Test("5h movement without weekly movement does not trigger a measurement")
    func fiveHourDeltaIgnored() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]

        let prev = makePoll(timestamp: 1000, sevenDayUtil: 28.0, fiveHourUtil: 10.0)
        let curr = makePoll(timestamp: 2000, sevenDayUtil: 28.0, fiveHourUtil: 15.0)

        await engine.processPoll(current: curr, previous: prev)

        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("Zero delta accumulation: tokens with 0 percent weekly delta are accumulated, not stored")
    func zeroDeltaAccumulation() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]

        let prev = makePoll(timestamp: 1000, sevenDayUtil: 28.0)
        let curr = makePoll(timestamp: 2000, sevenDayUtil: 28.0)

        await engine.processPoll(current: curr, previous: prev)

        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("Accumulate then flush: several flat polls then +1 percent stores one row with merged tokens")
    func accumulationFlush() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        // Three flat polls with tokens — accumulate
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 300, output: 200)]
        await engine.processPoll(current: makePoll(timestamp: 2000, sevenDayUtil: 28.0), previous: makePoll(timestamp: 1000, sevenDayUtil: 28.0))
        await engine.processPoll(current: makePoll(timestamp: 3000, sevenDayUtil: 28.0), previous: makePoll(timestamp: 2000, sevenDayUtil: 28.0))
        await engine.processPoll(current: makePoll(timestamp: 4000, sevenDayUtil: 28.0), previous: makePoll(timestamp: 3000, sevenDayUtil: 28.0))
        #expect(storage.storedMeasurements.isEmpty)

        // Weekly rises by 1% — flush accumulated + current
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 200, output: 300)]
        await engine.processPoll(current: makePoll(timestamp: 5000, sevenDayUtil: 29.0), previous: makePoll(timestamp: 4000, sevenDayUtil: 28.0))

        #expect(storage.storedMeasurements.count == 1)
        let m = storage.storedMeasurements[0]
        #expect(m.totalRawTokens == 2000)   // 3 × 500 accumulated + 500 current
        #expect(m.messageCount == 4)
        #expect(m.sevenDayBefore == 28.0)   // window start
        #expect(m.sevenDayDelta == 1.0)
        #expect(m.tppSevenDay == 2000.0)    // 2000 / 1%
        #expect(m.windowStart == 1000)      // Window started at the first poll
        #expect(m.tppFiveHour == nil)
    }

    @Test("Accumulation within the 6h cap keeps tokens")
    func accumulationWithinCap() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 500, output: 500)]
        let p1 = makePoll(timestamp: 1000, sevenDayUtil: 28.0)
        let p2 = makePoll(timestamp: 2000, sevenDayUtil: 28.0)
        await engine.processPoll(current: p2, previous: p1)

        // 5 hours later: still flat — within the 6h cap, tokens kept
        let p3 = makePoll(timestamp: 1000 + 5 * oneHourMs, sevenDayUtil: 28.0)
        await engine.processPoll(current: p3, previous: p2)

        let p4 = makePoll(timestamp: 1000 + 5 * oneHourMs + 1000, sevenDayUtil: 29.0)
        await engine.processPoll(current: p4, previous: p3)

        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].totalRawTokens == 3000)
        #expect(storage.storedMeasurements[0].windowStart == 1000)
    }

    @Test("6h cap: accumulation older than 6 hours restarts at the previous poll")
    func sixHourCap() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        // Start accumulation
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 500, output: 500)]
        let p1 = makePoll(timestamp: 1000, sevenDayUtil: 28.0)
        let p2 = makePoll(timestamp: 1000 + 2 * oneHourMs, sevenDayUtil: 28.0)
        await engine.processPoll(current: p2, previous: p1)

        // More than 6 hours later: another flat poll — cap and restart at p2
        let pastCap = 6 * oneHourMs + 60_000
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 100, output: 100)]
        let p3 = makePoll(timestamp: 1000 + pastCap, sevenDayUtil: 28.0)
        await engine.processPoll(current: p3, previous: p2)

        #expect(storage.storedMeasurements.isEmpty)

        // Now a delta comes — only tokens since the restart count
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 150, output: 150)]
        let p4 = makePoll(timestamp: 1000 + pastCap + 1000, sevenDayUtil: 29.0)
        await engine.processPoll(current: p4, previous: p3)

        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].totalRawTokens == 500)  // 200 (restarted) + 300 (current)
        #expect(storage.storedMeasurements[0].windowStart == p2.timestamp)  // Restarted at the previous poll
    }

    @Test("6h cap: a weekly step does not absorb tokens from a window older than the cap")
    func staleWindowNotFlushedByStep() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 500, output: 500)]
        let p1 = makePoll(timestamp: 1000, sevenDayUtil: 28.0)
        let p2 = makePoll(timestamp: 2000, sevenDayUtil: 28.0)
        await engine.processPoll(current: p2, previous: p1)

        // 7 hours of idle polls, then a step: the stale window must not be flushed
        logParser.tokensToReturn = []
        let p3 = makePoll(timestamp: 1000 + 7 * oneHourMs, sevenDayUtil: 28.0)
        await engine.processPoll(current: p3, previous: p2)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 150, output: 150)]
        let p4 = makePoll(timestamp: p3.timestamp + 1000, sevenDayUtil: 29.0)
        await engine.processPoll(current: p4, previous: p3)

        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].totalRawTokens == 300)
        #expect(storage.storedMeasurements[0].windowStart == p3.timestamp)
    }

    @Test("Weekly reset: any weekly decrease discards the window and stores nothing")
    func weeklyReset() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        // Start accumulation
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        let p1 = makePoll(timestamp: 1000, sevenDayUtil: 80.0)
        let p2 = makePoll(timestamp: 2000, sevenDayUtil: 80.0)
        await engine.processPoll(current: p2, previous: p1)

        // Weekly reset: drop from 80% to 79% — any decrease is a reset
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        let p3 = makePoll(timestamp: 3000, sevenDayUtil: 79.0)
        await engine.processPoll(current: p3, previous: p2)

        #expect(storage.storedMeasurements.isEmpty)

        // Next step starts fresh — only its own tokens, delta from new baseline
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 400, output: 600)]
        let p4 = makePoll(timestamp: 4000, sevenDayUtil: 80.0)
        await engine.processPoll(current: p4, previous: p3)

        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].sevenDayDelta == 1.0)
        #expect(storage.storedMeasurements[0].totalRawTokens == 1000)
        #expect(storage.storedMeasurements[0].windowStart == 3000)
    }

    @Test("Multi-model: two models produce two records with shared weekly delta and low confidence")
    func multiModelAttribution() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [
            makeTokens(model: "claude-sonnet-4-6", input: 300, output: 200),
            makeTokens(model: "claude-opus-4-6", input: 400, output: 100)
        ]

        let prev = makePoll(timestamp: 1000, sevenDayUtil: 10.0)
        let curr = makePoll(timestamp: 2000, sevenDayUtil: 13.0)

        await engine.processPoll(current: curr, previous: prev)

        #expect(storage.storedMeasurements.count == 2)

        let sonnet = storage.storedMeasurements.first { $0.model == "claude-sonnet-4-6" }
        let opus = storage.storedMeasurements.first { $0.model == "claude-opus-4-6" }

        #expect(sonnet?.totalRawTokens == 500)
        #expect(opus?.totalRawTokens == 500)
        #expect(sonnet?.sevenDayDelta == 3.0)
        #expect(opus?.sevenDayDelta == 3.0)
        #expect(sonnet?.confidence == .low)
        #expect(opus?.confidence == .low)
    }

    @Test("Single model confidence: weekly delta >= 2 percent gives medium, 1 percent gives low")
    func singleModelConfidence() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        // Medium confidence: 2% delta
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        await engine.processPoll(
            current: makePoll(timestamp: 2000, sevenDayUtil: 12.0),
            previous: makePoll(timestamp: 1000, sevenDayUtil: 10.0)
        )

        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].confidence == .medium)
        #expect(storage.storedMeasurements[0].tppSevenDay == 500.0)  // 1000 / 2%

        // Low confidence: 1% delta
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        await engine.processPoll(
            current: makePoll(timestamp: 4000, sevenDayUtil: 21.0),
            previous: makePoll(timestamp: 3000, sevenDayUtil: 20.0)
        )

        #expect(storage.storedMeasurements.count == 2)
        #expect(storage.storedMeasurements[1].confidence == .low)
    }

    @Test("Delta-only record: weekly delta with zero tokens stores model unknown and nil TPP")
    func deltaOnlyRecord() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = []  // No tokens

        let prev = makePoll(timestamp: 1000, sevenDayUtil: 28.0)
        let curr = makePoll(timestamp: 2000, sevenDayUtil: 29.0)

        await engine.processPoll(current: curr, previous: prev)

        #expect(storage.storedMeasurements.count == 1)
        let m = storage.storedMeasurements[0]
        #expect(m.model == "unknown")
        #expect(m.totalRawTokens == 0)
        #expect(m.sevenDayDelta == 1.0)
        #expect(m.tppSevenDay == nil)
        #expect(m.tppFiveHour == nil)
        #expect(m.fiveHourDelta == nil)
        #expect(m.confidence == .low)
    }

    @Test("Coverage health: correctly computes totalUtilizationChanges, windowsWithTokenData, coveragePercent")
    func coverageHealth() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        // 3 polls with delta: 2 with tokens, 1 without
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        await engine.processPoll(
            current: makePoll(timestamp: 2000, sevenDayUtil: 11.0),
            previous: makePoll(timestamp: 1000, sevenDayUtil: 10.0)
        )

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        await engine.processPoll(
            current: makePoll(timestamp: 4000, sevenDayUtil: 12.0),
            previous: makePoll(timestamp: 3000, sevenDayUtil: 11.0)
        )

        logParser.tokensToReturn = []
        await engine.processPoll(
            current: makePoll(timestamp: 6000, sevenDayUtil: 13.0),
            previous: makePoll(timestamp: 5000, sevenDayUtil: 12.0)
        )

        let health = await engine.getHealth()
        #expect(health.totalUtilizationChanges == 3)
        #expect(health.windowsWithTokenData == 2)
        // 2/3 = 66.67%
        #expect(health.coveragePercent > 66.0 && health.coveragePercent < 67.0)
        #expect(health.isDegraded == true)  // < 70%
        #expect(health.degradationSuggestion != nil)
    }

    @Test("Missing 7d utilization on either poll skips processing, even with 5h data")
    func missingSevenDay() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]

        await engine.processPoll(
            current: makePoll(timestamp: 2000, sevenDayUtil: 30.0, fiveHourUtil: 20.0),
            previous: makePoll(timestamp: 1000, sevenDayUtil: nil, fiveHourUtil: 10.0)
        )
        await engine.processPoll(
            current: makePoll(timestamp: 3000, sevenDayUtil: nil, fiveHourUtil: 30.0),
            previous: makePoll(timestamp: 2000, sevenDayUtil: 30.0, fiveHourUtil: 20.0)
        )

        #expect(storage.storedMeasurements.isEmpty)
        let health = await engine.getHealth()
        #expect(health.totalUtilizationChanges == 0)
    }

    @Test("Fractional weekly steps that reach 1 percent only in total flush the window")
    func cumulativeFractionalStep() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 300, output: 200)]
        await engine.processPoll(current: makePoll(timestamp: 2000, sevenDayUtil: 28.5), previous: makePoll(timestamp: 1000, sevenDayUtil: 28.0))
        #expect(storage.storedMeasurements.isEmpty)

        // Pair delta is only 0.5, but 1.0 since the window start
        await engine.processPoll(current: makePoll(timestamp: 3000, sevenDayUtil: 29.0), previous: makePoll(timestamp: 2000, sevenDayUtil: 28.5))

        #expect(storage.storedMeasurements.count == 1)
        let m = storage.storedMeasurements[0]
        #expect(m.sevenDayBefore == 28.0)
        #expect(m.sevenDayDelta == 1.0)
        #expect(m.totalRawTokens == 1000)
        #expect(m.windowStart == 1000)
    }

    @Test("Missing 7d utilization discards the open accumulation window")
    func missingSevenDayDiscardsWindow() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 500, output: 500)]
        await engine.processPoll(current: makePoll(timestamp: 2000, sevenDayUtil: 28.0), previous: makePoll(timestamp: 1000, sevenDayUtil: 28.0))
        await engine.processPoll(current: makePoll(timestamp: 3000, sevenDayUtil: nil), previous: makePoll(timestamp: 2000, sevenDayUtil: 28.0))

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 100, output: 100)]
        await engine.processPoll(current: makePoll(timestamp: 5000, sevenDayUtil: 29.0), previous: makePoll(timestamp: 4000, sevenDayUtil: 28.0))

        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].totalRawTokens == 200)  // only the last interval
        #expect(storage.storedMeasurements[0].windowStart == 4000)
    }
}
