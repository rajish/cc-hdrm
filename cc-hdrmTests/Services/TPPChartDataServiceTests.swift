import Testing
@testable import cc_hdrm

// MARK: - Mock TPP Storage

private final class MockChartTPPStorage: TPPStorageServiceProtocol, @unchecked Sendable {
    var measurements: [TPPMeasurement] = []
    var averageResult: (fiveHour: Double?, sevenDay: Double?) = (nil, nil)
    var latestBenchmarks: [String: TPPMeasurement] = []  // keyed by "model-variant"

    func storeBenchmarkResult(_ measurement: TPPMeasurement) async throws {
        measurements.append(measurement)
    }

    func latestBenchmark(model: String, variant: String?) async throws -> TPPMeasurement? {
        let key = "\(model)-\(variant ?? "any")"
        return latestBenchmarks[key]
    }

    func lastBenchmarkTimestamp() async throws -> Int64? {
        return measurements.filter { $0.source == .benchmark }.last?.timestamp
    }

    func storePassiveResult(_ measurement: TPPMeasurement) async throws {
        measurements.append(measurement)
    }

    func getMeasurements(from: Int64, to: Int64, source: MeasurementSource?, model: String?, confidence: MeasurementConfidence?) async throws -> [TPPMeasurement] {
        return measurements.filter { m in
            m.timestamp >= from && m.timestamp <= to
                && (source == nil || m.source == source)
                && (model == nil || m.model == model)
                && (confidence == nil || m.confidence == confidence)
        }.sorted { $0.timestamp < $1.timestamp }
    }

    func getAverageTPP(from: Int64, to: Int64, model: String?, source: MeasurementSource?) async throws -> (fiveHour: Double?, sevenDay: Double?) {
        return averageResult
    }
}

// MARK: - Test Helpers

private func makeMeasurement(
    timestamp: Int64,
    model: String = "claude-sonnet-4-6",
    variant: String? = nil,
    source: MeasurementSource = .passive,
    tppFiveHour: Double? = 1000.0,
    confidence: MeasurementConfidence = .high
) -> TPPMeasurement {
    TPPMeasurement(
        id: nil,
        timestamp: timestamp,
        windowStart: timestamp,
        model: model,
        variant: variant,
        source: source,
        fiveHourBefore: 50.0,
        fiveHourAfter: 51.0,
        fiveHourDelta: 1.0,
        sevenDayBefore: nil,
        sevenDayAfter: nil,
        sevenDayDelta: nil,
        inputTokens: 500,
        outputTokens: 500,
        cacheCreateTokens: 0,
        cacheReadTokens: 0,
        totalRawTokens: 1000,
        tppFiveHour: tppFiveHour,
        tppSevenDay: nil,
        confidence: confidence,
        messageCount: 1
    )
}

private let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
private let oneHourMs: Int64 = 3_600_000
private let oneDayMs: Int64 = 86_400_000

// MARK: - Tests

@Suite("TPPChartDataService Tests")
struct TPPChartDataServiceTests {

    // MARK: - Insight Text

    @Test("Insight text: benchmark drop >20% shows dropped message")
    func insightBenchmarkDrop() async throws {
        let storage = MockChartTPPStorage()
        storage.averageResult = (fiveHour: 1000.0, sevenDay: nil)
        let benchmarks = [makeMeasurement(timestamp: nowMs, source: .benchmark, tppFiveHour: 700.0)]

        let service = TPPChartDataService(tppStorage: storage)
        let insight = try await service.computeInsightText(
            benchmarkMeasurements: benchmarks,
            passivePoints: [],
            model: nil
        )

        #expect(insight.contains("dropped"))
        #expect(insight.contains("30%"))
    }

    @Test("Insight text: stable benchmark shows stable message")
    func insightBenchmarkStable() async throws {
        let storage = MockChartTPPStorage()
        storage.averageResult = (fiveHour: 1000.0, sevenDay: nil)
        let benchmarks = [makeMeasurement(timestamp: nowMs, source: .benchmark, tppFiveHour: 950.0)]

        let service = TPPChartDataService(tppStorage: storage)
        let insight = try await service.computeInsightText(
            benchmarkMeasurements: benchmarks,
            passivePoints: [],
            model: nil
        )

        #expect(insight.contains("stable"))
    }

    @Test("Insight text: no benchmark, passive data shows passive suggestion")
    func insightPassiveOnly() async throws {
        let storage = MockChartTPPStorage()
        let passivePoints = (0..<7).map { i in
            TPPChartPoint(
                timestamp: Date(timeIntervalSince1970: Double(nowMs - Int64(i) * oneDayMs) / 1000.0),
                tppValue: 1000.0 - Double(i) * 20,
                source: .passive,
                confidence: .medium,
                isAverage: false
            )
        }

        let service = TPPChartDataService(tppStorage: storage)
        let insight = try await service.computeInsightText(
            benchmarkMeasurements: [],
            passivePoints: passivePoints,
            model: nil
        )

        #expect(insight.contains("Passive monitoring"))
        #expect(insight.contains("benchmark"))
    }

    @Test("Insight text: no data shows empty message")
    func insightNoData() async throws {
        let storage = MockChartTPPStorage()
        let service = TPPChartDataService(tppStorage: storage)
        let insight = try await service.computeInsightText(
            benchmarkMeasurements: [],
            passivePoints: [],
            model: nil
        )

        #expect(insight.contains("Run a benchmark"))
    }

    // MARK: - Daily Averages

