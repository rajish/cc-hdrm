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

    func deleteBackfillRecords() async throws {}
}

// MARK: - Test Helpers

private func makeMeasurement(
    timestamp: Int64,
    model: String = "claude-sonnet-4-6",
    variant: String? = nil,
    source: MeasurementSource = .passive,
    tppFiveHour: Double? = 1000.0,
    tppSevenDay: Double? = nil,
    fiveHourDelta: Double? = 1.0,
    confidence: MeasurementConfidence = .high
) -> TPPMeasurement {
    TPPMeasurement(
        id: nil,
        timestamp: timestamp,
        windowStart: timestamp,
        model: model,
        variant: variant,
        source: source,
        fiveHourBefore: fiveHourDelta.map { _ in 50.0 },
        fiveHourAfter: fiveHourDelta.map { 50.0 + $0 },
        fiveHourDelta: fiveHourDelta,
        sevenDayBefore: nil,
        sevenDayAfter: nil,
        sevenDayDelta: nil,
        inputTokens: 500,
        outputTokens: 500,
        cacheCreateTokens: 0,
        cacheReadTokens: 0,
        totalRawTokens: 1000,
        tppFiveHour: tppFiveHour,
        tppSevenDay: tppSevenDay,
        confidence: confidence,
        messageCount: 1
    )
}

