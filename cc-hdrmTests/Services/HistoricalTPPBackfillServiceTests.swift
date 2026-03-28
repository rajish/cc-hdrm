import Foundation
import Testing
@testable import cc_hdrm

// MARK: - Test Mocks

private final class MockBackfillLogParser: ClaudeCodeLogParserProtocol, @unchecked Sendable {
    var scanCallCount = 0
    var tokensToReturn: [TokenAggregate] = []
    /// Allows returning different tokens based on time range
    var tokensByRange: [(start: Int64, end: Int64, tokens: [TokenAggregate])] = []

    func scan() async {
        scanCallCount += 1
    }

    func getTokens(from start: Int64, to end: Int64, model: String?) -> [TokenAggregate] {
        // Check range-specific overrides first
        for range in tokensByRange {
            if start >= range.start && end <= range.end {
                let tokens = model != nil ? range.tokens.filter { $0.model == model } : range.tokens
                if !tokens.isEmpty { return tokens }
            }
        }
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

private final class MockBackfillTPPStorage: TPPStorageServiceProtocol, @unchecked Sendable {
    var storedMeasurements: [TPPMeasurement] = []
    var deleteCallCount = 0

    func storeBenchmarkResult(_ measurement: TPPMeasurement) async throws {
        storedMeasurements.append(measurement)
    }

    func latestBenchmark(model: String, variant: String?) async throws -> TPPMeasurement? {
        return nil
    }

    func lastBenchmarkTimestamp() async throws -> Int64? {
        return nil
    }

    func storePassiveResult(_ measurement: TPPMeasurement) async throws {
        storedMeasurements.append(measurement)
    }

    func getMeasurements(from: Int64, to: Int64, source: MeasurementSource?, model: String?, confidence: MeasurementConfidence?) async throws -> [TPPMeasurement] {
        return storedMeasurements.filter { m in
            guard m.timestamp >= from && m.timestamp <= to else { return false }
            if let source, m.source != source { return false }
            if let model, m.model != model { return false }
            if let confidence, m.confidence != confidence { return false }
            return true
        }
    }

    func getAverageTPP(from: Int64, to: Int64, model: String?, source: MeasurementSource?) async throws -> (fiveHour: Double?, sevenDay: Double?) {
        return (nil, nil)
    }

    func deleteBackfillRecords() async throws {
        deleteCallCount += 1
        storedMeasurements.removeAll { $0.source == .passiveBackfill || $0.source == .rollupBackfill }
    }
}

// MARK: - Helper

private func makePoll(id: Int64, timestamp: Int64, fiveHourUtil: Double?, sevenDayUtil: Double? = nil) -> UsagePoll {
    UsagePoll(
        id: id,
        timestamp: timestamp,
        fiveHourUtil: fiveHourUtil,
        fiveHourResetsAt: nil,
        sevenDayUtil: sevenDayUtil,
        sevenDayResetsAt: nil
    )
}

private func makeRollup(id: Int64, periodStart: Int64, periodEnd: Int64, fiveHourPeak: Double?, fiveHourMin: Double?, resetCount: Int = 0, sevenDayPeak: Double? = nil, sevenDayMin: Double? = nil) -> UsageRollup {
    UsageRollup(
        id: id,
        periodStart: periodStart,
        periodEnd: periodEnd,
        resolution: .hourly,
        fiveHourAvg: nil,
        fiveHourPeak: fiveHourPeak,
        fiveHourMin: fiveHourMin,
        sevenDayAvg: nil,
        sevenDayPeak: sevenDayPeak,
        sevenDayMin: sevenDayMin,
        resetCount: resetCount,
        unusedCredits: nil
    )
}

// MARK: - Tests

@Suite("HistoricalTPPBackfillService Tests")
struct HistoricalTPPBackfillServiceTests {

    @Test("Idempotency: backfill runs once, second call returns early")
    func testIdempotency() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 10),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 15),
        ]

        let logParser = MockBackfillLogParser()
        logParser.tokensToReturn = [
            TokenAggregate(model: "claude-opus-4-6", inputTokens: 500, outputTokens: 500, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1)
        ]

        let tppStorage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        // First run
        let count1 = await service.runBackfill(force: false)
        #expect(count1 > 0)
        #expect(prefs.tppBackfillCompleted == true)

        let storedCount = tppStorage.storedMeasurements.count

        // Second run via runBackfillIfNeeded — should return early
        await service.runBackfillIfNeeded()
        #expect(tppStorage.storedMeasurements.count == storedCount)
    }

    @Test("Force re-run: deletes existing records and re-runs")
    func testForceRerun() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 10),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 15),
        ]

        let logParser = MockBackfillLogParser()
        logParser.tokensToReturn = [
            TokenAggregate(model: "claude-opus-4-6", inputTokens: 500, outputTokens: 500, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1)
        ]

        let tppStorage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        // First run
        let count1 = await service.runBackfill(force: false)
        #expect(count1 > 0)

        // Force re-run
        let count2 = await service.runBackfill(force: true)
        #expect(count2 > 0)
        #expect(tppStorage.deleteCallCount == 1)
    }

    @Test("Raw poll backfill: consecutive polls with deltas produce correct measurements")
    func testRawPollBackfill() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 10),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 14),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: 16),
            makePoll(id: 4, timestamp: 4000, fiveHourUtil: 20),
            makePoll(id: 5, timestamp: 5000, fiveHourUtil: 25),
        ]

        let logParser = MockBackfillLogParser()
        logParser.tokensToReturn = [
            TokenAggregate(model: "claude-opus-4-6", inputTokens: 200, outputTokens: 300, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1)
        ]

        let tppStorage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        let count = await service.runBackfill(force: false)
        #expect(count == 4)

        // All should have source = .passiveBackfill
        for m in tppStorage.storedMeasurements {
            #expect(m.source == .passiveBackfill)
        }

        // Verify TPP computation for first pair: 500 tokens / 4% delta = 125.0
        let first = tppStorage.storedMeasurements[0]
        #expect(first.model == "claude-opus-4-6")
        #expect(first.totalRawTokens == 500)
        #expect(first.fiveHourDelta == 4.0)
        #expect(first.tppFiveHour == 125.0)
        #expect(first.confidence == .medium) // delta >= 3%
    }

    @Test("Reset detection: poll pair with 50%+ drop is skipped")
    func testResetDetection() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 80),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 20), // 60% drop — reset
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: 25),
        ]

        let logParser = MockBackfillLogParser()
        logParser.tokensToReturn = [
            TokenAggregate(model: "claude-opus-4-6", inputTokens: 500, outputTokens: 500, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1)
        ]

        let tppStorage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        let count = await service.runBackfill(force: false)
        // Pair (80->20) skipped due to reset, pair (20->25) processed = 1 measurement
        #expect(count == 1)
        #expect(tppStorage.storedMeasurements[0].fiveHourDelta == 5.0)
    }

    @Test("Delta-only records: polls with delta but no tokens store model=unknown")
    func testDeltaOnlyRecords() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 10),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 15),
        ]

        let logParser = MockBackfillLogParser()
        logParser.tokensToReturn = [] // No tokens

        let tppStorage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        let count = await service.runBackfill(force: false)
        #expect(count == 1)

        let m = tppStorage.storedMeasurements[0]
        #expect(m.model == "unknown")
        #expect(m.totalRawTokens == 0)
        #expect(m.tppFiveHour == nil)
        #expect(m.confidence == .low)
        #expect(m.source == .passiveBackfill)
    }

    @Test("Rollup backfill: rollup buckets with peak/min produce correct measurements")
    func testRollupBackfill() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = [] // No raw polls
        histService.rolledUpDataToReturn = [
            makeRollup(id: 1, periodStart: 1000, periodEnd: 5000, fiveHourPeak: 30, fiveHourMin: 20),
            makeRollup(id: 2, periodStart: 5000, periodEnd: 10000, fiveHourPeak: 50, fiveHourMin: 35),
        ]

        let logParser = MockBackfillLogParser()
        logParser.tokensToReturn = [
            TokenAggregate(model: "claude-opus-4-6", inputTokens: 1000, outputTokens: 500, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 2)
        ]

        let tppStorage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        let count = await service.runBackfill(force: false)
        // .month range returns 2 rollup buckets: expect exactly 2 measurements
        #expect(count == 2)

        let first = tppStorage.storedMeasurements[0]
        #expect(first.source == .rollupBackfill)
        #expect(first.confidence == .low) // Rollup always low
        #expect(first.fiveHourDelta == 10.0) // peak(30) - min(20)
        // TPP = 1500 tokens / 10% delta = 150.0
        #expect(first.tppFiveHour == 150.0)
    }

    @Test("Rollup skip on reset: bucket with resetCount > 0 is skipped")
    func testRollupSkipOnReset() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = []
        histService.rolledUpDataToReturn = [
            makeRollup(id: 1, periodStart: 1000, periodEnd: 5000, fiveHourPeak: 50, fiveHourMin: 10, resetCount: 1),
        ]

        let logParser = MockBackfillLogParser()
        logParser.tokensToReturn = [
            TokenAggregate(model: "claude-opus-4-6", inputTokens: 500, outputTokens: 500, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1)
        ]

        let tppStorage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        let count = await service.runBackfill(force: false)
        #expect(count == 0)
    }

    @Test("Empty state: no polls, no rollups — completes without errors")
    func testEmptyState() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = []
        histService.rolledUpDataToReturn = []

        let logParser = MockBackfillLogParser()
        let tppStorage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        let count = await service.runBackfill(force: false)
        #expect(count == 0)
        #expect(tppStorage.storedMeasurements.isEmpty)
        #expect(prefs.tppBackfillCompleted == true) // Marked complete even with no data
    }

    @Test("Force re-run with no data still marks backfill completed")
    func testForceEmptySetsPreference() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = []
        histService.rolledUpDataToReturn = []

        let logParser = MockBackfillLogParser()
        let tppStorage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()
        prefs.tppBackfillCompleted = true

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        // Force re-run with no data — preference should still be set to true after
        let count = await service.runBackfill(force: true)
        #expect(count == 0)
        #expect(prefs.tppBackfillCompleted == true)
    }

    @Test("DB slow-path detects rollup-only backfill records")
    func testDBSlowPathDetectsRollupRecords() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 10),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 15),
        ]

        let logParser = MockBackfillLogParser()
        logParser.tokensToReturn = [
            TokenAggregate(model: "claude-opus-4-6", inputTokens: 500, outputTokens: 500, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1)
        ]

        let tppStorage = MockBackfillTPPStorage()
        // Pre-populate with a rollup-backfill record only (no passive-backfill)
        tppStorage.storedMeasurements = [
            TPPMeasurement(
                id: 1, timestamp: 500, windowStart: 100, model: "claude-opus-4-6", variant: nil,
                source: .rollupBackfill, fiveHourBefore: 5, fiveHourAfter: 10, fiveHourDelta: 5,
                sevenDayBefore: nil, sevenDayAfter: nil, sevenDayDelta: nil,
                inputTokens: 250, outputTokens: 250, cacheCreateTokens: 0, cacheReadTokens: 0,
                totalRawTokens: 500, tppFiveHour: 100.0, tppSevenDay: nil, confidence: .low, messageCount: 1
            )
        ]

        let prefs = MockPreferencesManager()
        prefs.tppBackfillCompleted = false

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        // runBackfillIfNeeded should detect the rollup record and skip
        await service.runBackfillIfNeeded()
        #expect(prefs.tppBackfillCompleted == true)
        // Should still have only the 1 pre-existing record
        #expect(tppStorage.storedMeasurements.count == 1)
    }

    @Test("Multi-model in raw poll: tokens from 2 models produce 2 records with confidence low")
    func testMultiModelRawPoll() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 10),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 20),
        ]

        let logParser = MockBackfillLogParser()
        logParser.tokensToReturn = [
            TokenAggregate(model: "claude-opus-4-6", inputTokens: 300, outputTokens: 200, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1),
            TokenAggregate(model: "claude-sonnet-4-6", inputTokens: 200, outputTokens: 100, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1),
        ]

        let tppStorage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        let count = await service.runBackfill(force: false)
        #expect(count == 2)

        // Both should be confidence = .low (multi-model)
        for m in tppStorage.storedMeasurements {
            #expect(m.confidence == .low)
            #expect(m.source == .passiveBackfill)
        }

        let models = Set(tppStorage.storedMeasurements.map(\.model))
        #expect(models.contains("claude-opus-4-6"))
        #expect(models.contains("claude-sonnet-4-6"))
    }

    @Test("DB idempotency check: existing backfill records in DB prevent re-run")
    func testDBIdempotencyCheck() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 10),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 15),
        ]

        let logParser = MockBackfillLogParser()
        logParser.tokensToReturn = [
            TokenAggregate(model: "claude-opus-4-6", inputTokens: 500, outputTokens: 500, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1)
        ]

        let tppStorage = MockBackfillTPPStorage()
        // Pre-populate with a backfill record
        tppStorage.storedMeasurements = [
            TPPMeasurement(
                id: 1, timestamp: 500, windowStart: 100, model: "claude-opus-4-6", variant: nil,
                source: .passiveBackfill, fiveHourBefore: 5, fiveHourAfter: 10, fiveHourDelta: 5,
                sevenDayBefore: nil, sevenDayAfter: nil, sevenDayDelta: nil,
                inputTokens: 250, outputTokens: 250, cacheCreateTokens: 0, cacheReadTokens: 0,
                totalRawTokens: 500, tppFiveHour: 100.0, tppSevenDay: nil, confidence: .medium, messageCount: 1
            )
        ]

        let prefs = MockPreferencesManager()
        prefs.tppBackfillCompleted = false // Preference says not done

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        // runBackfillIfNeeded should find existing records in DB and skip
        await service.runBackfillIfNeeded()
        #expect(prefs.tppBackfillCompleted == true)
        // Should still have only the 1 pre-existing record
        #expect(tppStorage.storedMeasurements.count == 1)
    }

    @Test("Confidence assignment: single model, delta < 3% gets low confidence")
    func testLowConfidenceSmallDelta() async {
        let histService = MockHistoricalDataService()
        histService.recentPollsToReturn = [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 10),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 12), // 2% delta — below 3% threshold
        ]

        let logParser = MockBackfillLogParser()
        logParser.tokensToReturn = [
            TokenAggregate(model: "claude-opus-4-6", inputTokens: 100, outputTokens: 100, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1)
        ]

        let tppStorage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()

        let service = HistoricalTPPBackfillService(
            historicalDataService: histService,
            logParser: logParser,
            tppStorage: tppStorage,
            preferencesManager: prefs
        )

        let count = await service.runBackfill(force: false)
        #expect(count == 1)
        #expect(tppStorage.storedMeasurements[0].confidence == .low) // single model, delta 2% < 3%
    }
}
