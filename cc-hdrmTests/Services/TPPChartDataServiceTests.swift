import Foundation
import Testing
@testable import cc_hdrm

// MARK: - Mock TPP Storage

private final class MockChartTPPStorage: TPPStorageServiceProtocol, @unchecked Sendable {
    var measurements: [TPPMeasurement] = []
    var averageResult: (fiveHour: Double?, sevenDay: Double?) = (nil, nil)
    var latestBenchmarks: [String: TPPMeasurement] = [:]  // keyed by "model-variant"

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

    func deleteBackfillRecords(passiveFrom: Int64?, rollupFrom: Int64?) async throws {}
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

        // Anchor at noon yesterday so all 5 hourly points stay in one calendar day
        let yesterdayNoon = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400)).addingTimeInterval(12 * 3_600)
        let baseDayMs = Int64(yesterdayNoon.timeIntervalSince1970 * 1000)
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

    @Test("Model discovery: models sorted by most recent measurement, newest first")
    func modelDiscovery() async throws {
        let storage = MockChartTPPStorage()
        // Opus has the most history but nothing recent; fable is newest with a single measurement
        for i in 0..<20 {
            storage.measurements.append(makeMeasurement(timestamp: nowMs - Int64(i + 48) * oneHourMs, model: "claude-opus-4-6"))
        }
        for i in 0..<5 {
            storage.measurements.append(makeMeasurement(timestamp: nowMs - Int64(i + 2) * oneHourMs, model: "claude-sonnet-4-6"))
        }
        storage.measurements.append(makeMeasurement(timestamp: nowMs, model: "claude-fable-5"))

        let service = TPPChartDataService(tppStorage: storage)
        let models = try await service.availableModels()

        #expect(models == ["claude-fable-5", "claude-sonnet-4-6", "claude-opus-4-6"])
    }

    @Test("Model discovery: equal recency falls back to measurement count")
    func modelDiscoveryTieBreak() async throws {
        let storage = MockChartTPPStorage()
        for i in 0..<3 {
            storage.measurements.append(makeMeasurement(timestamp: nowMs - Int64(i) * oneHourMs, model: "claude-sonnet-4-6"))
        }
        storage.measurements.append(makeMeasurement(timestamp: nowMs, model: "claude-haiku-4-5"))

        let service = TPPChartDataService(tppStorage: storage)
        let models = try await service.availableModels()

        #expect(models == ["claude-sonnet-4-6", "claude-haiku-4-5"])
    }

    // MARK: - Weighting Discovery

    @Test("Weighting discovery: output-heavy TPP lower than input-heavy produces ratio >1")
    func weightingDiscovery() async throws {
        let storage = MockChartTPPStorage()
        let model = "claude-sonnet-4-6"

        // output-heavy: TPP=1000 (cheaper, more tokens per %)
        let outputHeavy = makeMeasurement(
            timestamp: nowMs,
            model: model,
            variant: "output-heavy",
            source: .benchmark,
            tppFiveHour: 1000.0
        )
        // input-heavy: TPP=5000 (most tokens per %)
        let inputHeavy = makeMeasurement(
            timestamp: nowMs,
            model: model,
            variant: "input-heavy",
            source: .benchmark,
            tppFiveHour: 5000.0
        )
        storage.latestBenchmarks["\(model)-output-heavy"] = outputHeavy
        storage.latestBenchmarks["\(model)-input-heavy"] = inputHeavy
        storage.measurements = [outputHeavy, inputHeavy]

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

// MARK: - Bases

@Suite("TPPChartDataService Basis Tests")
struct TPPChartDataServiceBasisTests {
    private func weekly(_ timestamp: Int64, tpp: Double?, source: MeasurementSource = .passive) -> TPPMeasurement {
        TPPMeasurement(
            id: nil, timestamp: timestamp, windowStart: timestamp - 1000, model: "claude-sonnet-4-6", variant: nil, source: source,
            fiveHourBefore: nil, fiveHourAfter: nil, fiveHourDelta: nil,
            sevenDayBefore: 10, sevenDayAfter: 11, sevenDayDelta: 1,
            inputTokens: 500, outputTokens: 500, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 1000,
            tppFiveHour: nil, tppSevenDay: tpp, confidence: .low, messageCount: 1
        )
    }

    private func makeService(_ measurements: [TPPMeasurement]) -> (TPPChartDataService, MockChartTPPStorage) {
        let storage = MockChartTPPStorage()
        storage.measurements = measurements
        return (TPPChartDataService(tppStorage: storage), storage)
    }

    @Test("Only 5-hour rows: values, label and caption are as in 1.6.0, with no picker")
    func fiveHourOnlyUnchanged() async throws {
        let (service, _) = makeService([
            makeMeasurement(timestamp: nowMs - oneHourMs * 2, tppFiveHour: 1000),
            makeMeasurement(timestamp: nowMs - oneHourMs, tppFiveHour: 2000),
        ])

        let data = try await service.loadTPPData(timeRange: .day, model: nil)

        #expect(data.passivePoints.map(\.tppValue) == [1000, 2000])
        #expect(data.basis == .fiveHour)
        #expect(data.availableBases == [.fiveHour])
        #expect(data.yAxisLabel == "tokens/%")
        #expect(data.basisCaption == nil)
        #expect(data.insightText == "Passive monitoring suggests efficiency is improving. Run a benchmark to confirm.")
    }

    @Test("A 5-hour row's weekly value is never charted")
    func fiveHourRowWeeklyValueHidden() async throws {
        let row = TPPMeasurement(
            id: nil, timestamp: nowMs - oneHourMs, windowStart: nowMs - oneHourMs - 1000, model: "claude-sonnet-4-6", variant: nil, source: .passive,
            fiveHourBefore: 10, fiveHourAfter: 10, fiveHourDelta: 0,
            sevenDayBefore: 20, sevenDayAfter: 21, sevenDayDelta: 1,
            inputTokens: 500, outputTokens: 500, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 1000,
            tppFiveHour: nil, tppSevenDay: 1000, confidence: .low, messageCount: 1
        )
        let (service, _) = makeService([row])

        let data = try await service.loadTPPData(timeRange: .day, model: nil)

        #expect(data.passivePoints.isEmpty)
    }

    @Test("Only weekly rows: charted and labelled as weekly")
    func weeklyOnly() async throws {
        let (service, _) = makeService([weekly(nowMs - oneHourMs, tpp: 40_000)])

        let data = try await service.loadTPPData(timeRange: .day, model: nil)

        #expect(data.passivePoints.map(\.tppValue) == [40_000])
        #expect(data.basis == .weekly)
        #expect(data.availableBases == [.weekly])
        #expect(data.yAxisLabel == "tokens per weekly %")
        #expect(data.basisCaption?.contains("weekly steps") == true)
        #expect(data.insightText.contains("Run a benchmark") == false)
    }

    @Test("Both bases: the default follows the newest passive row")
    func defaultFollowsNewest() async throws {
        let older5h = makeMeasurement(timestamp: nowMs - oneHourMs * 3, tppFiveHour: 4000)
        let newer = weekly(nowMs - oneHourMs, tpp: 40_000)
        let (toWeekly, _) = makeService([older5h, newer])
        #expect(try await toWeekly.loadTPPData(timeRange: .day, model: nil).basis == .weekly)

        let (toFiveHour, _) = makeService([weekly(nowMs - oneHourMs * 3, tpp: 40_000), makeMeasurement(timestamp: nowMs - oneHourMs, tppFiveHour: 4000)])
        #expect(try await toFiveHour.loadTPPData(timeRange: .day, model: nil).basis == .fiveHour)
    }

    @Test("Old 5-hour benchmarks do not pull a weekly account back to 5-hour")
    func benchmarkDoesNotSetDefault() async throws {
        let (service, _) = makeService([
            weekly(nowMs - oneHourMs * 3, tpp: 40_000),
            makeMeasurement(timestamp: nowMs - oneHourMs, source: .benchmark, tppFiveHour: 4000),
        ])

        let data = try await service.loadTPPData(timeRange: .day, model: nil)

        #expect(data.basis == .weekly)
        #expect(data.benchmarkPoints.isEmpty)
        #expect(data.availableBases == [.weekly, .fiveHour])

        let fiveHour = try await service.loadTPPData(timeRange: .day, model: nil, basis: .fiveHour)
        #expect(fiveHour.benchmarkPoints.map(\.tppValue) == [4000])
        #expect(fiveHour.passivePoints.isEmpty)
    }

    @Test("No 5-hour number: past benchmarks stay charted, described as history with no prompt to run one")
    func noNumberPastBenchmarks() async throws {
        let (service, _) = makeService([
            makeMeasurement(timestamp: nowMs - oneHourMs, source: .benchmark, tppFiveHour: 4000),
        ])

        let noNumber = try await service.loadTPPData(timeRange: .day, model: nil, basis: .fiveHour, hasNoFiveHourNumber: true)
        #expect(noNumber.benchmarkPoints.map(\.tppValue) == [4000])
        #expect(noNumber.insightText == "These are earlier 5-hour readings. This account no longer has a 5-hour limit.")

        let withNumber = try await service.loadTPPData(timeRange: .day, model: nil, basis: .fiveHour)
        #expect(withNumber.insightText == "Run a benchmark to get a calibrated reading of your token efficiency.")
    }

    @Test("No 5-hour number: old trends and benchmark comparisons are not presented as current")
    func noNumberOldTrend() async throws {
        let (service, storage) = makeService([
            makeMeasurement(timestamp: nowMs - oneHourMs * 3, source: .benchmark, tppFiveHour: 4000),
            makeMeasurement(timestamp: nowMs - oneHourMs * 2, tppFiveHour: 1000),
            makeMeasurement(timestamp: nowMs - oneHourMs, tppFiveHour: 2000),
        ])
        storage.averageResult = (fiveHour: 8000, sevenDay: nil)

        let data = try await service.loadTPPData(timeRange: .day, model: nil, basis: .fiveHour, hasNoFiveHourNumber: true)

        #expect(data.insightText == "These are earlier 5-hour readings. This account no longer has a 5-hour limit.")
    }

    @Test("No 5-hour number: the weekly basis keeps its own text")
    func noNumberWeeklyBasis() async throws {
        let (service, _) = makeService([weekly(nowMs - oneHourMs, tpp: 40_000)])

        let data = try await service.loadTPPData(timeRange: .day, model: nil, hasNoFiveHourNumber: true)

        #expect(data.insightText.hasPrefix("Collecting weekly-step readings"))
    }

    @Test("A day holding both bases is never averaged together, on either basis")
    func bucketsNeverMix() async throws {
        // Noon yesterday, so all four rows share a calendar day and none lies in the future.
        let ts = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000) - 12 * oneHourMs
        let (service, _) = makeService([
            makeMeasurement(timestamp: ts, tppFiveHour: 1000),
            makeMeasurement(timestamp: ts + 1, tppFiveHour: 3000),
            weekly(ts + 2, tpp: 20_000),
            weekly(ts + 3, tpp: 40_000),
        ])

        let weeklyData = try await service.loadTPPData(timeRange: .week, model: nil, basis: .weekly)
        #expect(weeklyData.passivePoints.map(\.tppValue) == [30_000])
        #expect(weeklyData.yAxisLabel == "tokens per weekly %")

        let fiveHourData = try await service.loadTPPData(timeRange: .week, model: nil, basis: .fiveHour)
        #expect(fiveHourData.passivePoints.map(\.tppValue) == [2000])
        #expect(fiveHourData.yAxisLabel == "tokens per 5-hour %")
        #expect(fiveHourData.basisCaption?.contains("not comparable") == true)
    }

    @Test("Trend and shifts use one basis: a jump between bases is not a shift")
    func trendStaysOnOneBasis() async throws {
        var rows = (0..<8).map { makeMeasurement(timestamp: nowMs - oneHourMs * Int64(20 - $0), tppFiveHour: 1000) }
        rows += (0..<8).map { weekly(nowMs - oneHourMs * Int64(10 - $0), tpp: 10_000) }
        let (service, _) = makeService(rows)

        let data = try await service.loadTPPData(timeRange: .day, model: nil)

        #expect(data.basis == .weekly)
        #expect(data.passivePoints.count == 8)
        #expect(data.trendLine.allSatisfy { $0.tppValue == 10_000 })
        #expect(data.shiftAnnotations.isEmpty)
    }

    @Test("A requested basis absent from the range falls back to the default")
    func requestedBasisAbsent() async throws {
        let (service, _) = makeService([weekly(nowMs - oneHourMs, tpp: 40_000)])

        let data = try await service.loadTPPData(timeRange: .day, model: nil, basis: .fiveHour)

        #expect(data.basis == .weekly)
    }

    @Test("Rollup rows and delta-only rows offer no basis")
    func hiddenRowsOfferNoBasis() async throws {
        let (service, _) = makeService([
            makeMeasurement(timestamp: nowMs - oneHourMs, tppFiveHour: 1000),
            weekly(nowMs - oneHourMs, tpp: 40_000, source: .rollupBackfill),
            weekly(nowMs - oneHourMs, tpp: nil),
        ])

        let data = try await service.loadTPPData(timeRange: .day, model: nil)

        #expect(data.availableBases == [.fiveHour])
        #expect(data.basisCaption == nil)
    }

    @Test("Weekly insight has no benchmark prompt, and benchmarks never feed it")
    func weeklyInsight() async throws {
        let (service, _) = makeService([
            weekly(nowMs - oneHourMs * 2, tpp: 10_000),
            weekly(nowMs - oneHourMs, tpp: 20_000),
            makeMeasurement(timestamp: nowMs - oneHourMs * 3, source: .benchmark, tppFiveHour: 2000),
        ])

        let data = try await service.loadTPPData(timeRange: .day, model: nil)

        #expect(data.insightText == "Weekly-step readings suggest efficiency is improving.")
    }

    @Test("A weekly step with no tokens does not become the default model; a 5-hour one still does, as in 1.6.0")
    func unknownModel() async throws {
        let unknown = TPPMeasurement(
            id: nil, timestamp: nowMs - oneHourMs, windowStart: nowMs - oneHourMs * 2, model: "unknown", variant: nil, source: .passive,
            fiveHourBefore: nil, fiveHourAfter: nil, fiveHourDelta: nil, sevenDayBefore: 10, sevenDayAfter: 11, sevenDayDelta: 1,
            inputTokens: 0, outputTokens: 0, cacheCreateTokens: 0, cacheReadTokens: 0, totalRawTokens: 0,
            tppFiveHour: nil, tppSevenDay: nil, confidence: .low, messageCount: 0
        )
        let (weeklyService, _) = makeService([weekly(nowMs - oneHourMs * 3, tpp: 40_000), unknown])
        #expect(try await weeklyService.availableModels() == ["claude-sonnet-4-6"])

        let fiveHourUnknown = makeMeasurement(timestamp: nowMs - oneHourMs, model: "unknown", tppFiveHour: nil)
        let (fiveHourService, _) = makeService([makeMeasurement(timestamp: nowMs - oneHourMs * 3), fiveHourUnknown])
        #expect(try await fiveHourService.availableModels() == ["unknown", "claude-sonnet-4-6"])
    }

    @Test("Weighting ratios read only the 5-hour value, so one basis, whatever else the benchmark row holds")
    func weightingStaysOnOneBasis() async throws {
        let model = "claude-sonnet-4-6"
        let (service, storage) = makeService([])
        storage.latestBenchmarks["\(model)-output-heavy"] = makeMeasurement(timestamp: nowMs, model: model, variant: "output-heavy", source: .benchmark, tppFiveHour: 1000)
        storage.latestBenchmarks["\(model)-input-heavy"] = weekly(nowMs, tpp: 90_000, source: .benchmark)
        storage.measurements = [storage.latestBenchmarks["\(model)-output-heavy"]!]

        let data = try await service.loadTPPData(timeRange: .week, model: model)

        #expect(data.weightingDiscovery?.outputToInputRatio == nil)
    }
}
