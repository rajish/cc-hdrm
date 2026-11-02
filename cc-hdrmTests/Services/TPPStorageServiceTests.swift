import Foundation
import Testing
@testable import cc_hdrm

@Suite("TPPStorageService Tests")
struct TPPStorageServiceTests {

    /// Creates an isolated DatabaseManager and TPPStorageService for testing.
    private func makeService() throws -> (TPPStorageService, DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("tpp_test_\(UUID().uuidString).db")
        let manager = DatabaseManager(databasePath: testPath)
        try manager.ensureSchema()
        let service = TPPStorageService(databaseManager: manager)
        return (service, manager, testPath)
    }

    private func cleanup(manager: DatabaseManager, path: URL) {
        manager.closeConnection()
        try? FileManager.default.removeItem(at: path)
    }

    @Test("storeBenchmarkResult inserts a measurement into the database")
    func storeAndRetrieve() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        let measurement = TPPMeasurement.fromBenchmark(
            model: "claude-sonnet-4-6",
            variant: .outputHeavy,
            fiveHourBefore: 10.0,
            fiveHourAfter: 12.0,
            sevenDayBefore: 5.0,
            sevenDayAfter: 5.5,
            inputTokens: 15,
            outputTokens: 985
        )

        try await service.storeBenchmarkResult(measurement)

        let latest = try await service.latestBenchmark(model: "claude-sonnet-4-6", variant: "output-heavy")
        #expect(latest != nil)
        #expect(latest?.model == "claude-sonnet-4-6")
        #expect(latest?.variant == "output-heavy")
        #expect(latest?.source == .benchmark)
        #expect(latest?.inputTokens == 15)
        #expect(latest?.outputTokens == 985)
        #expect(latest?.totalRawTokens == 1000)
    }

    @Test("latestBenchmark returns nil when no measurements exist")
    func latestBenchmarkEmpty() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        let latest = try await service.latestBenchmark(model: "claude-sonnet-4-6", variant: nil)
        #expect(latest == nil)
    }

    @Test("latestBenchmark with nil variant returns any variant for the model")
    func latestBenchmarkAnyVariant() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        let m1 = TPPMeasurement.fromBenchmark(
            model: "claude-sonnet-4-6",
            variant: .inputHeavy,
            fiveHourBefore: 10.0,
            fiveHourAfter: 12.0,
            sevenDayBefore: nil,
            sevenDayAfter: nil,
            inputTokens: 3000,
            outputTokens: 50
        )
        try await service.storeBenchmarkResult(m1)

        let latest = try await service.latestBenchmark(model: "claude-sonnet-4-6", variant: nil)
        #expect(latest != nil)
        #expect(latest?.variant == "input-heavy")
    }

    @Test("lastBenchmarkTimestamp returns the most recent benchmark timestamp")
    func lastBenchmarkTimestamp() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        // Initially nil
        let initialTs = try await service.lastBenchmarkTimestamp()
        #expect(initialTs == nil)

        let measurement = TPPMeasurement.fromBenchmark(
            model: "claude-sonnet-4-6",
            variant: .outputHeavy,
            fiveHourBefore: 10.0,
            fiveHourAfter: 12.0,
            sevenDayBefore: nil,
            sevenDayAfter: nil,
            inputTokens: 15,
            outputTokens: 985
        )
        try await service.storeBenchmarkResult(measurement)

        let ts = try await service.lastBenchmarkTimestamp()
        #expect(ts != nil)
        #expect(ts == measurement.timestamp)
    }

    @Test("Multiple measurements for same model returns latest")
    func latestBenchmarkReturnsMostRecent() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        // Insert an older measurement
        let old = TPPMeasurement(
            id: nil,
            timestamp: 1000,
            windowStart: 1000,
            model: "claude-sonnet-4-6",
            variant: "output-heavy",
            source: .benchmark,
            fiveHourBefore: 10.0,
            fiveHourAfter: 12.0,
            fiveHourDelta: 2.0,
            sevenDayBefore: nil,
            sevenDayAfter: nil,
            sevenDayDelta: nil,
            inputTokens: 15,
            outputTokens: 485,
            cacheCreateTokens: 0,
            cacheReadTokens: 0,
            totalRawTokens: 500,
            tppFiveHour: 250.0,
            tppSevenDay: nil,
            confidence: .high,
            messageCount: 1
        )
        try await service.storeBenchmarkResult(old)

        // Insert a newer measurement
        let new = TPPMeasurement(
            id: nil,
            timestamp: 2000,
            windowStart: 2000,
            model: "claude-sonnet-4-6",
            variant: "output-heavy",
            source: .benchmark,
            fiveHourBefore: 12.0,
            fiveHourAfter: 15.0,
            fiveHourDelta: 3.0,
            sevenDayBefore: nil,
            sevenDayAfter: nil,
            sevenDayDelta: nil,
            inputTokens: 20,
            outputTokens: 980,
            cacheCreateTokens: 0,
            cacheReadTokens: 0,
            totalRawTokens: 1000,
            tppFiveHour: 333.3,
            tppSevenDay: nil,
            confidence: .high,
            messageCount: 1
        )
        try await service.storeBenchmarkResult(new)

        let latest = try await service.latestBenchmark(model: "claude-sonnet-4-6", variant: "output-heavy")
        #expect(latest?.timestamp == 2000)
        #expect(latest?.totalRawTokens == 1000)
    }
}

// MARK: - Weekly Basis

