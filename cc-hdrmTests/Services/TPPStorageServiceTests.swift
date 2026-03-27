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
