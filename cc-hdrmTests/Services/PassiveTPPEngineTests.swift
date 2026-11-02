import Foundation
import Testing
@testable import cc_hdrm

// MARK: - Test Mocks

private final class MockLogParser: ClaudeCodeLogParserProtocol, @unchecked Sendable {
    var scanCallCount = 0
    var tokensToReturn: [TokenAggregate] = []
    var queriedRanges: [ClosedRange<Int64>] = []

    func scan() async {
        scanCallCount += 1
    }

    func getTokens(from start: Int64, to end: Int64, model: String?) -> [TokenAggregate] {
        queriedRanges.append(start...end)
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

    func deleteBackfillRecords(passiveFrom: Int64?, rollupFrom: Int64?) async throws {
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

// MARK: - Weekly Steps

@Suite("PassiveTPPEngine Weekly Step Tests")
struct PassiveTPPEngineWeeklyTests {
    private let model = "claude-sonnet-4-6"
    private let hourMs: Int64 = 3_600_000

    private func weekly(_ timestamp: Int64, _ util: Double?, resetsAt: Int64? = nil) -> UsagePoll {
        UsagePoll(id: 0, timestamp: timestamp, fiveHourUtil: nil, fiveHourResetsAt: nil, sevenDayUtil: util, sevenDayResetsAt: resetsAt)
    }

    private func makeEngine() -> (PassiveTPPEngine, MockLogParser, MockPassiveTPPStorage) {
        let parser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        return (PassiveTPPEngine(logParser: parser, tppStorage: storage), parser, storage)
    }

    @Test("First step anchors with no value; the next step stores a weekly row and no 5-hour fields")
    func anchoredStep() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model, input: 600, output: 400, cacheCreate: 400, cacheRead: 9000, messages: 2)]

        await engine.processPoll(current: weekly(2000, 29), previous: weekly(1000, 28))
        #expect(storage.storedMeasurements.isEmpty)

        await engine.processPoll(current: weekly(3000, 30), previous: weekly(2000, 29))

        #expect(storage.storedMeasurements == [TPPMeasurement(
            id: nil, timestamp: 3000, windowStart: 2000, model: model, variant: nil, source: .passive,
            fiveHourBefore: nil, fiveHourAfter: nil, fiveHourDelta: nil,
            sevenDayBefore: 29, sevenDayAfter: 30, sevenDayDelta: 1,
            inputTokens: 600, outputTokens: 400, cacheCreateTokens: 400, cacheReadTokens: 9000, totalRawTokens: 10400,
            tppFiveHour: nil, tppSevenDay: 1500, confidence: .low, messageCount: 2
        )])
        #expect(storage.storedMeasurements[0].basis == .weekly)
        #expect(storage.storedMeasurements[0].chartTPP == 1500)
    }

    @Test("Tokens across flat polls accumulate into the step")
    func accumulates() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model, input: 500, output: 500)]

        await engine.processPoll(current: weekly(2000, 29), previous: weekly(1000, 28))
        await engine.processPoll(current: weekly(3000, 29), previous: weekly(2000, 29))
        await engine.processPoll(current: weekly(4000, 29), previous: weekly(3000, 29))
        await engine.processPoll(current: weekly(5000, 30), previous: weekly(4000, 29))

        #expect(storage.storedMeasurements.count == 1)
        let row = storage.storedMeasurements[0]
        #expect(row.windowStart == 2000)
        #expect(row.sevenDayBefore == 29)
        #expect(row.tppSevenDay == 3000)
        #expect(parser.queriedRanges == [1000...2000, 2000...3000, 3000...4000, 4000...5000])
    }

    @Test("A night with no step and no tokens keeps the anchor")
    func overnightKeepsAnchor() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]
        await engine.processPoll(current: weekly(2000, 29), previous: weekly(1000, 28))

        parser.tokensToReturn = []
        let morning = 2000 + 9 * hourMs
        await engine.processPoll(current: weekly(morning, 29), previous: weekly(2000, 29))

        parser.tokensToReturn = [makeTokens(model: model)]
        await engine.processPoll(current: weekly(morning + 1000, 30), previous: weekly(morning, 29))

        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].windowStart == morning)
    }

    @Test("A long gap holding tokens drops the anchor, because that window is already stale")
    func longGapWithTokensDropsAnchor() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]
        await engine.processPoll(current: weekly(2000, 29), previous: weekly(1000, 28))

        let late = 2000 + 9 * hourMs
        await engine.processPoll(current: weekly(late, 29), previous: weekly(2000, 29))
        await engine.processPoll(current: weekly(late + 1000, 30), previous: weekly(late, 29))

        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("Idle hours after a step keep the anchor, because no tokens were lost")
    func idleKeepsAnchor() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]
        await engine.processPoll(current: weekly(2000, 29), previous: weekly(1000, 28))

        parser.tokensToReturn = []
        let later = 10 * hourMs
        await engine.processPoll(current: weekly(later, 29), previous: weekly(later - hourMs, 29))

        parser.tokensToReturn = [makeTokens(model: model)]
        await engine.processPoll(current: weekly(later + 1000, 30), previous: weekly(later, 29))

        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].windowStart == later)
    }

    @Test("A window older than 6 hours gives no value when the step arrives; the following step does")
    func staleWindowAtStep() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]
        await engine.processPoll(current: weekly(2000, 29), previous: weekly(1000, 28))
        await engine.processPoll(current: weekly(3000, 29), previous: weekly(2000, 29))

        let late = 2000 + 6 * hourMs + 1
        await engine.processPoll(current: weekly(late, 30), previous: weekly(late - 1000, 29))
        #expect(storage.storedMeasurements.isEmpty)

        await engine.processPoll(current: weekly(late + 1000, 31), previous: weekly(late, 30))
        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].windowStart == late)
    }

    @Test("A window aged past 6 hours on a flat poll restarts unanchored")
    func staleWindowFlat() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]
        await engine.processPoll(current: weekly(2000, 29), previous: weekly(1000, 28))
        await engine.processPoll(current: weekly(3000, 29), previous: weekly(2000, 29))

        let late = 2000 + 6 * hourMs + 1
        await engine.processPoll(current: weekly(late, 29), previous: weekly(late - 1000, 29))
        await engine.processPoll(current: weekly(late + 1000, 30), previous: weekly(late, 29))

        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("A single poll pair spanning more than 6 hours gives no value")
    func sleepGap() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]
        await engine.processPoll(current: weekly(2000, 29), previous: weekly(1000, 28))

        let late = 2000 + 8 * hourMs
        await engine.processPoll(current: weekly(late, 35), previous: weekly(2000, 29))

        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("A weekly drop discards the window, and the first step after it only anchors")
    func resetByDrop() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]
        await engine.processPoll(current: weekly(2000, 89), previous: weekly(1000, 88))
        await engine.processPoll(current: weekly(3000, 89), previous: weekly(2000, 89))

        await engine.processPoll(current: weekly(4000, 0), previous: weekly(3000, 89))
        await engine.processPoll(current: weekly(5000, 1), previous: weekly(4000, 0))
        #expect(storage.storedMeasurements.isEmpty)

        await engine.processPoll(current: weekly(6000, 2), previous: weekly(5000, 1))
        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].sevenDayBefore == 1)
    }

    @Test("A reset followed by a rise within one poll is caught by the reset time")
    func resetCaughtByResetTime() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]
        let resetsAt: Int64 = 1_000_000_000
        await engine.processPoll(current: weekly(2000, 3, resetsAt: resetsAt), previous: weekly(1000, 2, resetsAt: resetsAt))
        await engine.processPoll(
            current: weekly(3000, 5, resetsAt: resetsAt + 7 * 24 * hourMs),
            previous: weekly(2000, 3, resetsAt: resetsAt)
        )
        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("A small drift in the reset time is not a reset")
    func resetTimeDrift() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]
        let resetsAt: Int64 = 1_000_000_000
        await engine.processPoll(current: weekly(2000, 3, resetsAt: resetsAt), previous: weekly(1000, 2, resetsAt: resetsAt))
        await engine.processPoll(
            current: weekly(3000, 4, resetsAt: resetsAt + 2 * hourMs),
            previous: weekly(2000, 3, resetsAt: resetsAt)
        )
        #expect(storage.storedMeasurements.count == 1)
    }

    @Test("A step with no tokens stores a delta-only row, anchored or not")
    func deltaOnly() async {
        let (engine, _, storage) = makeEngine()
        await engine.processPoll(current: weekly(2000, 29), previous: weekly(1000, 28))

        #expect(storage.storedMeasurements.count == 1)
        let row = storage.storedMeasurements[0]
        #expect(row.model == "unknown")
        #expect(row.tppSevenDay == nil)
        #expect(row.sevenDayDelta == 1)
        #expect(row.fiveHourDelta == nil)
        #expect(row.confidence == .low)
    }

    @Test("Confidence: 1% and 2% steps are low, 3% single-model is medium, multi-model is low", arguments: [
        (1.0, 1, MeasurementConfidence.low),
        (2.0, 1, MeasurementConfidence.low),
        (3.0, 1, MeasurementConfidence.medium),
        (3.0, 2, MeasurementConfidence.low),
    ])
    func confidence(delta: Double, models: Int, expected: MeasurementConfidence) async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = (0..<models).map { makeTokens(model: "model-\($0)") }
        await engine.processPoll(current: weekly(2000, 10), previous: weekly(1000, 9))
        await engine.processPoll(current: weekly(3000, 10 + delta), previous: weekly(2000, 10))

        #expect(storage.storedMeasurements.count == models)
        #expect(storage.storedMeasurements.allSatisfy { $0.confidence == expected })
    }

    @Test("A missing weekly value drops the window and the anchor")
    func missingWeekly() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]
        await engine.processPoll(current: weekly(2000, 29), previous: weekly(1000, 28))
        await engine.processPoll(current: weekly(3000, nil), previous: weekly(2000, 29))
        await engine.processPoll(current: weekly(4000, 30), previous: weekly(3000, nil))
        await engine.processPoll(current: weekly(5000, 31), previous: weekly(4000, 30))

        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("Number to no number: the 5-hour window never reaches a weekly row, and no row mixes bases")
    func numberToNoNumber() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]

        // Opens a 5-hour window that would otherwise flush later.
        await engine.processPoll(current: makePoll(timestamp: 2000, fiveHourUtil: 10.5, sevenDayUtil: 40), previous: makePoll(timestamp: 1000, fiveHourUtil: 10, sevenDayUtil: 40))
        // The account loses its number.
        await engine.processPoll(current: weekly(3000, 41), previous: makePoll(timestamp: 2000, fiveHourUtil: 10.5, sevenDayUtil: 40))
        #expect(storage.storedMeasurements.isEmpty)

        await engine.processPoll(current: weekly(4000, 42), previous: weekly(3000, 41))
        #expect(storage.storedMeasurements.isEmpty)

        await engine.processPoll(current: weekly(5000, 43), previous: weekly(4000, 42))
        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].windowStart == 4000)
        #expect(storage.storedMeasurements[0].fiveHourBefore == nil)
        #expect(storage.storedMeasurements[0].tppFiveHour == nil)
        #expect(storage.storedMeasurements[0].tppSevenDay == 1000)
    }

    @Test("No number to number: the weekly window never reaches a 5-hour row")
    func noNumberToNumber() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]

        await engine.processPoll(current: weekly(2000, 41), previous: weekly(1000, 40))
        await engine.processPoll(current: weekly(3000, 41), previous: weekly(2000, 41))
        #expect(storage.storedMeasurements.isEmpty)

        // The account regains its number; 1.6.0 skips a pair with a missing side.
        await engine.processPoll(current: makePoll(timestamp: 4000, fiveHourUtil: 10, sevenDayUtil: 42), previous: weekly(3000, 41))
        #expect(storage.storedMeasurements.isEmpty)

        await engine.processPoll(current: makePoll(timestamp: 5000, fiveHourUtil: 12, sevenDayUtil: 42), previous: makePoll(timestamp: 4000, fiveHourUtil: 10, sevenDayUtil: 42))
        #expect(storage.storedMeasurements.count == 1)
        let row = storage.storedMeasurements[0]
        #expect(row.basis == .fiveHour)
        #expect(row.windowStart == 4000)
        #expect(row.totalRawTokens == 1000)
        #expect(row.tppFiveHour == 500)

        // Back to no number after a 5-hour row: the weekly tracker starts unanchored again.
        await engine.processPoll(current: weekly(6000, 43), previous: makePoll(timestamp: 5000, fiveHourUtil: 12, sevenDayUtil: 42))
        await engine.processPoll(current: weekly(7000, 44), previous: weekly(6000, 43))
        #expect(storage.storedMeasurements.count == 1)
    }

    @Test("An open 5-hour window does not survive a gap with no number")
    func fiveHourWindowDroppedAcrossGap() async {
        let (engine, parser, storage) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]

        await engine.processPoll(current: makePoll(timestamp: 2000, fiveHourUtil: 10.5), previous: makePoll(timestamp: 1000, fiveHourUtil: 10))
        await engine.processPoll(current: weekly(3000, 40), previous: makePoll(timestamp: 2000, fiveHourUtil: 10.5))
        await engine.processPoll(current: makePoll(timestamp: 4000, fiveHourUtil: 11), previous: weekly(3000, 40))
        await engine.processPoll(current: makePoll(timestamp: 5000, fiveHourUtil: 13), previous: makePoll(timestamp: 4000, fiveHourUtil: 11))

        #expect(storage.storedMeasurements.count == 1)
        #expect(storage.storedMeasurements[0].windowStart == 4000)
        #expect(storage.storedMeasurements[0].fiveHourBefore == 11)
        #expect(storage.storedMeasurements[0].totalRawTokens == 1000)
    }

    @Test("Health counts weekly steps and token coverage")
    func health() async {
        let (engine, parser, _) = makeEngine()
        parser.tokensToReturn = [makeTokens(model: model)]
        await engine.processPoll(current: weekly(2000, 29), previous: weekly(1000, 28))
        parser.tokensToReturn = []
        await engine.processPoll(current: weekly(3000, 30), previous: weekly(2000, 29))

        let health = await engine.getHealth()
        #expect(health.totalUtilizationChanges == 2)
        #expect(health.windowsWithTokenData == 1)
    }
}