private func makePoint(dayOffset: Int, value: Double, isFiveHourBased: Bool) -> TPPChartPoint {
    TPPChartPoint(
        timestamp: Date(timeIntervalSince1970: Double(nowMs + Int64(dayOffset) * oneDayMs) / 1000.0),
        tppValue: value,
        source: .passive,
        confidence: .high,
        isAverage: false,
        isFiveHourBased: isFiveHourBased
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

    // MARK: - Weekly vs 5h basis

    @Test("Old 5h-only row is shown and flagged as 5h-based")
    func oldFiveHourRowFlagged() async throws {
        let storage = MockChartTPPStorage()
        storage.measurements = [makeMeasurement(timestamp: nowMs - oneHourMs, tppFiveHour: 1200.0, tppSevenDay: nil)]

        let service = TPPChartDataService(tppStorage: storage)
        let data = try await service.loadTPPData(timeRange: .day, model: nil)

        #expect(data.passivePoints.count == 1)
        #expect(data.passivePoints.first?.tppValue == 1200.0)
        #expect(data.passivePoints.first?.isFiveHourBased == true)
    }

    @Test("Row without a 5h delta is charted with its weekly value")
    func weeklyRowCharted() async throws {
        let storage = MockChartTPPStorage()
        storage.measurements = [makeMeasurement(timestamp: nowMs - oneHourMs, tppFiveHour: nil, tppSevenDay: 15000.0, fiveHourDelta: nil)]

        let service = TPPChartDataService(tppStorage: storage)
        let data = try await service.loadTPPData(timeRange: .day, model: nil)

        #expect(data.passivePoints.count == 1)
        #expect(data.passivePoints.first?.tppValue == 15000.0)
        #expect(data.passivePoints.first?.isFiveHourBased == false)
    }

    @Test("Pre-retirement row with both values and a 5h delta is charted as 5h-based")
    func bothValuesWithFiveHourDeltaIsFiveHourBased() async throws {
        let storage = MockChartTPPStorage()
        storage.measurements = [makeMeasurement(timestamp: nowMs - oneHourMs, tppFiveHour: 1200.0, tppSevenDay: 15000.0, fiveHourDelta: 2.0)]

        let service = TPPChartDataService(tppStorage: storage)
        let data = try await service.loadTPPData(timeRange: .day, model: nil)

        #expect(data.passivePoints.count == 1)
        #expect(data.passivePoints.first?.tppValue == 1200.0)
        #expect(data.passivePoints.first?.isFiveHourBased == true)
    }

    @Test("Daily averages: 5h-based and weekly rows in one day produce one point per basis")
    func dailyAveragePerBasis() {
        let service = TPPChartDataService(tppStorage: MockChartTPPStorage())

        let yesterdayNoon = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400)).addingTimeInterval(12 * 3_600)
        let baseDayMs = Int64(yesterdayNoon.timeIntervalSince1970 * 1000)
        let measurements = [
            makeMeasurement(timestamp: baseDayMs, tppFiveHour: 100.0, tppSevenDay: nil),
            makeMeasurement(timestamp: baseDayMs + oneHourMs, tppFiveHour: nil, tppSevenDay: 2000.0, fiveHourDelta: nil),
            makeMeasurement(timestamp: baseDayMs + 2 * oneHourMs, tppFiveHour: 300.0, tppSevenDay: nil),
            makeMeasurement(timestamp: baseDayMs + 3 * oneHourMs, tppFiveHour: nil, tppSevenDay: 4000.0, fiveHourDelta: nil),
        ]

        let result = service.computeDailyAverages(from: measurements)
        #expect(result.count == 2)
        let weekly = result.first { !$0.isFiveHourBased }
        let fiveHour = result.first { $0.isFiveHourBased }
        #expect(weekly?.tppValue == 3000.0)
        #expect(fiveHour?.tppValue == 200.0)
        #expect(weekly?.timestamp == fiveHour?.timestamp)
    }

    @Test("Moving average: 5h-based and weekly points form separate trend series")
    func movingAveragePerBasis() {
        let service = TPPChartDataService(tppStorage: MockChartTPPStorage())

        // Interleaved: 7 weekly points at 10000, 7 5h-based points at 1000
        let points = (0..<14).map { i in
            makePoint(dayOffset: i, value: i.isMultiple(of: 2) ? 10_000.0 : 1_000.0, isFiveHourBased: !i.isMultiple(of: 2))
        }

        let trend = service.computeMovingAverage(points: points, windowSize: 7)
        #expect(trend.count == 2)
        #expect(trend.filter { !$0.isFiveHourBased }.map(\.tppValue) == [10_000.0])
        #expect(trend.filter(\.isFiveHourBased).map(\.tppValue) == [1_000.0])
    }

    @Test("Shift detection: interleaved bases with stable values produce no shift")
    func shiftDetectionPerBasis() {
        let service = TPPChartDataService(tppStorage: MockChartTPPStorage())

        // Mixing these would put every point >20% off a blended average
        let points = (0..<20).map { i in
            makePoint(dayOffset: i, value: i.isMultiple(of: 2) ? 10_000.0 : 1_000.0, isFiveHourBased: !i.isMultiple(of: 2))
        }

        let trend = service.computeMovingAverage(points: points, windowSize: 7)
        let shifts = service.detectShifts(points: points, trendLine: trend)
        #expect(shifts.isEmpty)
    }

    @Test("Insight text: benchmark comparison prefers the weekly basis")
    func insightBenchmarkWeeklyPreferred() async throws {
        let storage = MockChartTPPStorage()
        storage.averageResult = (fiveHour: 1000.0, sevenDay: 10_000.0)
        // Stable on 5h, 30% lower on weekly
        let benchmarks = [makeMeasurement(timestamp: nowMs, source: .benchmark, tppFiveHour: 1000.0, tppSevenDay: 7000.0)]

        let service = TPPChartDataService(tppStorage: storage)
        let insight = try await service.computeInsightText(
            benchmarkMeasurements: benchmarks,
            passivePoints: [],
            model: nil
        )

        #expect(insight.contains("dropped"))
        #expect(insight.contains("30%"))
    }

    @Test("Insight text: passive trend compares weekly points only")
    func insightPassiveSameBasis() async throws {
        let service = TPPChartDataService(tppStorage: MockChartTPPStorage())
        // Older weekly points, then newer 5h-based points at a tenth of the value
        let passivePoints = (0..<4).map { makePoint(dayOffset: $0, value: 10_000.0, isFiveHourBased: false) }
            + (4..<7).map { makePoint(dayOffset: $0, value: 1_000.0, isFiveHourBased: true) }

        let insight = try await service.computeInsightText(
            benchmarkMeasurements: [],
            passivePoints: passivePoints,
            model: nil
        )

        #expect(insight.contains("stable"))
    }

    @Test("Weighting discovery: ratios use weekly values when both variants have them")
    func weightingDiscoveryWeeklyPreferred() async throws {
        let storage = MockChartTPPStorage()
        let model = "claude-sonnet-4-6"

        let outputHeavy = makeMeasurement(
            timestamp: nowMs, model: model, variant: "output-heavy", source: .benchmark,
            tppFiveHour: 1000.0, tppSevenDay: 10_000.0
        )
        let inputHeavy = makeMeasurement(
            timestamp: nowMs, model: model, variant: "input-heavy", source: .benchmark,
            tppFiveHour: 5000.0, tppSevenDay: 30_000.0
        )
        storage.latestBenchmarks["\(model)-output-heavy"] = outputHeavy
        storage.latestBenchmarks["\(model)-input-heavy"] = inputHeavy
        storage.measurements = [outputHeavy, inputHeavy]

        let service = TPPChartDataService(tppStorage: storage)
        let data = try await service.loadTPPData(timeRange: .week, model: model)

        #expect(data.weightingDiscovery?.outputToInputRatio == 3.0)
    }

    @Test("Mixed range: old 5h-only and new weekly rows both appear, flagged, never averaged together")
    func mixedRangeLoad() async throws {
        let storage = MockChartTPPStorage()
        let yesterdayNoon = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86_400)).addingTimeInterval(12 * 3_600)
        let baseDayMs = Int64(yesterdayNoon.timeIntervalSince1970 * 1000)
        storage.measurements = [
            makeMeasurement(timestamp: baseDayMs, tppFiveHour: 1000.0, tppSevenDay: nil),
            makeMeasurement(timestamp: baseDayMs + oneHourMs, tppFiveHour: 1000.0, tppSevenDay: nil),
            makeMeasurement(timestamp: baseDayMs + 2 * oneHourMs, tppFiveHour: nil, tppSevenDay: 12_000.0, fiveHourDelta: nil),
        ]

        let service = TPPChartDataService(tppStorage: storage)
        let data = try await service.loadTPPData(timeRange: .week, model: nil)

        #expect(data.passivePoints.count == 2)
        #expect(data.passivePoints.filter(\.isFiveHourBased).map(\.tppValue) == [1000.0])
        #expect(data.passivePoints.filter { !$0.isFiveHourBased }.map(\.tppValue) == [12_000.0])
    }

    @Test("Shift detection: weekly shifts take priority over larger 5h-based shifts in the top-3 cap")
    func shiftCapPrefersWeekly() {
        let service = TPPChartDataService(tppStorage: MockChartTPPStorage())

        // Weekly: one moderate drop (~-28%)
        let weekly = (0..<10).map { makePoint(dayOffset: $0, value: $0 < 7 ? 1000.0 : 600.0, isFiveHourBased: false) }
        // 5h-based: two steep drops, each sustained long enough for two annotations
        let fiveHour = (0..<21).map { i in
            makePoint(dayOffset: i, value: i < 7 ? 1000.0 : (i < 14 ? 100.0 : 10.0), isFiveHourBased: true)
        }
        let points = weekly + fiveHour

        let trend = service.computeMovingAverage(points: points, windowSize: 7)
        let shifts = service.detectShifts(points: points, trendLine: trend)

        #expect(shifts.count == 3)
        let first = shifts.first?.percentChange ?? 0
        #expect(first > -30 && first < -25)  // the weekly shift is kept and listed first
    }

    @Test("Shift detection: a real drop on 5h-based points yields a down annotation")
    func shiftDetectionFiveHourDrop() {
        let service = TPPChartDataService(tppStorage: MockChartTPPStorage())
        let points = (0..<12).map { makePoint(dayOffset: $0, value: $0 < 7 ? 1000.0 : 600.0, isFiveHourBased: true) }

        let trend = service.computeMovingAverage(points: points, windowSize: 7)
        let shifts = service.detectShifts(points: points, trendLine: trend)

        let trendIsFiveHourBased = !trend.isEmpty && trend.allSatisfy { $0.isFiveHourBased }
        #expect(trendIsFiveHourBased)
        #expect(shifts.first?.direction == .down)
        #expect(shifts.first?.label.contains("dropped") == true)
    }

    @Test("Insight text: with fewer than 2 weekly points, passive insight falls back to 5h-based points")
    func insightPassiveFiveHourFallback() async throws {
        let service = TPPChartDataService(tppStorage: MockChartTPPStorage())
        let passivePoints = [makePoint(dayOffset: 0, value: 50_000.0, isFiveHourBased: false)]
            + (1..<8).map { makePoint(dayOffset: $0, value: 1000.0 - Double($0) * 100, isFiveHourBased: true) }

        let insight = try await service.computeInsightText(
            benchmarkMeasurements: [],
            passivePoints: passivePoints,
            model: nil
        )

        #expect(insight.contains("Passive monitoring"))
        #expect(insight.contains("declining"))
    }

    @Test("Weighting discovery: cache-to-input ratio uses weekly values, falling back to 5h when weekly is missing")
    func cacheToInputRatioBasis() async throws {
        let model = "claude-sonnet-4-6"
        let inputHeavy = makeMeasurement(
            timestamp: nowMs, model: model, variant: "input-heavy", source: .benchmark,
            tppFiveHour: 1000.0, tppSevenDay: 10_000.0
        )
        let cacheWeekly = makeMeasurement(
            timestamp: nowMs, model: model, variant: "cache-heavy", source: .benchmark,
            tppFiveHour: 2000.0, tppSevenDay: 40_000.0
        )
        let cacheFiveHourOnly = makeMeasurement(
            timestamp: nowMs, model: model, variant: "cache-heavy", source: .benchmark,
            tppFiveHour: 2000.0, tppSevenDay: nil
        )

        for (cacheHeavy, expected) in [(cacheWeekly, 4.0), (cacheFiveHourOnly, 2.0)] {
            let storage = MockChartTPPStorage()
            storage.latestBenchmarks["\(model)-input-heavy"] = inputHeavy
            storage.latestBenchmarks["\(model)-cache-heavy"] = cacheHeavy
            storage.measurements = [inputHeavy, cacheHeavy]

            let service = TPPChartDataService(tppStorage: storage)
            let data = try await service.loadTPPData(timeRange: .week, model: model)

            #expect(data.weightingDiscovery?.cacheToInputRatio == expected)
            #expect(data.weightingDiscovery?.outputToInputRatio == nil)
        }
    }
}
