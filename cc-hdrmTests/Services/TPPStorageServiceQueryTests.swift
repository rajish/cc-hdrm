import Foundation
import Testing
@testable import cc_hdrm

@Suite("TPPStorageService Query Tests")
struct TPPStorageServiceQueryTests {

    /// Creates an isolated DatabaseManager and TPPStorageService for testing.
    private func makeService() throws -> (TPPStorageService, DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("tpp_query_test_\(UUID().uuidString).db")
        let manager = DatabaseManager(databasePath: testPath)
        try manager.ensureSchema()
        let service = TPPStorageService(databaseManager: manager)
        return (service, manager, testPath)
    }

    private func cleanup(manager: DatabaseManager, path: URL) {
        manager.closeConnection()
        try? FileManager.default.removeItem(at: path)
    }

    private func makePassiveMeasurement(
        timestamp: Int64,
        model: String = "claude-sonnet-4-6",
        fiveHourDelta: Double = 2.0,
        inputTokens: Int = 500,
        outputTokens: Int = 500,
        confidence: MeasurementConfidence = .medium
    ) -> TPPMeasurement {
        let totalRaw = inputTokens + outputTokens
        return TPPMeasurement(
            id: nil,
            timestamp: timestamp,
            windowStart: timestamp - 1000,
            model: model,
            variant: nil,
            source: .passive,
            fiveHourBefore: 10.0,
            fiveHourAfter: 10.0 + fiveHourDelta,
            fiveHourDelta: fiveHourDelta,
            sevenDayBefore: nil,
            sevenDayAfter: nil,
            sevenDayDelta: nil,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreateTokens: 0,
            cacheReadTokens: 0,
            totalRawTokens: totalRaw,
            tppFiveHour: Double(totalRaw) / fiveHourDelta,
            tppSevenDay: nil,
            confidence: confidence,
            messageCount: 1
        )
    }

    @Test("storePassiveResult inserts a passive measurement")
    func storePassiveResult() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        let measurement = makePassiveMeasurement(timestamp: 5000, model: "claude-sonnet-4-6")
        try await service.storePassiveResult(measurement)

        let results = try await service.getMeasurements(from: 0, to: 10000, source: .passive, model: nil, confidence: nil)
        #expect(results.count == 1)
        #expect(results[0].model == "claude-sonnet-4-6")
        #expect(results[0].source == .passive)
    }

    @Test("getMeasurements with source filter")
    func getMeasurementsSourceFilter() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        let passive = makePassiveMeasurement(timestamp: 5000)
        try await service.storePassiveResult(passive)

        let benchmark = TPPMeasurement.fromBenchmark(
            model: "claude-sonnet-4-6",
            variant: .outputHeavy,
            fiveHourBefore: 10.0,
            fiveHourAfter: 12.0,
            sevenDayBefore: nil,
            sevenDayAfter: nil,
            inputTokens: 500,
            outputTokens: 500
        )
        try await service.storeBenchmarkResult(benchmark)

        // Filter by passive only
        let passiveResults = try await service.getMeasurements(from: 0, to: Int64.max, source: .passive, model: nil, confidence: nil)
        #expect(passiveResults.count == 1)
        #expect(passiveResults[0].source == .passive)

        // Filter by benchmark only
        let benchmarkResults = try await service.getMeasurements(from: 0, to: Int64.max, source: .benchmark, model: nil, confidence: nil)
        #expect(benchmarkResults.count == 1)
        #expect(benchmarkResults[0].source == .benchmark)

        // No filter — returns all
        let allResults = try await service.getMeasurements(from: 0, to: Int64.max, source: nil, model: nil, confidence: nil)
        #expect(allResults.count == 2)
    }

    @Test("getMeasurements with model filter")
    func getMeasurementsModelFilter() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        try await service.storePassiveResult(makePassiveMeasurement(timestamp: 5000, model: "claude-sonnet-4-6"))
        try await service.storePassiveResult(makePassiveMeasurement(timestamp: 6000, model: "claude-opus-4-6"))

        let sonnetResults = try await service.getMeasurements(from: 0, to: Int64.max, source: nil, model: "claude-sonnet-4-6", confidence: nil)
        #expect(sonnetResults.count == 1)
        #expect(sonnetResults[0].model == "claude-sonnet-4-6")
    }

    @Test("getMeasurements with confidence filter")
    func getMeasurementsConfidenceFilter() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        try await service.storePassiveResult(makePassiveMeasurement(timestamp: 5000, confidence: .medium))
        try await service.storePassiveResult(makePassiveMeasurement(timestamp: 6000, confidence: .low))

        let mediumResults = try await service.getMeasurements(from: 0, to: Int64.max, source: nil, model: nil, confidence: .medium)
        #expect(mediumResults.count == 1)
        #expect(mediumResults[0].confidence == .medium)
    }

    @Test("getMeasurements returns results sorted by timestamp ascending")
    func getMeasurementsOrdering() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        try await service.storePassiveResult(makePassiveMeasurement(timestamp: 8000))
        try await service.storePassiveResult(makePassiveMeasurement(timestamp: 5000))
        try await service.storePassiveResult(makePassiveMeasurement(timestamp: 6000))

        let results = try await service.getMeasurements(from: 0, to: Int64.max, source: nil, model: nil, confidence: nil)
        #expect(results.count == 3)
        #expect(results[0].timestamp == 5000)
        #expect(results[1].timestamp == 6000)
        #expect(results[2].timestamp == 8000)
    }

    @Test("getAverageTPP computes correct averages")
    func getAverageTPP() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        // Two measurements with TPP 5h: 500.0 and 300.0 → average 400.0
        try await service.storePassiveResult(makePassiveMeasurement(
            timestamp: 5000, fiveHourDelta: 2.0, inputTokens: 500, outputTokens: 500  // TPP = 500.0
        ))
        try await service.storePassiveResult(makePassiveMeasurement(
            timestamp: 6000, fiveHourDelta: 2.0, inputTokens: 300, outputTokens: 0  // TPP = 150.0
        ))

        let avg = try await service.getAverageTPP(from: 0, to: Int64.max, model: nil, source: nil)
        #expect(avg.fiveHour != nil)
        // (500.0 + 150.0) / 2 = 325.0
        let fh = try #require(avg.fiveHour)
        #expect(abs(fh - 325.0) < 0.01)
    }

    @Test("getAverageTPP returns nil when no data")
    func getAverageTPPEmpty() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        let avg = try await service.getAverageTPP(from: 0, to: Int64.max, model: nil, source: nil)
        #expect(avg.fiveHour == nil)
        #expect(avg.sevenDay == nil)
    }

    @Test("getAverageTPP with model filter")
    func getAverageTPPModelFilter() async throws {
        let (service, manager, path) = try makeService()
        defer { cleanup(manager: manager, path: path) }

        try await service.storePassiveResult(makePassiveMeasurement(
            timestamp: 5000, model: "claude-sonnet-4-6", fiveHourDelta: 2.0, inputTokens: 500, outputTokens: 500
        ))
        try await service.storePassiveResult(makePassiveMeasurement(
            timestamp: 6000, model: "claude-opus-4-6", fiveHourDelta: 2.0, inputTokens: 100, outputTokens: 100
        ))

        let avg = try await service.getAverageTPP(from: 0, to: Int64.max, model: "claude-sonnet-4-6", source: nil)
        let fh = try #require(avg.fiveHour)
        #expect(abs(fh - 500.0) < 0.01)
    }
}