// MARK: - Unchanged With a Number

@Suite("PassiveTPPEngine Unchanged With a Number")
struct PassiveTPPEngineUnchangedTests {
    private let model = "claude-sonnet-4-6"

    private func expected(
        timestamp: Int64, windowStart: Int64,
        fiveHour: (Double, Double), sevenDay: (Double?, Double?),
        tokens: TokenAggregate, confidence: MeasurementConfidence
    ) -> TPPMeasurement {
        let fiveHourDelta = fiveHour.1 - fiveHour.0
        let sevenDayDelta = sevenDay.0.flatMap { before in sevenDay.1.map { $0 - before } }
        let effective = Double(tokens.inputTokens + tokens.outputTokens) + Double(tokens.cacheCreateTokens) * 1.25
        return TPPMeasurement(
            id: nil, timestamp: timestamp, windowStart: windowStart, model: tokens.model, variant: nil, source: .passive,
            fiveHourBefore: fiveHour.0, fiveHourAfter: fiveHour.1, fiveHourDelta: fiveHourDelta,
            sevenDayBefore: sevenDay.0, sevenDayAfter: sevenDay.1, sevenDayDelta: sevenDayDelta,
            inputTokens: tokens.inputTokens, outputTokens: tokens.outputTokens,
            cacheCreateTokens: tokens.cacheCreateTokens, cacheReadTokens: tokens.cacheReadTokens,
            totalRawTokens: tokens.inputTokens + tokens.outputTokens + tokens.cacheCreateTokens + tokens.cacheReadTokens,
            tppFiveHour: fiveHourDelta >= 1 ? effective / fiveHourDelta : nil,
            tppSevenDay: sevenDayDelta.flatMap { $0 >= 1 ? effective / $0 : nil },
            confidence: confidence,
            messageCount: tokens.messageCount
        )
    }