@Suite("TPPStorageService Weekly Basis Tests")
struct TPPStorageServiceWeeklyBasisTests {
    private func makeService() throws -> (TPPStorageService, DatabaseManager, URL) {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("tpp_weekly_\(UUID().uuidString).db")
        let manager = DatabaseManager(databasePath: path)
        try manager.ensureSchema()
        return (TPPStorageService(databaseManager: manager), manager, path)
    }

    private func row(
        _ timestamp: Int64,
        source: MeasurementSource = .passive,
        basis: TPPBasis,
        tppFiveHour: Double? = nil,
        tppSevenDay: Double? = nil
    ) -> TPPMeasurement {
        TPPMeasurement(
            id: nil, timestamp: timestamp, windowStart: timestamp - 100, model: "m", variant: nil, source: source,
            fiveHourBefore: basis == .fiveHour ? 1 : nil, fiveHourAfter: basis == .fiveHour ? 2 : nil, fiveHourDelta: basis == .fiveHour ? 1 : nil,
            sevenDayBefore: 10, sevenDayAfter: 11, sevenDayDelta: 1,
            inputTokens: 1, outputTokens: 1, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 2,
            tppFiveHour: tppFiveHour, tppSevenDay: tppSevenDay, confidence: .low, messageCount: 1
        )
    }

    @Test("A stored row keeps its basis on an existing schema, with no migration")
    func basisSurvivesStorage() async throws {
        let (service, manager, path) = try makeService()
        defer { manager.closeConnection(); try? FileManager.default.removeItem(at: path) }

        try await service.storePassiveResult(row(1000, basis: .weekly, tppSevenDay: 500))
        try await service.storePassiveResult(row(2000, basis: .fiveHour, tppFiveHour: 50, tppSevenDay: 40))

        let rows = try await service.getMeasurements(from: 0, to: Int64.max, source: nil, model: nil, confidence: nil)
        #expect(rows.map(\.basis) == [.weekly, .fiveHour])
        #expect(rows.map(\.chartTPP) == [500, 50])
        #expect(try manager.getSchemaVersion() == 9)
    }

    @Test("Averages stay on one basis: a 5-hour row's weekly value does not join weekly rows")
    func averagesPerBasis() async throws {
        let (service, manager, path) = try makeService()
        defer { manager.closeConnection(); try? FileManager.default.removeItem(at: path) }

        try await service.storePassiveResult(row(1000, basis: .fiveHour, tppFiveHour: 100, tppSevenDay: 7))
        try await service.storePassiveResult(row(2000, basis: .fiveHour, tppFiveHour: 200, tppSevenDay: 9))
        try await service.storePassiveResult(row(3000, basis: .weekly, tppSevenDay: 1000))
        try await service.storePassiveResult(row(4000, basis: .weekly, tppSevenDay: 3000))

        let average = try await service.getAverageTPP(from: 0, to: Int64.max, model: nil, source: nil)
        #expect(average.fiveHour == 150)
        #expect(average.sevenDay == 2000)
    }

    @Test("Scoped delete keeps weekly backfill rows")
    func scopedDeleteKeepsWeekly() async throws {
        let (service, manager, path) = try makeService()
        defer { manager.closeConnection(); try? FileManager.default.removeItem(at: path) }

        try await service.storePassiveResult(row(5000, source: .passiveBackfill, basis: .weekly, tppSevenDay: 500))
        try await service.storePassiveResult(row(5000, source: .rollupBackfill, basis: .weekly, tppSevenDay: 500))

        try await service.deleteBackfillRecords(passiveFrom: 0, rollupFrom: 0)

        let rows = try await service.getMeasurements(from: 0, to: Int64.max, source: nil, model: nil, confidence: nil)
        #expect(rows.count == 2)
    }

    @Test("Scoped delete removes only rebuildable backfill rows, never passive or benchmark rows")
    func scopedDelete() async throws {
        let (service, manager, path) = try makeService()
        defer { manager.closeConnection(); try? FileManager.default.removeItem(at: path) }

        try await service.storePassiveResult(row(1000, source: .passiveBackfill, basis: .fiveHour))
        try await service.storePassiveResult(row(5000, source: .passiveBackfill, basis: .fiveHour))
        try await service.storePassiveResult(row(1000, source: .rollupBackfill, basis: .fiveHour))
        try await service.storePassiveResult(row(5000, source: .rollupBackfill, basis: .fiveHour))
        try await service.storePassiveResult(row(5000, source: .passive, basis: .fiveHour))
        try await service.storePassiveResult(row(5000, source: .benchmark, basis: .fiveHour))

        try await service.deleteBackfillRecords(passiveFrom: 5000, rollupFrom: 2000)

        let rows = try await service.getMeasurements(from: 0, to: Int64.max, source: nil, model: nil, confidence: nil)
        let remaining = rows.map { "\($0.source.rawValue)@\($0.timestamp)" }.sorted()
        #expect(remaining == ["benchmark@5000", "passive-backfill@1000", "passive@5000", "rollup-backfill@1000"])
    }

    @Test("A nil limit deletes nothing for that source")
    func nilLimits() async throws {
        let (service, manager, path) = try makeService()
        defer { manager.closeConnection(); try? FileManager.default.removeItem(at: path) }

        try await service.storePassiveResult(row(5000, source: .passiveBackfill, basis: .fiveHour))
        try await service.storePassiveResult(row(5000, source: .rollupBackfill, basis: .fiveHour))

        try await service.deleteBackfillRecords(passiveFrom: nil, rollupFrom: nil)

        let rows = try await service.getMeasurements(from: 0, to: Int64.max, source: nil, model: nil, confidence: nil)
        #expect(rows.count == 2)
    }
}