    @Test("Daily averages: multiple points in one day produce single averaged point")
    func dailyAverage() {
        let storage = MockChartTPPStorage()
        let service = TPPChartDataService(tppStorage: storage)

        let baseDayMs = nowMs - oneDayMs
        let measurements = (0..<5).map { i in
            makeMeasurement(
                timestamp: baseDayMs + Int64(i) * oneHourMs,
                tppFiveHour: Double(800 + i * 100)
            )
        }

        let result = service.computeDailyAverages(from: measurements)
        #expect(result.count == 1)
        // Average of 800, 900, 1000, 1100, 1200 = 1000
        #expect(result.first?.tppValue == 1000.0)
        #expect(result.first?.isAverage == true)
    }

    // MARK: - Moving Average

    @Test("Moving average: 7-point window produces correct smoothed values")
    func movingAverage() {
        let storage = MockChartTPPStorage()
        let service = TPPChartDataService(tppStorage: storage)

        // 10 points with known values
        let points = (0..<10).map { i in
            TPPChartPoint(
                timestamp: Date(timeIntervalSince1970: Double(nowMs + Int64(i) * oneDayMs) / 1000.0),
                tppValue: Double(100 * (i + 1)),  // 100, 200, 300, ..., 1000
                source: .passive,
                confidence: .high,
                isAverage: false
            )
        }

        let result = service.computeMovingAverage(points: points, windowSize: 7)

        // Should have 10 - 7 + 1 = 4 points
        #expect(result.count == 4)

        // First MA: avg(100..700) = 400
        #expect(result[0].tppValue == 400.0)
        // Second MA: avg(200..800) = 500
        #expect(result[1].tppValue == 500.0)
    }

    @Test("Moving average: fewer than window size points returns empty")
    func movingAverageTooFew() {
        let storage = MockChartTPPStorage()
        let service = TPPChartDataService(tppStorage: storage)

        let points = (0..<5).map { i in
            TPPChartPoint(
                timestamp: Date(timeIntervalSince1970: Double(nowMs + Int64(i) * oneDayMs) / 1000.0),
                tppValue: Double(100 * (i + 1)),
                source: .passive,
                confidence: .high,
                isAverage: false
            )
        }

        let result = service.computeMovingAverage(points: points, windowSize: 7)
        #expect(result.isEmpty)
    }

    // MARK: - Shift Detection

    @Test("Shift detection: 30% TPP drop produces annotation with correct direction")
    func shiftDetectionDrop() {
        let storage = MockChartTPPStorage()
        let service = TPPChartDataService(tppStorage: storage)

        // Create points: first 7 stable at 1000, then 5 drop to 600 (40% below)
        var points: [TPPChartPoint] = []
        for i in 0..<12 {
            let value: Double = i < 7 ? 1000.0 : 600.0
            points.append(TPPChartPoint(
                timestamp: Date(timeIntervalSince1970: Double(nowMs + Int64(i) * oneDayMs) / 1000.0),
                tppValue: value,
                source: .passive,
                confidence: .high,
                isAverage: false
            ))
        }

        let trendLine = service.computeMovingAverage(points: points, windowSize: 7)
        let shifts = service.detectShifts(points: points, trendLine: trendLine)

        #expect(!shifts.isEmpty)
        #expect(shifts.first?.direction == .down)
        #expect(shifts.first?.label.contains("dropped") == true)
    }

    // MARK: - Model Discovery

    @Test("Model discovery: mixed models sorted by frequency descending")
    func modelDiscovery() async throws {
        let storage = MockChartTPPStorage()
        // Add 5 sonnet, 3 opus, 1 haiku
        for i in 0..<5 {
            storage.measurements.append(makeMeasurement(timestamp: nowMs - Int64(i) * oneHourMs, model: "claude-sonnet-4-6"))
        }
        for i in 0..<3 {
            storage.measurements.append(makeMeasurement(timestamp: nowMs - Int64(i) * oneHourMs, model: "claude-opus-4-6"))
        }
        storage.measurements.append(makeMeasurement(timestamp: nowMs, model: "claude-haiku-4-5"))

        let service = TPPChartDataService(tppStorage: storage)
        let models = try await service.availableModels()

        #expect(models.count == 3)
        #expect(models.first == "claude-sonnet-4-6")
        #expect(models.last == "claude-haiku-4-5")
    }

    // MARK: - Weighting Discovery

    @Test("Weighting discovery: output-heavy TPP lower than input-heavy produces ratio >1")
    func weightingDiscovery() async throws {
        let storage = MockChartTPPStorage()
        let model = "claude-sonnet-4-6"

        // output-heavy: TPP=1000 (cheaper, more tokens per %)
        storage.latestBenchmarks["\(model)-output-heavy"] = makeMeasurement(
            timestamp: nowMs,
            model: model,
            variant: "output-heavy",
            source: .benchmark,
            tppFiveHour: 1000.0
        )
        // input-heavy: TPP=5000 (most tokens per %)
        storage.latestBenchmarks["\(model)-input-heavy"] = makeMeasurement(
            timestamp: nowMs,
            model: model,
            variant: "input-heavy",
            source: .benchmark,
            tppFiveHour: 5000.0
        )

        let service = TPPChartDataService(tppStorage: storage)
        let data = try await service.loadTPPData(timeRange: .week, model: model)

        #expect(data.weightingDiscovery != nil)
        #expect(data.weightingDiscovery?.outputToInputRatio == 5.0)
    }

    // MARK: - Time Range Filtering

    @Test("Time range filtering: day range returns only last 24h data")
    func timeRangeDay() async throws {
        let storage = MockChartTPPStorage()
        // One within 24h, one outside
        storage.measurements.append(makeMeasurement(timestamp: nowMs - oneHourMs))
        storage.measurements.append(makeMeasurement(timestamp: nowMs - 2 * oneDayMs))

        let service = TPPChartDataService(tppStorage: storage)
        let data = try await service.loadTPPData(timeRange: .day, model: nil)

        #expect(data.passivePoints.count == 1)
    }
}
