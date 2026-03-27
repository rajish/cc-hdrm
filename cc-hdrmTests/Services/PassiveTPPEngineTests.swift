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
            totalFilesScanned: 0,
            totalLinesProcessed: 0,
            totalLinesFailed: 0,
            successRate: 100.0,
            lastScanTimestamp: nil,
            lastScanDuration: nil
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
        storedMeasurements.removeAll { $0.source == .passiveBackfill || $0.source == .rollupBackfill }
    }
}

// MARK: - Test Helpers

private func makePoll(
    timestamp: Int64,
    fiveHourUtil: Double?,
    sevenDayUtil: Double? = nil
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

// MARK: - Tests

@Suite("PassiveTPPEngine Tests")
struct PassiveTPPEngineTests {

    @Test("Basic passive measurement: single model with 5h delta >= 1 percent stores TPP")
    func basicPassiveMeasurement() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 600, output: 400)]

        let prev = makePoll(timestamp: 1000, fiveHourUtil: 10.0)
        let curr = makePoll(timestamp: 2000, fiveHourUtil: 12.0)

        await engine.processPoll(current: curr, previous: prev)

        #expect(storage.storedMeasurements.count == 1)
        let m = storage.storedMeasurements[0]
        #expect(m.model == "claude-sonnet-4-6")
        #expect(m.source == .passive)
        #expect(m.fiveHourDelta == 2.0)
        #expect(m.totalRawTokens == 1000)
        #expect(m.tppFiveHour == 500.0)  // 1000 tokens / 2% delta
        #expect(m.confidence == .low)  // 2% delta < 3% threshold
    }

    @Test("Zero delta accumulation: tokens with 0 percent delta are accumulated, not stored")
    func zeroDeltaAccumulation() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]

        let prev = makePoll(timestamp: 1000, fiveHourUtil: 10.0)
        let curr = makePoll(timestamp: 2000, fiveHourUtil: 10.0)

        await engine.processPoll(current: curr, previous: prev)

        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("Accumulation flush: accumulated tokens with subsequent delta stores TPP for full window")
    func accumulationFlush() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        // First poll: tokens but no delta — accumulate
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 300, output: 200)]
        let p1 = makePoll(timestamp: 1000, fiveHourUtil: 10.0)
        let p2 = makePoll(timestamp: 2000, fiveHourUtil: 10.0)
        await engine.processPoll(current: p2, previous: p1)
        #expect(storage.storedMeasurements.isEmpty)

        // Second poll: tokens and delta — flush accumulated + current
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 200, output: 300)]
        let p3 = makePoll(timestamp: 3000, fiveHourUtil: 12.0)
        await engine.processPoll(current: p3, previous: p2)

        #expect(storage.storedMeasurements.count == 1)
        let m = storage.storedMeasurements[0]
        #expect(m.totalRawTokens == 1000)  // 500 accumulated + 500 current
        #expect(m.fiveHourDelta == 2.0)    // 12.0 - 10.0 (from window start)
        #expect(m.tppFiveHour == 500.0)    // 1000 / 2.0
        #expect(m.windowStart == 1000)     // Window started at p1
    }

    @Test("30-minute cap: accumulation exceeding 30 minutes discards tokens and restarts")
    func thirtyMinuteCap() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        // Start accumulation
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 500, output: 500)]
        let p1 = makePoll(timestamp: 1000, fiveHourUtil: 10.0)
        let p2 = makePoll(timestamp: 2000, fiveHourUtil: 10.0)
        await engine.processPoll(current: p2, previous: p1)

        // 31 minutes later: another zero-delta poll — should cap and restart
        let thirtyOneMinutesMs: Int64 = 31 * 60 * 1000
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 100, output: 100)]
        let p3 = makePoll(timestamp: 1000 + thirtyOneMinutesMs, fiveHourUtil: 10.0)
        await engine.processPoll(current: p3, previous: p2)

        // No measurement stored — window was discarded
        #expect(storage.storedMeasurements.isEmpty)

        // Now a delta comes — should only include the tokens from after the restart
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 150, output: 150)]
        let p4 = makePoll(timestamp: 1000 + thirtyOneMinutesMs + 1000, fiveHourUtil: 12.0)
        await engine.processPoll(current: p4, previous: p3)

        #expect(storage.storedMeasurements.count == 1)
        // Should include the restarted window tokens (200) + current (300)
        #expect(storage.storedMeasurements[0].totalRawTokens == 500)  // 200 (restarted) + 300 (current)
    }

    @Test("Monotonic guard: utilization decrease during accumulation discards window")
    func monotonicGuard() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        // Start accumulation at 10%
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        let p1 = makePoll(timestamp: 1000, fiveHourUtil: 10.0)
        let p2 = makePoll(timestamp: 2000, fiveHourUtil: 10.0)
        await engine.processPoll(current: p2, previous: p1)

        // Utilization decreases to 9% (sliding window decay) — window discarded
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        let p3 = makePoll(timestamp: 3000, fiveHourUtil: 9.0)
        await engine.processPoll(current: p3, previous: p2)

        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("Reset handling: 50 percent drop discards accumulation and skips TPP")
    func resetHandling() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        // Start accumulation
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        let p1 = makePoll(timestamp: 1000, fiveHourUtil: 80.0)
        let p2 = makePoll(timestamp: 2000, fiveHourUtil: 80.0)
        await engine.processPoll(current: p2, previous: p1)

        // Reset detected: drop from 80% to 10% (70% drop >= 50% threshold)
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        let p3 = makePoll(timestamp: 3000, fiveHourUtil: 10.0)
        await engine.processPoll(current: p3, previous: p2)

        #expect(storage.storedMeasurements.isEmpty)

        // Next poll should start fresh — delta from new baseline
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 400, output: 600)]
        let p4 = makePoll(timestamp: 4000, fiveHourUtil: 12.0)
        await engine.processPoll(current: p4, previous: p3)

        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].fiveHourDelta == 2.0)
    }

    @Test("Multi-model: two models in window produce two records with shared delta and low confidence")
    func multiModelAttribution() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [
            makeTokens(model: "claude-sonnet-4-6", input: 300, output: 200),
            makeTokens(model: "claude-opus-4-6", input: 400, output: 100)
        ]

        let prev = makePoll(timestamp: 1000, fiveHourUtil: 10.0)
        let curr = makePoll(timestamp: 2000, fiveHourUtil: 15.0)

        await engine.processPoll(current: curr, previous: prev)

        #expect(storage.storedMeasurements.count == 2)

        let sonnet = storage.storedMeasurements.first { $0.model == "claude-sonnet-4-6" }
        let opus = storage.storedMeasurements.first { $0.model == "claude-opus-4-6" }

        #expect(sonnet != nil)
        #expect(opus != nil)
        #expect(sonnet?.totalRawTokens == 500)
        #expect(opus?.totalRawTokens == 500)
        #expect(sonnet?.fiveHourDelta == 5.0)
        #expect(opus?.fiveHourDelta == 5.0)
        #expect(sonnet?.confidence == .low)
        #expect(opus?.confidence == .low)
    }

    @Test("Single model confidence: delta >= 3 percent gives medium, delta 1-2 percent gives low")
    func singleModelConfidence() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        // Medium confidence: 5% delta
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        let prev1 = makePoll(timestamp: 1000, fiveHourUtil: 10.0)
        let curr1 = makePoll(timestamp: 2000, fiveHourUtil: 15.0)
        await engine.processPoll(current: curr1, previous: prev1)

        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].confidence == .medium)

        // Low confidence: 1% delta
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        let prev2 = makePoll(timestamp: 3000, fiveHourUtil: 20.0)
        let curr2 = makePoll(timestamp: 4000, fiveHourUtil: 21.0)
        await engine.processPoll(current: curr2, previous: prev2)

        #expect(storage.storedMeasurements.count == 2)
        #expect(storage.storedMeasurements[1].confidence == .low)
    }

    @Test("Delta-only record: delta > 0 but zero tokens stores record with model unknown")
    func deltaOnlyRecord() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = []  // No tokens

        let prev = makePoll(timestamp: 1000, fiveHourUtil: 10.0)
        let curr = makePoll(timestamp: 2000, fiveHourUtil: 13.0)

        await engine.processPoll(current: curr, previous: prev)

        #expect(storage.storedMeasurements.count == 1)
        let m = storage.storedMeasurements[0]
        #expect(m.model == "unknown")
        #expect(m.totalRawTokens == 0)
        #expect(m.tppFiveHour == nil)
        #expect(m.confidence == .low)
    }

    @Test("Coverage health: correctly computes totalUtilizationChanges, windowsWithTokenData, coveragePercent")
    func coverageHealth() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        // 3 polls with delta: 2 with tokens, 1 without
        // Poll 1: delta + tokens
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        await engine.processPoll(
            current: makePoll(timestamp: 2000, fiveHourUtil: 12.0),
            previous: makePoll(timestamp: 1000, fiveHourUtil: 10.0)
        )

        // Poll 2: delta + tokens
        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6")]
        await engine.processPoll(
            current: makePoll(timestamp: 4000, fiveHourUtil: 15.0),
            previous: makePoll(timestamp: 3000, fiveHourUtil: 12.0)
        )

        // Poll 3: delta + no tokens (delta-only)
        logParser.tokensToReturn = []
        await engine.processPoll(
            current: makePoll(timestamp: 6000, fiveHourUtil: 18.0),
            previous: makePoll(timestamp: 5000, fiveHourUtil: 15.0)
        )

        let health = await engine.getHealth()
        #expect(health.totalUtilizationChanges == 3)
        #expect(health.windowsWithTokenData == 2)
        // 2/3 = 66.67%
        #expect(health.coveragePercent > 66.0 && health.coveragePercent < 67.0)
        #expect(health.isDegraded == true)  // < 70%
        #expect(health.degradationSuggestion != nil)
    }

    @Test("Missing 5h utilization data skips processing")
    func missingUtilization() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        let prev = makePoll(timestamp: 1000, fiveHourUtil: nil)
        let curr = makePoll(timestamp: 2000, fiveHourUtil: 10.0)

        await engine.processPoll(current: curr, previous: prev)
        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("Seven-day delta is computed when available")
    func sevenDayDelta() async {
        let logParser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: logParser, tppStorage: storage)

        logParser.tokensToReturn = [makeTokens(model: "claude-sonnet-4-6", input: 500, output: 500)]

        let prev = makePoll(timestamp: 1000, fiveHourUtil: 10.0, sevenDayUtil: 5.0)
        let curr = makePoll(timestamp: 2000, fiveHourUtil: 15.0, sevenDayUtil: 7.0)

        await engine.processPoll(current: curr, previous: prev)

        #expect(storage.storedMeasurements.count == 1)
        let m = storage.storedMeasurements[0]
        #expect(m.sevenDayDelta == 2.0)
        #expect(m.tppSevenDay == 500.0)  // 1000 / 2.0
    }
}
