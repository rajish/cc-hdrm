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
            totalLinesProcessed: 0,
            successfulExtractions: 0,
            failedLines: 0,
            successRate: 100.0,
            lastScanTimestamp: Date(),
            filesScanned: 0
        )
    }
}

private final class MockBackfillTPPStorage: TPPStorageServiceProtocol, @unchecked Sendable {
    var storedMeasurements: [TPPMeasurement] = []
    var deleteCallCount = 0
    var shouldThrowOnGetMeasurements = false
    var shouldThrowOnStorePassive = false

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
        if shouldThrowOnStorePassive { throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: "mock")) }
        storedMeasurements.append(measurement)
    }

    func getMeasurements(from: Int64, to: Int64, source: MeasurementSource?, model: String?, confidence: MeasurementConfidence?) async throws -> [TPPMeasurement] {
        if shouldThrowOnGetMeasurements { throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: "mock")) }
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

    func deleteBackfillRecords(passiveFrom: Int64?, rollupFrom: Int64?) async throws {
        deleteCallCount += 1
        storedMeasurements.removeAll { m in
            guard m.fiveHourDelta != nil else { return false }
            switch m.source {
            case .passiveBackfill: return passiveFrom.map { m.timestamp >= $0 } ?? false
            case .rollupBackfill: return rollupFrom.map { m.timestamp >= $0 } ?? false
            default: return false
            }
        }
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

// MARK: - Weekly Steps

@Suite("HistoricalTPPBackfillService Weekly Step Tests")
struct HistoricalTPPBackfillWeeklyTests {
    private let model = "claude-opus-4-6"

    private var tokens: TokenAggregate {
        TokenAggregate(model: model, inputTokens: 500, outputTokens: 500, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1)
    }

    private func make(
        polls: [UsagePoll] = [],
        rollups: [UsageRollup] = []
    ) -> (HistoricalTPPBackfillService, MockBackfillTPPStorage, MockPreferencesManager, MockBackfillLogParser) {
        let hist = MockHistoricalDataService()
        hist.recentPollsToReturn = polls
        hist.rolledUpDataToReturn = rollups
        let parser = MockBackfillLogParser()
        parser.tokensToReturn = [tokens]
        let storage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()
        let service = HistoricalTPPBackfillService(historicalDataService: hist, logParser: parser, tppStorage: storage, preferencesManager: prefs)
        return (service, storage, prefs, parser)
    }

    @Test("Raw polls: the first step only anchors, later steps carry all their flat polls")
    func rawWeekly() async {
        let (service, storage, _, _) = make(polls: [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: nil, sevenDayUtil: 28),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, sevenDayUtil: 29),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 29),
            makePoll(id: 4, timestamp: 4000, fiveHourUtil: nil, sevenDayUtil: 30),
        ])

        let count = await service.runBackfill(force: false)

        #expect(count == 1)
        let row = storage.storedMeasurements[0]
        #expect(row.source == .passiveBackfill)
        #expect(row.basis == .weekly)
        #expect(row.windowStart == 2000)
        #expect(row.timestamp == 4000)
        #expect(row.tppSevenDay == 2000)
        #expect(row.confidence == .low)
        #expect(row.fiveHourBefore == nil && row.fiveHourDelta == nil && row.tppFiveHour == nil)
    }

    @Test("A weekly reset produces no row, and the step after it only anchors")
    func rawReset() async {
        let (service, storage, _, _) = make(polls: [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: nil, sevenDayUtil: 88),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, sevenDayUtil: 89),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 0),
            makePoll(id: 4, timestamp: 4000, fiveHourUtil: nil, sevenDayUtil: 1),
        ])

        let count = await service.runBackfill(force: false)

        #expect(count == 0)
        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("State change both ways: each row keeps its own basis and none mixes them")
    func rawStateChange() async {
        let (service, storage, _, _) = make(polls: [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 10, sevenDayUtil: 30),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 12, sevenDayUtil: 31),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 32),
            makePoll(id: 4, timestamp: 4000, fiveHourUtil: nil, sevenDayUtil: 33),
            makePoll(id: 5, timestamp: 5000, fiveHourUtil: nil, sevenDayUtil: 34),
            makePoll(id: 6, timestamp: 6000, fiveHourUtil: 20, sevenDayUtil: 35),
            makePoll(id: 7, timestamp: 7000, fiveHourUtil: 22, sevenDayUtil: 36),
        ])

        await service.runBackfill(force: false)

        #expect(storage.storedMeasurements.map(\.timestamp) == [2000, 5000, 7000])
        #expect(storage.storedMeasurements.map(\.basis) == [.fiveHour, .weekly, .fiveHour])
        let weekly = storage.storedMeasurements[1]
        #expect(weekly.windowStart == 4000)
        #expect(weekly.fiveHourBefore == nil && weekly.fiveHourAfter == nil && weekly.tppFiveHour == nil)
        let fiveHour = storage.storedMeasurements[2]
        #expect(fiveHour.fiveHourBefore == 20 && fiveHour.fiveHourAfter == 22)
    }

    @Test("Polls with a number: the stored row matches the 1.6.0 calculation field for field")
    func unchangedWithNumber() async {
        let (service, storage, _, parser) = make(polls: [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 10, sevenDayUtil: 30),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 14, sevenDayUtil: 31),
        ])
        parser.tokensToReturn = [TokenAggregate(model: model, inputTokens: 600, outputTokens: 400, cacheCreateTokens: 200, cacheReadTokens: 5000, messageCount: 3)]

        await service.runBackfill(force: false)

        #expect(storage.storedMeasurements == [TPPMeasurement(
            id: nil, timestamp: 2000, windowStart: 1000, model: model, variant: nil, source: .passiveBackfill,
            fiveHourBefore: 10, fiveHourAfter: 14, fiveHourDelta: 4,
            sevenDayBefore: 30, sevenDayAfter: 31, sevenDayDelta: 1,
            inputTokens: 600, outputTokens: 400, cacheCreateTokens: 200, cacheReadTokens: 5000, totalRawTokens: 6200,
            tppFiveHour: 312.5, tppSevenDay: 1250, confidence: .medium, messageCount: 3
        )])
    }

    @Test("Rollup with a number: the stored row matches the 1.6.0 calculation field for field")
    func unchangedRollupWithNumber() async {
        let (service, storage, _, _) = make(rollups: [
            makeRollup(id: 1, periodStart: 1000, periodEnd: 2000, fiveHourPeak: 15, fiveHourMin: 5, sevenDayPeak: 31, sevenDayMin: 30),
        ])

        await service.runBackfill(force: false)

        #expect(storage.storedMeasurements == [TPPMeasurement(
            id: nil, timestamp: 2000, windowStart: 1000, model: model, variant: nil, source: .rollupBackfill,
            fiveHourBefore: 5, fiveHourAfter: 15, fiveHourDelta: 10,
            sevenDayBefore: 30, sevenDayAfter: 31, sevenDayDelta: nil,
            inputTokens: 500, outputTokens: 500, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 1000,
            tppFiveHour: 100, tppSevenDay: nil, confidence: .low, messageCount: 1
        )])
    }

    @Test("Rollup buckets with no number store nothing, because their windows start at bucket edges")
    func rollupsWithNoNumberStoreNothing() async {
        let (service, storage, _, _) = make(rollups: [
            makeRollup(id: 1, periodStart: 0, periodEnd: 1000, fiveHourPeak: nil, fiveHourMin: nil, sevenDayPeak: 28, sevenDayMin: 28),
            makeRollup(id: 2, periodStart: 1000, periodEnd: 2000, fiveHourPeak: nil, fiveHourMin: nil, sevenDayPeak: 30, sevenDayMin: 28),
        ])

        await service.runBackfill(force: false)

        #expect(storage.storedMeasurements.isEmpty)
    }

    @Test("Tokens come from each poll gap, summed across the window")
    func tokensPerGap() async {
        let (service, storage, _, parser) = make(polls: [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: nil, sevenDayUtil: 28),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, sevenDayUtil: 29),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 29),
            makePoll(id: 4, timestamp: 4000, fiveHourUtil: nil, sevenDayUtil: 30),
        ])
        func gap(_ input: Int) -> [TokenAggregate] {
            [TokenAggregate(model: model, inputTokens: input, outputTokens: 0, cacheCreateTokens: 0, cacheReadTokens: 0, messageCount: 1)]
        }
        parser.tokensToReturn = []
        parser.tokensByRange = [(1000, 2000, gap(7)), (2000, 3000, gap(100)), (3000, 4000, gap(20))]

        await service.runBackfill(force: false)

        #expect(storage.storedMeasurements.map(\.tppSevenDay) == [120])
    }

    @Test("Another model's stored weekly row does not block a backfill row for the same step")
    func overlapIsPerModel() async {
        let (service, storage, _, _) = make(polls: [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: nil, sevenDayUtil: 28),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, sevenDayUtil: 29),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 30),
        ])
        let otherModel = TPPMeasurement(
            id: nil, timestamp: 3000, windowStart: 2000, model: "another-model", variant: nil, source: .passive,
            fiveHourBefore: nil, fiveHourAfter: nil, fiveHourDelta: nil, sevenDayBefore: 29, sevenDayAfter: 30, sevenDayDelta: 1,
            inputTokens: 1, outputTokens: 1, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 2,
            tppFiveHour: nil, tppSevenDay: 2, confidence: .low, messageCount: 1
        )
        storage.storedMeasurements = [otherModel]

        await service.runBackfill(force: false)

        #expect(storage.storedMeasurements.contains { $0.model == model && $0.timestamp == 3000 })
    }

    @Test("A backfill row overlapping a stored weekly row is skipped; a 5-hour row never blocks one")
    func overlap() async {
        let (service, storage, _, _) = make(polls: [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: nil, sevenDayUtil: 28),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, sevenDayUtil: 29),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 30),
            makePoll(id: 4, timestamp: 4000, fiveHourUtil: nil, sevenDayUtil: 31),
        ])
        let fiveHourRow = TPPMeasurement(
            id: nil, timestamp: 4000, windowStart: 3000, model: model, variant: nil, source: .passive,
            fiveHourBefore: 1, fiveHourAfter: 2, fiveHourDelta: 1, sevenDayBefore: nil, sevenDayAfter: nil, sevenDayDelta: nil,
            inputTokens: 1, outputTokens: 1, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 2,
            tppFiveHour: 2, tppSevenDay: nil, confidence: .low, messageCount: 1
        )
        let livePassive = TPPMeasurement(
            id: nil, timestamp: 3000, windowStart: 2000, model: model, variant: nil, source: .passive,
            fiveHourBefore: nil, fiveHourAfter: nil, fiveHourDelta: nil, sevenDayBefore: 29, sevenDayAfter: 30, sevenDayDelta: 1,
            inputTokens: 1, outputTokens: 1, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 2,
            tppFiveHour: nil, tppSevenDay: 2, confidence: .low, messageCount: 1
        )
        storage.storedMeasurements = [fiveHourRow, livePassive]

        let count = await service.runBackfill(force: false)

        #expect(count == 1)
        #expect(storage.storedMeasurements.last?.timestamp == 4000)
        #expect(storage.storedMeasurements.last?.source == .passiveBackfill)
    }

    @Test("A stored row with no value does not hide a real reading, and blocks only a row with no value")
    func deltaOnlyOverlap() async {
        let (service, storage, _, parser) = make(polls: [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: nil, sevenDayUtil: 28),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, sevenDayUtil: 29),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 30),
        ])
        storage.storedMeasurements = [TPPMeasurement(
            id: nil, timestamp: 3000, windowStart: 2000, model: "unknown", variant: nil, source: .passive,
            fiveHourBefore: nil, fiveHourAfter: nil, fiveHourDelta: nil, sevenDayBefore: 29, sevenDayAfter: 30, sevenDayDelta: 1,
            inputTokens: 0, outputTokens: 0, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 0,
            tppFiveHour: nil, tppSevenDay: nil, confidence: .low, messageCount: 0
        )]

        await service.runBackfill(force: false)
        #expect(storage.storedMeasurements.map(\.tppSevenDay) == [nil, 1000])

        storage.storedMeasurements.removeLast()
        parser.tokensToReturn = []
        await service.runBackfill(force: false)
        // Two steps with no tokens, of which the second overlaps the stored row.
        #expect(storage.storedMeasurements.count == 2)
        #expect(storage.storedMeasurements.map(\.timestamp) == [3000, 2000])
    }

    @Test("After upgrade the weekly pass runs once, with no delete and no 5-hour rows")
    func automaticWeeklyPass() async {
        let (service, storage, prefs, _) = make(polls: [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: 10, sevenDayUtil: 25),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: 14, sevenDayUtil: 26),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 27),
            makePoll(id: 4, timestamp: 4000, fiveHourUtil: nil, sevenDayUtil: 28),
            makePoll(id: 5, timestamp: 5000, fiveHourUtil: nil, sevenDayUtil: 29),
        ], rollups: [
            makeRollup(id: 1, periodStart: 100, periodEnd: 200, fiveHourPeak: 15, fiveHourMin: 5),
        ])
        prefs.tppBackfillCompleted = true
        prefs.tppWeeklyBackfillCompleted = false

        await service.runBackfillIfNeeded()

        #expect(prefs.tppWeeklyBackfillCompleted)
        #expect(storage.deleteCallCount == 0)
        #expect(storage.storedMeasurements.map(\.basis) == [.weekly])
        #expect(storage.storedMeasurements[0].timestamp == 5000)

        await service.runBackfillIfNeeded()
        #expect(storage.storedMeasurements.count == 1)
    }

    @Test("A failed weekly pass stays open and retries on the next launch")
    func failedPassRetries() async {
        let hist = MockHistoricalDataService()
        hist.recentPollsToReturn = [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: nil, sevenDayUtil: 27),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, sevenDayUtil: 28),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 29),
        ]
        hist.shouldThrowOnGetRecentPolls = true
        let parser = MockBackfillLogParser()
        parser.tokensToReturn = [tokens]
        let storage = MockBackfillTPPStorage()
        let prefs = MockPreferencesManager()
        prefs.tppBackfillCompleted = true
        let service = HistoricalTPPBackfillService(historicalDataService: hist, logParser: parser, tppStorage: storage, preferencesManager: prefs)

        await service.runBackfillIfNeeded()
        #expect(!prefs.tppWeeklyBackfillCompleted)
        #expect(storage.storedMeasurements.isEmpty)

        hist.shouldThrowOnGetRecentPolls = false
        await service.runBackfillIfNeeded()
        #expect(prefs.tppWeeklyBackfillCompleted)
        #expect(storage.storedMeasurements.count == 1)
    }

    @Test("A weekly row that fails to store keeps the weekly pass open for the next launch")
    func failedStoreRetries() async {
        let hist = MockHistoricalDataService()
        hist.recentPollsToReturn = [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: nil, sevenDayUtil: 27),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, sevenDayUtil: 28),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 29),
        ]
        let parser = MockBackfillLogParser()
        parser.tokensToReturn = [tokens]
        let storage = MockBackfillTPPStorage()
        storage.shouldThrowOnStorePassive = true
        let prefs = MockPreferencesManager()
        prefs.tppBackfillCompleted = true
        let service = HistoricalTPPBackfillService(historicalDataService: hist, logParser: parser, tppStorage: storage, preferencesManager: prefs)

        await service.runBackfillIfNeeded()
        #expect(!prefs.tppWeeklyBackfillCompleted)

        storage.shouldThrowOnStorePassive = false
        await service.runBackfillIfNeeded()
        #expect(prefs.tppWeeklyBackfillCompleted)
        #expect(storage.storedMeasurements.count == 1)
    }

    @Test("If existing rows cannot be read, weekly rows wait for a later launch instead of risking duplicates")
    func unreadableRowsStoreNothing() async {
        let (service, storage, prefs, _) = make(polls: [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: nil, sevenDayUtil: 27),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, sevenDayUtil: 28),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 29),
        ])
        prefs.tppBackfillCompleted = true
        storage.shouldThrowOnGetMeasurements = true

        await service.runBackfillIfNeeded()

        #expect(storage.storedMeasurements.isEmpty)
        #expect(!prefs.tppWeeklyBackfillCompleted)
    }

    @Test("Backfill rows already in the database still trigger the weekly pass, once")
    func slowPathRunsWeeklyPass() async {
        let (service, storage, prefs, _) = make(polls: [
            makePoll(id: 1, timestamp: 10_000, fiveHourUtil: nil, sevenDayUtil: 27),
            makePoll(id: 2, timestamp: 20_000, fiveHourUtil: nil, sevenDayUtil: 28),
            makePoll(id: 3, timestamp: 30_000, fiveHourUtil: nil, sevenDayUtil: 29),
        ])
        storage.storedMeasurements = [TPPMeasurement(
            id: nil, timestamp: 1000, windowStart: 900, model: model, variant: nil, source: .passiveBackfill,
            fiveHourBefore: 1, fiveHourAfter: 2, fiveHourDelta: 1, sevenDayBefore: nil, sevenDayAfter: nil, sevenDayDelta: nil,
            inputTokens: 1, outputTokens: 1, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 2,
            tppFiveHour: 2, tppSevenDay: nil, confidence: .low, messageCount: 1
        )]

        await service.runBackfillIfNeeded()

        #expect(prefs.tppBackfillCompleted && prefs.tppWeeklyBackfillCompleted)
        #expect(storage.storedMeasurements.map(\.timestamp) == [1000, 30_000])
    }

    @Test("Force re-run keeps backfill rows older than the rebuild can reach")
    func forceKeepsOlderRows() async {
        let (service, storage, _, _) = make(
            polls: [
                makePoll(id: 1, timestamp: 10_000, fiveHourUtil: 10),
                makePoll(id: 2, timestamp: 11_000, fiveHourUtil: 12),
            ],
            rollups: [makeRollup(id: 1, periodStart: 5000, periodEnd: 6000, fiveHourPeak: 15, fiveHourMin: 5)]
        )
        func row(_ timestamp: Int64, _ source: MeasurementSource) -> TPPMeasurement {
            TPPMeasurement(
                id: nil, timestamp: timestamp, windowStart: timestamp - 500, model: "old", variant: nil, source: source,
                fiveHourBefore: 1, fiveHourAfter: 2, fiveHourDelta: 1, sevenDayBefore: nil, sevenDayAfter: nil, sevenDayDelta: nil,
                inputTokens: 1, outputTokens: 1, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 2,
                tppFiveHour: 2, tppSevenDay: nil, confidence: .low, messageCount: 1
            )
        }
        storage.storedMeasurements = [
            row(1000, .passiveBackfill),  // beyond raw polls: kept
            row(9000, .passiveBackfill),  // beyond raw polls, covered only by a rollup: kept
            row(11_000, .passiveBackfill),  // rebuilt
            row(1000, .rollupBackfill),  // older than the rollups: kept
            row(6000, .rollupBackfill),  // rebuilt
            row(500, .passive),
        ]

        await service.runBackfill(force: true)

        let old = storage.storedMeasurements.filter { $0.model == "old" }
        #expect(old.map(\.timestamp) == [1000, 9000, 1000, 500])
        #expect(storage.storedMeasurements.filter { $0.model == model }.map(\.source) == [.passiveBackfill, .rollupBackfill])
    }

    @Test("Force re-run never deletes a weekly row, and rebuilding adds no duplicate")
    func forceKeepsWeeklyRows() async {
        let (service, storage, _, _) = make(polls: [
            makePoll(id: 1, timestamp: 1000, fiveHourUtil: nil, sevenDayUtil: 28),
            makePoll(id: 2, timestamp: 2000, fiveHourUtil: nil, sevenDayUtil: 29),
            makePoll(id: 3, timestamp: 3000, fiveHourUtil: nil, sevenDayUtil: 30),
        ])
        // Its window starts before the raw polls, so a rebuild could not recreate this first step.
        let olderAnchor = TPPMeasurement(
            id: nil, timestamp: 2000, windowStart: 500, model: model, variant: nil, source: .passiveBackfill,
            fiveHourBefore: nil, fiveHourAfter: nil, fiveHourDelta: nil, sevenDayBefore: 28, sevenDayAfter: 29, sevenDayDelta: 1,
            inputTokens: 1, outputTokens: 1, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 2,
            tppFiveHour: nil, tppSevenDay: 2, confidence: .low, messageCount: 1
        )
        storage.storedMeasurements = [olderAnchor]

        await service.runBackfill(force: true)
        #expect(storage.storedMeasurements.map(\.timestamp) == [2000, 3000])

        await service.runBackfill(force: true)
        #expect(storage.storedMeasurements.map(\.timestamp) == [2000, 3000])
    }

    @Test("Force re-run with no source data deletes nothing")
    func forceWithNoDataDeletesNothing() async {
        let (service, storage, _, _) = make()
        storage.storedMeasurements = [TPPMeasurement(
            id: nil, timestamp: 1000, windowStart: 900, model: model, variant: nil, source: .passiveBackfill,
            fiveHourBefore: 1, fiveHourAfter: 2, fiveHourDelta: 1, sevenDayBefore: nil, sevenDayAfter: nil, sevenDayDelta: nil,
            inputTokens: 1, outputTokens: 1, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 2,
            tppFiveHour: 2, tppSevenDay: nil, confidence: .low, messageCount: 1
        )]

        await service.runBackfill(force: true)

        #expect(storage.storedMeasurements.count == 1)
    }
}
