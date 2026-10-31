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

    private func makeRow(timestamp: Int64, source: MeasurementSource, fiveHourDelta: Double?, sevenDayDelta: Double?) -> TPPMeasurement {
        TPPMeasurement(
            id: nil,
            timestamp: timestamp,
            windowStart: timestamp - 1000,
            model: "claude-sonnet-4-6",
            variant: nil,
            source: source,
            fiveHourBefore: fiveHourDelta.map { _ in 10.0 },
            fiveHourAfter: fiveHourDelta.map { 10.0 + $0 },
            fiveHourDelta: fiveHourDelta,
            sevenDayBefore: sevenDayDelta.map { _ in 28.0 },
            sevenDayAfter: sevenDayDelta.map { 28.0 + $0 },
            sevenDayDelta: sevenDayDelta,
            inputTokens: 500,
            outputTokens: 500,
            cacheCreateTokens: 0,
            cacheReadTokens: 0,
            totalRawTokens: 1000,
            tppFiveHour: fiveHourDelta.map { 1000.0 / $0 },
            tppSevenDay: sevenDayDelta.map { 1000.0 / $0 },
            confidence: .low,
            messageCount: 1
        )
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

    @Test("deleteBackfillRecords removes only weekly backfill rows and keeps 5h-based backfill rows")
    func deleteBackfillKeepsFiveHourRows() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        let rows = [
            makeRow(timestamp: 1000, source: .passiveBackfill, fiveHourDelta: 2.0, sevenDayDelta: nil),  // old 5h-based — kept
            makeRow(timestamp: 2000, source: .rollupBackfill, fiveHourDelta: 5.0, sevenDayDelta: 1.0),   // old 5h-based — kept
            makeRow(timestamp: 3000, source: .passiveBackfill, fiveHourDelta: nil, sevenDayDelta: 1.0),  // weekly — deleted
            makeRow(timestamp: 4000, source: .rollupBackfill, fiveHourDelta: nil, sevenDayDelta: 2.0),   // weekly — deleted
            makeRow(timestamp: 5000, source: .passive, fiveHourDelta: nil, sevenDayDelta: 1.0),          // not backfill — kept
        ]
        for row in rows {
            try await service.storePassiveResult(row)
        }

        try await service.deleteBackfillRecords()

        let remaining = try await service.getMeasurements(from: 0, to: Int64.max, source: nil, model: nil, confidence: nil)
        #expect(remaining.map(\.timestamp) == [1000, 2000, 5000])
    }
}
