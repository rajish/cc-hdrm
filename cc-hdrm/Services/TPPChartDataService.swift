import Foundation
import os

/// Transforms raw TPP measurements into chart-ready data.
///
/// Fetches from `TPPStorageServiceProtocol`, computes averages, trend lines,
/// shift detection, insight text, and weighting discovery.
final class TPPChartDataService: TPPChartDataServiceProtocol, Sendable {
    private let tppStorage: any TPPStorageServiceProtocol

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "tpp-chart"
    )

    init(tppStorage: any TPPStorageServiceProtocol) {
        self.tppStorage = tppStorage
    }

    // MARK: - Public API

    func loadTPPData(timeRange: TimeRange, model: String?) async throws -> TPPChartData {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let fromMs = timeRange.startTimestamp
        let toMs = nowMs

        Self.logger.info("Loading TPP chart data: range=\(timeRange.displayLabel), model=\(model ?? "all")")

        // Fetch all measurements for the time range
        let allMeasurements = try await tppStorage.getMeasurements(
            from: fromMs, to: toMs, source: nil, model: model, confidence: nil
        )

        guard !allMeasurements.isEmpty else {
            Self.logger.info("No TPP measurements found for range")
            return TPPChartData(
                passivePoints: [],
                benchmarkPoints: [],
                trendLine: [],
                shiftAnnotations: [],
                insightText: "Run a benchmark to get a calibrated reading of your token efficiency.",
                availableModels: try await availableModels(),
                weightingDiscovery: nil
            )
        }

        // Separate by source
        let passiveMeasurements = allMeasurements.filter { $0.source == .passive || $0.source == .passiveBackfill || $0.source == .rollupBackfill }
        let benchmarkMeasurements = allMeasurements.filter { $0.source == .benchmark }

        // Convert benchmark measurements to chart points (always individual)
        let benchmarkPoints = benchmarkMeasurements.compactMap { toChartPoint($0) }

        // Convert passive measurements based on time range resolution
        let passivePoints: [TPPChartPoint]
        switch timeRange {
        case .day:
            passivePoints = passiveMeasurements.compactMap { toChartPoint($0) }
        case .week, .month:
            passivePoints = computeDailyAverages(from: passiveMeasurements)
        case .all:
            passivePoints = computeWeeklyAverages(from: passiveMeasurements)
        }

        // Compute trend line from passive data
        let trendLine = computeMovingAverage(points: passivePoints)

        // Detect shifts
        let shiftAnnotations = detectShifts(points: passivePoints, trendLine: trendLine)

        // Compute insight text
        let insightText = try await computeInsightText(
            benchmarkMeasurements: benchmarkMeasurements,
            passivePoints: passivePoints,
            model: model
        )

        // Compute weighting discovery
        let weightingDiscovery: TPPWeightingDiscovery?
        if let model {
            weightingDiscovery = try await computeWeightingDiscovery(model: model)
        } else {
            weightingDiscovery = nil
        }

        let models = try await availableModels()

        Self.logger.info("TPP chart data loaded: \(passivePoints.count) passive, \(benchmarkPoints.count) benchmark, \(trendLine.count) trend, \(shiftAnnotations.count) shifts")

        return TPPChartData(
            passivePoints: passivePoints,
            benchmarkPoints: benchmarkPoints,
            trendLine: trendLine,
            shiftAnnotations: shiftAnnotations,
            insightText: insightText,
            availableModels: models,
            weightingDiscovery: weightingDiscovery
        )
    }

    func availableModels() async throws -> [String] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let allMeasurements = try await tppStorage.getMeasurements(
            from: 0, to: nowMs, source: nil, model: nil, confidence: nil
        )

        // Count occurrences per model
        var modelCounts: [String: Int] = [:]
        for m in allMeasurements {
            modelCounts[m.model, default: 0] += 1
        }

        // Sort by count descending
        return modelCounts.sorted { $0.value > $1.value }.map(\.key)
    }

    // MARK: - Chart Point Conversion

    private func toChartPoint(_ measurement: TPPMeasurement) -> TPPChartPoint? {
        guard let tppValue = measurement.tppFiveHour else { return nil }
        return TPPChartPoint(
            timestamp: Date(timeIntervalSince1970: Double(measurement.timestamp) / 1000.0),
            tppValue: tppValue,
            source: measurement.source,
            confidence: measurement.confidence,
            isAverage: false
        )
    }

    // MARK: - Averaging

    /// Groups passive measurements by calendar day and computes daily averages.
    func computeDailyAverages(from measurements: [TPPMeasurement]) -> [TPPChartPoint] {
        computeAverages(from: measurements, groupBy: { date in
            Calendar.current.startOfDay(for: date)
        })
    }

    /// Groups passive measurements by calendar week and computes weekly averages.
    func computeWeeklyAverages(from measurements: [TPPMeasurement]) -> [TPPChartPoint] {
        computeAverages(from: measurements, groupBy: { date in
            let calendar = Calendar.current
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: components) ?? date
        })
    }

    private func computeAverages(from measurements: [TPPMeasurement], groupBy: (Date) -> Date) -> [TPPChartPoint] {
        // Filter to measurements with valid TPP
        let valid = measurements.filter { $0.tppFiveHour != nil }
        guard !valid.isEmpty else { return [] }

        // Group by time bucket
        var buckets: [Date: [TPPMeasurement]] = [:]
        for m in valid {
            let date = Date(timeIntervalSince1970: Double(m.timestamp) / 1000.0)
            let bucket = groupBy(date)
            buckets[bucket, default: []].append(m)
        }

        // Compute average for each bucket
        return buckets.sorted { $0.key < $1.key }.compactMap { (bucket, measurements) -> TPPChartPoint? in
            let tppValues = measurements.compactMap(\.tppFiveHour)
            guard !tppValues.isEmpty else { return nil }
            let avg = tppValues.reduce(0, +) / Double(tppValues.count)

            // Use the worst confidence in the bucket
            let worstConfidence: MeasurementConfidence = measurements.contains(where: { $0.confidence == .low }) ? .low
                : measurements.contains(where: { $0.confidence == .medium }) ? .medium
                : .high

            return TPPChartPoint(
                timestamp: bucket,
                tppValue: avg,
                source: .passive,
                confidence: worstConfidence,
                isAverage: true
            )
        }
    }

    // MARK: - Trend Line

    /// Computes a 7-point moving average from the given points.
    func computeMovingAverage(points: [TPPChartPoint], windowSize: Int = 7) -> [TPPChartPoint] {
        guard points.count >= windowSize else { return [] }
        var result: [TPPChartPoint] = []
        for i in (windowSize - 1)..<points.count {
            let window = points[(i - windowSize + 1)...i]
            let avg = window.map(\.tppValue).reduce(0, +) / Double(windowSize)
            result.append(TPPChartPoint(
                timestamp: points[i].timestamp,
                tppValue: avg,
                source: .passive,
                confidence: .medium,
                isAverage: true
            ))
        }
        return result
    }

    // MARK: - Shift Detection

    /// Detects significant trend shifts by comparing points to their moving average.
    ///
    /// A shift is detected when the ratio `point / MA` deviates by >20% for 3+
    /// consecutive points. Only the first point in each sustained run is reported.
    func detectShifts(points: [TPPChartPoint], trendLine: [TPPChartPoint]) -> [TPPShiftAnnotation] {
        guard !trendLine.isEmpty, points.count >= trendLine.count else { return [] }

        // Align: trendLine[i] corresponds to points[offset + i] where offset = points.count - trendLine.count
        let offset = points.count - trendLine.count
        var annotations: [TPPShiftAnnotation] = []
        var consecutiveDeviations = 0
        var currentDirection: ShiftDirection?
        var shiftStartIndex: Int?

        for i in 0..<trendLine.count {
            let pointIndex = offset + i
            let pointValue = points[pointIndex].tppValue
            let maValue = trendLine[i].tppValue

            guard maValue > 0 else { continue }

            let ratio = pointValue / maValue

            if ratio < 0.8 {
                // Below threshold — potential downward shift
                if currentDirection == .down {
                    consecutiveDeviations += 1
                } else {
                    currentDirection = .down
                    consecutiveDeviations = 1
                    shiftStartIndex = pointIndex
                }
            } else if ratio > 1.2 {
                // Above threshold — potential upward shift
                if currentDirection == .up {
                    consecutiveDeviations += 1
                } else {
                    currentDirection = .up
                    consecutiveDeviations = 1
                    shiftStartIndex = pointIndex
                }
            } else {
                // Within normal range — reset
                consecutiveDeviations = 0
                currentDirection = nil
                shiftStartIndex = nil
            }

            // 3+ consecutive deviations = confirmed shift
            if consecutiveDeviations == 3, let direction = currentDirection, let startIdx = shiftStartIndex {
                let percentChange = ((pointValue / maValue) - 1.0) * 100
                let date = points[startIdx].timestamp
                let label: String
                if direction == .down {
                    label = "TPP dropped ~\(Int(abs(percentChange)))%"
                } else {
                    label = "TPP rose ~\(Int(abs(percentChange)))%"
                }

                annotations.append(TPPShiftAnnotation(
                    date: date,
                    direction: direction,
                    percentChange: percentChange,
                    label: label
                ))

                // Reset to avoid annotation spam for the same sustained run
                consecutiveDeviations = 0
                currentDirection = nil
                shiftStartIndex = nil
            }
        }

        return annotations
    }

    // MARK: - Insight Text

    /// Computes the plain-English insight text following AC-7 priority order.
    func computeInsightText(
        benchmarkMeasurements: [TPPMeasurement],
        passivePoints: [TPPChartPoint],
        model: String?
    ) async throws -> String {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let thirtyDaysAgoMs = nowMs - (30 * 24 * 60 * 60 * 1000)

        // Priority 1: Compare recent benchmark vs 30-day average
        if !benchmarkMeasurements.isEmpty {
            let avgResult = try await tppStorage.getAverageTPP(
                from: thirtyDaysAgoMs, to: nowMs, model: model, source: .benchmark
            )

            if let avgTPP = avgResult.fiveHour,
               let latestTPP = benchmarkMeasurements.max(by: { $0.timestamp < $1.timestamp })?.tppFiveHour,
               avgTPP > 0 {
                let changePercent = ((latestTPP - avgTPP) / avgTPP) * 100

                if changePercent < -20 {
                    return "Your token efficiency dropped ~\(Int(abs(changePercent)))% recently -- the same work now costs more headroom."
                } else if changePercent > 20 {
                    return "Your token efficiency improved ~\(Int(abs(changePercent)))% -- you're getting more tokens per % of headroom."
                } else {
                    return "Token efficiency is stable -- no detectable rate limit changes."
                }
            }
        }

        // Priority 2: Passive data only — analyze trend direction
        if !passivePoints.isEmpty {
            let recentPoints = passivePoints.suffix(7)
            if recentPoints.count >= 2 {
                let firstHalf = recentPoints.prefix(recentPoints.count / 2)
                let secondHalf = recentPoints.suffix(recentPoints.count / 2)
                let firstAvg = firstHalf.map(\.tppValue).reduce(0, +) / Double(firstHalf.count)
                let secondAvg = secondHalf.map(\.tppValue).reduce(0, +) / Double(secondHalf.count)

                let direction: String
                if firstAvg > 0 {
                    let change = ((secondAvg - firstAvg) / firstAvg) * 100
                    if change < -10 {
                        direction = "declining"
                    } else if change > 10 {
                        direction = "improving"
                    } else {
                        direction = "stable"
                    }
                } else {
                    direction = "stable"
                }
                return "Passive monitoring suggests efficiency is \(direction). Run a benchmark to confirm."
            }
        }

        // Priority 3: No data
        return "Run a benchmark to get a calibrated reading of your token efficiency."
    }

    // MARK: - Weighting Discovery

    /// Computes token type weighting ratios from benchmark variants.
    private func computeWeightingDiscovery(model: String) async throws -> TPPWeightingDiscovery? {
        let outputHeavy = try await tppStorage.latestBenchmark(model: model, variant: BenchmarkVariant.outputHeavy.rawValue)
        let inputHeavy = try await tppStorage.latestBenchmark(model: model, variant: BenchmarkVariant.inputHeavy.rawValue)
        let cacheHeavy = try await tppStorage.latestBenchmark(model: model, variant: BenchmarkVariant.cacheHeavy.rawValue)

        // Need at least two variants for meaningful ratios
        let variantsPresent = [outputHeavy, inputHeavy, cacheHeavy].compactMap { $0 }.count
        guard variantsPresent >= 2 else { return nil }

        // Compute ratios: inputTPP / outputTPP (lower TPP = more expensive)
        let outputToInputRatio: Double?
        if let outTPP = outputHeavy?.tppFiveHour, let inTPP = inputHeavy?.tppFiveHour, outTPP > 0 {
            outputToInputRatio = inTPP / outTPP
        } else {
            outputToInputRatio = nil
        }

        let cacheToInputRatio: Double?
        if let inTPP = inputHeavy?.tppFiveHour, let caTPP = cacheHeavy?.tppFiveHour, inTPP > 0 {
            cacheToInputRatio = caTPP / inTPP
        } else {
            cacheToInputRatio = nil
        }

        // Use the most recent measurement date
        let dates = [outputHeavy, inputHeavy, cacheHeavy].compactMap { $0 }.map { $0.timestamp }
        guard let latestTs = dates.max() else { return nil }

        return TPPWeightingDiscovery(
            model: model,
            outputToInputRatio: outputToInputRatio,
            cacheToInputRatio: cacheToInputRatio,
            lastMeasuredDate: Date(timeIntervalSince1970: Double(latestTs) / 1000.0)
        )
    }
}