    @Test("Direct step: every stored field matches the 1.6.0 calculation, measured from the first poll")
    func directStep() async {
        let parser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: parser, tppStorage: storage)
        let tokens = makeTokens(model: model, input: 600, output: 400, cacheCreate: 200, cacheRead: 5000, messages: 3)
        parser.tokensToReturn = [tokens]

        await engine.processPoll(current: makePoll(timestamp: 2000, fiveHourUtil: 14, sevenDayUtil: 31), previous: makePoll(timestamp: 1000, fiveHourUtil: 10, sevenDayUtil: 30))

        #expect(storage.storedMeasurements == [expected(timestamp: 2000, windowStart: 1000, fiveHour: (10, 14), sevenDay: (30, 31), tokens: tokens, confidence: .medium)])
    }

    @Test("Accumulated flush, including one older than 30 minutes, matches 1.6.0")
    func accumulatedFlush() async {
        let parser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: parser, tppStorage: storage)
        parser.tokensToReturn = [makeTokens(model: model, input: 500, output: 500)]

        await engine.processPoll(current: makePoll(timestamp: 2000, fiveHourUtil: 10.2, sevenDayUtil: 30), previous: makePoll(timestamp: 1000, fiveHourUtil: 10, sevenDayUtil: 30))
        // A delta arriving 3 hours later still flushes the old window, as 1.6.0 does.
        let late: Int64 = 3 * 3_600_000
        await engine.processPoll(current: makePoll(timestamp: late, fiveHourUtil: 12, sevenDayUtil: 30), previous: makePoll(timestamp: 2000, fiveHourUtil: 10.2, sevenDayUtil: 30))

        let merged = makeTokens(model: model, input: 1000, output: 1000, messages: 2)
        #expect(storage.storedMeasurements == [expected(timestamp: late, windowStart: 1000, fiveHour: (10, 12), sevenDay: (30, 30), tokens: merged, confidence: .low)])
    }

    @Test("A weekly step with no 5-hour step stays a 5-hour row with no 5-hour value, as in 1.6.0")
    func weeklyStepOnFiveHourPoll() async {
        let parser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: parser, tppStorage: storage)
        let tokens = makeTokens(model: model)
        parser.tokensToReturn = [tokens]

        await engine.processPoll(current: makePoll(timestamp: 2000, fiveHourUtil: 10, sevenDayUtil: 31), previous: makePoll(timestamp: 1000, fiveHourUtil: 10, sevenDayUtil: 30))

        #expect(storage.storedMeasurements == [expected(timestamp: 2000, windowStart: 1000, fiveHour: (10, 10), sevenDay: (30, 31), tokens: tokens, confidence: .low)])
        #expect(storage.storedMeasurements[0].basis == .fiveHour)
        #expect(storage.storedMeasurements[0].chartTPP == nil)
    }

    @Test("A 50% drop in the 5-hour value still counts as a reset, as in 1.6.0")
    func fiveHourDropStillResets() async {
        let parser = MockLogParser()
        let storage = MockPassiveTPPStorage()
        let engine = PassiveTPPEngine(logParser: parser, tppStorage: storage)
        parser.tokensToReturn = [makeTokens(model: model)]

        await engine.processPoll(current: makePoll(timestamp: 2000, fiveHourUtil: 20, sevenDayUtil: 30), previous: makePoll(timestamp: 1000, fiveHourUtil: 80, sevenDayUtil: 30))

        #expect(storage.storedMeasurements.isEmpty)
    }
}
