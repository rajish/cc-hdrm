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

        // Separate by source — exclude rollup-backfill (too noisy for charting)
        let passiveMeasurements = allMeasurements.filter { $0.source == .passive || $0.source == .passiveBackfill }
        let benchmarkMeasurements = allMeasurements.filter { $0.source == .benchmark }

        // Convert benchmark measurements to chart points (always individual)
        let benchmarkPoints = benchmarkMeasurements.compactMap { toChartPoint($0) }

        // Convert passive measurements based on time range resolution, sorted by time
        let sortedPassive = passiveMeasurements.sorted { $0.timestamp < $1.timestamp }
        let passivePoints: [TPPChartPoint]
        switch timeRange {
        case .day:
            passivePoints = sortedPassive.compactMap { toChartPoint($0) }
        case .week, .month:
            passivePoints = computeDailyAverages(from: sortedPassive)
        case .all:
            passivePoints = computeWeeklyAverages(from: sortedPassive)
        }

        let trendLine = computeMovingAverage(points: passivePoints)
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

        let fiveHourBasedCount = passivePoints.filter(\.isFiveHourBased).count
        Self.logger.info("TPP chart data loaded: \(passivePoints.count) passive (\(fiveHourBasedCount) 5h-based), \(benchmarkPoints.count) benchmark, \(trendLine.count) trend, \(shiftAnnotations.count) shifts")

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

    /// A row is 5h-based iff it has a 5h delta (same rule as `TPPStorageService.deleteBackfillRecords`):
    /// its weekly value, if any, came from a 5h-era window and must not join the weekly series.
    private static func chartValue(_ measurement: TPPMeasurement) -> (value: Double, isFiveHourBased: Bool)? {
        if measurement.fiveHourDelta != nil {
            return measurement.tppFiveHour.map { ($0, true) }
        }
        return measurement.tppSevenDay.map { ($0, false) }
    }

    private func toChartPoint(_ measurement: TPPMeasurement) -> TPPChartPoint? {
        guard let chartValue = Self.chartValue(measurement) else { return nil }
        return TPPChartPoint(
            timestamp: Date(timeIntervalSince1970: Double(measurement.timestamp) / 1000.0),
            tppValue: chartValue.value,
            source: measurement.source,
            confidence: measurement.confidence,
            isAverage: false,
            isFiveHourBased: chartValue.isFiveHourBased
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

    private struct BucketKey: Hashable {
        let date: Date
        let isFiveHourBased: Bool
    }

    /// Averages each time bucket separately per basis, so a bucket holding both
    /// 5h-based and weekly-based rows yields two points.
    private func computeAverages(from measurements: [TPPMeasurement], groupBy: (Date) -> Date) -> [TPPChartPoint] {
        var buckets: [BucketKey: [(value: Double, confidence: MeasurementConfidence)]] = [:]
        for m in measurements {
            guard let chartValue = Self.chartValue(m) else { continue }
            let date = Date(timeIntervalSince1970: Double(m.timestamp) / 1000.0)
            let key = BucketKey(date: groupBy(date), isFiveHourBased: chartValue.isFiveHourBased)
            buckets[key, default: []].append((chartValue.value, m.confidence))
        }
        guard !buckets.isEmpty else { return [] }

        let sortedKeys = buckets.keys.sorted {
            $0.date != $1.date ? $0.date < $1.date : !$0.isFiveHourBased && $1.isFiveHourBased
        }
        return sortedKeys.map { key in
            let entries = buckets[key] ?? []
            let avg = entries.map(\.value).reduce(0, +) / Double(entries.count)

            // Use the worst confidence in the bucket
            let worstConfidence: MeasurementConfidence = entries.contains(where: { $0.confidence == .low }) ? .low
                : entries.contains(where: { $0.confidence == .medium }) ? .medium
                : .high

            return TPPChartPoint(
                timestamp: key.date,
                tppValue: avg,
                source: .passive,
                confidence: worstConfidence,
                isAverage: true,
                isFiveHourBased: key.isFiveHourBased
            )
        }
    }

    // MARK: - Trend Line

    /// Computes a 7-point moving average from the given points.
    /// Weekly-based and 5h-based points form separate series; the result holds the
    /// weekly series first, then the 5h-based series.
    func computeMovingAverage(points: [TPPChartPoint], windowSize: Int = 7) -> [TPPChartPoint] {
        movingAverage(of: points.filter { !$0.isFiveHourBased }, windowSize: windowSize, isFiveHourBased: false)
            + movingAverage(of: points.filter(\.isFiveHourBased), windowSize: windowSize, isFiveHourBased: true)
    }

    private func movingAverage(of points: [TPPChartPoint], windowSize: Int, isFiveHourBased: Bool) -> [TPPChartPoint] {
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
                isAverage: true,
                isFiveHourBased: isFiveHourBased
            ))
        }
        return result
    }

    // MARK: - Shift Detection

    /// Detects significant trend shifts by comparing points to their moving average.
    ///
    /// A shift is detected when the ratio `point / MA` deviates by >20% for 3+
    /// consecutive points. Only the first point in each sustained run is reported.
    /// Runs are detected per basis: weekly points only against the weekly trend,
    /// 5h-based points only against the 5h-based trend.
    func detectShifts(points: [TPPChartPoint], trendLine: [TPPChartPoint]) -> [TPPShiftAnnotation] {
        let largestFirst: (TPPShiftAnnotation, TPPShiftAnnotation) -> Bool = {
            abs($0.percentChange) > abs($1.percentChange)
        }
        let weekly = shiftRuns(
            points: points.filter { !$0.isFiveHourBased },
            trendLine: trendLine.filter { !$0.isFiveHourBased }
        ).sorted(by: largestFirst)
        let fiveHour = shiftRuns(
            points: points.filter(\.isFiveHourBased),
            trendLine: trendLine.filter(\.isFiveHourBased)
        ).sorted(by: largestFirst)

        // Cap annotations to avoid visual clutter; current weekly shifts take priority over old 5h-based ones
        return Array((weekly + fiveHour).prefix(3))
    }

    private func shiftRuns(points: [TPPChartPoint], trendLine: [TPPChartPoint]) -> [TPPShiftAnnotation] {
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
            let latest = benchmarkMeasurements.max(by: { $0.timestamp < $1.timestamp })

            // Compare on one basis only, weekly preferred
            let comparison: (latest: Double, average: Double)? = {
                if let latestTPP = latest?.tppSevenDay, let avgTPP = avgResult.sevenDay { return (latestTPP, avgTPP) }
                if let latestTPP = latest?.tppFiveHour, let avgTPP = avgResult.fiveHour { return (latestTPP, avgTPP) }
                return nil
            }()

            if let comparison, comparison.average > 0 {
                let changePercent = ((comparison.latest - comparison.average) / comparison.average) * 100

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
            // Compare on one basis only, weekly preferred
            let weeklyPoints = passivePoints.filter { !$0.isFiveHourBased }
            let sameBasisPoints = weeklyPoints.count >= 2 ? weeklyPoints : passivePoints.filter(\.isFiveHourBased)
            let recentPoints = sameBasisPoints.suffix(7)
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
        let outputToInputRatio = Self.sameBasisRatio(inputHeavy, over: outputHeavy)
        let cacheToInputRatio = Self.sameBasisRatio(cacheHeavy, over: inputHeavy)

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

    /// `numerator / denominator` TPP on one basis, weekly preferred.
    private static func sameBasisRatio(_ numerator: TPPMeasurement?, over denominator: TPPMeasurement?) -> Double? {
        if let num = numerator?.tppSevenDay, let den = denominator?.tppSevenDay, den > 0 { return num / den }
        if let num = numerator?.tppFiveHour, let den = denominator?.tppFiveHour, den > 0 { return num / den }
        return nil
    }
}
